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
[greta.benchmarks/2026-08-22-optimiser-r-loop](https://github.com/greta-dev/greta.benchmarks/tree/main/2026-08-22-optimiser-r-loop).

**`opt()` costs the same per iteration whatever the model size** — 0.61 to
0.86 ms per iteration across a 500-fold change in free parameters. That is fixed
overhead, not gradient work.

**The same 200 steps driven inside TF instead of from R run 25x faster**, which
puts the bare round trip at about **0.063 ms per step**.

But that is the honest ceiling only for a bare loop. 0.063 ms of round trip
against ~0.64 ms per `opt()` iteration is roughly **10%**. The other 90% is
greta's own loop body, which also runs in R:

- [the objective pulled back with `$numpy()`](https://github.com/greta-dev/greta/blob/e8563dae0ef2b8be384fac023f62df1febf17ae6/R/optimiser_class.R#L175)
- [`check_numerical_overflow()`](https://github.com/greta-dev/greta/blob/e8563dae0ef2b8be384fac023f62df1febf17ae6/R/optimiser_class.R#L179)
- the convergence test in the `while` condition itself

## Fix

Move the loop into TF with `tf$while_loop`, **and the body with it** — the
convergence check and the overflow check have to become tensor operations, or
the round trip they force is simply moved rather than removed. Wrapping the loop
alone and leaving the body in R recovers only the 10%.

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
