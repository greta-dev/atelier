# Issue #739 — data interface into the log-prob function

Provide a way to swap the data feeding a model without rebuilding the
whole model. This is the enabling hook for cheaper Geweke tests (the
originating context), model reuse (#181), and pointwise log-likelihood
for information criteria (#519).

## Approach

Data enters the graph as data nodes (`R/node_types.R`), and each data
node carries a "using constants" flag that already distinguishes baked-in
constants from swappable data (noted in the issue). The fix parameterises
the compiled log-prob closure by its data inputs instead of closing over
them:

1. When generating the log-prob function
   (`define_tf_log_prob_function()` → `generate_log_prob_function()`,
   `R/dag_class.R:50-56`), expose the model's (non-constant) data nodes
   as explicit arguments/placeholders of the traced function rather than
   constants captured at trace time.
2. Add a public entry point that evaluates log-prob (or traces values)
   with a supplied data list, feeding the placeholders — so `mcmc()`,
   Geweke tests, and `calculate()` can re-point data without a rebuild.
3. This is exactly the seam that naming the `(log_prob, gradient)`
   boundary would define. The clean place to parameterise by data is that
   boundary, so #739 should be built on top of it rather than
   retrofitting the current ad-hoc log-prob wiring.

**Dependency to flag:** #739's natural implementation sits on top of the
sampler-interface boundary, so it wants that settled first. If #519 (info
criteria) is wanted sooner, pull just the data/log-lik hook forward as a
narrow feature ahead of the full boundary work.

## Files / functions touched

- `R/dag_class.R:50-56` — `define_tf_log_prob_function()` /
  `generate_log_prob_function()`: turn swappable data into function
  arguments.
- `R/node_types.R` — data node "using constants" flag drives which nodes
  become swappable inputs.
- New public evaluate-with-data entry point (shape decided by the sampler-interface
  sampler interface).

## Acceptance test

`tests/testthat/test-data-hook.R`:

```r
test_that("log-prob can be re-evaluated with swapped data, no rebuild", {
  skip_if_not(check_tf_version())
  y <- as_data(rnorm(10)); mu <- normal(0, 1)
  distribution(y) <- normal(mu, 1)
  m <- model(mu)
  lp1 <- m$dag$evaluate_log_prob_function_with_data(
    free_state = 0, data = list(y = rnorm(10)))
  lp2 <- m$dag$evaluate_log_prob_function_with_data(
    free_state = 0, data = list(y = rnorm(10)))
  expect_false(isTRUE(all.equal(lp1, lp2)))  # different data -> different lp
})
```

(Exact API name follows the sampler-interface boundary.)

## Dependencies

- **Wants the sampler-interface boundary settled first** — flagged above.
- **Blocks #519** (info criteria need this pointwise-data/log-lik hook)
  and is the enabler for #181 (model reuse).
- Independent of the #595 self-healing work.

## Risk / effort

Medium-high, and gated on the sampler-interface boundary. The narrow "pull the data hook forward"
option is medium if only #519 needs it soon.
