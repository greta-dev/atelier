# Issue #509 — MCMC crash under `future::plan(cluster)` / `(multisession)`

The reported crash is `RuntimeError: Evaluation error: object 'tf' not
found` inside TFP's `sample_chain`/`bootstrap_results`. The worker
process receives a serialised sampler/dag whose closures reference the
`tf` module handle, but the worker's Python session is fresh (or absent)
so the handle is dead and `tf` is unbound — the same dead-pointer cause
as #595, surfacing on a `future` worker.

## Approach

Two parts, in order:

1. **Land #595 first.** Once every handle use goes through the
   self-healing accessor, a worker rebuilds the tf environment
   (`new_tf_environment()` + `define_tf_*`) on its first log-prob
   evaluation instead of relying on the pointer that was serialised from
   the parent. This removes the "object 'tf' not found" failure because
   the worker regenerates the log-prob closure locally where `tf` is
   bound.

2. **Guarantee Python is initialised on the worker before rebuild.** The
   parallel dispatch is `future::future` at `R/inference.R:343` with
   `future::value` collection at `R/inference.R:388-389`; the plan is
   validated in `check_future_plan()` (`R/checkers.R:567`). Add an
   explicit worker-side initialisation step so greta's Python deps are
   loaded on the worker (e.g. force `.onLoad`/`check_tf_version()` inside
   the dispatched future) rather than depending on future's global
   auto-export. This is the greta analogue of mirai's explicit
   dependency passing.

### mirai / future.mirai angle

`future`'s implicit global detection is exactly what makes this fragile:
the `tf` module and greta's stashed environment are not plain globals
future can serialise. The robust direction (recommended follow-up, not a
hard requirement of the fix) is to make the parallel path pass
dependencies explicitly, which mirai enforces by design:

- `future::plan(multisession)` → `mirai::daemons(n)`;
  `future::future(expr)` → `mirai::mirai(expr, .args = list(...))`;
  `future::value(f)` → `m[]`.
- Load greta and initialise Python once per daemon with
  `everywhere(library(greta))` (and a forced Python init), so each
  daemon has a live `tf` before any sampler runs — the failure mode in
  this issue cannot occur.
- greta can offer this without dropping `future`: test and document
  `future.mirai` (a `future` backend backed by mirai daemons), i.e.
  `plan(future.mirai::mirai_multisession)`, giving users mirai's clean
  worker environments through the existing `future` API.

Keep the `future` path working (back-compat) and document the supported
plans; add the mirai path as the recommended parallel backend.

## Files / functions touched

- `R/inference.R:342-389` — the `future::future` dispatch / `future::value`
  collection; add explicit worker-side Python init.
- `R/checkers.R:567` — `check_future_plan()`; extend recognised plans and
  messaging (already rejects `multicore`/fork via
  `test_if_forked_cluster()`).
- `R/sampler_class.R:122-127` — removed by #595 (no longer rebuilds only
  in the parallel branch).
- Docs: `?mcmc` parallel section (`R/inference.R:85-101`) — document
  `plan(multisession)`, `plan(cluster)` (non-fork, local/remote), and
  `future.mirai`.

## Acceptance test

`tests/testthat/test-parallel.R` (testthat 3), run the same tiny model
under each supported plan and assert draws come back:

```r
test_that("mcmc runs under multisession and cluster plans", {
  skip_if_not(check_tf_version())
  skip_on_cran()
  m <- local({
    y <- as_data(rnorm(10)); mu <- normal(0, 10)
    distribution(y) <- normal(mu, 1); model(mu)
  })
  for (p in list(future::multisession, future::cluster)) {
    withr::local_options(future.rng.onMisuse = "ignore")
    old <- future::plan(p, workers = 2)
    withr::defer(future::plan(old))
    d <- mcmc(m, chains = 2, n_samples = 50, warmup = 50,
              verbose = FALSE)
    expect_s3_class(d, "greta_mcmc_list")
    expect_equal(length(d), 2)
  }
})
```

Add an equivalent block under `plan(future.mirai::mirai_multisession)`
guarded by `skip_if_not_installed("future.mirai")`.

## Dependencies

- **Blocked by #595** (self-healing accessors) — this is a direct
  blocker; #509 is essentially the parallel-worker
  acceptance test of #595 plus worker Python init.
- Independent of the ecosystem/community items.
- No hard dependencies; benefits from the backend abstraction work
  only indirectly.

## Risk / effort

Medium. #595 does the heavy lifting; the incremental work is the
worker-side init and CI that actually exercises `multisession`/`cluster`
(slow, `skip_on_cran`). The mirai/`future.mirai` path is optional scope
and can ship as a documented, tested alternative rather than a
replacement.
