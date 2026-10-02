`opt()` ignores `adjust = FALSE` for `bfgs()` and `nelder_mead()`: both optimise the adjusted density whatever `adjust` is.

The mode of a `lognormal(0, 1)` density is `exp(-1)`, about 0.37. With `adjust = FALSE`, `opt()` should find it; with `adjust = TRUE`, it optimises on the log scale, whose mode is 1.

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

sd <- lognormal(0, 1)
#> ℹ Initialising Python
#> ✔ Python, TensorFlow and TFP are ready
#> 
m <- model(sd)
```

`adam()` gets both right:

``` r
opt(m, optimiser = adam(), adjust = TRUE)$par$sd
#> [1] 1.001964
opt(m, optimiser = adam(), adjust = FALSE)$par$sd
#> [1] 0.3652718
```

`bfgs()` gives 1 either way:

``` r
opt(m, optimiser = bfgs(), adjust = TRUE)$par$sd
#> [1] 1
opt(m, optimiser = bfgs(), adjust = FALSE)$par$sd
#> [1] 1
```

So does `nelder_mead()`, shown with two parameters since it errors on a model with one (a separate problem):

``` r
a <- lognormal(0, 1)
b <- lognormal(0, 1)
m2 <- model(a, b)
unlist(opt(m2, optimiser = nelder_mead(), adjust = FALSE)$par)
#>         a         b 
#> 0.9999565 1.0000868
```

Both branches of the `if` in `tfp_optimiser` use `$adjusted`:

https://github.com/greta-dev/greta/blob/179021a818cd7282896c42b03814a53556c1d98d/R/optimiser_class.R#L219-L227

The fix is `$unadjusted` in the `else` branch. Any `bfgs()` or `nelder_mead()` fit with `adjust = FALSE` on a constrained parameter (positive, bounded, a simplex, a correlation matrix) has returned the wrong estimate, with no warning. Unconstrained parameters are unaffected, since there the two densities are the same.

<sup>Created on 2026-09-30 with [reprex v2.1.1](https://reprex.tidyverse.org)</sup>
