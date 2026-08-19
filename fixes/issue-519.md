# Issue #519 — DIC and other model-evaluation metrics

Ship information criteria (DIC, and ideally WAIC / LOO) for greta fits.
These are all post-processing over the *pointwise* log-likelihood of the
posterior draws.

## Approach

DIC needs the deviance at the posterior mean and the posterior mean
deviance; WAIC/LOO (via {loo}) need a draws × observations pointwise
log-likelihood matrix. The blocker is that greta today exposes the joint
log-prob, not a per-observation log-likelihood.

1. **Build on the #739 data/log-lik hook.** Once #739 exposes the
   likelihood term parameterised by data, add a
   `log_likelihood(draws)` accessor that returns the draws × n pointwise
   log-lik matrix.
2. **Thin helpers on top:**
   - `dic(draws)` — `mean(deviance) + var(deviance)/2`-style effective
     parameters from the pointwise log-lik.
   - `waic(draws)` / `loo(draws)` — hand the pointwise matrix to the
     {loo} package (`Suggests`) and wrap the result.
3. All of this is pure R post-processing; no sampler change beyond the
   #739 hook.

**Dependency to flag:** #519's enabling hook (pointwise log-lik) lands with
the sampler-interface boundary, via #739. If #519 is wanted sooner, it is
the concrete reason to pull the #739 data hook forward on its own.

## Files / functions touched

- New `R/model_criteria.R` — `log_likelihood()`, `dic()`, `waic()`,
  `loo()`; roxygen; NEWS bullets (alphabetical by function name).
- `DESCRIPTION` — `loo` in `Suggests`.
- Depends on the #739 hook in `R/dag_class.R` / `R/node_types.R`.

## Acceptance test

`tests/testthat/test-model-criteria.R`:

```r
test_that("dic and waic return finite scalars for a simple model", {
  skip_if_not(check_tf_version())
  skip_if_not_installed("loo")
  mu <- normal(0, 5)
  y <- as_data(rnorm(30))
  distribution(y) <- normal(mu, 1)
  d <- mcmc(model(mu), n_samples = 200, warmup = 200, verbose = FALSE)
  expect_true(is.finite(dic(d)))
  w <- waic(d)
  expect_s3_class(w, "waic")
})
```

## Dependencies

- **Blocked by #739**, which itself wants the sampler-interface boundary
  settled first.
- Independent of the #595 self-healing work.

## Risk / effort

Low-medium for the criteria helpers *once the pointwise log-lik hook
exists*; the real cost is upstream in #739.
