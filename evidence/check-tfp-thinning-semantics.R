# How many chain steps does tfp$mcmc$sample_chain() take per kept draw?
#
#   Rscript --vanilla check-tfp-thinning-semantics.R
#
# A flat target, so RandomWalkMetropolis accepts every proposal and each kept
# draw's step is the sum of the proposal steps taken since the last kept one.
# The variance of those steps divided by one step's variance counts the steps.
#
# Result on TF 2.21.0 / TFP 0.25.0, 2026-09-29: num_steps_between_results = k
# keeps one draw in k + 1 (k = 1, 2, 3, 4 gave 2.02, 3.01, 4.01, 5.01).

library(greta)
invisible(greta:::check_tf_version())
tfp <- greta:::tfp
tf <- tensorflow::tf

kernel <- tfp$mcmc$RandomWalkMetropolis(
  target_log_prob_fn = function(x) tf$zeros_like(x),
  new_state_fn = tfp$mcmc$random_walk_normal_fn(scale = 1)
)

steps_var <- function(k) {
  draws <- tfp$mcmc$sample_chain(
    num_results = 20000L,
    current_state = tf$constant(0, dtype = tf$float64),
    kernel = kernel,
    num_burnin_steps = 0L,
    num_steps_between_results = as.integer(k),
    trace_fn = NULL,
    seed = tf$constant(c(1L, 2L), dtype = tf$int32)
  )
  stats::var(diff(as.numeric(draws)))
}

base <- steps_var(0)
for (k in 1:4) {
  cat(sprintf(
    "num_steps_between_results = %d: %.2f steps per kept draw\n",
    k,
    steps_var(k) / base
  ))
}
