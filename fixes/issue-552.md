# Issue #552 — replacement value overwritten early in `[<-`

## Approach

Noticed via `check_expr()` in `test_extract_replace_combine.R` with:

```r
x <- randn(10)
check_expr({
  x[1:6] <- seq_len(6)
  x
})
```

`[<-.greta_array` computes the post-replacement value **eagerly** at
construction time and caches it on the op node:

```r
# R/extract_replace_combine.R:225-251
x_value <- node$value()
replacement_value <- get_node(replacement)$value()

new_value <- x_value
r_index <- match(index, dummy)
new_value[r_index] <- replacement_value
...
op("replace", x, replacement, dim = dims,
   operation_args = list(index = index, dims = dims),
   value = new_value,                         # <- cached eagerly  (keep this - see below)
   tf_operation = "tf_replace")
```

The problem the issue title flags is that this cached `new_value` (and the
replacement node's `.value`) can be **overwritten early** — the op stores a
snapshot of the parents' current values, but those parent node values are
mutated later during DAG value propagation / repeated replacement, so the
preview value baked into the `replace` op node no longer matches what
`tf_replace` will actually compute. The node dump in the issue shows the
`replace` operation node carrying the fully merged value while the replacement
data node carries only `1 2 3 4 5 6`, i.e. the two are out of step.

Approach:

1. Add the regression test above as a failing test to pin the exact
   discrepancy (compare the op node's cached `.value` against a freshly
   recomputed replacement).
2. Make the cached `value` a defensive, order-independent snapshot: ensure
   `new_value` is a copy (it already is via `new_value <- x_value` + subassign,
   but confirm no shared reference leaks through `as.unknowns()` at
   `R/extract_replace_combine.R:236`), and that the op recomputes from parents
   at `define_tf` time rather than trusting a stale cache.
3. If the eager preview cannot be kept consistent, compute it lazily (drop the
   `value = new_value` arg and let the op derive it from parents on demand),
   matching how other ops in the family defer to their `tf_operation`.

## Files / functions touched

- `R/extract_replace_combine.R` — `[<-.greta_array` (172–252), specifically the
  value-caching block at 225–249.
- `R/tf_functions.R` — `tf_replace` (the op's TensorFlow implementation) to
  confirm it recomputes the merged value from parents (so the R-side cache is
  only a preview, never the source of truth).

## Acceptance test

Add to `tests/testthat/test_extract_replace_combine.R`:

```r
test_that("replacement value is not overwritten early", {
  x <- as_data(as.numeric(1:10))
  x[1:6] <- as.numeric(seq_len(6))
  out <- calculate(x)[[1]]
  expect_equal(as.vector(out), c(1:6, 7:10))
})

test_that("chained replacements keep independent values", {
  x <- as_data(as.numeric(1:10))
  x[1:3] <- 0
  y <- x
  x[4:6] <- 99
  expect_equal(as.vector(calculate(y)[[1]]), c(0, 0, 0, 4:10))
  expect_equal(as.vector(calculate(x)[[1]]), c(0, 0, 0, 99, 99, 99, 7:10))
})
```

The second test guards against a shared/overwritten value leaking between the
pre- and post-replacement arrays.

## Dependencies

- **Same file as #512** (`R/extract_replace_combine.R`) and likely the **same
  root cause** (fixed-data / unknowns value merging). Investigate the two
  together; neither strictly blocks the other, but a shared fix to the
  value-merge step could resolve both.
- Independent of #583 (also same file, different function).

## Risk / effort

Medium. Diagnosis-led; the patch is small once the stale-cache vs shared-
reference question is settled. Because the DAG's value previews feed printing
and `calculate()`, verify the wider extract/replace/combine suite still passes.

## Correction: keep the eager cache

An earlier version of this document proposed dropping the eager
`value = new_value` cache. **Do not.** That cache is what makes fixed values
display correctly through `[<-`. Removing it turns
[#512](https://github.com/greta-dev/greta/issues/512)'s display asymmetry
from a `cbind`-only bug into a general one.
