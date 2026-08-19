# Issue #728 — `calculate()` errors on a mixture distribution

## Approach

`calculate(weights, values = fit, nsim = 10)` on a model containing a
`mixture()` throws `argument is of length zero`.

**The failure is in the DAG definition, not in sampling.** An earlier version of
this document blamed the mixture node's `sample()` closure in `R/mixture.R`;
that was checked by running it and is wrong. The model never gets as far as
sampling. `how_to_define_hybrid()` in `R/dag_class.R` aborts first:

```r
# R/dag_class.R, inside `if (node_type == "distribution")`
target <- node$target
target_type <- node_type(target)

# a mixture distribution has no target, so this sets sampling mode ...
if (is.null(target)) {
  node_mode <- "sampling"
}

# ... but does not skip what follows, and node_type(NULL) is character(0),
# so this evaluates `if (character(0) == "data")` -> argument is of length zero
if (target_type == "data") {
  node_mode <- "sampling"
}
```

A mixture distribution node has a `NULL` target. `node_type(NULL)` returns
`character(0)`, `character(0) == "data"` returns `logical(0)`, and `if
(logical(0))` is the error. The `is.null(target)` branch above *sets*
`node_mode` but falls through to the checks below rather than short-circuiting.

**The fix** is to make those four branches mutually exclusive — an
`if` / `else if` chain rather than four independent `if`s — so a `NULL` target
stops after the first. Nothing in `R/mixture.R` needs to change.

## Files / functions touched

- `R/dag_class.R` — `how_to_define_hybrid()`, the four `if` blocks inside the
  `node_type == "distribution"` branch (around lines 158-180 on `main`).
  Convert to `if` / `else if`.
- `R/mixture.R` — **no change needed.** The `sample` closure at 235-277 is
  never reached; it was the previous suspect and is not the cause.
- `R/calculate.R` — no change expected, but the stochastic branch
  (`calculate_greta_mcmc_list`, `R/calculate.R:275`; `stochastic` at
  `R/calculate.R:402`) is the caller to test against.

## Acceptance test

Add to `tests/testthat/test_calculate.R`:

```r
test_that("calculate() works on a mixture with nsim and values", {
  weights_raw <- uniform(0, 1, dim = 1)
  weights <- c(weights_raw, 1 - weights_raw)
  alpha <- normal(0, 1)
  beta <- normal(0, 1)
  a <- mixture(normal(alpha, 0.5), normal(beta, 0.5), weights = weights)
  m <- model(a)
  fit <- mcmc(m, n_samples = 50, warmup = 50, verbose = FALSE)
  expect_no_error(calculate(weights, values = fit, nsim = 10))
  out <- calculate(weights, values = fit, nsim = 10)
  expect_equal(dim(out[[1]])[1], 10L)
})
```

This is the issue's reprex with a short chain for speed.

## Dependencies

- **Related to #528** (both `mixture()` dimension handling) but on a **different
  function** (`sample()` closure vs `check_weights_dim()`); neither blocks the
  other. Doing #528 first gives a clean single-column mixture to test with.
- Independent of the rest of the plan.

## Risk / effort

Medium. The one-line-symptom hides a shape-handling subtlety; the effort is in
the runtime diagnosis, not the patch. Keep the fix scoped to the scalar/
single-element guard so multivariate and array mixtures (already tested) do not
regress.
