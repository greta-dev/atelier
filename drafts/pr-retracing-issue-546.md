Closes #546.

## What retracing is

greta does not run a model's maths in R. It writes the model as a TensorFlow graph, and `tf_function()` turns the R code that builds that graph into something TensorFlow can run on its own. The first time such a function is called, TensorFlow runs the R code once and records every operation it creates. That recording is called **tracing**. From then on, TensorFlow runs the recording without going back to R, which is what makes sampling fast.

A recording is made for the shape of the inputs it was traced with. Call the function with a differently shaped input, and TensorFlow cannot reuse it: it runs the R code again and makes another recording. That is **retracing**. Each retrace costs as much as the first trace, because it re-runs all of greta's R code for building the model.

When the same function is retraced several times in quick succession, TensorFlow prints a warning, "triggered tf.function retracing", because that usually means work is being redone that could have been reused. That warning is what #546 reported.

## Where greta retraced

- **`mcmc()` and `calculate()`.** A model's log-density and trace-values functions take a matrix of parameter values, one row per chain or per draw. They were traced for a fixed number of rows, so they were traced again for every number of rows they met: one row while checking initial values, one row per chain inside the sampler, and each chunk of draws when converting them to values. Every model's functions were traced at least twice.
- **`opt(hessian = TRUE)`.** For each target greta array, greta rebuilt the model's graph, and took the hessian with TensorFlow's vectorised `pfor` jacobian, which traces a new function on every call. A model with 20 scalar targets meant 20 graph builds and 20 new traces.

## What this changes

- The log-density and trace-values functions now declare their input's shape with the number of rows left open, so each is traced once per model, whatever number of rows it meets. The sampler's function already did this.
- `calculate()` rebuilds the trace-values function when it adds new variables to a model, since that changes the width of the parameter matrix.
- `opt()` uses its own log-density function, traced for exactly one row and built the first time `opt()` needs it. An open number of rows made each `opt()` step slower, and `opt()` only ever passes one row. It checks its initial values with the same function it optimises, so with a Keras optimiser such as `adam()` the log-density is traced once rather than twice.
- `opt(hessian = TRUE)` builds the graph once for all targets, and takes every gradient in one pass. It uses `pfor` only for targets of at least 100 elements, where vectorising pays for itself, and a while loop below that, which does not retrace. The hessians are identical to main's.

## What it looks like

The same document, rendered against each branch. It shows five of greta's example models, what each does, and one run of each:

https://github.com/greta-dev/greta.benchmarks/blob/main/2026-09-29-retracing-i546/single-run-main.md

https://github.com/greta-dev/greta.benchmarks/blob/main/2026-09-29-retracing-i546/single-run-faster-hessians-i546.md

Every function greta traces, counted on main and this branch for `model()`, `opt()`, `mcmc()`, `extra_samples()` and `calculate()`; none is traced more than once here:

https://github.com/greta-dev/greta.benchmarks/blob/main/2026-09-30-trace-census-i546/results.md

| | main | this branch |
| --- | --- | --- |
| traces of each model's log-density function | 2 | 1 |
| traces of each model's trace-values function | 2 | 1 |
| `opt(hessian = TRUE)`, 20 scalar targets | 12.42 s, 2 retracing warnings | 1.99 s, none |

Across five replicates, each in a fresh R process, the first `opt(hessian = TRUE)` on 20 scalar targets takes 12.46 s on main and 1.95 s here (medians):

https://github.com/greta-dev/greta.benchmarks/blob/main/2026-09-29-hessian-timing-i546/results.md

## Not changed

- Targets of 100 or more elements still use `pfor`, so a model with several of them can still print the warning.
- TensorFlow can still print the warning when a session builds several models, though no function is traced more than once. It counts traces per Python code object, and every function greta traces is an R function that reticulate wraps in the same closure, `wrap_fn.<locals>.fn`, so the first traces of several models' functions count as one function retracing. #852 is about hiding it.
- The test suite prints 9 retracing warnings, on main and on this branch alike. None come from the retracing this PR removes: 6 are `wrap_fn.<locals>.fn`, the shared counter above (#852), and 3 come from inside TFP's samplers, 2 from `_random_gamma_no_gradient` and 1 from `_random_binomial`. The warning count is not what this PR changes; the trace counts in the table above are.
- `calculate()` still builds a new graph, with new traced functions, on every call. Caching graphs per set of targets would remove that; it is a follow-up.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
