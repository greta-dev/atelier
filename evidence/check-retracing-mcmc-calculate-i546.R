# Retracing warnings and trace counts from mcmc() and calculate(), for #546 and
# #843. Run with main installed and with faster-hessians-i546 installed:
#
#   Rscript --vanilla check-retracing-mcmc-calculate-i546.R
#
# Four models, each sampled with mcmc() and then used in calculate() on its
# posterior draws and with nsim. Prints the retracing warnings TensorFlow logged,
# and how many times each model's tf_functions were traced.

library(greta)

rebind_tf_logger <- function() {
  reticulate::py_run_string(paste(
    "import sys",
    "from tensorflow.python.platform import tf_logging",
    "for _h in tf_logging.get_logger().handlers: _h.stream = sys.stderr",
    sep = "\n"
  ))
}

retracing <- function(expr) {
  out <- reticulate::py_capture_output(
    {
      rebind_tf_logger()
      force(expr)
    },
    type = "stderr"
  )
  grep("triggered tf.function retracing", strsplit(out, "\n")[[1]], value = TRUE)
}

traces <- function(f) {
  as.integer(f$experimental_get_tracing_count())
}

fit_one <- function(k) {
  y <- as_data(rnorm(10, k))
  mu <- normal(0, 10)
  distribution(y) <- normal(mu, 1)
  draws <- mcmc(model(mu), n_samples = 10, warmup = 10, verbose = FALSE)
  list(mu = mu, draws = draws)
}

set.seed(2026 - 09 - 29)

mcmc_warnings <- retracing(fits <- lapply(1:4, fit_one))
calculate_warnings <- retracing(
  for (fit in fits) {
    calculate(fit$mu * 2, values = fit$draws)
    calculate(fit$mu * 2, nsim = 5)
  }
)

dags <- lapply(fits, \(fit) attr(fit$draws, "model_info")$model$dag)
samplers <- lapply(fits, \(fit) attr(fit$draws, "model_info")$samplers[[1]])

cat("\nRETRACE mcmc warnings:", length(mcmc_warnings), "\n")
cat(substr(mcmc_warnings, 1, 100), sep = "\n")
cat("\nRETRACE calculate warnings:", length(calculate_warnings), "\n")
cat(substr(calculate_warnings, 1, 100), sep = "\n")
cat("\nRETRACE traces per model\n")
print(data.frame(
  sampler = vapply(samplers, \(s) traces(s$tf_evaluate_sample_batch), 1L),
  log_prob = vapply(dags, \(d) traces(d$tf_log_prob_function), 1L),
  trace_values = vapply(dags, \(d) traces(d$tf_trace_values_batch), 1L)
))
