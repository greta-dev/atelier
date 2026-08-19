# Issue #345 — Bayesian R-squared helper

Provide the Gelman et al. Bayesian R² for greta model fits. It only
needs the observed response `y` and posterior draws of the linear
predictor on the response scale (`ypred`), both of which the user can
already obtain from `calculate()`.

## Approach

Pure post-processing over draws — no core/DAG change. Implement a helper
that takes a greta array for the predictor and the draws, evaluates the
predictor over the posterior with `calculate()`, and applies the
standard formula:

```r
# R/r_squared.R (new, exported)
bayes_r2 <- function(y_pred, y, draws) {
  # y_pred: a greta array (linear predictor, response scale)
  # draws:  a greta_mcmc_list
  pred <- calculate(y_pred, values = draws)         # draws x n
  pred <- as.matrix(pred[[1]])
  e <- sweep(pred, 2, y)                             # residuals
  var_pred <- apply(pred, 1, var)
  var_e <- apply(e, 1, var)
  var_pred / (var_pred + var_e)                      # one R2 per draw
}
```

Returns a posterior vector of R² (one value per draw) so users can
summarise/plot it. Document that it is meaningful only for GLM(M)-style
models (per the issue discussion). Optionally surface it as an opt-in
column in a draws summary later.

## Files / functions touched

- New `R/r_squared.R` — exported `bayes_r2()`, roxygen, NEWS bullet.
- Uses existing `calculate()` (`R/calculate.R`) — no change there.

## Acceptance test

`tests/testthat/test-r-squared.R`:

```r
test_that("bayes_r2 returns a posterior of R2 in [0, 1]", {
  skip_if_not(check_tf_version())
  x <- rnorm(30); y <- 2 * x + rnorm(30)
  b <- normal(0, 5); mu <- b * as_data(x)
  y_obs <- as_data(y)
  distribution(y_obs) <- normal(mu, 1)
  d <- mcmc(model(b), n_samples = 100, warmup = 100, verbose = FALSE)
  r2 <- bayes_r2(mu, y, d)
  expect_length(r2, 100)
  expect_true(all(r2 >= 0 & r2 <= 1))
})
```

## Dependencies

- Independent. Builds only on `calculate()`, which exists today.
- Orthogonal to the #595 self-healing work and to #519/#739 (those need
  a pointwise log-lik hook; Bayesian R² does not).

## Risk / effort

Low. One small exported function plus a test and a documentation note on
applicability.
