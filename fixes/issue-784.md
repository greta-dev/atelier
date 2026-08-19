# Issue #784 — `calculate()` produces the wrong error message

## Approach

When `calculate()` is called without values or `nsim`, the error is confusing:
it surfaces from `lapply()` inside `calculate.R`, it never mentions that setting
`nsim` is an option, and its pluralisation is wrong. The cause is in
`check_dependencies_satisfied()`, which **builds a good message and then throws
a different, worse one**:

```r
# R/checkers.R:749-778
if (any(matches)) {
  names_text <- toString(unmet_names)
  msg <- cli::format_error(c(
    "Please provide values for the following {length(names_text)} \\
     {.cls greta_array}{?s}:",     # length(names_text) is always 1 (a string)
    "{.var {names_text}}"
  ))
} else {
  msg <- cli::format_error(
    "The names of the missing {.cls greta_array}s could not be detected"
  )
}

final_msg <- cli::format_error(c(
  "greta array(s) do not have values",
  "values have not been provided for all {.cls greta_array}s on which \\
   the target depends, and {.var nsim} has not been set.",   # <- the useful hint
  "{msg}"
))

rlang::abort(message = msg, call = call)   # <- aborts with msg, discards final_msg!
```

Three concrete defects:

1. **`final_msg` is discarded.** The abort uses `msg`, so the "and `nsim` has
   not been set" hint the author already wrote never reaches the user. Fix:
   `rlang::abort(message = final_msg, call = call)`.
2. **Broken pluralisation.** `length(names_text)` is the length of a single
   comma-joined string (always `1`), so `{?s}` never pluralises. Use the true
   count `length(unmet_names)` and build the list from the vector, not
   `toString()`.
3. **Wrong call frame.** The message reads as coming from `lapply()` because
   `check_dependencies_satisfied()` defaults `call = rlang::caller_env()`, which
   is the `lapply` FUN frame at `R/calculate.R:407`. Fix: pass an explicit
   user-facing `call` from `calculate()` down to the checker.

## Files / functions touched

- `R/checkers.R` — `check_dependencies_satisfied()` (699–780): fix the
  `length()` count and pluralisation (749–758), abort with `final_msg`
  (775–778).
- `R/calculate.R` — the `lapply()` call at `R/calculate.R:407` should pass an
  explicit `call = ` (e.g. the calculate call captured near
  `R/calculate.R:152`) so the backtrace points at `calculate()`, not `lapply`.

## Acceptance test

Snapshot the two reprex cases in `tests/testthat/test_calculate.R`:

```r
test_that("calculate() gives a helpful error when values are missing", {
  a <- normal(0, 1)
  expect_snapshot(calculate(a), error = TRUE)
})

test_that("calculate() error mentions nsim when names cannot be detected", {
  b <- 1 + normal(0, 1)
  expect_snapshot(calculate(b), error = TRUE)
})
```

The accepted snapshots must (a) name `a`, (b) mention that `nsim` can be set,
and (c) not reference `lapply`. Review with `testthat::snapshot_review()`.

## Dependencies

- **Complementary to #615** (both improve `calculate()` argument/error
  handling, both live in `calculate.R` + `checkers.R`). They touch different
  code paths (#784 = missing-values message; #615 = misspelt-argument
  detection) and can land independently, but sharing a review is sensible to
  keep the `calculate()` error surface consistent.
- Message-only change: no behaviour change, so it does not block or depend on
  any functional fix.

## Risk / effort

Low ("quick"). Pure messaging. Risk: snapshot churn — this will update existing
`calculate` error snapshots; regenerate and review them deliberately.
