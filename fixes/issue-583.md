# Issue #583 — extracting the diagonal from a rectangular matrix errors

## Approach

`diag.greta_array()` refuses any non-square matrix. The guard is not only
over-strict but mis-named:

```r
# R/extract_replace_combine.R:700-705
is_square <- dim[1] != dim[2]
if (is_square) {
  cli::cli_abort(
    "Diagonal elements can only be extracted from square matrices"
  )
}
```

`is_square` is `TRUE` precisely when the matrix is **not** square, so the branch
is really `is_not_square`. Base R's `diag()` happily extracts the main diagonal
of a rectangular matrix (length `min(nrow, ncol)`), and `tf$linalg$diag_part`
already does the same on the TensorFlow side. The fix is to delete the square
restriction and compute the output length as `min(dim[1], dim[2])`.

Change:

- remove the `is_square`/`cli_abort` block (700–705);
- set `dims <- c(min(dim[1], dim[2]), 1)` instead of `c(dim[1], 1)` at line 708;
- keep the existing `tf$linalg$diag_part` op.

Rename any residual `is_square` usage to avoid re-introducing the confusion.

## Files / functions touched

- `R/extract_replace_combine.R` — `diag.greta_array()` (689–712), specifically
  the guard at 700–705 and the `dims` line at 708.

## Acceptance test

Add to `tests/testthat/test_extract_replace_combine.R`:

```r
test_that("diag() extracts the diagonal of a rectangular greta array", {
  m <- matrix(1:12, 3, 4)
  x <- as_data(m)
  d <- diag(x)
  expect_equal(dim(d), c(3L, 1L))
  expect_equal(as.vector(calculate(d)[[1]]), diag(m))
})
```

This is the reprex from the issue (`greta::diag(x)` on a 3×4 array must return
`c(1, 5, 9)` rather than erroring).

## Dependencies

- **Blocker with #216.** Same function, same PR (see
  `fixes/issue-216.md`). #583 is the extraction half, #216 the construction
  half.
- The `fix-diag-i583` branch has a one-commit start that can be salvaged.
- Otherwise independent.

## Risk / effort

Low. A few lines. The only behaviour change is that a previously erroring call
now succeeds, so no existing passing test can regress; add the test above to
lock in the new behaviour.
