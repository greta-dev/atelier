# Why does thinning-i318 get fewer effective samples per second than main?
#
# The quick benchmark tier (greta.benchmarks, main 282944f5 vs thinning-i318
# 8ddcdece) had the branch's seconds per 1000 ESS 3-7x worse on three of four
# examples, although each draw now costs one HMC iteration instead of two.
# This runs the linear example on both, and on the branch with main's work
# restored two ways: twice the warmup, and thin = 2.
#
# Run from the greta repo root, with main checked out at
# .claude/worktrees/main-ref and thinning-i318 in the main checkout.

run_case <- function(path, label, warmup, thin, seed) {
  callr::r(
    function(path, label, warmup, thin, seed) {
      pkgload::load_all(path, quiet = TRUE)
      int <- normal(0, 10)
      coef <- normal(0, 10)
      sd <- cauchy(0, 3, truncation = c(0, Inf))
      mu <- int + coef * attitude$complaints
      distribution(attitude$rating) <- normal(mu, sd)
      m <- model(int, coef, sd)

      set.seed(seed)
      draws <- mcmc(
        m,
        warmup = warmup,
        n_samples = 2000 * thin,
        thin = thin,
        chains = 4,
        verbose = FALSE
      )
      sampler <- attr(draws, "model_info")$samplers[[1]]
      ess <- posterior::summarise_draws(
        posterior::as_draws(draws),
        ess_bulk = posterior::ess_bulk
      )
      data.frame(
        label = label,
        warmup = warmup,
        thin = thin,
        seed = seed,
        epsilon = sampler$parameters$epsilon,
        diag_sd_mean = mean(sampler$parameters$diag_sd),
        accept_rate = mean(sampler$accept_history),
        ess_bulk_min = min(ess$ess_bulk),
        ess_bulk_median = stats::median(ess$ess_bulk)
      )
    },
    args = list(
      path = path,
      label = label,
      warmup = warmup,
      thin = thin,
      seed = seed
    )
  )
}

cases <- expand.grid(
  seed = 1:3,
  case = c("main", "branch", "branch_2x_warmup", "branch_thin_2"),
  stringsAsFactors = FALSE
)
settings <- list(
  main = list(path = ".claude/worktrees/main-ref", warmup = 1000, thin = 1),
  branch = list(path = ".", warmup = 1000, thin = 1),
  branch_2x_warmup = list(path = ".", warmup = 2000, thin = 1),
  branch_thin_2 = list(path = ".", warmup = 1000, thin = 2)
)

results <- do.call(
  rbind,
  Map(
    function(case, seed) {
      s <- settings[[case]]
      run_case(s$path, case, s$warmup, s$thin, seed)
    },
    cases$case,
    cases$seed
  )
)

print(results, digits = 3)
saveRDS(results, "~/github/greta-dev/atelier/evidence/check-thinning-ess-i318.rds")
