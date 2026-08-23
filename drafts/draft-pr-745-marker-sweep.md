Part of #745. Retires 31 of the 38 `TF1/2` code markers, one at a time.

The markers are a design index rather than stale TODOs, so each one was read
against the code it flags, the question answered, and the marker either removed
(question resolved) or repointed at the issue that owns it. Almost all of the
diff is comments; the code changes are the removal of the unused `tf_graph`
field, one rename, and two dead blocks.

## Things found along the way

- **`mcmc()` builds a warmup trace it throws away.** Filed as #834, with the
  measurement in
  [greta.benchmarks/2026-08-20-warmup-trace](https://github.com/greta-dev/greta.benchmarks/tree/main/2026-08-20-warmup-trace).
  Vestigial since Sep 2018, when the Welford accumulator replaced the read it
  fed.
- **`?hmc` gave the wrong cadence for the leapfrog count.** It is not redrawn
  every iteration, and not every `pb_update` either: tuning breaks warmup up
  roughly every 3 iterations. Docs and NEWS corrected.
- **`dag$tf_graph` was a TF1 graph object built for every model and read
  nowhere.** Removed.
- **The `*_data_list` plumbing is write-only.** `get_tf_data_list()` has no
  callers in greta or in greta.dynamics, greta.gp, greta.gam or
  greta.distributions, and removing both writers leaves the suite green. Left in
  place and pointed at #739, which may repurpose the seam.
- **`as_tf_function()` looks dead from inside greta and is not** - it is
  exported through `.internals` and greta.dynamics calls it in six places. The
  marker said it appeared unused, which would have got it deleted.
- **The sampler kernels never touch `free_state`**, despite three markers asking
  where it comes from.
- **`define_free_state()` was dead and both its branches were broken** - the
  `placeholder` branch errors on an undefined variable, and the `variable`
  branch coerces every non-zero initial value to `TRUE`. Removed.

## Not in scope

Ten markers remain, deliberately:

| where | why |
|---|---|
| `utils.R`, `dag_class.R` (2) | the `## TF1/2 retracing` index, until #546 closes |
| `sampler_class.R` (2) | understood and kept, tied to #547 |
| `optimiser_class.R` (2) | the R-side optimiser loop, tied to #547 |
| `greta_model_class.R` (1) | `model(compile = TRUE)` is inert, see #833 |

Every remaining marker is deliberate: each one indexes a question that an open
issue owns.

## Testing

`devtools::test()` at every step, including after each deletion:
`FAIL 0 | WARN 0 | SKIP 2 | PASS 1952`,
unchanged from the branch point. No behaviour change intended - the one
behavioural check that mattered, removing the warmup trace, was verified to give
bit-identical draws before being deferred to #834.
