# Issue #257 — tidyverse / tidymodels compatibility

Users want `mcmc()`/`calculate()` output to flow into tidyverse tooling
(tidy data frames, ggplot, tidybayes). The maintainer's stated position
(issue thread) is to keep the return type as the de-facto standard
`coda::mcmc.list` and *not* add arguments to core functions — so the
bridge should be documentation plus small, cheap accessors, not a change
to the return type.

## Approach

1. **A "greta with the tidyverse" vignette** showing the existing bridges:
   `coda::mcmc.list` → `tidybayes::spread_draws()`/`gather_draws()`, and
   `ggmcmc`, on greta draws. This is the bulk of the value and matches
   the maintainer's "beyond the scope of the package" stance.
2. **Small, cheap tidy accessors** where they are one-liners and don't
   bloat the core API:
   - `as.data.frame()` / `tibble::as_tibble()` methods for
     `greta_mcmc_list` that return long tidy draws (chain, iteration,
     parameter, value).
   - Confirm `broom::tidy()` support via a documented recipe (or a
     lightweight `tidy.greta_mcmc_list` if trivial).
3. Compose with #439 (`mcmc_diagnostics()` returns a data frame) and #345
   (`bayes_r2()` returns a posterior vector) so the tidy story is
   coherent.

Keep it proportionate — an article + a couple of S3 methods, no new
arguments on `mcmc()`/`calculate()`.

## Files / functions touched

- New `vignettes/greta-and-the-tidyverse.Rmd`.
- `R/greta_mcmc_list.R` — optional `as_tibble`/`as.data.frame` methods.
- `DESCRIPTION` — `tibble`/`tidybayes` in `Suggests` (article only).

## Acceptance test

`tests/testthat/test-tidy.R`:

```r
test_that("greta draws convert to a tidy data frame", {
  skip_if_not(check_tf_version())
  mu <- normal(0, 1)
  y <- as_data(rnorm(10))
  distribution(y) <- normal(mu, 1)
  d <- mcmc(model(mu), chains = 2, n_samples = 50, warmup = 50,
            verbose = FALSE)
  df <- as.data.frame(d)
  expect_true(all(c("chain", "iteration", "value") %in% names(df)))
  expect_true(is.numeric(df$value))
})
```

Plus the vignette building under `pkgdown` (docs-lane CI).

## Dependencies

- Independent of the #595 self-healing work.
- Light synergy with #439 and #345 (shared tidy return shapes) but no
  hard ordering.

## Risk / effort

Low. Mostly documentation; the S3 methods are thin wrappers over the
existing `mcmc.list` structure.
