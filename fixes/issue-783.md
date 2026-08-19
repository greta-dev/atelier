# Issue #783 — `tapply()` cannot produce a 2-D table

## Approach

`tapply.greta_array()` only handles a single `INDEX` vector; passing
`list(row, col)` fails with `'x' must be atomic` because the code calls
`sort(unique(index))` directly on the list:

```r
# R/functions.R:1069-1101
tapply.greta_array <- function(X, INDEX, FUN = c("sum", ...), ...) {
  x <- X
  index <- INDEX
  fun <- match.arg(FUN)
  check_not_greta_array(INDEX)
  groups <- sort(unique(index))   # <- errors when INDEX is a list of vectors
  id <- match(index, groups) - 1L
  len <- length(groups)
  check_2_by_1(x)
  op("tapply", x, operation_args = list(segment_ids = id,
     num_segments = len, op_name = fun),
     tf_operation = "tf_tapply", dim = c(len, 1))
}
```

Approach: detect a list `INDEX` and reduce the *cross* of the index factors to a
single segment id, then reshape the flat segment result to the 2-D table. This
reuses the existing `tf_tapply()` (unsorted segment reduction) unchanged — we
only compute a combined segment id and a final `dim(out)`.

```r
if (is.list(INDEX)) {
  factors <- lapply(INDEX, function(ix) {
    g <- sort(unique(ix)); list(g = g, id = match(ix, g) - 1L)
  })
  dims <- vapply(factors, function(f) length(f$g), integer(1))
  # row-major combined id across the index dimensions
  strides <- rev(cumprod(rev(c(dims[-1], 1L))))
  id <- Reduce(`+`, Map(function(f, s) f$id * s, factors, strides))
  len <- prod(dims)
  out <- op("tapply", x, operation_args = list(
    segment_ids = as.integer(id), num_segments = as.integer(len),
    op_name = fun), tf_operation = "tf_tapply", dim = c(len, 1))
  dim(out) <- dims          # reshape flat segments to the n-D table
  return(out)
}
```

The 1-D path is unchanged. This mirrors the multi-margin reshape that
`apply.greta_array()` already does (`dim(out) <- dim_out`,
`R/functions.R:1032`), which is why the design notes #783 "extends the apply
work in #514".

## Files / functions touched

- `R/functions.R` — `tapply.greta_array()` (1069–1101). Add the list-`INDEX`
  branch; leave `tapply.default()` (1048) and `tf_tapply()`
  (`R/tf_functions.R:151`) untouched.
- `R/functions.R` — `@details` for `tapply` at `R/functions.R:98` ("works on
  column vectors") to document 2-D `INDEX`.

## Acceptance test

Add to `tests/testthat/test_functions.R`:

```r
test_that("tapply() supports a 2-D INDEX list", {
  set.seed(123)
  n <- 20
  row <- sample(1:3, n, replace = TRUE)
  col <- sample(1:2, n, replace = TRUE)
  vals <- rnorm(n)
  x <- as_data(vals)
  ga <- tapply(x, list(row, col), "sum")
  expect_equal(dim(ga), c(3L, 2L))
  expect_equal(
    calculate(ga)[[1]],
    tapply(vals, list(row, col), sum),
    ignore_attr = TRUE
  )
})
```

Compares the greta result to base `tapply()` on the same data (the issue's use
case: a model matrix of weighted sums).

## Dependencies

- **Related to #514** (shared reshape idiom) but touches a different function;
  neither strictly blocks the other. If #514's `fn_to_name()` coercion lands,
  reuse it here so `tapply(x, idx, sum)` (bare function) also works.
- Otherwise independent.

## Risk / effort

Medium. The segment-id cross-product and row/column-major ordering must match
base `tapply()`'s layout; the acceptance test compares element-for-element
against base to catch transposition errors. Empty index cells (combinations
with no data) need a decision — base fills `NA`; document that greta fills the
segment default from `tf_tapply()`.
