# Issue #800 — `backsolve()`/`forwardsolve()` mangle args for non-greta arrays

## Approach

The `.default` methods exist only so that `backsolve()`/`forwardsolve()` can be
made generic, but they hard-code the base functions' *default* argument values
instead of forwarding what the caller passed:

```r
# R/functions.R:856-865
backsolve.default <- function(r, x, k = ncol(r), upper.tri = TRUE,
                              transpose = FALSE) {
  base::backsolve(r, x, k = ncol(r), upper.tri = TRUE, transpose = FALSE)
}
```

```r
# R/functions.R:908-917
forwardsolve.default <- function(l, x, k = ncol(l), upper.tri = FALSE,
                                 transpose = FALSE) {
  base::forwardsolve(l, x, k = ncol(l), upper.tri = FALSE, transpose = FALSE)
}
```

So once greta is attached, a plain-matrix call like
`backsolve(r, x, upper.tri = FALSE)` silently ignores `upper.tri`/`transpose`
and returns wrong numbers. Fix is to forward the actual arguments:

```r
backsolve.default <- function(r, x, k = ncol(r), upper.tri = TRUE,
                              transpose = FALSE) {
  base::backsolve(r, x, k = k, upper.tri = upper.tri, transpose = transpose)
}

forwardsolve.default <- function(l, x, k = ncol(l), upper.tri = FALSE,
                                 transpose = FALSE) {
  base::forwardsolve(l, x, k = k, upper.tri = upper.tri, transpose = transpose)
}
```

Two-line change per method (`ncol(r)`→`k`, literals→argument names).

## Files / functions touched

- `R/functions.R` — `backsolve.default()` (line 864 body) and
  `forwardsolve.default()` (line 916 body).

## Acceptance test

Add to `tests/testthat/test_functions.R`:

```r
test_that("backsolve.default forwards args to base", {
  r <- matrix(c(2, 0, 1, 3), 2, 2)
  b <- c(1, 2)
  expect_equal(
    backsolve(r, b, upper.tri = FALSE, transpose = TRUE),
    base::backsolve(r, b, upper.tri = FALSE, transpose = TRUE)
  )
})

test_that("forwardsolve.default forwards args to base", {
  l <- matrix(c(2, 1, 0, 3), 2, 2)
  b <- c(1, 2)
  expect_equal(
    forwardsolve(l, b, upper.tri = TRUE, transpose = TRUE),
    base::forwardsolve(l, b, upper.tri = TRUE, transpose = TRUE)
  )
})
```

Both fail before the fix (the greta method drops the non-default args) and pass
after.

## Dependencies

- **Fully independent / orthogonal.** No other issue touches these methods.

## Risk / effort

Trivial (four edited tokens) but **high value**: currently silently wrong
results for any base user with greta loaded. Priority high. No behaviour change
for greta-array callers, which route to `backsolve.greta_array()`.
