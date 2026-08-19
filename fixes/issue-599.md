# Issue #599 — greta in a targets workflow's `imports`

Adding `greta` to `tar_option_set(imports = c("greta"))` breaks targets
change-tracking of greta objects, whereas listing it only in `packages`
is fine. `imports` makes targets reach into greta's namespace and hash
its objects for package-based invalidation; greta objects that carry
(dead) reticulate pointers or non-deterministic hashes trip this up.

## Approach

Once #595 makes greta objects reload-safe, this becomes mostly a
documentation + verification task rather than a code change:

1. **Verify with a real pipeline.** Add a `targets::tar_script()`
   integration test that runs a pipeline both with `packages = "greta"`
   and with `imports = "greta"`, and asserts the pipeline completes and
   re-runs invalidate correctly.
2. **Document the recommended pattern.** Following maintainer guidance in
   the issue thread, the recommended route is `packages = "greta"` plus
   `renv` for version pinning, *not* `imports = "greta"`, because
   importing the whole namespace makes every internal greta change
   invalidate the pipeline. Put this in the "greta and targets" vignette
   shipped with #595.
3. If the `imports` path is to be supported, ensure greta objects hash
   stably across sessions — a stable `format`/hash for `greta_model`
   /`greta_mcmc_list` that ignores volatile Python-handle fields (which
   #595 already nulls/rebuilds). This is the only potential code change.

## Files / functions touched

- No greta source change required for the recommended path (docs + test).
- Optional: a stable serialisation/hash surface on `greta_model_class.R`
  / `greta_mcmc_list.R` if `imports` support is pursued.
- New: `tests/testthat/test-targets.R` and the targets vignette.

## Acceptance test

`tests/testthat/test-targets.R`, using a real targets pipeline in a temp
project (testthat 3 + `withr` + `callr`):

```r
test_that("a greta model flows through a targets pipeline", {
  skip_if_not(check_tf_version())
  skip_if_not_installed("targets")
  dir <- withr::local_tempdir()
  targets::tar_script({
    library(greta)
    list(
      targets::tar_target(m, {
        mu <- normal(0, 1)
        y <- as_data(rnorm(10))
        distribution(y) <- normal(mu, 1)
        model(mu)
      }),
      targets::tar_target(d, mcmc(m, n_samples = 50, warmup = 50,
                                  verbose = FALSE))
    )
  }, script = file.path(dir, "_targets.R"))
  withr::with_dir(dir, {
    targets::tar_make(callr_function = callr::r)
    expect_s3_class(targets::tar_read(d), "greta_mcmc_list")
  })
})
```

Add a second variant setting `imports = "greta"` (may be
`skip`-documented if the recommendation is to avoid it).

## Dependencies

- **Rides on #595** — reload-safety is the precondition.
- Shares the vignette/integration-test deliverable with #595.
- Otherwise independent.

## Risk / effort

Low if scoped as docs + integration test; medium only if stable-hash
`imports` support is pursued.
