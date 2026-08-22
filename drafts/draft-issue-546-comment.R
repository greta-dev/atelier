#' Had a look at this on TF 2.21 / TFP 0.25. Two things.
#'
#' ## Why it will not reproduce in a reprex
#'
#' The warning comes from TensorFlow's Python logger on **stderr**, so knitr
#' never sees it — the chunk that triggers it renders with no output at all. It
#' may well have been reproducing all along, invisibly.
#'
#' In a plain R session it can be caught from Python's stderr (shown rather than
#' run, since this returns nothing under knitr too):

## retracing <- function(expr) {
##   out <- reticulate::py_capture_output(expr, type = "stderr")
##   grep("triggered tf.function retracing", strsplit(out, "\n")[[1]], value = TRUE)
## }

#' ## The two `## TF1/2 retracing` markers produce different warnings
#'
#' The sites flagged in 2023 turn out to be two separate phenomena.
#'
#' **`dag_class.R` (`opt` hessian) → `pfor`.** Reproducible, using the 2024
#' reprex above, and a clean on/off:
#'
#' ```
#' retracing(opt(m, hessian = TRUE))   # 1 warning, pfor.<locals>.f
#' retracing(opt(m, hessian = FALSE))  # 0 warnings
#' ```
#'
#' **`utils.R` (`build_sampler`) → `wrap_fn`.** A different function, seen when
#' several short-lived models are built in one session. **Intermittent**: the
#' same loop gave four warnings in one session and none in another, differing
#' only in what ran before it, so TF's detector seems sensitive to recent call
#' history. `wrap_fn` is reticulate's wrapper, so this is one `tf_function` per
#' model rather than one being reused — it shows up in test suites and
#' benchmarks, not in single-model use.
#'
#' ## What is *not* the cause
#'
#' The obvious suspect, ruled out. greta's two long-lived `tf_function`s settle
#' and stay settled — reusing one model across four runs:

library(greta)

m <- model(normal(0, 1, dim = 2))
for (i in 1:4) {
  invisible(mcmc(m, n_samples = 15, warmup = 15, chains = 2, verbose = FALSE))
}

c(log_prob = m$dag$tf_log_prob_function$experimental_get_tracing_count(),
  trace_values = m$dag$tf_trace_values_batch$experimental_get_tracing_count())

#' Neither has an `input_signature`, so each retraces once per distinct batch
#' shape and then caches: calling the log-prob function with 1 row, 1 row, 4
#' rows, 1 row gives counts of 1, 1, 2, 2. Bounded by how many chain counts a
#' session uses, not by how often it is called.
#'
#' So `reduce_retracing = TRUE` on those two — the fix the warning text
#' suggests — would do nothing. They are not the ones retracing.
#'
#' The two remaining cases have unrelated fixes: `pfor` is a real retrace in
#' ordinary use, `wrap_fn` is noise in loops.
