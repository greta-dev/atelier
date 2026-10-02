# Do the hessians from opt(hessian = TRUE) change with greta-dev/greta#843?
#
# Run once with main installed and once with faster-hessians-i546 installed:
#
#   Rscript --vanilla check-hessians-identical-i546.R <output.rds>
#
# then compare the two .rds files with compare-hessians-i546.R. Targets of 2, 20,
# 100 and 200 elements cover both jacobian routes on the branch: below
# pfor_min_elements() (100) a while loop, at or above it pfor.

library(greta)

dims <- c(2, 20, 100, 200)
targets <- lapply(dims, \(n) variable(dim = n))
names(targets) <- paste0("t", dims)
list2env(targets, environment())

x <- rnorm(sum(dims))
distribution(x) <- normal(do.call(c, unname(targets)), 1)
m <- model(t2, t20, t100, t200)

inits <- initials(t2 = rep(0.1, 2), t20 = rep(0.1, 20), t100 = rep(0.1, 100),
                  t200 = rep(0.1, 200))

set.seed(2026 - 09 - 29)
fit <- opt(m, initial_values = inits, max_iterations = 50, hessian = TRUE)

saveRDS(
  list(
    greta = as.character(packageVersion("greta")),
    greta_path = find.package("greta"),
    hessian = fit$hessian
  ),
  commandArgs(TRUE)[1]
)
