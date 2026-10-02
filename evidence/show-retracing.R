# Show greta's tracing: every traced function greta creates, how many times
# each was traced, and TensorFlow's own retracing warnings.
#
# Run from a greta checkout, in a fresh R session, once per branch:
#
#   git switch main
#   Rscript --vanilla ~/github/greta-dev/atelier/evidence/show-retracing.R
#   git switch faster-hessians-i546
#   Rscript --vanilla ~/github/greta-dev/atelier/evidence/show-retracing.R
#
# A function traced more than once is retracing: TensorFlow rebuilt its graph.

# record every traced function greta makes. This has to happen before greta is
# loaded, and it catches everything because greta always calls
# tensorflow::tf_function() by its full name
made <- list()
original_tf_function <- tensorflow::tf_function
utils::assignInNamespace(
  "tf_function",
  function(f, input_signature = NULL, ...) {
    traced <- original_tf_function(f, input_signature = input_signature, ...)
    made[[length(made) + 1]] <<- list(
      traced = traced,
      made_by = deparse(sys.call(-1)[[1]])
    )
    traced
  },
  ns = "tensorflow"
)

pkgload::load_all(".", quiet = TRUE)

# TensorFlow logs its retracing warning through Python, where R cannot see
# it; pointing its logger at stderr lets py_capture_output() collect it
rebind_tf_logger <- function() {
  reticulate::py_run_string(paste(
    "import sys",
    "from tensorflow.python.platform import tf_logging",
    "for _h in tf_logging.get_logger().handlers: _h.stream = sys.stderr",
    sep = "\n"
  ))
}

trace_counts <- function() {
  vapply(
    made,
    function(x) as.integer(x$traced$experimental_get_tracing_count()),
    1L
  )
}

# run `expr`, then print TensorFlow's retracing warnings and every function
# greta traced while it ran, including functions made earlier - model() makes
# the log-density and trace-values functions before anything calls them
show_tracing <- function(label, expr) {
  before <- trace_counts()
  logged <- reticulate::py_capture_output(
    {
      rebind_tf_logger()
      force(expr)
    },
    type = "stderr"
  )
  warnings <- grep(
    "triggered tf.function retracing",
    strsplit(logged, "\n")[[1]],
    value = TRUE
  )

  after <- trace_counts()
  during <- after - c(before, rep(0L, length(after) - length(before)))
  traced <- data.frame(
    made_by = vapply(made, `[[`, "", "made_by"),
    traces = during
  )

  cat("\n==", label, "==\n")
  cat("retracing warnings:", length(warnings), "\n")
  if (length(warnings) > 0) {
    cat(substr(warnings, 1, 110), sep = "\n")
  }
  cat("functions traced during this call:\n")
  print(traced[traced$traces > 0, ], row.names = FALSE)
}

cat("greta from", getwd(), "at", system("git rev-parse --short HEAD", intern = TRUE), "\n")

# the linear example
linear_model <- function() {
  int <- normal(0, 10)
  coef <- normal(0, 10)
  sd <- cauchy(0, 3, truncation = c(0, Inf))
  mu <- int + coef * attitude$complaints
  distribution(attitude$rating) <- normal(mu, sd)
  list(model = model(int, coef, sd), mu = mu)
}

set.seed(2026 - 09 - 30)

linear <- linear_model()
show_tracing(
  "opt() with adam()",
  opt(linear$model, optimiser = adam(), max_iterations = 100)
)

linear <- linear_model()
show_tracing(
  "mcmc()",
  draws <- mcmc(
    linear$model,
    n_samples = 200,
    warmup = 200,
    chains = 4,
    verbose = FALSE
  )
)
show_tracing("calculate() on those draws", calculate(linear$mu, values = draws))

# greta-dev/greta#546's case: twenty separate targets, each needing a hessian
y <- rnorm(20)
target_names <- paste0("b", 1:20)
for (name in target_names) {
  assign(name, variable())
}
distribution(y) <- normal(do.call(c, mget(target_names)), 1)
many_targets <- eval(as.call(c(quote(model), lapply(target_names, as.name))))
show_tracing(
  "opt(hessian = TRUE), 20 targets",
  opt(many_targets, hessian = TRUE)
)
