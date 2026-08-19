# Issue #557 — explore {bundle} for storing greta models

[{bundle}](https://github.com/rstudio/bundle) is the tidymodels-adjacent
standard for serialising fitted model objects so they survive a fresh R
session / worker. A greta model that is reload-safe is, by definition,
bundle-able.

## Approach

Once #595 lands, `saveRDS()`/`readRDS()` already round-trips a greta
model (the accessor rebuilds Python on access), so a `bundle` method is
a thin adapter that declares the greta model as its own native-format
payload:

1. Implement S3 methods `bundle.greta_model()` and the matching
   `unbundle()` behaviour, following the {bundle} vignette's "package
   author" contract (a `bundle` method that returns a `bundled_*` object
   wrapping the serialised model plus a `situate`/rehydrate step).
2. For greta the "rehydrate" step is a no-op beyond `readRDS` semantics:
   the model's Python side is rebuilt lazily by the #595 accessor on
   first use, so `unbundle()` just returns the deserialised
   `greta_model` and optionally calls `awaken_greta_model()` eagerly.
3. Ship {bundle} as `Suggests`, with the method registered via
   `.onLoad`/`vctrs`-style conditional registration so greta does not
   hard-depend on it.

## Files / functions touched

- New `R/bundle.R` — `bundle.greta_model()` / rehydrate; register in
  `NAMESPACE` conditionally.
- `DESCRIPTION` — add `bundle` to `Suggests`.
- Reuses `awaken_greta_model()` and the `py_xptr_stale()` accessor from
  #595.

## Acceptance test

`tests/testthat/test-bundle.R`, round-trip through a clean process:

```r
test_that("a greta model survives bundle/unbundle in a fresh session", {
  skip_if_not(check_tf_version())
  skip_if_not_installed("bundle")
  tmp <- withr::local_tempfile(fileext = ".rds")
  local({
    mu <- normal(0, 1)
    y <- as_data(rnorm(10))
    distribution(y) <- normal(mu, 1)
    saveRDS(bundle::bundle(model(mu)), tmp)
  })
  ok <- callr::r(function(path) {
    library(greta)
    m <- bundle::unbundle(readRDS(path))
    d <- mcmc(m, n_samples = 20, warmup = 20, verbose = FALSE)
    inherits(d, "greta_mcmc_list")
  }, args = list(path = tmp))
  expect_true(ok)
})
```

## Dependencies

- **Blocked by #595** — without reload-safety the
  bundle method has nothing to lean on.
- Independent of everything else.

## Risk / effort

Low. Small adapter once #595 is in; main effort is matching the {bundle}
method contract and conditional registration.
