#' `smooths()` accepts `sp` and `knots` and then silently ignores them.
#'
#' Found while writing up the default `sp` prior being 40,000 times too small.
#' The two compound: the default prior is wrong, and this is why you cannot
#' override it.

library(greta)
library(greta.gam)
library(mgcv)
library(testthat)

set.seed(2026-07-29)
d <- gamSim(1, n = 100, verbose = FALSE)

#' ## What I expect
#'
#' `?smooths` documents `sp` as "smoothing parameter", and `jagam2greta()`
#' accepts it, so fixing it at a large value should shrink the smooth hard and
#' remove the smoothing parameters from the model.
#'
#' ## What happens instead

default <- smooths(~ s(x2), data = d)
fixed_sp <- smooths(~ s(x2), data = d, sp = c(1e6, 1e6))

identical(dim(default), dim(fixed_sp))

n_nodes <- function(z) length(model(z)$dag$node_list)
c(default = n_nodes(default), fixed_sp = n_nodes(fixed_sp))

#' Identical models. `sp` had no effect at all. Same for `knots`.
#'
#' ## Why it happens
#'
#' `smooths()` takes both arguments
#' ([`smooths.R#L76-L80`](https://github.com/greta-dev/greta.gam/blob/653a7012fe4abe551ec1a6b885fef763af6b9e1e/R/smooths.R#L76-L80)):

## smooths <- function(formula,
##                     data = list(),
##                     knots = NULL,
##                     sp = NULL,
##                     tol = 0) {

#' and then calls `jagam2greta()` without them
#' ([`smooths.R#L85-L89`](https://github.com/greta-dev/greta.gam/blob/653a7012fe4abe551ec1a6b885fef763af6b9e1e/R/smooths.R#L85-L89)):

## jg <- jagam2greta(
##   formula,
##   data = data,
##   tol = tol
## )

#' `jagam2greta()` itself takes `sp` and `knots`
#' ([`jagam2greta.R#L36-L41`](https://github.com/greta-dev/greta.gam/blob/653a7012fe4abe551ec1a6b885fef763af6b9e1e/R/jagam2greta.R#L36-L41)) and
#' uses them. So the machinery exists; the wrapper never passes anything to it.
#'
#' ## Why this is a problem
#'
#' Two documented arguments do nothing, with no error and no warning. A user
#' who sets `sp` to control wiggliness — the main reason anyone reaches for it —
#' gets the default fit back and no indication why.
#'
#' It also removes the only workaround for the default `sp` prior being wrong
#' (separate issue): even a user who knows the default is off cannot supply
#' their own.
#'
#' `knots` is the same story, and matters for anyone wanting to control basis
#' placement, for cyclic smooths in particular.
#'
#' What the fix would change. Reaching past the wrapper and calling
#' `jagam2greta()` directly, with the same `sp`, gives the model the user was
#' asking for:

jg <- greta.gam:::jagam2greta(~ s(x2), data = d, sp = c(1e6, 1e6))
direct <- with(jg, X %*% betas)

c(via_smooths = n_nodes(fixed_sp), via_jagam2greta = n_nodes(direct))

#' 14 nodes rather than 33: the smoothing parameters are fixed, so they are no
#' longer free variables in the model. That is the behaviour `sp` is documented
#' to give, and it is already implemented — the wrapper simply never asks for
#' it.
#'
#' ## Fix
#'
#' Forward them:

## jg <- jagam2greta(
##   formula,
##   data = data,
##   sp = sp,
##   knots = knots,
##   tol = tol
## )

#' ### Chesterton's fence: why might it be there
#'
#' It never was. `sp = sp` has never appeared in `R/smooths.R`:
#'
#'     git log -S"sp = sp" -- R/smooths.R
#'     (no commits)
#'
#' So this is an omission rather than a deliberate removal — the arguments were
#' put in the signature and documented, and the wiring was never added. Nothing
#' is being taken away by fixing it.
#'
#' One thing to check before merging: `jagam2greta()` passes `sp` on to
#' `mgcv::jagam()`, so a user-supplied value needs validating for length and
#' type first. [#5](https://github.com/greta-dev/greta.gam/issues/5) anticipated exactly this — Golding's note there was to "check
#' the dimensions and error informatively if incorrect", since a user cannot
#' easily know the required specification. That check does not exist yet, and
#' forwarding without it turns a silent no-op into a confusing `jagam` error.
#'
#' ### What it does to a conclusion
#'
#' Fixing `sp` is how you check whether a result is driven by the data or by the
#' smoothing prior — refit at a few fixed penalties and see what moves. Right
#' now that check silently returns the same fit every time, so it looks like the
#' result is robust to the smoothing parameter when in fact the parameter was
#' never changed. A sensitivity analysis that cannot fail is worse than none.
#'
#' ## A test for this
#'
#' The assertion is that supplying `sp` changes the model:

test_that("smooths() forwards sp to jagam2greta()", {
  skip_if_not(check_tf_version())
  d <- gamSim(1, n = 100, verbose = FALSE)
  n_nodes <- function(z) length(model(z)$dag$node_list)
  free  <- smooths(~ s(x2), data = d)
  fixed <- smooths(~ s(x2), data = d, sp = c(1e6, 1e6))
  # fixing sp removes the smoothing parameters as free variables
  expect_lt(n_nodes(fixed), n_nodes(free))
})

#' `expect_lt` rather than an exact count, so the test survives unrelated
#' changes to how many nodes a smooth builds. A matching test for `knots` is
#' worth adding at the same time, since it is dropped by the same line.
#'
#' ## Related
#'
#' - [#5](https://github.com/greta-dev/greta.gam/issues/5) (closed) asked for `sp` support in `jagam2greta()`. It was added there
#'   and works. This issue is that `smooths()` never uses it, which is why the
#'   feature is unreachable from the documented interface.
#' - The default `sp` prior is separately wrong by a factor of 40,000.
