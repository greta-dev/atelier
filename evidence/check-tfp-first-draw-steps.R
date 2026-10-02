# How many steps does tfp$mcmc$sample_chain() take before its FIRST result,
# and in total, with num_burnin_steps = 0?
#
#   Rscript --vanilla check-tfp-first-draw-steps.R
#
# check-tfp-thinning-semantics.R measured the gap between consecutive results
# (num_steps_between_results + 1). This measures the gap between the starting
# state and the first result, which sets how many iterations a burst runs and
# the gap between the last draw of one burst and the first of the next.
#
# A flat target, so RandomWalkMetropolis accepts every proposal. The state is
# 20000 independent coordinates starting at 0, so the variance across
# coordinates of a result counts the unit-variance steps taken to reach it.

library(greta)
invisible(greta:::check_tf_version())
tfp <- greta:::tfp
tf <- tensorflow::tf

kernel <- tfp$mcmc$RandomWalkMetropolis(
  target_log_prob_fn = function(x) tf$reduce_sum(tf$zeros_like(x)),
  new_state_fn = tfp$mcmc$random_walk_normal_fn(scale = 1)
)

steps_to_each_result <- function(num_results, k) {
  draws <- tfp$mcmc$sample_chain(
    num_results = as.integer(num_results),
    current_state = tf$zeros(20000L, dtype = tf$float64),
    kernel = kernel,
    num_burnin_steps = 0L,
    num_steps_between_results = as.integer(k),
    trace_fn = NULL,
    seed = tf$constant(c(1L, 2L), dtype = tf$int32)
  )
  apply(as.matrix(draws), 1, stats::var)
}

for (k in 0:3) {
  steps <- steps_to_each_result(num_results = 3, k = k)
  cat(sprintf(
    "num_steps_between_results = %d: steps to results 1-3 = %s\n",
    k,
    paste(sprintf("%.2f", steps), collapse = ", ")
  ))
}
