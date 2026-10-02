# Whether mcmc()'s seeded draws depend on pb_update and verbose, on main.
#
#   Rscript --vanilla ~/github/greta-dev/atelier/evidence/check-seeded-draws-depend-on-pb-update.R
#
# Run from a greta checkout on main (179021a8).
#
# Result, 2026-09-30: the same seed and pb_update give identical draws, but
# pb_update = 50, pb_update = 100 and verbose = FALSE give three different
# sets. Each call to TensorFlow gets its own seed, and hmc() draws its leapfrog
# count in R once per call, so the split of sampling into calls changes the
# draws.

pkgload::load_all(".", quiet = TRUE)

x <- as_data(rep(0, 10))
z <- normal(0, 10)
distribution(x) <- normal(z, 1)
m <- model(z)

draw <- function(...) {
  set.seed(2026)
  draws <- mcmc(m, chains = 1, warmup = 200, n_samples = 200, ...)
  as.vector(as.matrix(draws))
}

quiet <- draw(verbose = FALSE)
pb50 <- suppressMessages(draw(verbose = TRUE, pb_update = 50))
pb100 <- suppressMessages(draw(verbose = TRUE, pb_update = 100))
pb50_again <- suppressMessages(draw(verbose = TRUE, pb_update = 50))

c(
  same_pb_update = identical(pb50, pb50_again),
  pb_update_50_vs_100 = identical(pb50, pb100),
  pb_update_50_vs_quiet = identical(pb50, quiet)
)
