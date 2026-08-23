`model(compile = TRUE)` is documented as applying XLA JIT compilation. It
does nothing at all — the value is stored on the dag and never read again.

Found while sweeping the `#TF1/2` markers for \#745.

``` r
library(greta)
#> 
#> Attaching package: 'greta'
#> The following objects are masked from 'package:stats':
#> 
#>     binomial, cov2cor, poisson
#> The following objects are masked from 'package:base':
#> 
#>     %*%, %o%, apply, backsolve, beta, chol2inv, colMeans, colSums,
#>     diag, eigen, forwardsolve, gamma, identity, outer, rowMeans,
#>     rowSums, sweep, tapply

x <- normal(0, 1)
#> ℹ Initialising python and checking dependencies, this may take a moment.
#> ✔ Initialising python and checking dependencies ... done!
#> 
m_on <- model(x, compile = TRUE)
m_off <- model(x, compile = FALSE)
```

It is [stored on the dag](https://github.com/greta-dev/greta/blob/e8563dae0ef2b8be384fac023f62df1febf17ae6/R/dag_class.R#L39) and never read again.

``` r
c(on = m_on$dag$compile, off = m_off$dag$compile)
#>    on   off 
#>  TRUE FALSE
```

and that is the only thing that ever happens to it. Nothing reads it:

``` r
## $ grep -rn '\$compile' R/
## R/dag_class.R:39:      self$compile <- compile
```

## What I expect

[`?model`](https://github.com/greta-dev/greta/blob/e8563dae0ef2b8be384fac023f62df1febf17ae6/R/greta_model_class.R#L26-L29) says it applies *“XLA JIT
compilation to the TensorFlow graph representing the model”*, so
`compile = TRUE` should compile with XLA and `compile = FALSE` should not.

## What happens instead

Neither does anything. The argument has been inert since
[`7e3e81ac`](https://github.com/greta-dev/greta/commit/7e3e81ac)
(Jan 2023), which removed its only consumer — the TF1 session-config API,
`config$graph_options$optimizer_options$global_jit_level`. TF2 has no such
thing, so removing it was right, but nothing replaced it.

## Wiring it up is two lines

`jit_compile` passes straight through `tf_function()`’s `...` to Python, so
at the two `tf_function()` sites in `R/dag_class.R`:

``` r
## self$tf_log_prob_function <- tensorflow::tf_function(
##   f = self$generate_log_prob_function(),
##   jit_compile = self$compile
## )
```

With that applied, `devtools::test()` goes from
`FAIL 0 | PASS 1952` to `FAIL 8 | PASS 1934`. All eight failures are
`wishart()`, `lkj_correlation()` and `cholesky_variable()` models.

## Why they break

That needs the patch to reproduce, so here is the underlying operation
instead. greta traces its log-prob function with a *dynamic* batch
dimension — `shape = list(NULL, n_free)` — so one traced function serves any
number of chains. Take the gradient of a cholesky bijector through that:

``` r
library(tensorflow)
tfp <- reticulate::import("tensorflow_probability")

grad_through <- function(bijector, batch_shape, jit) {
  f <- tf_function(
    function(v) {
      with(tf$GradientTape() %as% tape, {
        tape$watch(v)
        loss <- tf$reduce_sum(bijector$forward(v))
      })
      tape$gradient(loss, v)
    },
    input_signature = list(
      tf$TensorSpec(shape = batch_shape, dtype = tf$float32)
    ),
    jit_compile = jit
  )
  x <- tf$constant(matrix(c(0.5, 0.3, 0.8), nrow = 1), dtype = tf$float32)
  tryCatch(
    {
      invisible(f(x))
      cat("OK\n")
    },
    error = function(e) {
      # first line, plus the node that failed - the rest is a stack trace of
      # local paths
      lines <- strsplit(conditionMessage(e), "\n")[[1]]
      cat(lines[1], "\n")
      cat(grep("node ", lines, value = TRUE)[1], "\n")
    }
  )
}
```

With a **static** shape, XLA is perfectly happy:

``` r
grad_through(tfp$bijectors$FillScaleTriL(), list(1L, 3L), jit = TRUE)
#> OK
```

With the **dynamic** batch dimension greta actually uses, it is not:

``` r
grad_through(tfp$bijectors$FillScaleTriL(), list(NULL, 3L), jit = TRUE)
#> tensorflow.python.framework.errors_impl.InvalidArgumentError: Reading input as constant from a dynamic tensor is not yet supported. Xla shape: s32[<=3] 
#>   [[{{node gradient_tape/fill_scale_tril/forward/transform_diagonal/forward/zeros}}]]
```

Same for the other cholesky bijector:

``` r
grad_through(tfp$bijectors$CorrelationCholesky(), list(NULL, 3L), jit = TRUE)
#> tensorflow.python.framework.errors_impl.InvalidArgumentError: Reading input as constant from a dynamic tensor is not yet supported. Xla shape: s32[<=3] 
#>   [[{{node gradient_tape/correlation_cholesky/forward/zeros}}]]
```

And both are fine with the dynamic shape as long as XLA is off, which is
the status quo:

``` r
grad_through(tfp$bijectors$FillScaleTriL(), list(NULL, 3L), jit = FALSE)
#> OK
```

So: the gradients of `FillScaleTriL` and `CorrelationCholesky` call
`set_diag`, which reads a shape as a constant. Under XLA with a dynamic
leading dimension that shape is `s32[<=3]` — bounded, not known at compile
time — and XLA cannot read it as a constant. Removing the dynamic dimension
makes the failure go away, which is what pins the cause.

## Why this is a problem, and what wiring it buys

Today a documented argument silently does nothing, and a user who sets
`compile = FALSE` to avoid a slow model definition gets no change and no
warning.

**Measured** in
[greta.benchmarks/2026-08-19-jit-compile-vs-main/results.md](https://github.com/greta-dev/greta.benchmarks/blob/main/2026-08-19-jit-compile-vs-main/results.md),
from [`01-measure.R`](https://github.com/greta-dev/greta.benchmarks/blob/main/2026-08-19-jit-compile-vs-main/01-measure.R): wiring it through makes
[sampling **4.8% faster**](https://github.com/greta-dev/greta.benchmarks/blob/main/2026-08-19-jit-compile-vs-main/results.md#what-this-says) on a plain
regression — 816 ms against 858 ms, Welch p = 0.006, 95% CI \[9, 55\] ms, at 50
iterations per branch. Model definition is unchanged, as expected: XLA
compiles at first call, not at definition.

That number needed 50 iterations to see. At 10 the same comparison gave 27 ms
and 62 ms on separate runs, against a within-branch sd of ~58 ms — so treat
any small run of it as uninformative.

**But `compile` defaults to `TRUE`**, so wiring it as-is would start failing
every `wishart()`, `lkj_correlation()` and `cholesky_variable()` model.

## Three options

1.  **Wire it up and exclude the cholesky family** — take the 4.8%, warn when
    `compile = TRUE` meets a model XLA cannot compile, and say so in `?model`.
    This is what the measurement favours.
2.  **Fix the documentation** — say the argument is inert, or remove it.
    Cheapest, and gives up a real if modest speed-up.
3.  **Deprecate `compile`** — now has a measured cost, where before it looked
    free.

Also worth fixing whichever way this goes:
[`model()` defaults `compile = TRUE`](https://github.com/greta-dev/greta/blob/e8563dae0ef2b8be384fac023f62df1febf17ae6/R/greta_model_class.R#L52) while
[`dag_class$new()` defaults `FALSE`](https://github.com/greta-dev/greta/blob/e8563dae0ef2b8be384fac023f62df1febf17ae6/R/dag_class.R#L24).

## A test for this

``` r
## test_that("compile = TRUE actually compiles with XLA", {
##   m <- model(normal(0, 1), compile = TRUE)
##   expect_true(m$dag$tf_log_prob_function$`_jit_compile`)
## })
```
