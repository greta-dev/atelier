# The examples from greta-dev/greta#546, run as they were posted: do they
# still print TensorFlow's retracing warning, and how many times is each of
# greta's functions traced?
#
# Run from a greta checkout, in a fresh R session, once per branch:
#
#   Rscript --vanilla ~/github/greta-dev/atelier/evidence/check-546-examples.R
#
# The warning goes to Python's stderr, where R never sees it, so it is
# captured here by pointing TensorFlow's logger at stderr and reading that.

pkgload::load_all(".", quiet = TRUE)

rebind_tf_logger <- function() {
  reticulate::py_run_string(paste(
    "import sys",
    "from tensorflow.python.platform import tf_logging",
    "for _h in tf_logging.get_logger().handlers: _h.stream = sys.stderr",
    sep = "\n"
  ))
}

# the retracing warnings TensorFlow printed while `expr` ran, shortened to
# the function each names
retracing <- function(expr) {
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
  sub(".*calls to <function ([^ ]+) at.*", "\\1", warnings)
}

report <- function(label, warnings) {
  cat(sprintf("%-55s %d warnings", label, length(warnings)))
  if (length(warnings) > 0) {
    cat(":", paste(unique(warnings), collapse = ", "))
  }
  cat("\n")
}

cat("greta at", system("git rev-parse --short HEAD", intern = TRUE))
dirty <- length(system("git status --porcelain -- R", intern = TRUE)) > 0
cat(if (dirty) " plus uncommitted changes\n" else "\n")

# 1. #546, 2024-05-10: five scalar targets, each needing a hessian
set.seed(2026 - 09 - 30)
sd <- runif(5)
x <- rnorm(5, 2, 0.1)
z1 <- variable(dim = 1)
z2 <- variable(dim = 1)
z3 <- variable(dim = 1)
z4 <- variable(dim = 1)
z5 <- variable(dim = 1)
z <- c(z1, z2, z3, z4, z5)
distribution(x) <- normal(z, sd)
m <- model(z1, z2, z3, z4, z5)
report("1. opt(m, hessian = TRUE), five scalar targets", retracing(opt(m, hessian = TRUE)))
report("   opt(m, hessian = FALSE), the same model", retracing(opt(m, hessian = FALSE)))

# 2. #546, 2026-08-23: several short-lived models in one session, as a test
#    suite or a benchmark builds them. Reported as intermittent, so run it
#    three times
short_lived <- function() {
  for (i in 1:10) {
    y <- as_data(rnorm(10, i))
    mu <- normal(0, 10)
    distribution(y) <- normal(mu, 1)
    invisible(mcmc(model(mu), n_samples = 20, warmup = 20, verbose = FALSE))
  }
}
for (attempt in 1:3) {
  report(
    sprintf("2. ten short-lived models sampled, attempt %d", attempt),
    retracing(short_lived())
  )
}

# 3. #546, 2026-08-23: one model sampled four times, and how often its two
#    long-lived functions were traced
reused <- model(normal(0, 1, dim = 2))
warnings <- retracing(
  for (i in 1:4) {
    invisible(mcmc(reused, n_samples = 15, warmup = 15, chains = 2, verbose = FALSE))
  }
)
report("3. one model sampled four times", warnings)
cat(sprintf(
  "   traces: log density %d, trace values %d\n",
  as.integer(reused$dag$tf_log_prob_function$experimental_get_tracing_count()),
  as.integer(reused$dag$tf_trace_values_batch$experimental_get_tracing_count())
))
