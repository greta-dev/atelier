`opt()` drives its optimisation loop from R, stepping into TensorFlow once
per iteration. The marker at `optimiser_class.R:321` already asks for this —
`# get this to work inside TF with TF while loop` — so this is that note,
with a measurement.

The per-iteration cost barely moves with model size, so it is dominated by
the round trip rather than by the gradient step:

``` r
library(greta)
#> 
#> Attaching package: 'greta'
#> The following objects are masked from 'package:stats':
#> 
#>     binomial, cov2cor, poisson
#> The following objects are masked from 'package:base':
#> 
#>     %*%, %o%, apply, backsolve, beta, chol2inv, colMeans, colSums,
#>     diag, eigen, forwardsolve, gamma, identity, outer, rowMeans,
#>     rowSums, sweep, tapply

set.seed(2026 - 08 - 21)

time_opt <- function(p) {
  z <- normal(0, 1, dim = p)
  y <- as_data(rnorm(p))
  distribution(y) <- normal(z, 1)
  m <- model(z)
  # one short run first, to keep tracing out of the timing
  invisible(opt(m, optimiser = adam(), max_iterations = 5))
  elapsed <- system.time(
    o <- opt(m, optimiser = adam(), max_iterations = 100)
  )[["elapsed"]]
  data.frame(n_free = p, iterations = o$iterations,
             per_iter_ms = round(1000 * elapsed / o$iterations, 2))
}

do.call(rbind, lapply(c(1, 50, 500), time_opt))
#> ℹ Initialising python and checking dependencies, this may take a moment.
#> ✔ Initialising python and checking dependencies ... done!
#> 
#>   n_free iterations per_iter_ms
#> 1      1         70        0.74
#> 2     50         81        0.68
#> 3    500        100        0.61
```

A 500-parameter model costs about the same per iteration as a one-parameter
one. Single runs, so read the flatness rather than the individual numbers.

## Where the loop is

Two of the three optimiser classes run their own `while` loop in R:

- `tf_optimiser` (`optimiser_class.R:165`) — 8 user-facing optimisers
- `tf_compat_optimiser` (`optimiser_class.R:323`) — 3 more

`tfp_optimiser` (the remaining 2) has no R loop: TFP drives the iteration
itself. So there is already a working reference in the repo for the shape
this would take.

## Not covered by \#547

\#547 is sampler-scoped — it names warmup and links the mcmc burst code.
`opt()` runs none of that, and shares no code with it, so the two would need
fixing separately.
