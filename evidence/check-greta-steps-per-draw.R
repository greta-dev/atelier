# How many sampler steps does greta take per draw it returns?
#
#   Rscript --vanilla check-greta-steps-per-draw.R
#
# greta passes `thin` to sample_chain() as num_steps_between_results, which
# keeps one draw in thin + 1 (check-tfp-thinning-semantics.R). A target so wide
# that rwmh accepts every proposal makes the steps between draws the sum of the
# proposal steps, so their variance over one step's variance counts the steps.
# rwmh's step for a single parameter is epsilon * diag_sd / sum(diag_sd) = 0.1.
#
# Result on main at 282944f5, 2026-09-29, with every step accepted: thin = 1,
# 2, 3, 5 gave 2.01, 2.97, 4.05, 6.00 steps per draw - thin + 1 each, so every
# chain at the default thin = 1 runs twice the iterations it reports.

library(greta)

x <- normal(0, 1e6)
m <- model(x)

draw_steps <- function(thin, n = 20000) {
  set.seed(2026 - 09 - 29)
  d <- mcmc(
    m,
    sampler = rwmh(epsilon = 0.1, diag_sd = 1),
    warmup = 0,
    n_samples = n,
    thin = thin,
    chains = 1,
    initial_values = initials(x = 0),
    verbose = FALSE
  )
  diff(as.vector(d[[1]]))
}

one_step_var <- 0.1^2
thin_one <- draw_steps(1)
cat(sprintf(
  "thin = 1: %.2f steps per draw (%.1f%% of steps accepted)\n",
  stats::var(thin_one) / one_step_var,
  100 * mean(thin_one != 0)
))
for (thin in c(2, 3, 5)) {
  cat(sprintf(
    "thin = %d: %.2f steps per draw\n",
    thin,
    stats::var(draw_steps(thin)) / one_step_var
  ))
}
