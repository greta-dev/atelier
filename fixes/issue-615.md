# Issue #615 — misspelt argument names pass silently

## Approach

`calculate(x, nsims = 5)` (note the typo) does not warn. `nsim` is a named
formal of `calculate()`, but `nsims` is not, so it is swept into `...` and
treated as a *target* greta array. It then trips the generic
`check_greta_arrays()` guard with a misleading message ("`nsims` is not a
<greta array>"), never hinting that the user meant `nsim`.

```r
# R/calculate.R:152-196 — nsims lands in `...`, becomes a "target"
target <- list(...)               # list(x, nsims = 5)
...
check_greta_arrays(target, "calculate", "Perhaps you forgot to ...")
```

Approach: before treating `...` names as targets, compare each *named* `...`
element against the function's real argument names plus known aliases, and if a
name is a near-match (small edit distance) to a formal, abort with a
did-you-mean hint. Non-greta-array, non-near-match names keep the existing
error.

Add a small reusable checker (usable by other varargs greta functions too):

```r
check_dots_misspelled <- function(dots, known, call = rlang::caller_env()) {
  nms <- names(dots)
  named <- nms[nzchar(nms %||% "")]
  # only flag names whose value is not a greta array
  suspect <- named[!are_greta_array(dots[named])]
  for (nm in suspect) {
    # bounded edit distance, not agrep: agrep's max.distance is a
    # *fraction of pattern length*, so short names match almost anything
    d <- utils::adist(nm, known)[1, ]
    hit <- known[d <= 2 & nchar(nm) >= 3][order(d[d <= 2 & nchar(nm) >= 3])]
    if (length(hit)) {
      cli::cli_abort(c(
        "Unknown argument {.arg {nm}} passed to {.fun calculate}.",
        "i" = "Did you mean {.arg {hit[[1]]}}?"
      ), call = call)
    }
  }
}
```

Wire it into `calculate()` just after names are resolved
(`R/calculate.R:185`), with
`known = c("values", "nsim", "seed", "precision", "trace_batch_size",
"compute_options")`. `utils::adist()` (base R, Levenshtein) keeps it dependency-free;
`nsims`->`nsim` is distance 1 and matches, while a legitimately named target
greta array is skipped by the `are_greta_array()` filter.

**Do not use `agrep(max.distance = 0.34)`.** An earlier version of this
document did. `max.distance` is a *fraction of pattern length*, so short
names match nearly every formal: `sd`, `x` and `n` each match all six of
`calculate()`'s formals, and `beta` matches `trace_batch_size`. Those are
exactly the names users give greta arrays, so `calculate(x, sd = 3)` would
suggest "did you mean `trace_batch_size`?" - worse than saying nothing. Pin
those four as regression tests.

## Files / functions touched

- `R/checkers.R` — new `check_dots_misspelled()` helper (near the other
  `check_*` functions, e.g. `check_greta_arrays` at `R/checkers.R:610`).
- `R/calculate.R` — call the helper in `calculate()` after
  `names(target) <- names` (`R/calculate.R:184-185`), before
  `check_greta_arrays()` (192).

## Acceptance test

Add to `tests/testthat/test_calculate.R`:

```r
test_that("calculate() flags a misspelt nsim argument", {
  x <- normal(0, 1)
  expect_snapshot(calculate(x, nsims = 5), error = TRUE)
})

test_that("calculate() still accepts a correctly named greta array target", {
  x <- normal(0, 1)
  y <- x + 1
  expect_no_error(calculate(y, values = list(x = 2)))
})
```

The snapshot should show the "Did you mean `nsim`?" hint. The second test
guards against false positives on genuine named targets.

## Dependencies

- **Complementary to #784** — both harden `calculate()`'s error surface and
  share `calculate.R`/`checkers.R`. Independent code paths; can land in either
  order. Coordinating them keeps the two `calculate()` error messages
  stylistically consistent.
- The helper is written to be reusable by other varargs greta functions (a
  broader "misspelt argument" rollout), but this issue only needs the
  `calculate()` wiring.

## Risk / effort

Low–medium; flagged in the issue as a good contributor task. Risk: an
over-eager `agrep` threshold could flag a legitimate target whose name happens
to resemble a formal — the `are_greta_array()` pre-filter plus a conservative
`max.distance` mitigate this, and the second test pins it.
