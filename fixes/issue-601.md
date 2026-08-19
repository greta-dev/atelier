# Issue #601 — plotting a reloaded model doesn't always work

After `saveRDS()` + reload (and the current hand-written
`awaken_greta_model()` step), `plot(m)` sometimes fails because the plot
path reaches into dag state that still holds a dead Python handle.

## Approach

`plot.greta_model` (`R/greta_model_class.R:154`) itself mostly reads
structural R data — `x$dag$adjacency_matrix`, `x$dag$node_list`,
`x$dag$node_types`, node `plotting_label()`s (`:158-196`) — none of
which need Python. The failure comes from any lazy field on the dag that
triggers a tf touch when first accessed on a reloaded object. The fix is
to ensure the plot path never dereferences a Python handle:

1. Confirm (ast-grep over `plot.greta_model`) that plotting only touches
   R-side structure; if any branch reads a tf handle, route it through
   the #595 self-healing accessor so it rebuilds instead of erroring.
2. Guarantee `adjacency_matrix`/`node_types` are computed from the node
   list (pure R) and are populated on a reloaded dag without a live
   Python session.

Net effect: `plot()` on a reloaded model works with no `awaken` call.

## Files / functions touched

- `R/greta_model_class.R:154-210` — `plot.greta_model`.
- `R/dag_class.R` — `adjacency_matrix` accessor and any lazily-built
  field the plot reads; ensure it is Python-free or accessor-guarded
  (depends on #595).

## Acceptance test

Folded into the #595 callr round-trip (the `ok_plot` assertion): after
reload in a fresh process, `plot(m)` returns a `grViz` htmlwidget with no
error. A focused test:

```r
test_that("plot works on a model reloaded in a clean session", {
  skip_if_not(check_tf_version())
  tmp <- withr::local_tempfile(fileext = ".rds")
  local({
    y <- as_data(rnorm(5)); mu <- normal(0, 1)
    distribution(y) <- normal(mu, 1)
    saveRDS(model(mu), tmp)
  })
  ok <- callr::r(function(path) {
    library(greta)
    inherits(plot(readRDS(path)), "grViz")
  }, args = list(path = tmp))
  expect_true(ok)
})
```

## Dependencies

- **Rides on #595** — if plotting turns out to be
  entirely Python-free it becomes independent, but the reload guarantee
  is cleanest expressed through the same accessor.
- Otherwise independent.

## Risk / effort

Low. Likely a one- or two-line guard plus a confirming test.
