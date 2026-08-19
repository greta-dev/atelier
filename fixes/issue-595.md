# Issue #595 — self-healing Python pointers

Make a greta model survive `saveRDS()` /
`targets` / a parallel worker by rebuilding dead reticulate pointers on
first access, replacing the parallel-only special case with a single
code path.

## Approach

1. Add a pointer-staleness predicate to `dag_class`:

   ```r
   # R/dag_class.R (new)
   py_xptr_stale <- function(x) {
     is.null(x) || reticulate::py_is_null_xptr(x)
   }
   ```

   Named `py_xptr_stale()` (not `tf_stale()`) — see
   `notes/py-stale-naming.md`; it is a thin wrapper over reticulate's
   `py_is_null_xptr()` and is backend-neutral.

2. Route every access to a live Python handle through a self-healing
   accessor that rebuilds the whole tf environment if the handle is
   stale. The rebuild recipe already exists and is exactly what the
   parallel branch runs today:

   - `new_tf_environment()` — `R/dag_class.R:73`
   - `define_tf_trace_values_batch()` — `R/dag_class.R:44`
   - `define_tf_log_prob_function()` — `R/dag_class.R:50`

   ```r
   # R/dag_class.R (new self-healing accessor)
   evaluate_log_prob_function = function(free_state) {
     if (py_xptr_stale(self$tf_log_prob_function)) {
       self$new_tf_environment()
       self$define_tf_trace_values_batch()
       self$define_tf_log_prob_function()
     }
     self$tf_log_prob_function(free_state)
   }
   ```

   Existing direct callers of `self$tf_log_prob_function(...)`
   (`R/dag_class.R:60,64` — `tf_log_prob_function_adjusted/unadjusted`)
   are re-pointed through the accessor.

3. Remove the parallel-only special case at `R/sampler_class.R:122-127`
   (the `if (plan_is$parallel) { dag$define_tf_trace_values_batch();
   dag$define_tf_log_prob_function(); self$define_tf_evaluate_sample_batch() }`
   block). With the accessor, the first log-prob evaluation on any fresh
   Python session (parallel worker, reloaded model, targets) rebuilds
   transparently.

4. Give the sampler the same treatment for
   `tf_evaluate_sample_batch` (`R/sampler_class.R:74` define, `:585`
   field, `:600` call) so sequential `extra_samples()` on reloaded draws
   rebuilds too.

5. Keep an exported `awaken_greta_model()` (users currently hand-write
   it — see the issue and the `example-greta-targets` repo) but make it a
   thin, now-optional wrapper that simply forces one accessor call. It
   stays for backwards compatibility and as the documented `tar_hook`
   entry point, but is no longer required for correctness.

## Files / functions touched

- `R/dag_class.R` — new `py_xptr_stale()`, new
  `evaluate_log_prob_function()` accessor; wrap `:44/:50/:60/:64/:73`.
- `R/sampler_class.R` — self-healing `tf_evaluate_sample_batch`
  accessor (`:74/:585/:600`); delete the parallel branch `:122-127`.
- `R/greta_model_class.R` — `plot.greta_model` (`:154`) reaches the dag
  via the accessor (see #601).
- `R/calculate.R` — `calculate()` builds/traces a dag (`:352,:366`); its
  trace path goes through the accessor (reloaded `calculate()`).
- New exported `awaken_greta_model()` + roxygen.

## Acceptance test

Round-trip through a fresh R process with `callr` (testthat 3, in
`tests/testthat/test-portability.R`):

```r
test_that("a reloaded model rebuilds dead pointers and samples", {
  skip_if_not(check_tf_version())
  tmp <- withr::local_tempfile(fileext = ".rds")
  # build + save in this session
  local({
    y <- as_data(rnorm(10))
    mu <- normal(0, 10)
    distribution(y) <- normal(mu, 1)
    m <- model(mu)
    d <- mcmc(m, n_samples = 50, warmup = 50, verbose = FALSE)
    saveRDS(list(m = m, d = d), tmp)
  })
  # reload in a clean process — Python session is gone
  out <- callr::r(
    function(path) {
      library(greta)
      obj <- readRDS(path)
      d2 <- extra_samples(obj$d, 50, verbose = FALSE)
      cd <- calculate(obj$m$dag$target_nodes[[1]], values = obj$d,
                      nsim = 5)
      p <- plot(obj$m)
      list(ok_extra = coda::niter(d2) > coda::niter(obj$d),
           ok_calc = !is.null(cd),
           ok_plot = inherits(p, "grViz"))
    },
    args = list(path = tmp)
  )
  expect_true(out$ok_extra)
  expect_true(out$ok_calc)
  expect_true(out$ok_plot)
})
```

Plus a real `targets::tar_script()` pipeline test (see #599) and a
"greta and targets" vignette.

## Dependencies

- Upstream: none. This is the enabling fix that #509, #557, #599 and #601
  all depend on.
- Blocks: **#509** (parallel workers), **#557** ({bundle}), **#599**
  (targets imports), **#601** (reloaded plot).
- Complementary to the flat node registry and the backend-neutral
  op-dictionary work (the `py_xptr_*` naming is chosen to survive a
  JAX/torch backend).

## Risk / effort

Medium-high. The predicate and accessor are small, but every handle
consumer must be found and re-pointed (ast-grep for
`self$tf_log_prob_function`, `self$tf_trace_values_batch`,
`self$tf_evaluate_sample_batch`). Main risk: missing a direct-access
call site, which would still hit a dead pointer — the callr round-trip
test is the guard.
