`dag_class$define_free_state()` has no callers, and one of its two branches
throws an error if it is ever reached.

Found while sweeping the `TF1/2` code markers for \#745 — the function carries
two of them.

The `placeholder` branch:

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

x <- normal(0, 1)
#> ℹ Initialising python and checking dependencies, this may take a moment.
#> ✔ Initialising python and checking dependencies ... done!
#> 
m <- model(x)

m$dag$define_free_state("placeholder")
#> Error in `m$dag$define_free_state()`:
#> ! object 'free_state' not found
```

## What I expect

Either the branch works, or the argument that selects it is gone.

## What happens instead

`type = "placeholder"` computes a shape and then does nothing with it,
because the rest of that branch is commented out, so `free_state` is never
assigned:

``` r
## } else {
##   shape <- shape(NULL, length(vals))
##   # TF1/2 check
##   # instead?
##   # free_state <- tensorflow::as_tensor(
##   #   dtype = tf_float(),
##   #   shape = shape
##   # )
## }
##
## assign(name, free_state, envir = tfe)
```

The `variable` branch does work:

``` r
m$dag$define_free_state("variable")
```

## Why this is a problem

It is dead code that looks live. `define_free_state` appears exactly once in
`R/` and once in `tests/` — its own definition — so nothing calls it. Its
last caller went with commit [`7e3e81ac`](https://github.com/greta-dev/greta/commit/7e3e81ac) (Jan 2023), which removed the TF1
session/placeholder machinery this function existed to serve.

The cost is not runtime, it is reading time: anyone auditing the free-state
path finds a function offering a `placeholder` mode, spends time working out
where placeholders are still used, and arrives at nothing. It also carries
two of the `TF1/2` markers being retired in \#745, so it has to be resolved
before that sweep can finish.

## Fix

Delete `define_free_state()` from `R/dag_class.R`, along with its two
`TF1/2` markers.

Before deleting, check the extension packages. greta exposes internals
through `.internals`, so “no callers in `R/`” is not on its own sufficient —
greta.gp, greta.dynamics, greta.gam and greta.distributions each need
checking for `define_free_state`.

## A test for this

No new test. Deleting an uncalled function is covered by the existing suite
continuing to pass; a test asserting the function does not exist would only
assert the implementation.
