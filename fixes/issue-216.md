# Issue #216 — `diag()` cannot construct a diagonal matrix

## Approach

`diag.greta_array()` currently only ever *extracts* a diagonal: it ignores the
`nrow`/`ncol` arguments entirely and always calls `tf$linalg$diag_part`. Base R
overloads `diag()` for four jobs: extract a diagonal, build an identity of a
given size, build a diagonal matrix from a vector, and (with `nrow`/`ncol`)
build a rectangular diagonal matrix. We add the *construction* path so that
`diag(x, nrow, ncol)` on a vector-like greta array returns a diagonal
`greta_array` via `tf$linalg$diag`.

Dispatch decision inside `diag.greta_array()`:

- if `nrow`/`ncol` are supplied, or `x` is a length-≥1 column/row vector, treat
  it as *construction* and build a diagonal matrix from the values of `x`;
- otherwise fall through to the existing *extraction* branch (which #583 fixes
  for the rectangular case).

Construction uses a new op wrapping `tf$linalg$diag`, with output dims
`c(n, n)` (or `c(nrow, ncol)` when given), where `n = length(x)`. This mirrors
`jeffreypullin`'s fork suggestion in the issue thread, generalised to cover the
`nrow`/`ncol` forms.

## Files / functions touched

- `R/extract_replace_combine.R` — `diag.greta_array()`
  (defined at `R/extract_replace_combine.R:689`, currently 689–712). Add the
  construction branch ahead of the existing extraction code at line 711
  (`op("diag", x, dim = dims, tf_operation = "tf$linalg$diag_part")`).
- `R/functions.R` — the `#'  diag(x, nrow, ncol)` usage block and `@details`
  around `R/functions.R:30` and `R/functions.R:50`, to document that
  construction is now supported.
- No new `tf_*` helper needed: `tf$linalg$diag` is called directly like the
  existing `tf$linalg$diag_part`.

## Acceptance test

Add to `tests/testthat/test_extract_replace_combine.R` (sits beside the existing
diag tests):

```r
test_that("diag() constructs a diagonal greta array from a vector", {
  x <- as_data(1:3)
  d <- diag(x)
  expect_s3_class(d, "greta_array")
  expect_equal(dim(d), c(3L, 3L))
  expect_equal(as.matrix(calculate(d)[[1]]), diag(1:3))
})

test_that("diag(x, nrow, ncol) constructs a rectangular diagonal", {
  x <- as_data(1)
  d <- diag(x, 100, 100)
  expect_equal(dim(d), c(100L, 100L))
})
```

The second test is exactly the reprex in the issue (`dim(diag(xx, N, N))`
should be `100 100`, not `1 1`).

## Dependencies

- **Blocker with #583.** Both edit the *same function*
  `diag.greta_array()`. #583 fixes the extraction branch (rectangular source
  matrices); #216 adds the construction branch. They must be developed and
  landed together to avoid a merge conflict and to keep the dispatch logic
  coherent. Recommend a single PR covering both.
- Independent of every other issue in the plan.

## Risk / effort

Low–medium. ~30 lines plus tests. Main risk is getting the extract-vs-construct
dispatch right so existing extraction callers are untouched; the acceptance
tests plus the existing diag extraction tests guard against regressions.
