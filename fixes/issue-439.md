# Issue #439 — extract MCMC behaviour from a fitted model

Users want to read the sampler's adaptation behaviour (final step
size/`epsilon`, acceptance rate, mass-matrix/`diag_sd`, numerical
rejections, per-iteration accept history) off a fitted `greta_mcmc_list`.
Today these live buried in the R6 sampler object.

## Approach

The sampler already accumulates exactly these quantities as fields on
`sampler_class` (`R/sampler_class.R`):

- `numerical_rejections` (`:10`)
- `mean_accept_stat` / `accept_history` / `accept_target` (`:15,:26,:27`)
- `sum_epsilon_trace` / `log_epsilon_bar` (`:16,:18`) — the tuned step size
- `welford_state` (`:21`) — running posterior mean/variance
- `parameters$epsilon` / `parameters$diag_sd` (`:31,:32`) — tuning params
- `tune_epsilon()` / `tune_diag_sd()` (`:411`, `:439`)

The mcmc object already carries a handle to its samplers via
`get_model_info(draws)` (used by `extra_samples()` at
`R/inference.R:496`). So the fix is a public accessor that reads these
off the stored samplers and returns them as a tidy per-chain structure:

```r
# R/greta_mcmc_list.R (new, exported)
mcmc_diagnostics <- function(draws) {
  info <- get_model_info(draws)
  lapply(info$samplers, function(s) {
    list(
      epsilon = exp(s$log_epsilon_bar),
      diag_sd = s$parameters$diag_sd,
      accept_rate = s$mean_accept_stat,
      numerical_rejections = s$numerical_rejections,
      accept_history = s$accept_history
    )
  })
}
```

Return a data.frame (one row per chain) so it composes with the
tidyverse article (#257). This is read-only reporting — no change to
sampling.

## Files / functions touched

- `R/greta_mcmc_list.R` — new exported `mcmc_diagnostics()` (or
  `sampler_stats()`), roxygen, NEWS bullet.
- Reads existing fields on `R/sampler_class.R` (`:10-32`); reuses
  `get_model_info()` plumbing from `R/inference.R`.

## Acceptance test

`tests/testthat/test-mcmc-diagnostics.R`:

```r
test_that("mcmc_diagnostics reports step size and accept rate", {
  skip_if_not(check_tf_version())
  mu <- normal(0, 1)
  y <- as_data(rnorm(20))
  distribution(y) <- normal(mu, 1)
  d <- mcmc(model(mu), chains = 2, n_samples = 100, warmup = 100,
            verbose = FALSE)
  diag <- mcmc_diagnostics(d)
  expect_equal(nrow(as.data.frame(diag)), 2)      # one row per chain
  expect_true(all(diag$epsilon > 0))
  expect_true(all(diag$accept_rate >= 0 & diag$accept_rate <= 1))
})
```

## Dependencies

- Independent of the #595 self-healing work.
- **Soft tie to the sampler-interface work**: naming the sampler/mcmc
  boundary may relocate or rename these fields. Building
  `mcmc_diagnostics()` now against the current field names is fine, but the
  accessor should be revisited once that boundary settles, so as not to
  bake in field names it will move.
- Orthogonal to all ecosystem/community items.

## Risk / effort

Low. Pure read-side accessor over fields that already exist; main care
is choosing a stable return shape that survives the sampler-interface work.

## Correction: there is one sampler object, not one per chain

This document proposes a per-chain return shape built on
`lapply(info$samplers, ...)`. That yields a **single element**: greta has one
sampler object serving all chains, not one per chain. The acceptance test's
`expect_equal(nrow(as.data.frame(diag)), 2)` ("one row per chain") therefore
fails.

`mean_accept_stat` and `log_epsilon_bar` are scalars shared across chains. The
only genuinely per-chain quantity is `accept_history` (iterations x chains), so
per-chain values have to be *derived* - `colMeans(accept_history)`.

Related trap: the raw `mean_accept_stat` reads 0.042 against an
`accept_target` of 0.651. It is not a run-level acceptance rate, and exposing
it as one would have users conclude their sampler is broken.
