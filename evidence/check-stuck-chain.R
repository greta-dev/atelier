# An HMC chain that accepts every proposal but barely moves, on main.
#
#   Rscript --vanilla ~/github/greta-dev/atelier/evidence/check-stuck-chain.R
#
# Run from a greta checkout on main (179021a8). Found through PR #843's CI:
# test-data-swapping.R's "swapped data reaches the sampler" failed on Ubuntu
# and Windows because its first chain's mean was 0.556 against a posterior
# mean of 0. The random state R reached at the start of that test, saved in
# stuck-chain-random-state.rds, reproduces it in a fresh session, on main as
# well as the branch, and with plain as_data() as well as as_data_mutable().
#
# Result, 2026-09-30, TensorFlow 2.21.0: every draw between 0.54 and 0.56,
# 100% acceptance during sampling, tuned epsilon 0.51, where the posterior sd
# is about 0.32 - the step size should move the chain about that far each
# iteration. Forcing only the sampler seed (940355922) in a fresh session
# does not reproduce it, so the initial values from this state matter too.
#
# Cause: hmc() draws its leapfrog count L once per call to TensorFlow, and with
# verbose = FALSE sampling is one call, so L = 5 is used throughout. One step
# of epsilon 0.5115 turns this posterior (sd 0.3161) through 1.885 radians, so
# five steps are 3 pi, and every proposal is the mirror image of the current
# draw. On the thinning fix (#850) the kept draws alternate 0.39, -0.39; on
# main, which keeps one draw in two, the two flips cancel. one_by_one = TRUE
# from the same state mixes. How often it happens, and the issue draft:
# greta.benchmarks/2026-09-30-stuck-chain-rate/ and
# drafts/issue-hmc-fixed-leapfrog-count.R.

pkgload::load_all(".", quiet = TRUE)
assign(
  ".Random.seed",
  readRDS("~/github/greta-dev/atelier/evidence/stuck-chain-random-state.rds"),
  envir = globalenv()
)

x <- as_data(rep(0, 10))
z <- normal(0, 10)
distribution(x) <- normal(z, 1)
m <- model(z)
draws <- mcmc(m, chains = 1, warmup = 200, n_samples = 100, verbose = FALSE)

v <- as.vector(as.matrix(draws))
sampler <- attr(draws, "model_info")$samplers[[1]]
cat(sprintf(
  "mean %.3f, range %.2f to %.2f, sampling acceptance %.2f, epsilon %.3g, sampler seed %s\n",
  mean(v),
  min(v),
  max(v),
  mean(utils::tail(sampler$accept_history, 100)),
  sampler$parameters$epsilon,
  sampler$seed
))
