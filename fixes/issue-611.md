# Issue #611 — `greta_conflicts()`

greta masks a large set of base/stats functions on attach (`%*%`,
`apply`, `beta`, `diag`, `poisson`, …). Mirror `tidyverse_conflicts()`
with a `greta_conflicts()` that reports which names greta masks and what
they mask.

## Approach

Self-contained; good first issue. Compute the conflict set by comparing
greta's exports against the currently attached search path:

```r
# R/greta_conflicts.R (new, exported)
greta_conflicts <- function() {
  # ls() on the attached package, not getNamespaceExports(): the latter
  # returns 27 names, 5 of them S4 method-table internals such as
  # `.__T__[[<-:base`
  greta_exports <- ls("package:greta")
  masked <- Filter(function(nm) {
    # nm is exported by greta AND exists elsewhere on the search path
    exists(nm, where = "package:greta", inherits = FALSE) &&
      length(find(nm)) > 1
  }, greta_exports)
  # build a cli-styled report: greta::fn() masks pkg::fn()
  ...
}
```

Format the report with the cli package (greta already depends on cli),
matching the tidyverse look. Optionally call it from `.onAttach`
(`R/zzz.R`) behind an option so startup can show the conflicts, mirroring
tidyverse.

## Files / functions touched

- New `R/greta_conflicts.R` — exported `greta_conflicts()`, roxygen,
  NEWS bullet.
- `R/zzz.R` — optional opt-in call from `.onAttach`.
- Uses `cli` (already a dependency).

## Acceptance test

`tests/testthat/test-greta-conflicts.R`:

```r
test_that("greta_conflicts reports known masks", {
  out <- greta_conflicts()
  nms <- conflict_names(out)   # helper extracting reported names
  expect_true("diag" %in% nms)
  expect_true("poisson" %in% nms)
})

test_that("greta_conflicts prints without error", {
  expect_snapshot(print(greta_conflicts()))
})
```

## Dependencies

- Fully independent. Orthogonal to every other issue in the plan.
- Pairs naturally with the tidyverse article (#257) but does not depend
  on it.

## Risk / effort

Low. A single self-contained helper plus a snapshot test; classic good
first issue.
