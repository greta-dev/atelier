#' `zero_inflated_negative_binomial()` documents `pi` as the "proportion of
#' zeros". It is not.
#'
#' Found while reviewing the docs ahead of the first CRAN release, prompted by
#' the question on [#32](https://github.com/greta-dev/greta.distributions/issues/32) of whether a truncated (hurdle) variant should also be
#' offered. No user has reported it; it is the sort of thing that gets reported
#' as "my zero-inflation estimate looks wrong".

library(greta)
library(greta.distributions)
library(testthat)

#' ## What I expect
#'
#' `?zero_inflated_negative_binomial` documents the third argument as:
#'
#'     @param pi proportion of zeros
#'
#' So setting `pi = 0.10`, with the other parameters from the function's own
#' `@examples`, should give 10% zeros.
#'
#' ## What happens instead

size <- 2
prob <- 0.2
pi <- 0.10

zinb <- zero_inflated_negative_binomial(size = size, prob = prob, pi = pi)
mean(calculate(zinb, nsim = 2e5, seed = 1)[[1]] == 0)

#' 13.7%, not 10%.
#'
#' The negative binomial component is untruncated, so it produces zeros of its
#' own on top of the point mass:

pi + (1 - pi) * dnbinom(0, size = size, prob = prob)

dnbinom(0, size = size, prob = prob)

#' So `pi` is the mixing weight on the point mass, not the proportion of zeros.
#' The same wording, and the same problem, apply to `zero_inflated_poisson()`.
#'
#' ## Why this is a problem
#'
#' The gap grows with the base distribution's own `P(0)`, so it is worst exactly
#' where zero inflation is most interesting — count data with many zeros. Nobody
#' gets a warning; the model fits and returns a number.
#'
#' A user fitting `pi` and reporting it as "the proportion of structural zeros"
#' is reporting the wrong quantity, and a user *setting* `pi` to match an
#' observed zero fraction is setting it too high. Neither error is visible from
#' the output.
#'
#' It also decides which of two models a reader thinks they have. Under the
#' hurdle reading, `P(Y = 0) = pi` exactly, and that is precisely what the
#' current `@param` promises. Getting a first CRAN release out with that wording
#' bakes the confusion in.
#'
#' What a correct `@param` would let a user do. To actually get a target
#' proportion of zeros, they have to subtract the negative binomial's own
#' contribution and rescale:
#'
#'     pi = (target - dnbinom(0, size, prob)) / (1 - dnbinom(0, size, prob))

target <- 0.10
p0 <- dnbinom(0, size = size, prob = prob)
pi_needed <- (target - p0) / (1 - p0)
pi_needed

z <- zero_inflated_negative_binomial(size = size, prob = prob, pi = pi_needed)
mean(calculate(z, nsim = 2e5, seed = 1)[[1]] == 0)

#' So the value needed for 10% zeros is 0.0625, not 0.10. That is a calculation
#' nobody can derive from the current documentation, because it never says the
#' negative binomial contributes zeros of its own.
#'
#' The fix is documentation only — the density is right. But it is the
#' difference between a user being able to work this out and not.
#'
#' ### What it does to a conclusion
#'
#' Zero inflation is usually fitted *because* the excess zeros are the question:
#' unoccupied sites, non-detections, structural zeros. `pi` is the quantity that
#' gets reported.
#'
#' Under the current documentation a fitted `pi` of 0.10 is written down as "10%
#' of sites are structurally unoccupied". The model says 13.7% of observations
#' are zero, of which 10 percentage points are structural and 3.7 are the count
#' process producing zeros of its own. Those are different claims about the
#' ecology, and the gap widens as the counts get sparser — exactly the regime
#' where the model gets used.
#'
#' ## A test for this
#'
#' The density is correct, so the test is that the documented relationship holds
#' — which pins the parameterisation against a future change to a hurdle form:

test_that("pi is the inflation weight, not the proportion of zeros", {
  skip_if_not(check_tf_version())
  size <- 2; prob <- 0.2; pi <- 0.1
  z <- zero_inflated_negative_binomial(size, prob, pi)
  p_zero <- mean(calculate(z, nsim = 2e5, seed = 1)[[1]] == 0)
  expect_equal(p_zero, pi + (1 - pi) * dnbinom(0, size, prob), tolerance = 0.01)
  # and explicitly *not* the hurdle form
  expect_gt(p_zero, pi)
})

#' The second assertion is the useful one: it fails if anyone later swaps the
#' untruncated negative binomial for a truncated one without updating the docs.
#'
#' ## The wider point
#'
#' This is the zero-inflated *mixture*: a point mass at zero plus a
#' distribution that can already produce zeros.
#'
#' The alternative — a point mass plus a negative binomial truncated from 1, so
#' that `P(Y = 0) = pi` exactly — is the **hurdle** model. Different model, not
#' a reparameterisation. Nothing on the help page says which one you get, and
#' `pi` reads naturally as "the proportion of zeros" under the hurdle reading,
#' which is exactly what the docs currently claim.
#'
#' ### Chesterton's fence: why might it be there
#'
#' The wording is not load-bearing. `git log -S"proportion of zeros"` finds it
#' only in [`89eb6a2`](https://github.com/greta-dev/greta.distributions/commit/89eb6a2), a commit about exploring `distributional` for sampling —
#' it was written alongside the distribution, not as a considered statement
#' about which parameterisation this is.
#'
#' The distributions themselves came from [#1](https://github.com/greta-dev/greta.distributions/issues/1) and [#2](https://github.com/greta-dev/greta.distributions/issues/2), both closed, and neither
#' discusses the hurdle alternative. [#20](https://github.com/greta-dev/greta.distributions/issues/20) raises that distinction, and does so
#' precisely, but postdates this wording.
#'
#' So there is no earlier decision to overturn. The `@param` says "proportion of
#' zeros" because that is the loose way people describe zero inflation, not
#' because a hurdle model was intended.
#'
#' ## Fix
#'
#' Documentation only, no change to the density.

## #' @param pi the zero-inflation probability: the weight on the point mass at
## #'   zero. This is *not* the overall proportion of zeros, since the negative
## #'   binomial component also produces zeros. See details.

#' Plus an `@details` giving the density:
#'
#'     P(Y = 0) = pi + (1 - pi) * dnbinom(0, size, prob)
#'     P(Y = y) = (1 - pi) * dnbinom(y, size, prob),  y > 0
#'
#' and a cross-reference to [#20](https://github.com/greta-dev/greta.distributions/issues/20), where the hurdle variant is tracked, so a user
#' who wants `P(Y = 0) = pi` exactly knows it is planned rather than missing.
#'
#' Apply the same three changes to `zero_inflated_poisson()`.
