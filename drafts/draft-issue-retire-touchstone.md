# Retire touchstone, and keep benchmark results in greta.benchmarks

## What I expect

That a speed claim about greta — in `NEWS.md`, in a code comment, or in an
issue — can point at the code and numbers that produced it.

## What happens instead

Benchmarking lives in [`touchstone/`](https://github.com/greta-dev/greta/tree/e8563dae0ef2b8be384fac023f62df1febf17ae6/touchstone), set up in #365. It runs a
fixed script across the base and head branches of a PR and posts the relative
change as a PR comment. Three problems:

**The results are not durable.** They exist as a comment on one pull request.
Nothing can cite them later, and they are not comparable across time.

**The models are too small to see anything.** [`touchstone/script.R`](https://github.com/greta-dev/greta/blob/e8563dae0ef2b8be384fac023f62df1febf17ae6/touchstone/script.R)
benchmarks `normal(0, 1)`, `model(normal(0, 1))`, `mcmc(model(normal(0, 1)))`
and one `iris` regression. A model with no gradient work cannot distinguish
fixed overhead from model cost — measuring `opt()` that way gave "cost is flat
with model size", which is an artefact and not true of real models.

**It is already half-off.** In
[`touchstone-receive.yaml`](https://github.com/greta-dev/greta/blob/e8563dae0ef2b8be384fac023f62df1febf17ae6/.github/workflows/touchstone-receive.yaml) the
`pull_request` trigger is commented out; it now fires only on a PR comment
starting with `/benchmark`. The config also pins `ubuntu-20.04`, R 4.1.1 and a
January 2022 RSPM snapshot.

## Fix

Delete `touchstone/`, `.github/workflows/touchstone-receive.yaml` and
`.github/workflows/touchstone-comment.yaml`.

Benchmarking moves to
[greta.benchmarks](https://github.com/greta-dev/greta.benchmarks), which already
has:

- a [standing suite](https://github.com/greta-dev/greta.benchmarks/tree/main/suite)
  run locally across branches with [{cross}](https://github.com/DavisVaughan/cross),
  over models from greta's own `inst/examples/`
- dated run directories for one-off questions, each holding the script, the raw
  results and a rendered write-up that a `NEWS.md` entry can link to

## Why this is better than it sounds

The obvious objection is that this gives up automation: nobody is forced to
benchmark a PR. In practice touchstone was not providing that either — the
automatic trigger has been off, and the last change to `touchstone/` was a
formatting pass in March 2025.

What it buys is that results become evidence. Two recent examples, both of which
a PR comment could not have carried:

- greta#834 links to a run showing the discarded warmup trace allocates over a
  gigabyte for a matrix that is then deleted
- greta#833 now has a measured 4.8% for wiring `compile` through, with a
  confidence interval — which needed 50 iterations to resolve, where 10 gave
  answers ranging from 27 ms to 62 ms

That last point matters for automation: a benchmark that runs on every PR is
under pressure to be quick, and a quick run of a real effect looks exactly like
no effect.

## Not in scope

Whether to reinstate automated benchmarking later, with the suite as its model
set. Worth doing if the runtime can be made honest, but it is a separate
decision from removing something that is not running.
