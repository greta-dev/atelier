# Is #843's opt() slowdown caused by the log-density function's input
# signature?
#
#   Rscript --vanilla check-opt-slowdown-i546.R
#
# The thorough benchmark tier (greta.benchmarks 2026-09-29-retracing-i546)
# found opt() 1.28-1.38x slower on faster-hessians-i546 than on main, on all
# five example models, with mcmc() unchanged. #843 gives the log-density and
# trace-values functions an input signature whose batch dimension is left open
# (dag$free_state_signature()). This times opt() on main, on the branch, and on
# the branch with that signature switched off, each in a fresh process.
#
# Run from greta.benchmarks, after 2026-09-29-retracing-i546/01-single-runs.R
# has installed both builds into that run's libs/.

# fix: the branch with opt() moved onto a log-density function traced for one
# row, installed from the uncommitted worktree
libs <- c(
  main = "2026-09-29-retracing-i546/libs/main",
  branch = "2026-09-29-retracing-i546/libs/faster-hessians-i546",
  fix = "2026-09-29-retracing-i546/libs/faster-hessians-i546-fix"
)

# signature: "open" leaves the branch as it is, "none" drops the signature, and
# "one_row" fixes the batch dimension at 1, which is what opt() passes
time_opt <- function(lib, signature = "open") {
  callr::r(
    function(signature) {
      library(greta)
      tf <- tensorflow::tf
      if (signature == "none") {
        greta:::dag_class$set(
          "public",
          "free_state_signature",
          function() NULL,
          overwrite = TRUE
        )
      }
      if (signature == "one_row") {
        greta:::dag_class$set(
          "public",
          "free_state_signature",
          function() {
            n_free <- length(greta:::unlist_tf(
              self$example_parameters(free = TRUE)
            ))
            list(tf$TensorSpec(
              shape = list(1L, n_free),
              dtype = greta:::tf_float()
            ))
          },
          overwrite = TRUE
        )
      }
      int <- normal(0, 10)
      coef <- normal(0, 10)
      sd <- cauchy(0, 3, truncation = c(0, Inf))
      mu <- int + coef * attitude$complaints
      distribution(attitude$rating) <- normal(mu, sd)
      m <- model(int, coef, sd)

      # the suite's call: a fixed 100 adam steps, so every call does the same
      # work. opt()'s defaults stop at convergence, which varies call to call
      fit <- function() opt(m, optimiser = adam(), max_iterations = 100)

      # one call first, so every build has traced before timing
      fit()
      times <- replicate(30, system.time(fit())[["elapsed"]])
      c(
        median = stats::median(times),
        q25 = stats::quantile(times, 0.25)[[1]],
        q75 = stats::quantile(times, 0.75)[[1]]
      )
    },
    args = list(signature = signature),
    libpath = c(normalizePath(lib), .libPaths())
  )
}

results <- rbind(
  main = time_opt(libs[["main"]]),
  branch = time_opt(libs[["branch"]]),
  branch_without_signature = time_opt(libs[["branch"]], signature = "none"),
  branch_one_row_signature = time_opt(libs[["branch"]], signature = "one_row"),
  branch_with_fix = time_opt(libs[["fix"]])
)
print(round(results, 4))
saveRDS(results, "~/github/greta-dev/atelier/evidence/check-opt-slowdown-i546.rds")
