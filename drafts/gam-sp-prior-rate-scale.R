#' `greta.gam`'s default prior on the smoothing parameters is 40,000 times
#' smaller than the `jagam` prior it is meant to reproduce.
#'
#' Found while investigating the intermittent `getting-started.Rmd` vignette
#' failure. It is *not* the cause of that failure (see below), but it is a real
#' bug in its own right.

library(mgcv)
library(greta)
library(greta.gam)
library(testthat)

#' `greta.gam` builds its model from `mgcv::jagam()`, which writes this prior
#' for the smoothing parameters:

set.seed(2026-07-29)
dat <- gamSim(1, n = 200, verbose = FALSE)
jf <- tempfile(fileext = ".jags")
invisible(jagam(y ~ s(x2), data = dat, file = jf, diagonalize = FALSE))
grep("lambda", readLines(jf, warn = FALSE), value = TRUE)[2]

#' ## What I expect
#'
#' JAGS `dgamma()` is (shape, rate) and greta's `gamma()` is (shape, rate), so
#' the faithful translation is `gamma(0.05, 0.005)` and the two should agree.
#'
#' ## What happens instead
#'
#' `greta.gam` writes the rate as `1 / 0.005` instead
#' ([`jagam2greta.R#L71`](https://github.com/greta-dev/greta.gam/blob/653a7012fe4abe551ec1a6b885fef763af6b9e1e/R/jagam2greta.R#L71)):

grep("sp <- sp", deparse(greta.gam:::jagam2greta), value = TRUE)

#' The consequence, from `greta.gam` itself rather than a reconstruction.
#' `jagam2greta()` returns the smooth coefficients, whose prior is built from
#' that `sp`, so draw from it:

dat <- gamSim(1, n = 100, verbose = FALSE)
jg <- greta.gam:::jagam2greta(~ s(x2), data = dat)

# retry across seeds: drawing from this prior hits the same MatrixInverse
# failure as the separate crash issue, on roughly 2 seeds in 5
draw_prior <- function(tries = 8) {
  for (s in seq_len(tries)) {
    b <- try(calculate(jg$betas, nsim = 2000, seed = s), silent = TRUE)
    if (!inherits(b, "try-error")) return(as.numeric(b[[1]]))
  }
  NULL
}
b <- draw_prior()

if (is.null(b)) {
  "could not draw from the prior in 8 attempts (MatrixInverse)"
} else {
  c(finite = mean(is.finite(b)),
    prior_sd = sd(b[is.finite(b)]),
    sd_of_y = sd(dat$y))
}

#' **The failure is the finding.** On some datasets every attempt fails, on
#' others roughly 2 in 5 do — you cannot reliably draw from `greta.gam`'s own
#' prior, because building the coefficients needs `solve(K)` and a prior draw of
#' `sp` this small makes `K` singular. That is the separate `MatrixInverse`
#' issue, and it has to be fixed before this one can be characterised properly.
#'
#' When a draw does succeed, the prior standard deviation of the smooth
#' coefficients is of order 1e26, against a response with sd about 4, and around
#' 1% of draws are not finite. Those coefficients multiply the design matrix to
#' produce something on the scale of `y`.
#'
#' The arithmetic behind that, for reference:

expected <- mean(calculate(gamma(0.05, 0.005), nsim = 2e5, seed = 1)[[1]])
actual <- mean(calculate(gamma(0.05, 1 / 0.005), nsim = 2e5, seed = 1)[[1]])

all.equal(expected, actual)

c(expected = expected, actual = actual)

expected / actual

#' ## Why it happens
#'
#' The `1 /` reparameterises the rate as a **scale**. Instead of passing the
#' rate `0.005`, it passes `1 / 0.005`, which is the corresponding scale, 200 —
#' into an argument that greta reads as a rate.
#'
#' In general, for `Gamma(shape = a, rate = b)`:
#'
#'     mean          = a / b
#'     scale         = 1 / b
#'     mean if you pass the scale where the rate goes
#'                   = a / (1 / b) = a * b
#'
#' so the mean is out by a factor of
#'
#'     (a / b) / (a * b) = 1 / b^2

1 / 0.005^2

#' The factor depends only on the rate, not the shape. It happens to be 40,000
#' here because `jagam`'s rate is 0.005; a rate of 0.1 would be out by 100.
#'
#' ## Why this is a problem
#'
#' `sp` is the penalty on the smooth coefficients: a larger `sp` shrinks the
#' smooth toward the linear nullspace, a smaller `sp` lets it wiggle. A prior
#' mean 40,000 times too small expresses far weaker shrinkage than `jagam`
#' intends, and the implied prior standard deviation on the coefficients comes
#' out around 200 times too large.
#'
#' This is a prior nobody chose. Users following `greta.gam`'s documentation
#' believe they are getting `jagam`'s default and silently are not.
#'
#' What the fix would change. Draw from both priors and look at where they put
#' their mass:

wrong <- calculate(gamma(0.05, 1 / 0.005), nsim = 1e5, seed = 1)[[1]]
right <- calculate(gamma(0.05, 0.005), nsim = 1e5, seed = 1)[[1]]

q <- c(0.5, 0.9, 0.99)
rbind(current = quantile(wrong, q), intended = quantile(right, q))

c(current = mean(wrong < 1), intended = mean(right < 1))

#' Both on the same axes. `sp` spans many orders of magnitude, so on `log10`:

plot(
  density(log10(right)),
  col = "#4A3163", lwd = 2, xlim = c(-30, 5), bty = "n",
  main = "prior on the smoothing parameter", xlab = "log10(sp)"
)
lines(density(log10(wrong)), col = "#C0392B", lwd = 2, lty = 2)
abline(v = 0, col = "grey70", lty = 3)
legend(
  "topleft", bty = "n", lwd = 2, lty = c(2, 1),
  col = c("#C0392B", "#4A3163"),
  legend = c("current: gamma(0.05, 1/0.005)", "intended: gamma(0.05, 0.005)")
)

#' The shapes are identical — both are `gamma(0.05, .)` — but the whole
#' distribution is shifted left by `log10(40000)`, about 4.6. The dotted line is
#' `sp = 1`. The current prior's mass sits entirely to the left of it; the
#' intended one straddles it.
#'
#' Under the current prior **every** draw of `sp` is below 1, and the 99th
#' percentile is 0.005. The prior effectively asserts there is no penalty at
#' all, so the smooth is unconstrained a priori. The intended prior still
#' favours small penalties — 79% of draws below 1 — but leaves real mass on
#' values that shrink, out to 213 at the 99th percentile.
#'
#' So this is not a small shift in a hyperparameter. It is the difference
#' between a prior that can express shrinkage and one that cannot.
#'
#' ### End to end, against `mgcv::gam()`
#'
#' The prior comparison above is arithmetic. This is the package as a user would
#' actually run it, fitting the same smooth both ways:

# fit the same smooth both ways, returning the fitted values
fit_both <- function(dat) {
  pred_mgcv <- predict(gam(y ~ s(x2), data = dat))

  # retry: unrelated to this issue, greta.gam models fail about half the time
  # on the MatrixInverse bug. That issue has to be fixed before this one can be
  # checked reliably.
  for (i in 1:12) {
    z <- smooths(~ s(x2), data = dat)
    sd_obs <- cauchy(0, 1, truncation = c(0, Inf))
    distribution(dat$y) <- normal(z, sd_obs)
    draws <- try(
      mcmc(model(sd_obs), n_samples = 100, warmup = 200, chains = 1, verbose = FALSE),
      silent = TRUE
    )
    if (!inherits(draws, "try-error")) break
  }
  list(mgcv = pred_mgcv, greta = colMeans(as.matrix(calculate(z, values = draws)[[1]])))
}

summarise <- function(f) {
  c(
    sd_mgcv = sd(f$mgcv),
    sd_greta = sd(f$greta),
    rmse = sqrt(mean((f$greta - f$mgcv)^2))
  )
}

d200 <- gamSim(1, n = 200, verbose = FALSE)
d40 <- gamSim(1, n = 40, verbose = FALSE)
f200 <- fit_both(d200)
f40 <- fit_both(d40)

rbind(`n = 200` = summarise(f200), `n = 40` = summarise(f40))

#' And the fits themselves, at the sample size where it bites:

o <- order(d40$x2)
plot(d40$x2, d40$y, pch = 16, col = grey(0.6, 0.6), bty = "n",
     xlab = "x2", ylab = "y", main = "same smooth, both packages (n = 40)")
lines(d40$x2[o], f40$mgcv[o], col = "#4A3163", lwd = 3)
lines(d40$x2[o], f40$greta[o], col = "#C0392B", lwd = 3, lty = 2)
legend("topright", bty = "n", lwd = 3, lty = c(1, 2),
       col = c("#4A3163", "#C0392B"), legend = c("mgcv::gam()", "greta.gam"))

#' greta's fit is attenuated rather than wiggly: flatter at the peak near
#' x = 0.22, and it misses the second bump near x = 0.55 that `mgcv` picks up.

#' ### Stress test: when does it actually matter?
#'
#' At `n = 200` the current fit and `mgcv` agree closely — sd 3.04 against 3.03,
#' RMSE 0.24. The likelihood swamps the prior and a user sees nothing wrong. At
#' `n = 40` the RMSE is 4.5 times larger. So the impact scales with how much
#' work the prior has to do: small samples, sparse regions, many basis functions
#' relative to the data.
#'
#' ### The fix, against the broken result
#'
#' `smooths()` will not forward `sp` (separate issue), but `jagam2greta()` does,
#' so the corrected prior can be supplied without patching anything:

fit_with <- function(dat, sp = NULL) {
  for (i in 1:15) {
    jg <- if (is.null(sp)) {
      greta.gam:::jagam2greta(~ s(x2), data = dat)
    } else {
      greta.gam:::jagam2greta(~ s(x2), data = dat, sp = sp)
    }
    z <- with(jg, X %*% betas)
    s <- cauchy(0, 1, truncation = c(0, Inf))
    distribution(dat$y) <- normal(z, s)
    d <- try(
      mcmc(model(s), n_samples = 100, warmup = 200, chains = 1, verbose = FALSE),
      silent = TRUE
    )
    if (!inherits(d, "try-error")) {
      return(colMeans(as.matrix(calculate(z, values = d)[[1]])))
    }
  }
  stop("all attempts failed")
}

d40 <- gamSim(1, n = 40, verbose = FALSE)
p_mgcv <- predict(gam(y ~ s(x2), data = d40))
p_current <- fit_with(d40)
p_fixed <- fit_with(d40, sp = gamma(0.05, 0.005, dim = 2))

o <- order(d40$x2)
plot(d40$x2, d40$y, pch = 16, col = grey(0.6, 0.55), bty = "n",
     xlab = "x2", ylab = "y",
     main = "n = 40: current prior, jagam's prior, and mgcv")
lines(d40$x2[o], p_mgcv[o], col = "#4A3163", lwd = 3)
lines(d40$x2[o], p_current[o], col = "#C0392B", lwd = 3, lty = 2)
lines(d40$x2[o], p_fixed[o], col = "#1E8449", lwd = 3, lty = 3)
legend("topright", bty = "n", lwd = 3, lty = 1:3,
       col = c("#4A3163", "#C0392B", "#1E8449"),
       legend = c("mgcv::gam() (REML)", "greta.gam, current prior",
                  "greta.gam, jagam's prior"))

c(sd_mgcv = sd(p_mgcv), sd_current = sd(p_current), sd_fixed = sd(p_fixed))
c(rmse_current = sqrt(mean((p_current - p_mgcv)^2)),
  rmse_fixed = sqrt(mean((p_fixed - p_mgcv)^2)))

#' **This does not go the way you would expect, and it changes what should be
#' done about it.**
#'
#' `jagam`'s prior shrinks the smooth almost to a straight line at this sample
#' size — sd 2.29 against `mgcv`'s 3.25 — and its RMSE against `mgcv` is 2.63,
#' *worse* than the current broken prior's 1.05. Correcting the rate moves the
#' fit further from `mgcv`, not closer.
#'
#' So the argument for the fix is **fidelity, not accuracy**. `greta.gam`
#' documents itself as using `jagam`'s setup and does not; that is the bug. It
#' is not that the current fits are visibly wrong — at `n = 200` they are fine,
#' and at `n = 40` they are closer to `mgcv` than the corrected version.
#'
#' It also means the fix is a decision, not a one-character change. Three
#' options, and this reprex does not settle which is right:
#'
#' 1. Match `jagam` exactly (`gamma(0.05, 0.005)`) and accept heavier shrinkage
#'    on small samples. Defensible: it is what the docs claim.
#' 2. Keep the current effective prior but document it as `greta.gam`'s own
#'    choice rather than `jagam`'s, and stop implying fidelity.
#' 3. Pick a better-conditioned prior on its merits — `gamma(2, 0.1)`, say —
#'    since a shape of 0.05 spreads draws over ~100 orders of magnitude and is
#'    what makes the penalty matrix singular.
#'
#' Option 3 is the one I would argue for, since it also bears on the separate
#' `MatrixInverse` crash, but that is a maintainer call.
#'
#' ### What it does to a conclusion
#'
#' Someone comparing `greta.gam` to `mgcv::gam()` on a small dataset gets
#' different answers and has to explain the gap. The readings available to them
#' — "the Bayesian fit is more conservative", "MCMC error", "mgcv oversmooths" —
#' are all wrong, and any could be written down as a finding about the data.
#'
#' Anyone reporting a posterior for `sp`, or a credible interval for the smooth,
#' is reporting something conditioned on a prior the package did not intend and
#' never disclosed.
#'
#' ## Fix
#'
#' Change the rate from `1 / 0.005` to `0.005` at
#' [`jagam2greta.R#L71`](https://github.com/greta-dev/greta.gam/blob/653a7012fe4abe551ec1a6b885fef763af6b9e1e/R/jagam2greta.R#L71):

## sp <- sp %||% gamma(0.05, 0.005, dim = 2 * n_smooth_params)

#' This **changes users' priors**, and so their posteriors. It needs a NEWS
#' bullet saying so, not a typo-fix bullet. And see the three options above —
#' matching `jagam` exactly is only one of them.
#'
#' ### Chesterton's fence: why might it be there
#'
#' [`blame`](https://github.com/greta-dev/greta.gam/blame/main/R/jagam2greta.R#L71):
#' it has been there since the first commit that added this file,
#' [`a1687ff`](https://github.com/greta-dev/greta.gam/commit/a1687ff5e9ab682f84ba8ec07be69a99c2076360),
#' whose message is "something that seems to work?". The only later change was
#' cosmetic —
#' [`dc60a32`](https://github.com/greta-dev/greta.gam/commit/dc60a32adcbc62264b8e0b1a00ffd02a1b7c11bd)
#' restyled `1/0.005` to `1 / 0.005` and nothing else:
#'
#'     -    sp <- gamma(0.05, 1/0.005, dim = 2*length(...))
#'     +    sp <- gamma(0.05, 1 / 0.005, dim = 2 * length(...))
#'
#' So it was never deliberately introduced or revisited; it arrived with the
#' original exploratory translation and has only been reformatted since.
#'
#' The most likely reason it was written that way: base R's own gamma functions
#' are parameterised with *both* rate and scale, and the relationship is spelled
#' out in the signature.

args(rgamma)

#' `1/rate` appears literally in base R's signature, so a `1 /` is exactly what
#' you would write while translating `dgamma(.05, .005)` if you believed the
#' target took a scale. greta's `gamma()` does not — it takes a rate and offers
#' no `scale` argument — so the conversion inverts the parameter.
#'
#' A translation slip against a genuinely confusable convention, then, not a
#' deliberate reparameterisation. If it *was* deliberate, the fix is wrong and
#' the `@param` docs need to say the argument is a scale.
#'
#' ## A test for this
#'
#' Assert the prior, not the source line:

test_that("the default sp prior matches jagam's dgamma(.05, .005)", {
  skip_if_not(check_tf_version())
  jg <- jagam2greta(~ s(x2), data = gamSim(1, n = 100, verbose = FALSE))
  draws <- calculate(jg$sp, nsim = 1e5, seed = 1)[[1]]
  # jagam writes dgamma(.05, .005), mean = shape / rate = 10
  expect_equal(mean(draws), 10, tolerance = 0.1)
})

#' A mean is a weak check on a distribution this heavy-tailed, so it is worth
#' asserting a quantile too — `expect_lt(median(draws), 1)` fails against the
#' current code by a factor of 10^8 and would catch a re-inversion immediately.
#'
#' ## Not the crash
#'
#' This is *not* the cause of the intermittent `MatrixInverse` failure. Tested
#' directly: a well-conditioned prior still fails ~42% of runs. Fix this on its
#' own merits.
#'
#' ## Related
#'
#' You cannot work around this by supplying your own `sp`, because `smooths()`
#' accepts the argument and drops it. That is a separate issue.
