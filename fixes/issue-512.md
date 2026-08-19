# Issue #512 — `cbind`/subsetting a greta array with fixed zeros

## Approach

Reported on the forum (linked from the issue): building an array that mixes
*fixed data* (e.g. a column of zeros via `as_data()` / `zeros()`) with
*variables*, then `cbind()`-ing or subsetting it, misbehaves. The relevant
op family is entirely in `R/extract_replace_combine.R`:

- `cbind.greta_array()` (`R/extract_replace_combine.R:256-285`) →
  `tf_cbind`
- `[.greta_array` (`R/extract_replace_combine.R:86`) and `[<-.greta_array`
  (`R/extract_replace_combine.R:172`)

The suspected cause is the eager value/unknowns handling: when a column is a
fixed data node its `.value` is a concrete array, and when combined with a
variable (unknowns) column the combined op's cached value is computed from a
mix of knowns and unknowns. `cbind.greta_array()` computes only dimensions and
defers the values to `tf_cbind`, but the *value preview* and downstream
`calculate()` can mis-place the fixed-zero column if the data/variable ordering
is not preserved through the op's `dim`/`operation_args`.

Because the exact defect needs a runtime repro, the fix is **repro-first**:

1. Reproduce the forum case: an array where some columns are `as_data(0)` and
   others are variables, then `cbind()` and index it; compare
   `calculate()` output against the intended matrix.
2. Determine whether the corruption is in the *value preview* (the
   unknowns/data merge, cf. the `either_are_unknowns` logic at
   `R/extract_replace_combine.R:234-237`) or in `tf_cbind` column ordering.
3. Patch the identified step so fixed-zero (data) columns retain their position
   and value alongside variable columns.

## Files / functions touched

- `R/extract_replace_combine.R` — `cbind.greta_array()` (256–285), and/or
  `[.greta_array`/`[<-.greta_array` (86, 172) depending on where the repro
  localises.
- `R/tf_functions.R` — `tf_cbind` (referenced from `cbind.greta_array`) if the
  fault is in the TensorFlow-side concatenation ordering.

## Acceptance test

Add to `tests/testthat/test_extract_replace_combine.R`, once the repro is
minimised:

```r
test_that("cbind mixes fixed-zero data columns with variables correctly", {
  v <- normal(0, 1, dim = c(3, 1))
  z <- as_data(matrix(0, 3, 1))
  m <- cbind(z, v, z)
  expect_equal(dim(m), c(3L, 3L))
  out <- calculate(m, values = list(v = matrix(1:3, 3, 1)))[[1]]
  expect_equal(out[, 1], c(0, 0, 0))
  expect_equal(out[, 2], c(1, 2, 3))
  expect_equal(out[, 3], c(0, 0, 0))
})
```

Adjust to the exact minimal repro found in step 1.

## Dependencies

- **Same file as #552 and #583** (`R/extract_replace_combine.R`) but different
  functions (`cbind`/`[` vs `[<-` vs `diag`). No logical blocker — independently
  shippable — though #512 and #552 may share a root cause in how fixed-data
  values are merged with unknowns, so investigate them together.
- Independent of every other issue in the plan.

## Risk / effort

Medium. The one-line description hides a diagnosis step; the patch itself is
likely small once the repro pinpoints value-merge vs column-order. Regression
risk is contained by the existing extract/replace/combine test suite plus the
new mixed-column test.

## Correction: the behaviour this targets is already correct

This document targets `tf_cbind` column ordering and value-merge corruption.
All of it was checked against greta 0.6.0 and is correct: the acceptance test
below **passes unmodified**, so following this document would lock in
behaviour that was never broken.

What is genuinely live is narrower - a display asymmetry. `[<-` preserves
known values in the printed preview
(`R/extract_replace_combine.R:225-251`) while `cbind`/`c` render them as `?`.
That is a **printing** concern and belongs with the printing work, not here. Note it
is the inverse of what this document assumed about
[#552](https://github.com/greta-dev/greta/issues/552): #552's eager cache is
what makes the `[<-` side display correctly, so it must be kept.
