# Issue #514 — `apply()` on a greta array

## Approach

Since this issue was filed (greta 0.4.2, 2022), `apply.greta_array()` has been
added (commit `89c11f24`, "get apply working for single integer margins") and
now lives at `R/functions.R:963`. So the *shim exists* — but it does not accept
the call in the reprex:

```r
apply(z, 1, mean)   # FUN is the closure `mean`, not the string "mean"
```

`apply.greta_array()` does `fun <- match.arg(FUN)` against a character menu
(`R/functions.R:966-978`). Passing the bare function `mean` makes `match.arg()`
error with `'arg' must be NULL or a character vector`. Base `apply()` takes a
*function*; greta's takes a *string naming a reducer*. That mismatch is the
remaining bug.

Fix: coerce common base reducers passed as functions to their string names
before `match.arg()`, and give a clear error for genuinely unsupported `FUN`.

```r
if (is.function(FUN)) {
  fun_name <- fn_to_name(FUN)   # maps mean->"mean", sum->"sum", ...
  if (is.na(fun_name)) {
    cli::cli_abort(c(
      "{.arg FUN} must be one of the supported reducers for \\
      {.cls greta_array}s",
      "i" = "Supported: {.val {eval(formals()$FUN)}}",
      "i" = "Pass it as a string, e.g. {.code apply(x, 1, \"mean\")}"
    ))
  }
  FUN <- fun_name
}
fun <- match.arg(FUN)
```

`fn_to_name()` compares the supplied closure by identity against
`base::mean`, `base::sum`, `base::max`, `base::min`, `base::prod`,
`base::cumsum`, `base::cumprod` and returns the matching name or `NA`. This lets
both `apply(z, 1, mean)` and `apply(z, 1, "mean")` work.

## Files / functions touched

- `R/functions.R` — `apply.greta_array()` (963–1036); add the function-to-name
  coercion just before `fun <- match.arg(FUN)` at `R/functions.R:978`.
- `R/functions.R` — `@usage`/`@details` for `apply` at `R/functions.R:80`,
  clarifying that `FUN` may be a supported base reducer or its name.
- Optionally a small internal helper `fn_to_name()` in `R/utils.R`.

## Acceptance test

Add to `tests/testthat/test_functions.R`:

```r
test_that("apply() accepts a bare function and a string FUN", {
  z <- as_data(matrix(1:6, 2, 3))
  by_fun <- apply(z, 1, mean)
  by_str <- apply(z, 1, "mean")
  expect_s3_class(by_fun, "greta_array")
  expect_equal(
    as.vector(calculate(by_fun)[[1]]),
    as.vector(calculate(by_str)[[1]])
  )
  expect_equal(as.vector(calculate(by_fun)[[1]]), c(3, 4))
})

test_that("apply() errors helpfully on unsupported FUN", {
  z <- as_data(matrix(1:6, 2, 3))
  expect_snapshot(apply(z, 1, median), error = TRUE)
})
```

## Dependencies

- **Conceptually precedes #783** ("extends the apply work in #514"). #783 adds
  2-D index support to `tapply()` and can reuse the same permute/reshape idiom
  `apply.greta_array()` uses for multi-element margins. Not a hard blocker: the
  two touch different functions in the same file.
- Otherwise independent.

## Risk / effort

Low–medium. The reducer path already exists; this is an ergonomic fix plus a
helpful error. Confirm the function-identity match survives namespacing (e.g.
`base::mean` vs a user-masked `mean`); falling back to the clear error when no
match is found keeps it safe.
