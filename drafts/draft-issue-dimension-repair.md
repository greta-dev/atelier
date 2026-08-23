# Is the dimension-repair branch in `run_burst()` still reachable?

## What the code says

[`R/sampler_class.R#L556-L560`](https://github.com/greta-dev/greta/blob/e8563dae0ef2b8be384fac023f62df1febf17ae6/R/sampler_class.R#L556-L560):

```r
# if there is one sample at a time, and it's rejected, conversion from
# python back to R can drop a dimension, so handle that here. Ugh.
if (n_dim(free_state_draws) != 3) {
  dim(free_state_draws) <- c(1, dim(free_state_draws))
}
```

## What I measured

I could not make the drop happen. Calling
[`sample_carefully()`](https://github.com/greta-dev/greta/blob/e8563dae0ef2b8be384fac023f62df1febf17ae6/R/sampler_class.R#L588) directly with
`sampler_burst_length = 1L` and `hmc(epsilon = 1e10)` to force rejection, across
3 model shapes (scalar, `normal(dim = 5)`, two variables) x
{`epsilon = 0.1`, `1e10`} x {1, 3} chains:

**12 of 12 returned `ndim = 3`**, including every rejected single-sample case —
which is exactly the case the comment names.

```
scalar       eps=1e+10  ch=1  dim=1x1x1  ndim=3  any_rejected=TRUE
vector[5]    eps=1e+10  ch=1  dim=1x1x5  ndim=3  any_rejected=TRUE
2 variables  eps=1e+10  ch=3  dim=1x3x2  ndim=3  any_rejected=TRUE
```

## Why this is worth an issue rather than a deletion

Twelve probes cannot prove a branch unreachable. Deciding this properly means
reasoning about what `tfp$mcmc$sample_chain` guarantees for the shape of
`all_states`, and what `reticulate` does converting it — not running more
cases.

Two things make it worth someone's time when they are next in `run_burst()`:

- If it **is** dead, it is TF1-era handling that survived the TF2 port, and the
  "Ugh." is a standing invitation to leave it alone forever.
- If it is **not** dead, there is a reachable path where a burst returns
  something other than a 3-D array, and nothing in the test suite covers it.
  That is worth a test either way.

## A test for this

Whichever way it goes, the case the comment describes should be covered:

```r
test_that("a rejected single-sample burst still returns a 3d array", {
  x <- normal(0, 1)
  m <- model(x)
  s <- greta:::build_sampler(
    initial_values = greta:::prep_initials(initials(), 1, m$dag),
    sampler = hmc(epsilon = 1e10), model = m, compute_options = cpu_only()
  )
  res <- s$sample_carefully(
    free_state = s$free_state, sampler_burst_length = 1L,
    sampler_thin = 1L, sampler_param_vec = unlist(s$sampler_parameter_values())
  )
  expect_false(as.array(res$trace$is_accepted)[[1]])
  expect_length(dim(as.array(res$all_states)), 3)
})
```

Found sweeping the `TF1/2` markers for #745.
