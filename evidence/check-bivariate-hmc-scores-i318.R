# Does the thinning fix (greta#850) inflate HMC's scores in the bivariate normal
# test, or was CI's 4.4 one extreme seed?
#
#   Rscript --vanilla check-bivariate-hmc-scores-i318.R
#
# "samplers are unbiased for bivariate normals" failed on Ubuntu CI for #850:
# HMC's largest score was 4.4 against a threshold of 3.1. Each score is a
# posterior summary's error in batch-means Monte Carlo standard errors, so for
# a correct sampler and a correct standard error it is roughly the absolute
# value of a standard normal draw.
#
# This reruns the test's HMC half (check_mvn_samples() from helpers.R) across
# seeds, on main and on the branch, each in a fresh process. If the branch's
# scores are larger across seeds, the batch-means standard error is too small
# for the branch's draws, or the sampler is biased. If they match main's, CI's
# 4.4 was one seed.
#
# Run from the greta repo root, with main at .claude/worktrees/check-main and
# thinning-i318 at .claude/worktrees/check-thin.

seeds <- c(2026 - 09 - 27, 1:20)
paths <- c(
  main = ".claude/worktrees/check-main",
  thinning = ".claude/worktrees/check-thin"
)

run_seeds <- function(path, seeds) {
  callr::r(
    function(path, seeds) {
      pkgload::load_all(path, quiet = TRUE)
      source(file.path(path, "tests/testthat/helpers.R"))
      rows <- lapply(seeds, function(seed) {
        set.seed(seed)
        scores <- check_mvn_samples(sampler = hmc())
        data.frame(
          seed = seed,
          score = seq_along(scores),
          value = as.numeric(scores)
        )
      })
      do.call(rbind, rows)
    },
    args = list(path = path, seeds = seeds)
  )
}

results <- do.call(
  rbind,
  lapply(names(paths), function(branch) {
    cbind(branch = branch, run_seeds(paths[[branch]], seeds))
  })
)

saveRDS(results, "~/github/greta-dev/atelier/evidence/check-bivariate-hmc-scores-i318.rds")

threshold <- stats::qnorm(1 - 0.01 / (2 * 5))
max_per_seed <- aggregate(value ~ branch + seed, results, max)
print(aggregate(
  value ~ branch,
  max_per_seed,
  function(x) {
    c(median = median(x), mean = mean(x), over_threshold = sum(x > threshold))
  }
))
print(aggregate(value ~ branch + score, results, mean))
