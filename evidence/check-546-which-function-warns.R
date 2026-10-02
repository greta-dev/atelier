# Which function is TensorFlow's retracing warning about, when a session
# samples several short-lived models (greta-dev/greta#546, 2026-08-23 note)?
#
#   Rscript --vanilla ~/github/greta-dev/atelier/evidence/check-546-which-function-warns.R
#
# Run from a greta checkout. Records every function greta traces, with its
# Python address, and matches the addresses the warnings name. Addresses are
# printed truncated to 32 bits by sprintf(), so compare the low eight digits.
#
# Result, 2026-09-30, TensorFlow 2.21.0, on main and on faster-hessians-i546
# alike: 4 warnings, naming the log-density and trace-values functions of the
# 5th and 6th models, each traced once. TensorFlow keys its retracing counter
# on the Python code object (polymorphic_function.py,
# _get_key_for_call_stats()), and every function greta traces is an R
# function reticulate wraps in the same closure, wrap_fn.<locals>.fn, so all
# of them share one counter. A warning takes 5 traces in 10 calls, and there
# are at most 2 warnings per counter per session.

made <- list()
original <- tensorflow::tf_function
utils::assignInNamespace("tf_function", function(f, input_signature = NULL, ...) {
  traced <- original(f, input_signature = input_signature, ...)
  made[[length(made) + 1]] <<- list(traced = traced, made_by = deparse(sys.call(-1)[[1]]), i = length(made) + 1)
  traced
}, ns = "tensorflow")
pkgload::load_all(".", quiet = TRUE)
reticulate::py_run_string("import sys\nfrom tensorflow.python.platform import tf_logging\nfor _h in tf_logging.get_logger().handlers: _h.stream = sys.stderr")
builtins <- reticulate::import_builtins()
addresses <- character()
logged <- reticulate::py_capture_output({
  for (i in 1:10) {
    y <- as_data(rnorm(10, i)); mu <- normal(0, 10); distribution(y) <- normal(mu, 1)
    invisible(mcmc(model(mu), n_samples = 20, warmup = 20, verbose = FALSE))
    # record each new function's Python address while it is still alive
    for (j in seq_along(made)) {
      if (is.null(made[[j]]$address)) {
        made[[j]]$address <- sprintf("0x%x", builtins$id(made[[j]]$traced$python_function))
        made[[j]]$model <- i
      }
    }
  }
}, type = "stderr")
warned <- regmatches(logged, gregexpr("calls to <function [^ ]+ at (0x[0-9a-f]+)", logged))[[1]]
warned <- sub(".* at ", "", warned)
cat("warned about addresses:", warned, "\n")
tab <- data.frame(model = vapply(made, function(x) x$model %||% NA_integer_, 1L),
                  made_by = gsub("self[$]", "", vapply(made, `[[`, "", "made_by")),
                  address = vapply(made, function(x) x$address %||% NA_character_, ""))
tab$warned <- tab$address %in% warned
print(tab, row.names = FALSE)
