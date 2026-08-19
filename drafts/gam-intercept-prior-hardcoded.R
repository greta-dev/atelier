#' The intercept prior is hardcoded to `normal(0, 1.3)`, where `jagam` scales it
#' with the response.
#'
#' This is greta.gam [#6](https://github.com/greta-dev/greta.gam/issues/6),
#' which asks "why does the prior on the intercept always have a variance of
#' 1.3". Answering it turned up something worse than the title suggests: not
#' only is the number arbitrary, it does not vary with the data when `jagam`'s
#' equivalent does.

library(mgcv)

#' ## What I expect
#'
#' `greta.gam` builds its model from `mgcv::jagam()`, so the intercept prior
#' should match the one `jagam` writes. That prior is:

set.seed(2026 - 07 - 30)
dat <- gamSim(1, n = 100, verbose = FALSE)
jf <- tempfile(fileext = ".jags")
invisible(jagam(y ~ s(x2), data = dat, file = jf, diagonalize = FALSE))
grep("b\\[i\\] ~ dnorm", readLines(jf, warn = FALSE), value = TRUE)

#' JAGS `dnorm(mean, precision)` takes a **precision**, not a variance or a
#' standard deviation, so `dnorm(0, 0.00016)` is a standard deviation of

sqrt(1 / 0.00016)

#' about 79. A deliberately vague prior on the intercept.
#'
#' ## What happens instead
#'
#' [`jagam2greta.R#L107`](https://github.com/greta-dev/greta.gam/blob/653a7012fe4abe551ec1a6b885fef763af6b9e1e/R/jagam2greta.R#L107)
#' writes a constant:

## int <- normal(0, 1.3)

#' greta's `normal()` is (mean, sd), so that is a standard deviation of 1.3
#' against `jagam`'s 79 — about 60 times tighter.
#'
#' ## Why this is a problem
#'
#' `jagam` sets that precision from the scale of the response, so the prior
#' widens as the data get larger. The hardcoded 1.3 does not:

for (mult in c(1, 10, 100)) {
  d <- gamSim(1, n = 100, verbose = FALSE)
  d$y <- d$y * mult
  f <- tempfile(fileext = ".jags")
  invisible(jagam(y ~ s(x2), data = d, file = f, diagonalize = FALSE))
  l <- grep("b\\[i\\] ~ dnorm", readLines(f, warn = FALSE), value = TRUE)
  prec <- as.numeric(sub(".*dnorm\\(0,([0-9.e-]+)\\).*", "\\1", l))
  cat(sprintf(
    "y * %-4d  jagam sd = %-10.1f  greta.gam sd = 1.3  (%.0fx too tight)\n",
    mult, sqrt(1 / prec), sqrt(1 / prec) / 1.3
  ))
}

#' So the mismatch is 60x at unit scale and 7000x if the response is scaled by
#' 100. Any model whose response is not order 1 gets an intercept prior that is
#' informative by accident.
#'
#' The direction matters: a tight prior centred on zero pulls the intercept
#' toward zero. With `gamSim()`'s default response, whose mean is around 8, a
#' prior standard deviation of 1.3 puts the data's own intercept several prior
#' standard deviations out.
#'
#' ### What it does to a conclusion
#'
#' The intercept is the overall level of the fitted smooth. Shrinking it biases
#' every fitted value, and the bias grows with the scale of the response — so a
#' user analysing counts in the thousands gets a worse fit than one analysing
#' proportions, with nothing in the output to say why.
#'
#' It may be partly masked in practice: the smooth basis has a weak prior and
#' can absorb some of the level, so fitted values can look reasonable while the
#' intercept itself is wrong. That makes it harder to notice, not less real, and
#' it means anyone *reporting* the intercept is reporting a shrunk quantity.
#'
#' ## Fix
#'
#' Read the precision `jagam` generated instead of hardcoding a number. It is in
#' the JAGS model text that `jagam2greta()` already parses for the `K` lines, so
#' the value is available at that point — the same `jags_spec` object.
#'
#' Something of the shape:

## int_prec <- as.numeric(sub(".*dnorm\\(0,([0-9.e-]+)\\).*", "\\1",
##                            grep("b\\[i\\] ~ dnorm", jags_spec, value = TRUE)))
## int <- normal(0, sqrt(1 / int_prec))

#' This **changes users' priors**, so it needs a NEWS bullet saying so.
#'
#' ### Chesterton's fence: why might 1.3 be there
#'
#' It arrived with the first commit that added this file,
#' [`a1687ff`](https://github.com/greta-dev/greta.gam/commit/a1687ff5e9ab682f84ba8ec07be69a99c2076360)
#' ("something that seems to work?"), and has never been touched since.
#' `git log -S"dnorm" -- R/jagam2greta.R` returns no commits, so the code has
#' never read `jagam`'s precision — this is not a conversion that drifted, it is
#' a placeholder that was never replaced.
#'
#' I cannot find a derivation for 1.3. It is not `sqrt(1/0.00016)`, nor
#' `1/0.00016`, nor any obvious transform of it. Treating it as arbitrary seems
#' safe, but worth a second opinion before removing it.
#'
#' ## A test
#'
#' Assert the prior matches `jagam`'s, at two response scales so a hardcoded
#' constant cannot pass:

## test_that("the intercept prior matches jagam's, and scales with the data", {
##   for (mult in c(1, 100)) {
##     d <- gamSim(1, n = 100, verbose = FALSE)
##     d$y <- d$y * mult
##     f <- tempfile(fileext = ".jags")
##     invisible(jagam(y ~ s(x2), data = d, file = f, diagonalize = FALSE))
##     l <- grep("b\\[i\\] ~ dnorm", readLines(f, warn = FALSE), value = TRUE)
##     prec <- as.numeric(sub(".*dnorm\\(0,([0-9.e-]+)\\).*", "\\1", l))
##     jg <- jagam2greta(~ s(x2), data = d)
##     int_sd <- sd(calculate(jg$betas[1], nsim = 1e4, seed = 1)[[1]])
##     expect_equal(int_sd, sqrt(1 / prec), tolerance = 0.1)
##   }
## })

#' Left commented because `jagam2greta()` returns `betas` with the intercept
#' already combined, and drawing from that prior currently hits the separate
#' `MatrixInverse` failure. It becomes runnable once that is fixed.
