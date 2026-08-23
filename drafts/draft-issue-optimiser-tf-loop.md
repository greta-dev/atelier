# `opt()` drives its iteration loop from R, stepping into TensorFlow once per step

## What I expect

That greta's optimisers iterate the way `tfp_optimiser` already does — TFP
drives the loop and control returns to R once, at the end.

## What happens instead

Two of the three optimiser classes run a `while` loop in R:

- [`tf_optimiser`, `optimiser_class.R#L165-L169`](https://github.com/greta-dev/greta/blob/e8563dae0ef2b8be384fac023f62df1febf17ae6/R/optimiser_class.R#L165-L169)
  — **8** user-facing optimisers
- [`tf_compat_optimiser`, `optimiser_class.R#L323-L327`](https://github.com/greta-dev/greta/blob/e8563dae0ef2b8be384fac023f62df1febf17ae6/R/optimiser_class.R#L323-L327)
  — **3** more

[`tfp_optimiser`](https://github.com/greta-dev/greta/blob/e8563dae0ef2b8be384fac023f62df1febf17ae6/R/optimiser_class.R#L237-L241) (the remaining 2) has no R
loop. The marker directly above the second one already asks for this:
[`# get this to work inside TF with TF while loop`](https://github.com/greta-dev/greta/blob/e8563dae0ef2b8be384fac023f62df1febf17ae6/R/optimiser_class.R#L321-L322).

## Why this is a problem, and by how much

Measured in
[greta.benchmarks/2026-08-22-optimiser-r-loop/results.md](https://github.com/greta-dev/greta.benchmarks/blob/main/2026-08-22-optimiser-r-loop/results.md), from
[`01-measure.R`](https://github.com/greta-dev/greta.benchmarks/blob/main/2026-08-22-optimiser-r-loop/01-measure.R).

**[`opt()` has a large fixed cost per iteration](https://github.com/greta-dev/greta.benchmarks/blob/main/2026-08-22-optimiser-r-loop/results.md#part-1-opt-has-a-large-fixed-cost-per-iteration)**,
measured on `linear`, `multiple_linear` and `hierarchical_linear` from
`inst/examples/` plus a scaled-up regression:

| model | free parameters | per iteration |
|---|---|---|
| `linear` | 3 | 0.89 ms |
| `multiple_linear` | 8 | 0.96 ms |
| `hierarchical_linear` | 6 | 1.28 ms |
| 2000x200 regression | 202 | 1.40 ms |

The floor is ~0.89 ms. Giving the gradient a 2000x200 matrix multiply every
iteration only reaches 1.40 ms, so even there about **64% of an iteration is
cost that does not come from the model**. Parameter count is not the driver —
`hierarchical_linear` has 6 free parameters and costs more per iteration than
`multiple_linear`'s 8.

**[The same 200 steps driven inside TF instead of from R run 25x faster](https://github.com/greta-dev/greta.benchmarks/blob/main/2026-08-22-optimiser-r-loop/results.md#part-2-the-ceiling-on-identical-arithmetic)**,
which puts the bare round trip at about **0.061 ms per step**.

So the round trip alone is
[only ~5% of an `opt()` iteration](https://github.com/greta-dev/greta.benchmarks/blob/main/2026-08-22-optimiser-r-loop/results.md#what-that-means-for-the-fix).
The rest of that fixed cost is greta's own loop body, which also runs in R:

- [the objective pulled back with `$numpy()`](https://github.com/greta-dev/greta/blob/e8563dae0ef2b8be384fac023f62df1febf17ae6/R/optimiser_class.R#L175)
- [`check_numerical_overflow()`](https://github.com/greta-dev/greta/blob/e8563dae0ef2b8be384fac023f62df1febf17ae6/R/optimiser_class.R#L179)
- the convergence test in the `while` condition itself

## Fix

Move the loop into TF with `tf$while_loop`, **and the body with it** — the
convergence check and the overflow check have to become tensor operations, or
the round trip they force is simply moved rather than removed. Wrapping the loop
alone and leaving the body in R recovers only the ~5%; the prize is the rest of
the ~0.89 ms floor.

`tfp_optimiser` is a working in-repo reference for the target shape.

## A test for this

Assert the behaviour, not the implementation — that the optimiser still stops
where it used to:

```r
test_that("opt() converges to the same place with the TF-driven loop", {
  x <- normal(0, 1)
  m <- model(x)
  o <- opt(m, optimiser = adam(), max_iterations = 200)
  expect_lt(abs(o$par$x), 0.01)
  expect_lt(o$iterations, 200)
})
```

## Not covered by #547

#547 is sampler-scoped: it names warmup and links the mcmc burst code. `opt()`
runs none of that and shares no code with it, so the two need fixing separately.

## Separately

The other marker in this file,
[`optimiser_class.R#L239-L241`](https://github.com/greta-dev/greta/blob/e8563dae0ef2b8be384fac023f62df1febf17ae6/R/optimiser_class.R#L239-L241), is a
different question — ad-hoc `if/else` dispatch on optimiser name inside
`tfp_optimiser` — and is not part of this.
