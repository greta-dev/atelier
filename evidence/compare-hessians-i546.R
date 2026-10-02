# Compare the hessians written by check-hessians-identical-i546.R on main and
# on faster-hessians-i546:
#
#   Rscript --vanilla compare-hessians-i546.R <main.rds> <branch.rds>

args <- commandArgs(TRUE)
main <- readRDS(args[1])
branch <- readRDS(args[2])

stopifnot(identical(names(main$hessian), names(branch$hessian)))
for (target in names(main$hessian)) {
  cat(sprintf(
    "%-5s dim %-10s identical %-5s max abs diff %g\n",
    target,
    paste(dim(main$hessian[[target]]), collapse = "x"),
    identical(main$hessian[[target]], branch$hessian[[target]]),
    max(abs(main$hessian[[target]] - branch$hessian[[target]]))
  ))
}
