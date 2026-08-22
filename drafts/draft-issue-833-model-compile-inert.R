#' `model(compile = TRUE)` is documented as applying XLA JIT compilation. It
#' does nothing at all — the value is stored on the dag and never read again.
#'
#' Found while sweeping the `#TF1/2` markers for #745.

library(greta)

x <- normal(0, 1)
m_on <- model(x, compile = TRUE)
m_off <- model(x, compile = FALSE)

#' The flag is stored:

c(on = m_on$dag$compile, off = m_off$dag$compile)

#' and that is the only thing that ever happens to it. Nothing reads it:

## $ grep -rn '\$compile' R/
## R/dag_class.R:39:      self$compile <- compile

#' ## What I expect
#'
#' `?model` says: *"whether to apply XLA JIT compilation to the TensorFlow
#' graph representing the model. This may slow down model definition."* So
#' `compile = TRUE` should compile the graph with XLA, and `compile = FALSE`
#' should not.
#'
#' ## What happens instead
#'
#' Neither does anything. The argument has been inert since
#' [`7e3e81ac`](https://github.com/greta-dev/greta/commit/7e3e81ac)
#' (Jan 2023), which removed its only consumer — the TF1 session-config API,
#' `config$graph_options$optimizer_options$global_jit_level`. TF2 has no such
#' thing, so removing it was right, but nothing replaced it.
#'
#' ## Wiring it up is two lines
#'
#' `jit_compile` passes straight through `tf_function()`'s `...` to Python, so
#' at the two `tf_function()` sites in `R/dag_class.R`:

## self$tf_log_prob_function <- tensorflow::tf_function(
##   f = self$generate_log_prob_function(),
##   jit_compile = self$compile
## )

#' With that applied, `devtools::test()` goes from
#' `FAIL 0 | PASS 1952` to `FAIL 8 | PASS 1934`. All eight failures are
#' `wishart()`, `lkj_correlation()` and `cholesky_variable()` models.
#'
#' ## Why they break
#'
#' That needs the patch to reproduce, so here is the underlying operation
#' instead. greta traces its log-prob function with a *dynamic* batch
#' dimension — `shape = list(NULL, n_free)` — so one traced function serves any
#' number of chains. Take the gradient of a cholesky bijector through that:

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

#' With a **static** shape, XLA is perfectly happy:

grad_through(tfp$bijectors$FillScaleTriL(), list(1L, 3L), jit = TRUE)

#' With the **dynamic** batch dimension greta actually uses, it is not:

grad_through(tfp$bijectors$FillScaleTriL(), list(NULL, 3L), jit = TRUE)

#' Same for the other cholesky bijector:

grad_through(tfp$bijectors$CorrelationCholesky(), list(NULL, 3L), jit = TRUE)

#' And both are fine with the dynamic shape as long as XLA is off, which is
#' the status quo:

grad_through(tfp$bijectors$FillScaleTriL(), list(NULL, 3L), jit = FALSE)

#' So: the gradients of `FillScaleTriL` and `CorrelationCholesky` call
#' `set_diag`, which reads a shape as a constant. Under XLA with a dynamic
#' leading dimension that shape is `s32[<=3]` — bounded, not known at compile
#' time — and XLA cannot read it as a constant. Removing the dynamic dimension
#' makes the failure go away, which is what pins the cause.
#'
#' ## Why this is a problem
#'
#' Today: a documented argument silently does nothing, and a user who sets
#' `compile = FALSE` to avoid a slow model definition gets no change and no
#' warning.
#'
#' If wired up as-is: `compile` defaults to `TRUE`, so every `wishart()`,
#' `lkj_correlation()` and `cholesky_variable()` model would start failing.
#'
#' ## Suggested direction
#'
#' The argument should do something. When it is wired up:
#'
#' - warn on `compile = TRUE` that XLA does not support every model, naming the
#'   cholesky/LKJ limitation
#' - say so in `?model`
#'
#' **There is no speed measurement yet.** An earlier attempt patched the working
#' tree and compared `compile = TRUE` against `compile = FALSE` in one session;
#' it suggested no steady-state difference and a one-off compilation cost on
#' first run, but on three replicates, and it was discarded as not reproducible
#' by anyone else. A `{cross}` branch comparison replacing it is written at
#' `greta.benchmarks/2026-08-19-jit-compile-vs-main/run.R` and has not been run.
#'
#' Worth knowing before it is: that script measures a two-parameter regression,
#' and every model in the benchmark suite is 4 free parameters or fewer, so it
#' can only speak to small models.
#'
#' Also: `model()` defaults `compile = TRUE` while `dag_class$new()` defaults
#' `FALSE`.
#'
#' ## A test for this

## test_that("compile = TRUE actually compiles with XLA", {
##   m <- model(normal(0, 1), compile = TRUE)
##   expect_true(m$dag$tf_log_prob_function$`_jit_compile`)
## })
