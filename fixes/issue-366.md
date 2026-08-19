# Issue #366 — `get_unique_name()` may collide

## Approach

Node names are minted by `create_unique_name()`, which interpolates `rhex()`:

```r
# R/node_class.R:262-264
create_unique_name = function() {
  self$unique_name <- glue::glue("node_{rhex()}")
}
```

```r
# R/utils.R:252-255
rhex <- function() {
  paste(as.raw(sample.int(256L, 4, TRUE) - 1L), collapse = "")
}
```

`rhex()` draws 4 random bytes → a 32-bit space (~4.3e9 values). By the birthday
bound, collisions become likely well before a million nodes (the issue shows
~126 collisions in 1e6 draws). Because names key the TensorFlow graph, a
collision silently corrupts the DAG.

Fix: make identity **structural** rather than probabilistic by combining a
process-lifetime monotonic counter with the random suffix. A counter guarantees
uniqueness within a session; the random prefix keeps names stable-looking and
avoids collisions across the rare cases where counters reset (e.g. reloading).

Concrete change — introduce a counter in `greta_stash` (the existing internal
environment used for session state) and build the name from it:

```r
create_unique_name = function() {
  greta_stash$node_counter <- (greta_stash$node_counter %||% 0L) + 1L
  self$unique_name <- glue::glue("node_{rhex()}_{greta_stash$node_counter}")
}
```

The counter makes names unique by construction; `rhex()` is retained only as a
readability/back-compat prefix. (A pure counter also works; keeping `rhex()`
minimises churn in snapshot tests that match the `node_<hex>` shape.)

## Files / functions touched

- `R/node_class.R` — `create_unique_name()` (262–264).
- `R/greta_stash.R` — declare/initialise `node_counter` alongside the other
  stash fields.
- `R/utils.R` — `rhex()` (252–255) can stay; optionally widen to 8 bytes if the
  prefix is kept for cosmetic reasons only.

## Acceptance test

Add to `tests/testthat/test-node_class.R` (create if absent; mirrors
`R/node_class.R`):

```r
test_that("node names are unique across many nodes", {
  names <- replicate(1e4, {
    n <- data_node$new(1)
    n$unique_name
  })
  expect_equal(length(unique(names)), length(names))
})
```

10⁴ is enough to be fast while a 32-bit `rhex()` alone would already show a
non-trivial collision probability; the counter drives collisions to zero
deterministically.

## Dependencies

- **Independent / orthogonal.** Touches only node naming.
- Related to the flat node registry work, which would make ids fully
  structural, but this is a self-contained interim fix that does **not** depend
  on that work and does not block it.

## Risk / effort

Low. Small change. Risk: any snapshot/test that hard-codes an exact
`node_<hex>` string would need its regex loosened to allow the trailing
counter; grep the test suite for `node_` before landing.
