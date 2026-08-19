#' `smooths()` models fail about half the time, with a TensorFlow error.
#'
#' First seen as `vignettes/getting-started.Rmd` failing roughly one
#' `devtools::check()` run in three.

library(greta)
library(greta.gam)
library(mgcv)
library(testthat)

#' ## What happens
#'
#' Following the vignette, but cut down to the smallest thing that still shows
#' it:

set.seed(2026 - 07 - 30)
dat <- gamSim(1, n = 100, verbose = FALSE)

fit <- function() {
  z <- smooths(~ s(x2), data = dat)
  distribution(dat$y) <- normal(z, 1)
  mcmc(model(z), n_samples = 10, warmup = 50, verbose = FALSE)
}

#' Run it ten times and keep the results, so we can look at both a failure and
#' a success:

runs <- replicate(10, try(fit(), silent = TRUE))
errored <- vapply(runs, function(x) inherits(x, "try-error"), logical(1))
table(errored)

#' A failing run:
a_failed_run <- runs[errored][[1]]
cat(a_failed_run)

#' A successful one, for contrast — the model itself runs:
a_good_run <- runs[!errored][[1]]
head(a_good_run[[1]][, 1:2])

#' The underlying TensorFlow error:
greta_notes_tf_num_error()

#' ## It depends on warmup, not on the data
#'
#' The same model, varying only `warmup`, eight runs each:
#'
#' | warmup | failures |
#' | ------ | ----- |
#' | 0      | 0 / 8 |
#' | 5      | 0 / 8 |
#' | 20     | 0 / 8 |
#' | 50     | 5 / 8 |
#' | 200    | 1 / 8 |
#'
#' With `warmup = 0` it never fails, so this is not the initial values. It is
#' something the sampler reaches during warmup. The count varies run to run
#' because `mcmc()` takes no seed and greta does not respect `set.seed()` for
#' sampling (greta [#285](https://github.com/greta-dev/greta/issues/285),
#' [#427](https://github.com/greta-dev/greta/issues/427)).
#'
#' ## Workaround
#'
#' `mcmc(one_by_one = TRUE)` lets the run survive, at some cost in speed. greta
#' suggests this in the error message itself.
#'
#' ## Fix
#'
#' [`jagam2greta.R#L83`](https://github.com/greta-dev/greta.gam/blob/653a7012fe4abe551ec1a6b885fef763af6b9e1e/R/jagam2greta.R#L83)
#' inverts the penalty matrix with `solve()`:

## assign(thisK, solve(get(paste0("K", Ktosolve[i]))))

#' Use a Cholesky inverse instead:

## assign(thisK, chol2inv(chol(get(paste0("K", Ktosolve[i])))))

#' **This is an error-handling fix, not a mathematical one.** The two compute
#' the same inverse. `chol()` factors `K` into `R` with `K = R'R`, which is
#' possible because `K` is symmetric positive definite, and `chol2inv()` gets
#' `K^-1` from `R`:

jf <- tempfile(fileext = ".jags")
jg <- jagam(y ~ s(x2), data = dat, file = jf, diagonalize = FALSE)
S1 <- jg$jags.data$S1
K <- S1[, 1:9] + S1[, 10:18]

all.equal(solve(K), chol2inv(chol(K)))

#' What differs is how the two implementations behave when `K` becomes
#' **near-singular** — when its columns are nearly dependent, so it has no
#' well-behaved inverse and the entries of `K^-1` blow up.
#'
#' greta maps one-argument `solve()` to `tf$linalg$inv`. When TensorFlow decides
#' the input is not invertible, that op **throws an error**
#' (`InvalidArgumentError: Input is not invertible`), which halts everything.
#' The Cholesky route instead **returns `NaN`**.
#'
#' greta's sampler already checks whether a proposal gave a finite density and
#' rejects it if not, so `NaN` is handled — the proposal is discarded and
#' sampling carries on. It has no way to catch an error thrown inside
#' TensorFlow, so one unlucky proposal kills the whole run.
#'
#' ### Why `K` is hard to invert in the first place
#'
#' This part is structural, and worth knowing before treating the fix as a
#' patch. `K = Sa * sp[1] + Sb * sp[2]`, and neither term is invertible alone:

Sa <- S1[, 1:9]
Sb <- S1[, 10:18]

c(rank_Sa = qr(Sa)$rank, rank_Sb = qr(Sb)$rank, rank_sum = qr(Sa + Sb)$rank)

#' `Sa` penalises wiggliness. A straight line has no curvature, so the linear
#' part of the smooth is unpenalised — that direction is `Sa`'s null space, and
#' it is why `Sa` is rank 8 of 9 rather than full rank.
#'
#' `Sb` is the nullspace penalty `jagam` adds to cover exactly that direction,
#' making the prior proper. And it is exactly that direction:

ea <- eigen(Sa, symmetric = TRUE)
eb <- eigen(Sb, symmetric = TRUE)
null_dir <- ea$vectors[, which.min(abs(ea$values))]
range_dir <- eb$vectors[, which.max(abs(eb$values))]

abs(sum(null_dir * range_dir)) # 1 = perfectly aligned

#' So `K` is full rank *only* through a single rank-1 term, scaled by a free
#' parameter the sampler is free to move toward zero. Near-singularity is
#' designed in, not accidental — it is inherent to penalised smoothing. `mgcv`
#' rarely hits it because it *optimises* `sp` rather than sampling it, so it does
#' not explore the boundary.
#'
#' That suggests `chol2inv()` is the right immediate fix but not the end of it.
#' The structural alternative is to never form `K^-1` at all — build the prior
#' from `chol(K)` directly, non-centred. `design/notes/greta-gam-sp-default.md`
#' records a test of that: 0 failures in 25 runs, but noticeably worse mixing
#' (min ESS 11 against 55-69). Worth revisiting rather than adopting as-is.
#'
#' ### Does it work, and what does it cost
#'
#' Applied to `jagam2greta.R:83` and re-run:
#'
#' | version of line 83 | failures |
#' | --- | --- |
#' | `solve(K)` | 7 / 12 |
#' | `chol2inv(chol(K))` | 0 / 12 |
#'
#' Cost, timing five successful runs of 200 samples + 200 warmup each way:
#'
#' | | median seconds |
#' | --- | --- |
#' | `solve()` | 2.08 |
#' | `chol2inv(chol())` | 2.14 |
#'
#' About 3% slower. The TensorFlow op itself is ~8% slower, since
#' `cholesky_solve` is a factorisation plus a solve where `inv` is one fused
#' op; the rest of a sampling step dilutes it. Note this is the opposite of
#' base R, where the Cholesky route is the cheaper one — at 9x9 in TensorFlow,
#' overhead dominates the flop count.
#'
#' The prior and posterior are unchanged. A posterior check against
#' `mgcv::gam()`, and a comparison of the other candidate fixes (`tol`,
#' `one_by_one`, retuning the `sp` prior, a non-centred reparameterisation),
#' are in `design/notes/greta-gam-sp-default.md`.
#'
#' ## What I have not established
#'
#' **Why** the sampler reaches a singular `K`. Three explanations were tried and
#' each was contradicted by measurement:
#'
#' - *ill-conditioning from `sp[2]` going small* — but the TensorFlow inverse
#'   returns cleanly at `cond(K) = 3e22`, and even at exactly singular input
#' - *gradient overflow* — but gradients of both routes overflow identically, at
#'   the same threshold, and neither raises
#' - *`sp[1]` underflowing to zero in float32* — but observed `sp` draws sit
#'   around 1e-4 to 1e-3, some thirty orders of magnitude away
#'
#' The fix does not depend on knowing which it is: it converts a crash into a
#' rejected proposal regardless of the cause. But the cause is worth finding,
#' because it may point at something more general in how greta handles boundary
#' proposals.
#'
#' ### Why `solve()` was there
#'
#' Not a considered choice against `chol2inv()`. It arrived with the first
#' commit that added this file,
#' [`a1687ff`](https://github.com/greta-dev/greta.gam/commit/a1687ff5e9ab682f84ba8ec07be69a99c2076360)
#' ("something that seems to work?"), and `git log -S"chol" -- R/jagam2greta.R`
#' returns no commits — a Cholesky has never been used here.
#'
#' ## A test
#'
#' Fails now, passes with the fix:

test_that("smooths() models sample reliably", {
  fails <- sum(replicate(5, inherits(try(fit(), silent = TRUE), "try-error")))
  expect_equal(fails, 0)
})
