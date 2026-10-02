#' `opt()` ignores `adjust = FALSE` for `bfgs()` and `nelder_mead()`: both optimise the adjusted density whatever `adjust` is.
#'
#' The mode of a `lognormal(0, 1)` density is `exp(-1)`, about 0.37. With `adjust = FALSE`, `opt()` should find it; with `adjust = TRUE`, it optimises on the log scale, whose mode is 1.

library(greta)

sd <- lognormal(0, 1)
m <- model(sd)

#' `adam()` gets both right:

opt(m, optimiser = adam(), adjust = TRUE)$par$sd
opt(m, optimiser = adam(), adjust = FALSE)$par$sd

#' `bfgs()` gives 1 either way:

opt(m, optimiser = bfgs(), adjust = TRUE)$par$sd
opt(m, optimiser = bfgs(), adjust = FALSE)$par$sd

#' So does `nelder_mead()`, shown with two parameters since it errors on a model with one (a separate problem):

a <- lognormal(0, 1)
b <- lognormal(0, 1)
m2 <- model(a, b)
unlist(opt(m2, optimiser = nelder_mead(), adjust = FALSE)$par)

#' Both branches of the `if` in `tfp_optimiser` use `$adjusted`:
#'
#' https://github.com/greta-dev/greta/blob/179021a818cd7282896c42b03814a53556c1d98d/R/optimiser_class.R#L219-L227
#'
#' The fix is `$unadjusted` in the `else` branch. Any `bfgs()` or `nelder_mead()` fit with `adjust = FALSE` on a constrained parameter (positive, bounded, a simplex, a correlation matrix) has returned the wrong estimate, with no warning. Unconstrained parameters are unaffected, since there the two densities are the same.
