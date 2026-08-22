# What greta's benchmarks currently cover, and what they miss

Written 2026-08-20, prompted by the warmup-trace finding in the #745 marker
sweep.

## The audit

Every model in `greta.benchmarks` is tiny.

| run | model | free params |
|---|---|---|
| `2026-07-31-speed-and-ess` | `mvn_model(dim = 4)` | 4 |
| `2026-08-05-keras3-vs-main` | single `normal(0, 10)` mean | 1 |
| `2026-08-19-jit-compile-vs-main` | intercept + slope, n = 200 data | 2 |

Maximum across the whole suite: **4 free parameters**. Every run is `mcmc()` or
`opt()` on a model whose gradient is trivial.

Two of the three runs also have no results committed:
`2026-08-19-jit-compile-vs-main/` holds `run.R` and nothing else, so the
comparison has never actually been made.

## Why that matters, concretely

The warmup-trace bug is the proof. Warmup accumulates a matrix by repeated
`rbind` and then discards it, so the cost grows with the square of the burst
count and linearly in the number of free parameters. Measured:

| n_free | overhead |
|---|---|
| 1 | ~4% |
| 20 | ~7% |
| 200 | ~33% |

and at `n_free = 200`, warmup 4000, it is **+101%** - it doubles the run.

At 4 free parameters that is inside the noise. **The current suite would have
reported "no difference" on a change that doubles runtime for a real model.**
It cannot see this class of regression at all.

The same blind spot applies in the other direction: it cannot confirm a
speed-up either, which is why the `compile`/XLA question (#833) is still open
with no measurement behind it.

## The models already exist - do not invent them

`inst/examples/` holds **31 models**, rendered into the `example_models`
vignette. They are greta implementations of the BUGS project's example models
(WinBUGS examples volume 2), the Stan example-models wiki, plus greta's own
ecological examples. Real models, already idiomatic, already maintained,
already recognised by anyone who reads greta's docs.

They span the axes below without being contrived:

- small and dense: `linear`, `logistic`, `poisson`, `beetles`, `lightspeed`
- shrinkage priors, same shape, very different geometry: `linear_ridge`,
  `linear_lasso`, `linear_horseshoe`, `linear_finnish_horseshoe`,
  `linear_spike_and_slab`
- hierarchical, 5 variants: `hierarchical_linear`, `_slopes`, `_slopes_corr`,
  `_general`, `_marginal`; plus `eight_schools`, `multilevel`
- genuinely large: `factor_analysis` (`W` is `p x q`, `Z` is `q x n`),
  `bayesian_neural_network`, `cjs` (capture-recapture, vectors of length
  `n_time`), `multispecies_partial_pool`, `occdet_single_species`

**Only one of the 31 touches the cholesky family**:
`hierarchical_linear_slopes_corr`, via `lkj_correlation()`. Since that is the
family deciding greta#833, it is the single most load-bearing model in the set
and should not be dropped from any subset.

The 7 `tests/testthat/test_posteriors_*.R` files are the other source:
binomial, bivariate normal, chi-squared, LKJ, standard uniform, Wishart, and
the Geweke check. These check a sampled posterior against a known answer, so
they contribute the *correctness* half - a speed-up that quietly breaks the
posterior is not a speed-up. They also cover Wishart and LKJ, which
`inst/examples/` barely does.

## What a benchmark set needs to vary

Not just size - *kind*, because different model shapes exercise different parts
of the stack. A first proposal, to be argued with:

**Size**: `n_free` at roughly 1, 10, 100, 1000. The interesting behaviour is the
slope across these, not any single point.

**Shape**, each hitting a different part of the backend:

- plain regression - dense, cheap gradient, the baseline
- hierarchical / multilevel - many parameters, structured dependencies, the
  shape most real greta users actually write
- multivariate normal - matrix operations in the gradient
- cholesky / LKJ (`wishart()`, `lkj_correlation()`) - bijector-heavy, and
  notably the exact family XLA cannot compile, so it is the family that decides
  the #833 question
- a mixture or discrete-marginalised model - a different log-prob structure

**Inference**: `mcmc()` (hmc, and at least one other sampler) and `opt()`
(adam, bfgs). They stress different code: the warmup-trace bug is invisible to
`opt()`, and the optimiser's own R-side `while` loop is invisible to `mcmc()`.

**Warmup length**: has to be an axis, not a constant. The bug above is only
visible as warmup grows, and every current run fixes warmup at 100 or 1000.

## Shape of the runner

`{cross}` already does the hard part - `bench_branches()` runs one expression
against several branches and returns a `bench::mark` table, so results are
comparable and the equality check comes free.

What is missing is the *grid*: the model set above as data, mapped over, rather
than one expression per run directory. That keeps the existing
one-directory-one-question convention for ad-hoc comparisons while giving a
standing suite that any branch can be run against.

## ESS/sec or wall time - resolved by asking one question

Not a matter of taste. The two disagree only when a change alters the *draws*,
so ask whether it does:

| the change | measure | why |
|---|---|---|
| does not touch the draws - removing overhead, compilation, plumbing | **wall time** | ESS is a stochastic estimate, so ESS/sec only adds variance to a comparison where the posterior is provably identical |
| alters sampler behaviour - step size, adaptation, SNAPER, a new kernel | **ESS/sec** | faster iterations that mix worse are not an improvement, and wall time would call them one |

The warmup-trace fix is the first kind: it deletes work whose result is
discarded, so the sampler behaves identically. Wall time is the honest measure.
greta#547 and the SNAPER work are the second kind.

There is also a practical asymmetry. `mcmc()` does not respect `set.seed()`
(greta#285/#427), so an ESS estimate is a noisy statistic over an unseeded
sampler and needs many replicates to mean anything - which is why
`2026-07-31-speed-and-ess` ran 40-60 of them. Wall time converges much faster.
So: **default to wall time, reach for ESS/sec when the change touches the
sampler algorithm**, and expect the ESS runs to cost an order of magnitude more.

## Where a standing suite would live

The existing convention (top-level README) is one directory per run, named for
its date and its question, **never edited once written** - a lab notebook. That
is right for "did this branch change X?", which is a question asked once.

A standing model set is a different kind of object: it has to stay *constant*
across dates so that runs are comparable, and it has to be *editable* as models
are added. Those two conventions conflict, which is the whole question.

Proposal: split them by role rather than choosing.

- `suite/` - the model definitions only, as data. Shared, versioned, edited
  freely, no results. Sourced by run scripts.
- `2026-*-question/` - unchanged. Dated, immutable, holds results. A run
  sources `suite/` rather than redefining models inline.

That keeps the lab-notebook guarantee (a `NEWS.md` link still points at
immutable numbers) while stopping every run from reinventing its own models -
which is how the current three ended up at 1, 2 and 4 free parameters
independently.

## Open question

How long is acceptable for a full run? The grid is roughly 4 sizes x 5 shapes x
2 inference methods, which is not a per-commit thing. Probably a fast subset
plus a full sweep on demand - and the fast subset must keep
`hierarchical_linear_slopes_corr`, per above.
