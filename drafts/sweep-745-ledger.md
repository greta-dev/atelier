# #745 TF1/2 marker sweep — ledger

Branch `retire-tf-markers-i745` off [`e8563dae`](https://github.com/greta-dev/greta/commit/e8563dae). Test baseline before any change:
`FAIL 0 | WARN 0 | SKIP 2 | PASS 1952` (skips are the GRETA_GEWEKE gate and
test_distributions.R:304).

38 markers. Rule learned early: "no callers in R/" does NOT mean unused —
`.internals` exposes internals to greta.gp, greta.dynamics, greta.gam and
greta.distributions. Check those four before calling anything dead.

## Cleanup pile — trivial, land together at the end

| Marker | Finding |
|---|---|
| `R/chol2symm.R:39` | **DELETED** 2026-08-23, `449ba347`. `as.greta_array(x)` in `chol2symm.greta_array()` is a no-op: the method is only reachable via `UseMethod()`, so `x` is already a greta array, and `as.greta_array.greta_array()` is `function(x, ...) x`. Verified by running it. Not in `.internals`, no extension uses it, 3 test files cover `chol2symm`. Delete the coercion and the marker. |

## Findings needing an issue

| Marker | Finding | Where it went |
|---|---|---|
| `R/greta_model_class.R:85` | `model(compile=)` is documented as applying XLA JIT compilation but is stored and never read. Inert since [`7e3e81ac`](https://github.com/greta-dev/greta/commit/7e3e81ac) (Jan 2023), which removed its only consumer — the TF1 session-config API — and never replaced it. Wiring it up is 2 lines; doing so takes the suite from `PASS 1952 / FAIL 0` to `PASS 1934 / FAIL 8`, all wishart/LKJ/cholesky. XLA cannot compile the gradients of `FillScaleTriL` or `CorrelationCholesky` **when the batch dimension is dynamic**, which is how greta traces (`shape = list(NULL, n_free)`). Static shape is fine — that cut pins the cause. | **greta#833 already exists** ("Pass `compile` arg through to `jit_compile`", open, no milestone) - this is a **comment** on it, not a new issue. Reprex at `atelier/drafts/draft-issue-833-model-compile-inert.R`. **Now measured** (2026-08-23), which changes the decision: wiring `compile` through makes sampling **4.8% faster** on a plain regression - 816 ms against 858 ms, Welch p = 0.006, 95% CI [9, 55] ms, at 50 iterations per branch. See `greta.benchmarks/2026-08-19-jit-compile-vs-main/results.md`. **The draft still says "there is no speed measurement yet" and must be updated before posting.** Two bugs stopped that script running for four days: `run_branches()` defaulted to `current = TRUE`, so it measured whatever was checked out while labelling it `wire-jit-compile`; and a `calculate()` warm-up passed a node where a greta array was expected. Also: at 10 iterations the effect was unresolvable (27 ms and 62 ms on separate runs against a ~58 ms within-branch sd) - a small run of this comparison is uninformative. So the three-way choice is now: fix the docs, **wire it and skip cholesky/LKJ models** (the option the measurement favours), or deprecate. |
| `R/utils.R:629` (`as_tf_function`) | Redirected to a **greta.dynamics** issue rather than greta: explore replacing `greta:::as_tf_function()` with TF2's `tf_function()`. | drafted at `atelier/drafts/draft-issue-dynamics-as-tf-function.md` |
| `R/sampler_class.R:205` (`# this is the tuning stage, might not need to evaluate / record the parameter values ... so could remove trace here`) | **The marker is right, and it is not a TF1/2 question - it is R-side dead work.** During warmup `self$trace()` runs with the default `values = FALSE`, so parameter values are *already* not evaluated; all it does is `rbind` the burst's free state onto `traced_free_state`, which is scrubbed wholesale at `R/sampler_class.R:234` once warmup ends. Nothing reads it in between: `update_welford()` takes `last_burst_free_states` directly, and `tune()` works off the Welford state and `accept_history`. The abort path is safe too - `stashed_samples()` gates on `nrow(values_draws[[1]]) == 0`, i.e. on `traced_values`, which warmup never fills, so an abort during warmup returns NULLs and the documented *"only samples from the sampling phase will be returned"* still holds. **Verified by removing the call:** full suite unchanged at `FAIL 0 \| WARN 0 \| SKIP 2 \| PASS 1952`, and `traced_free_state` still ends with exactly `n_samples` rows per chain (100 after a warmup of 2000). **Cost scales with `n_free`** (2000 warmup, 100 samples, 2 chains): `n_free=1` 2.06s -> 1.98s (~4%); `n_free=20` 2.16s -> 2.00s (~7%); `n_free=200` 3.23s -> 2.18s (~33%). Repeated `rbind` growth is the mechanism. Note draws cannot be compared for identity because `set.seed()` does not make `mcmc()` reproducible - greta#285/#427. Scripts: `scratchpad/bench_warmup_trace.R`, `scratchpad/sweep_warmup_trace.R`. | **FILED as greta#834** 2026-08-20. Issue text and evidence both live in `greta.benchmarks/2026-08-20-warmup-trace/` (`issue.md`, `run.R`, `results.qmd`, `results.md`, `results.rds`) - deliberately **not** in atelier, so the wording cannot drift from the numbers. Parts 1-2 are run; part 3 (the `{cross}` comparison) skips cleanly until a `drop-warmup-trace` branch exists. **Checked:** removing the call does **not** cost the warmup progress bar - the bar is driven by the burst loop's `completed_iterations`, and the fix removes the trace, not the bursts (verified with `verbose = TRUE`, bar ran 0/200 to 200/200). **Relation to greta#547/#765:** a piece of #547, but #779 (resolving #765) does **not** fix it - it adds `do_warmup <- self$warmup > 0` so warmup can be skipped wholesale, and stubs `tune_tf`/`tune_r`, but never touches the `trace()` call. |
| `R/dag_class.R:238` (`define_free_state()`, carried two `# TF1/2 check` markers) | **DELETED** 2026-08-23, `2daea68b`. Zero callers in greta, tests, or the four extension packages. Both branches were broken: `placeholder` errors on an undefined `free_state`, and `variable` does `vals <- as.logical(vals)`, coercing every non-zero initial value to TRUE. Filing an issue was dropped in favour of deleting - the issue would have described a function nobody calls whose fix is deletion. Draft removed as moot. Suite unchanged at PASS 1952. |
| `R/samplers.R:154` / `:218` (sampler parameter unpacking) | **Refactor candidate, no owning issue.** The old marker at `:233` said "a good portion of this code could be abstracted away". It is right: `hmc` and `rwmh` both unpack the flat `sampler_param_vec` in near-identical blocks. **Careful, they are not identical** - HMC is `length(vec) - 2` and slices `[1]`, `[2:(1 + n)]` because it carries `l` as well as `epsilon`; RWMH is `length(vec) - 1` and slices `[0]`, `[1:(1 + n)]`. An off-by-one extraction would silently mis-slice the diagonal. Also entangled with greta#779, which is already rewriting `define_tf_kernel` dispatch, and with greta#547, which would remove the flat vector entirely by passing parameters as real arguments - so this may dissolve rather than need doing. `:218` still carries a pre-existing `# get it from dag object` note wanting the size to come from the dag rather than be back-derived from the vector length; same thought. | **deferred** - log only, not filed |
| `R/optimiser_class.R:321` (`# TF1/2 todo / get this to work inside TF with TF while loop`) | **No issue exists for this** - searched open and closed; greta#569 (convergence info from TF2 optimisers) is the nearest and is a different question. The optimiser drives its own R-side `while` loop, entirely separate from the sampler's `run_burst` choke point, so greta#547 does **not** cover it: #547 is sampler-scoped in its body (it names warmup and links the old warmup/run_burst code). Two loops affected - `optimiser_class.R:165` in `tf_optimiser` (**8** user-facing optimisers) and `:323` in `tf_compat_optimiser` (**3** more). Only `:323` carries a marker; `:165` has none despite the identical problem. Useful for whoever picks it up: `tfp_optimiser` (the remaining 2 optimisers) already has no R loop - TFP drives the iteration itself - so there is a working in-repo reference for the target shape. | **Drafted, and now scoped as a comment on greta#547 rather than a new issue** (2026-08-23, Nick's call: #547's title, "do more in tensorflow instead of coming back to R repeatedly", covers this; only its body is sampler-specific). Draft at `drafts/draft-issue-optimiser-tf-loop.md`, measurement at `greta.benchmarks/2026-08-22-optimiser-r-loop/`. **Two earlier claims here were wrong and are corrected.** (1) Only `:321` is about the loop; `:239` is ad-hoc if/else dispatch on optimiser name in `tfp_optimiser`, a different question. (2) "Per-iteration cost is flat across model size" was an artefact of benchmarking `normal(0, 1)`. On `inst/examples` models it runs 0.89 ms (`linear`) to 1.40 ms (2000x200 regression), and parameter count is not the driver - `hierarchical_linear` has 6 free parameters and costs more than `multiple_linear`'s 8. The honest claim is a **large fixed floor**, of which the bare round trip is only ~5%; the rest is greta's own R-side loop body. |

## Verified for greta#739: the data lists are removable

`get_tf_data_list()` (`R/dag_class.R:587`) has **zero callers** - not in greta,
not in greta.dynamics, greta.gp, greta.gam or greta.distributions. The only
writers are `node_types.R` (data values) and `sampler_class.R` (`.batch_size`).
**Removing both writers leaves the suite at `FAIL 0 | WARN 0 | SKIP 2 |
PASS 1952`.** Not removed here, because greta#739 may want to repurpose the seam
rather than delete it - that is its call. Markers repointed there; the full
explanation now lives at the accessor definition.

## Context to add to an existing issue

| Marker | Goes to |
|---|---|
| `R/utils.R:629` | greta#751 (add tests for `as_tf_function`) — greta has **no** call sites and no tests; the only consumer anywhere is greta.dynamics, in 3 places via `.internals`. So tests in greta are the only protection an extension has. |

## Resolved / no action

| Marker (line at the time) | Outcome |
|---|---|
| `R/sampler_class.R:494` (HMC leapfrog) | Marker **kept**, tied to greta#547. `?hmc` claimed L is redrawn "each iteration"; it is drawn once per burst in `sampler_parameter_values()`. Docs corrected + NEWS bullet; the behaviour fix belongs to greta#547. |
| `R/sampler_class.R:486` (seed) | Marker **replaced** with a note pointing at greta#285/#427. `set_tf_seed()` sets no TF seed at all - it assigns `self$seed` to `dag$tf_environment$rng_seed`, which has **zero readers** in `R/` (the `rng_seed()` in `tests/testthat/helpers.R` is an unrelated helper on R's `.Random.seed`). |
| `R/sampler_class.R:474` | Marker **kept**. "Already wrapped in `tf_function`" is not the same as "written as a TF function": the body constructs the kernel and sets the seed inside, so both happen at trace time. |
| `R/sampler_class.R:503` | Marker **removed**, replaced by a note. All three of its lines resolved - see below. |

### `sampler_class.R:503` in detail

The marker read:

```
# TF1/2 check
# `seed` arg now gets passed to `sample_chain`.
# Need to work out how to get sampler_batch() to run as a TF function.
# To do that we need to work out how to get the free state
```

- Line 1 is **true**, and was earlier mis-recorded here as false. The 2023
  original ([`17187c6b`](https://github.com/greta-dev/greta/commit/17187c6b)) read *"Looks like the `seed` arg now gets passed
  **through to** `sample_chain`"* - an observation about the **TFP API**, not a
  claim about greta's code. Confirmed: `tfp$mcmc$sample_chain` does take
  `seed=` in TFP 0.25.0, and greta's call never passes one. That is the route
  any fix for greta#285/#427 has to take.
- Lines 2 and 3 are **achieved**. `define_tf_evaluate_sample_batch()`
  (`R/sampler_class.R:74`) wraps `define_tf_draws` in `tf_function()` with
  `free_state` traced as `TensorSpec(shape = list(NULL, n_free))`.
- Verified by measurement, not by reading: `tf_evaluate_sample_batch` is a real
  `tf.function` (Python type `Function`) and
  `experimental_get_tracing_count()` returns **1** after a completed 200-iteration
  run, after 1000, and with 4 chains. Scalar `TensorSpec`s for burst length and
  thin are what stop value changes forcing a retrace.
- Because being traced turned out **not** to end the R round-tripping, the
  replacement note names greta#547 so the comment cannot be read as "TF2 work
  here is done". Burst counts and the mirai/mori direction are recorded on the
  greta#547 block in `milestone-04-adaptive-sampling.qmd`.

**Correction worth noting:** the comment added at `:486` in commit [`4e073af6`](https://github.com/greta-dev/greta/commit/4e073af6)
said *"sample_chain() below takes no seed argument"*. That is wrong and would
send a reader away from the only route that works; fixed in the same pass.

**Superseded by the comment audit (below):** the replacement note written here
was itself removed. Its facts were rehomed - the single-trace fact to the
`tf_function` wrap site, the #547 pointer to `run_burst()` - leaving the
`sample_chain()` call uncommented.

### The `run_burst` trio: `:204`, `:288`, `:527`

All three said "replace with `define_tf_draws`", which is **circular**:
`run_burst()` -> `sample_carefully()` -> `tf_evaluate_sample_batch` =
`tf_function(define_tf_draws)`. `define_tf_draws` is already what runs;
`run_burst` is the R-side wrapper around it. Nothing to swap. What the three
actually wanted is greta#547 - dissolving the R burst loop.

Handled as one unit, against the `code-comments` standard. The governing rule
was **one reason, one place**: greta#547 was about to appear at four sites. It
now appears once, at `run_burst()`, the implementation of the relay. The two
call sites carry nothing - a deliberate departure from "repoint, never delete",
justified because the question is recorded once rather than lost. Also fixed:
the plain comment at `:70`, *"define_tf_draws is now used in place of of
run_burst"* - backwards (and a doubled "of").

Asymmetry worth keeping in mind: `burst_lengths()` (`R/sampler_class.R:386`)
always breaks at progress-bar changepoints, and **additionally** at tuning
changepoints when `warmup = TRUE`. That is why the measured round-trips track
warmup alone.

## Pre-existing, found by code review of the sweep branch (2026-08-22)

Not introduced by the sweep, so not fixed in it. Each is real and verified.

| where | finding |
|---|---|
| `R/dag_class.R` `define_free_state()` | Its `variable` branch does `vals <- as.logical(vals)`, which **discards every non-zero initial value**, coercing them all to TRUE. This strengthens the case for deleting the function rather than filing an issue to repair it. |
| `R/samplers.R:152`, `:282`; `R/sampler_class.R:472`, `:512` | `tfe <- dag$tf_environment` bound and never used - and in `define_tf_draws`, `dag` itself is unused after that line. Each implies the function reaches into the tf environment when it does not, which is the misconception the sweep was removing. |
| `R/sampler_class.R:529` | An `if` with an **empty body**: the `GRETA_DEBUG` condition is evaluated every burst and can never do anything, and the next line then fails on a NULL `all_states` with an opaque reticulate error. Distinct from the `calculate.R` debug hook, which Nick asked to keep. |
| `R/dag_class.R` `tf_graph` removal | Removed a public field of a class exported through `.internals`, with no NEWS entry. R6 returns NULL for a missing field rather than erroring, so a downstream read fails later at an unrelated point. Nothing reads it today, so the risk is low. |

## The standing benchmark suite (2026-08-23)

Built at `greta.benchmarks/suite/` on Nick's direction: `{cross}`, run locally,
**not** touchstone and not CI. Five models from `inst/examples/` plus a scaled-up
regression; tasks are `build`, `opt_adam`, `mcmc_short`, covering both inference
entry points because they share almost no code.

Two things it encodes that this sweep learned the hard way: a **"is the
difference resolved?"** table that compares the between-branch difference to the
within-branch spread per cell, and `hierarchical_slopes_corr` flagged as the only
cholesky-path model, so a trimmed subset that drops it cannot see cholesky
regressions.

Note greta's `touchstone/` directory still exists and its workflows are still
present - `pull_request` is commented out, but `touchstone-receive.yaml` still
fires on a PR comment starting with `/benchmark`. Nick does not want to use it.

## Candidate for the cleanup pile: dead dimension repair

`run_burst()` carries:

```r
# if there is one sample at a time, and it's rejected, conversion from
# python back to R can drop a dimension, so handle that here. Ugh.
if (n_dim(free_state_draws) != 3) {
```

**The drop does not happen.** Probed by calling `sample_carefully()` directly
with `sampler_burst_length = 1L` and `hmc(epsilon = 1e10)` to force rejection,
across 3 model shapes (scalar, `normal(dim = 5)`, two variables) x
{`epsilon = 0.1`, `1e10`} x {1, 3} chains. **12/12 returned `ndim = 3`**,
every rejected single-sample case included. Reads as TF1-era handling.

12 probes cannot prove the branch unreachable in all cases, so this is **not**
a delete-on-sight. **Drafted as an issue** 2026-08-23:
`drafts/draft-issue-dimension-repair.md`. Deciding it properly means reasoning
about what `sample_chain` guarantees for the shape of `all_states`, not running
more cases - which is why it is an issue rather than more probing.
