# Issue #528 — `mixture()` fails with single-column arrays

## Approach

For component `dim = c(5, 1)` the user passes `weights` of dim `c(2, 5, 1)`, and
`check_weights_dim()` wrongly rejects it. The bug is an asymmetry: the check
strips a trailing `1` from the component `dim` but **not** from the weights'
trailing dimensions:

```r
# R/checkers.R:1394-1416
weights_extra_dim <- dim                 # c(5, 1)
n_extra_dim <- length(weights_extra_dim)
weights_last_dim_is_1 <- weights_extra_dim[n_extra_dim] == 1
if (weights_last_dim_is_1) {
  weights_extra_dim <- weights_extra_dim[-n_extra_dim]   # -> c(5)
}

w_dim <- weights_dim[-1]                  # c(5, 1)  <-- NOT stripped
dim_1 <- length(w_dim) == 1 && w_dim == 1
dim_same <- all(w_dim == weights_extra_dim)   # all(c(5,1) == c(5)) -> FALSE
incompatible_dims <- !(dim_1 | dim_same)      # TRUE  -> aborts
```

`dim = c(1, 5)` works only because its last dim is `5`, so nothing is stripped
and both sides read `c(1, 5)`.

Fix: strip a trailing `1` from `w_dim` (the weights' non-component dimensions)
with the same rule applied to `weights_extra_dim`, then compare:

```r
w_dim <- weights_dim[-1]
if (length(w_dim) > 1 && w_dim[length(w_dim)] == 1) {
  w_dim <- w_dim[-length(w_dim)]
}
dim_1 <- length(w_dim) == 1 && w_dim == 1
dim_same <- length(w_dim) == length(weights_extra_dim) &&
  all(w_dim == weights_extra_dim)
```

Adding the `length()` equality guard also removes the R recycling foot-gun in
`all(w_dim == weights_extra_dim)` (comparing `c(5,1)` with `c(5)` currently
recycles instead of erroring).

## Files / functions touched

- `R/checkers.R` — `check_weights_dim()` (1375–1417), specifically the
  `w_dim`/`dim_same` logic at 1402–1405.
- Called from `R/mixture.R:104` (`mixture_distribution$initialize`).

## Acceptance test

Add to `tests/testthat/test_mixture.R`:

```r
test_that("mixture() accepts single-column weights arrays", {
  dim <- c(5, 1)
  weights <- uniform(0, 1, dim = c(2, dim))
  expect_no_error(
    mixture(
      normal(1, 1, dim = dim),
      normal(-1, 1, dim = dim),
      weights = weights
    )
  )
})

test_that("mixture() still rejects genuinely wrong weights dims", {
  dim <- c(5, 4)
  bad <- uniform(0, 1, dim = c(2, 3, 3))
  expect_error(
    mixture(normal(1, 1, dim = dim), normal(-1, 1, dim = dim), weights = bad),
    "dimension of weights"
  )
})
```

The second test guards against the fix over-relaxing the check.

## Dependencies

- **Related to #728 (same subsystem) but not blocking.** #528 is purely the
  dimension *validation* in `check_weights_dim()`; #728 is the *sampling*
  path in `mixture.R`. They touch different functions and can land in either
  order. Landing #528 first is convenient because it gives #728 a working
  single-column mixture to build calculate() tests on.
- Otherwise independent.

## Risk / effort

Low. ~6 lines in one checker. Risk is over-relaxing validation; the negative
test above pins the boundary.
