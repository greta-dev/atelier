# Issue #532 — `round()` warns instead of honouring `digits`

## Approach

`round.greta_array()` aborts whenever `digits != 0`:

```r
# R/functions.R:213-225
round.greta_array <- function(x, digits = 0) {
  if (digits != 0) {
    cli::cli_abort(c(
      "the {.val digits} argument of {.fun round} cannot be set for \\
      {.cls greta_array}s", ...
    ))
  }
  op("round", x, tf_operation = "tf$round")
}
```

TensorFlow has no direct digits argument, but R's rounding to `digits` places
is just scale → round → unscale. Implement the maintainer's sketch from the
issue as a `tf_round()` backend and route the op through it, passing `digits`
as an operation argument. Drop the abort.

New backend (in `R/tf_functions.R`, beside the other `tf_*` ops):

```r
tf_round <- function(x, digits) {
  factor <- fl(10)^digits
  tf$round(x * factor) / factor
}
```

`round.greta_array()` becomes:

```r
round.greta_array <- function(x, digits = 0) {
  digits <- as.integer(digits)
  op(
    "round",
    x,
    operation_args = list(digits = digits),
    tf_operation = "tf_round"
  )
}
```

`digits = 0` reduces to `tf$round(x)` (factor = 1), preserving current
behaviour, so no existing caller changes. Negative `digits` (rounding to tens,
hundreds) also falls out for free, matching base R.

## Files / functions touched

- `R/functions.R` — `round.greta_array()` (213–225); remove the abort, add the
  `operation_args`.
- `R/tf_functions.R` — new `tf_round()` helper (near `tf_mean` at
  `R/tf_functions.R:80`).
- `R/functions.R` — `@details` note at `R/functions.R:87` currently says
  "TensorFlow only enables rounding to integers"; update it.

## Acceptance test

Add to `tests/testthat/test_functions.R`:

```r
test_that("round() honours the digits argument", {
  x <- as_data(c(1.234, 5.678))
  expect_equal(
    as.vector(calculate(round(x, digits = 2))[[1]]),
    c(1.23, 5.68)
  )
  expect_equal(
    as.vector(calculate(round(x, digits = 0))[[1]]),
    c(1, 6)
  )
})

test_that("round() no longer warns/errors on non-zero digits", {
  x <- normal(0, 1)
  expect_no_error(round(x, digits = 3))
})
```

Replaces any existing snapshot test that asserted the abort message.

## Dependencies

- **Independent / orthogonal.** Only touches the rounding op.

## Risk / effort

Low. ~15 lines. Watch floating-point exactness in the numeric test — use
`expect_equal()` (tolerant) not `expect_identical()`; TF float32 vs R float64
means digits beyond ~6 may differ, so keep test cases to a few decimal places.
