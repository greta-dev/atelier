An `hmc()` chain can stop mixing when the one leapfrog count it draws for the whole sampling phase moves every proposal a whole number of half-turns around a Gaussian posterior.

Found through \#843’s CI: `test-data-swapping.R`’s “swapped data reaches the sampler” failed on Ubuntu and Windows (<https://github.com/greta-dev/greta/actions/runs/36677492085/job/109765520334?pr=843#step:12:322>). This is that test’s model, on main.

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

x <- as_data(rep(0, 10))
#> ℹ Initialising Python
#> ✔ Python, TensorFlow and TFP are ready
#> 
z <- normal(0, 10)
distribution(x) <- normal(z, 1)
m <- model(z)

set.seed(34)
stuck <- mcmc(m, chains = 1, verbose = FALSE)
set.seed(33)
mixing <- mcmc(m, chains = 1, verbose = FALSE)

coda::effectiveSize(stuck)
#>       z 
#> 1.26136
coda::effectiveSize(mixing)
#>        z 
#> 1469.658

plot(
  as.vector(stuck[[1]]),
  type = "l",
  ylim = c(-1.2, 1.2),
  xlab = "draw",
  ylab = "z",
  col = "red"
)
lines(as.vector(mixing[[1]]), col = "grey50")
```

![](https://i.imgur.com/roaNjNa.png)<!-- -->

## Why

For a Gaussian posterior with sd `sigma`, one leapfrog step of size `epsilon` turns the position and momentum through an angle `theta = acos(1 - (epsilon / sigma)^2 / 2)`. When `L * theta` is a whole multiple of `pi`, each proposal lands back on the current value, or on its mirror image, with no energy error, so it is accepted. The posterior sd here is `1 / sqrt(10.01)`:

``` r
epsilon <- attr(stuck, "model_info")$samplers[[1]]$parameters$epsilon
theta <- acos(1 - (epsilon * sqrt(10.01))^2 / 2)
leapfrog_steps <- 5:10
setNames(round(leapfrog_steps * theta / pi, 2), leapfrog_steps)
#>    5    6    7    8    9   10 
#> 3.33 4.00 4.67 5.34 6.00 6.67
```

`L = 6` and `L = 9` land on whole numbers. `hmc()` draws `L` from `Lmin:Lmax` in R, once each time greta returns from TensorFlow, as its documentation says:

<https://github.com/greta-dev/greta/blob/179021a818cd7282896c42b03814a53556c1d98d/R/samplers.R#L25-L32>

With `verbose = FALSE`, sampling is one call to TensorFlow, so one `L` is used for every iteration of it:

<https://github.com/greta-dev/greta/blob/179021a818cd7282896c42b03814a53556c1d98d/R/samplers.R#L189-L193>

## What I expect

A new `L` each iteration, so no single value can hold the chain in place.

## How often

Over seeds 1 to 50 on this model, 8 chains have a bulk ESS below 100 from 1000 draws, and 2 below 10. All 8 drew `L = 6` or `L = 9`, and have `L * theta / pi` within 0.063 of a whole number. Tuned `epsilon` stays between 0.528 and 0.558 across seeds, so the same two values of `L` are the problem every time (<https://github.com/greta-dev/greta.benchmarks/tree/main/2026-09-30-stuck-chain-rate>). Larger models were not measured.

## Fix

Draw `L` inside TensorFlow, each iteration. `tfp$mcmc$HamiltonianMonteCarlo(store_parameters_in_results = TRUE)` reads `num_leapfrog_steps` from its kernel results, so a wrapper kernel can set a fresh value each step. Drawing `L` or `epsilon` at random is how Neal (2011, <https://arxiv.org/abs/1206.1901>) avoids this periodicity.

This belongs with \#547: moving warmup into TensorFlow makes each call to TensorFlow longer, so `L` would be fixed for warmup as well.

## A test for this

``` r
## test_that("hmc() mixes whichever seed it is given", {
##   ess <- vapply(1:10, function(seed) {
##     set.seed(seed)
##     draws <- mcmc(m, chains = 1, verbose = FALSE)
##     coda::effectiveSize(draws)
##   }, numeric(1))
##   expect_gt(min(ess), 100)
## })
```

## Workaround

`one_by_one = TRUE` draws `L` every iteration, at the cost of a call to TensorFlow for each one:

``` r
set.seed(34)
system.time(
  one_by_one <- mcmc(m, chains = 1, verbose = FALSE, one_by_one = TRUE)
)
#>    user  system elapsed 
#>   5.644   0.257   7.038
coda::effectiveSize(one_by_one)
#>        z 
#> 565.5084
```

## Separately

`sample(seq(l_min, l_max), 1)` draws from `1:Lmax` when `Lmin == Lmax`, because `sample()` treats a single number as `1:n`. So `hmc(Lmin = 6, Lmax = 6)` does not fix `L` at 6:

``` r
replicate(10, sample(seq(6, 6), 1))
#>  [1] 4 3 6 1 2 4 5 3 6 4
```

<sup>Created on 2026-09-30 with [reprex v2.1.1](https://reprex.tidyverse.org)</sup>
