Closes #241, closes #318, closes #567, closes #609.

This PR started as a fix for `mcmc()` erroring with some combinations of `thin`, `pb_update` and `n_samples`. Fixing it showed that greta has been running about twice the iterations it reports: at the default `thin = 1`, every kept draw has cost two iterations. The draws were valid, only thinned more than asked. So this is a substantial change to how efficient greta looks: the same arguments now do half the work and give about half the effective samples, and the defaults double to make up for it.

## What was wrong

greta passes `thin` to TFP's `sample_chain()` as `num_steps_between_results`:

https://github.com/greta-dev/greta/blob/179021a818cd7282896c42b03814a53556c1d98d/R/sampler_class.R#L495-L506

That argument is the number of iterations thrown away *between* kept draws, so passing `thin` keeps one draw in `thin + 1`. The same call passes `num_burnin_steps = 0`, and `sample_chain()` takes its first result after `num_burnin_steps + 1` iterations, so the first draw of each burst comes one iteration after the last draw of the burst before.

### Counting it

The iterations happen inside TensorFlow, so R cannot count them: the kernel's R code runs once, while TensorFlow traces it. A `tf$Variable` incremented inside the log-density function can. `rwmh()` evaluates the log density once per iteration, plus once when each burst starts, so this counts iterations:

<details>
<summary>Code</summary>

```r
library(greta)
library(tensorflow)

steps <- tf$Variable(0L)

greta:::rwmh_sampler$set(
  "public",
  "define_tf_kernel",
  function(sampler_param_vec) {
    free_state_size <- length(sampler_param_vec) - 1
    rwmh_epsilon <- sampler_param_vec[0]
    rwmh_diag_sd <- sampler_param_vec[1:(1 + free_state_size)]
    dag <- self$model$dag
    step_sizes <- tf$reshape(
      rwmh_epsilon * (rwmh_diag_sd / tf$reduce_sum(rwmh_diag_sd)),
      shape = shape(free_state_size)
    )
    counting_log_prob <- function(free_state) {
      steps$assign_add(1L)
      dag$tf_log_prob_function_adjusted(free_state)
    }
    tfp$mcmc$RandomWalkMetropolis(
      target_log_prob_fn = counting_log_prob,
      new_state_fn = tfp$mcmc$random_walk_normal_fn(scale = step_sizes)
    )
  },
  overwrite = TRUE
)

x <- normal(0, 1)
m <- model(x)

for (thin in c(1L, 3L)) {
  steps$assign(0L)
  draws <- mcmc(
    m,
    sampler = rwmh(),
    warmup = 0,
    n_samples = 12,
    thin = thin,
    chains = 1,
    verbose = FALSE
  )
  cat(sprintf(
    "thin = %d: %d draws, %d log-density evaluations\n",
    thin,
    nrow(draws[[1]]),
    as.integer(steps$numpy())
  ))
}
```

</details>

| `thin` | draws | evaluations on main | evaluations on this branch |
| ---    | ---   | ---                 | ---                        |
| 1      | 12    | 24                  | 13                         |
| 3      | 4     | 14                  | 13                         |

Take away the one evaluation when the burst starts. At `thin = 1`, main runs 23 iterations for 12 draws: the first draw after 1 iteration, then 2 per draw. At `thin = 3` it runs 13 for 4 draws: 1, then 4 per draw. This branch runs 12 for both, which is `thin` per draw.

### Why it went unnoticed

The line has been there since at least 2018, before 0.3.0. The draws it gives come from the right posterior, only thinned more than asked, so no test of whether greta samples correctly can fail. The tests checked how many draws came back, which was always right. The only symptoms are time and effective samples per draw, and nothing counted iterations per draw.

## What changes

- **`thin` iterations per draw, not `thin + 1`.** `thin - 1` is passed as `num_steps_between_results`. Warmup ran two iterations per step for the same reason.
- **Even spacing across bursts.** `thin - 1` is passed as `num_burnin_steps` too, so the first draw of each burst is `thin` iterations after the last.
- **Bursts of whole draws.** A burst shorter than `thin` asked TensorFlow for no draws, which errored: a final partial burst (#609, #318), `pb_update` below `thin` (#318), `one_by_one` with `thin` (#567), and `extra_samples()` with any of these (#567). Bursts are now whole draws, the iterations after the last draw run as a burst of their own, and `thin` larger than `n_samples` is an informative error (#241).
- **`one_by_one` with `thin`** runs one iteration per burst and keeps every `thin`-th state, so a numerical error rejects only the proposal that caused it.
- **The progress bar** reaches its total, and fills by the iterations run. With `thin` above 1 it updates on whole draws, so roughly every `pb_update` iterations; `?mcmc` gives worked examples.
- **Defaults.** `mcmc()` defaults to `warmup = 2000, n_samples = 2000`, and `extra_samples()` to `n_samples = 2000`, so a default run does the same work as in 0.6.0. Seeded draws change.

## Evidence

Timing agrees with the count, and is independent of it. With `rwmh()` on a 20,000-row regression, a draw costs 0.095 ms per iteration plus 0.022 ms for keeping it, if CRAN and main run `thin + 1` iterations per draw and this branch runs `thin`. Fitted at `thin = 1`, that predicts every other case to within 0.006 ms: CRAN at `thin = 1`, and all three versions at `thin = 3`.

At equal iterations, 4 chains of 2000 warmup and 2000 sampling iterations, 8 seeds, this branch's median smallest bulk ESS is higher than CRAN's on three example models and about the same on the fourth:

| model               | CRAN | main | this branch |
| ---                 | ---  | ---  | ---         |
| linear              | 213  | 278  | 680         |
| multiple_linear     | 49   | 48   | 124         |
| hierarchical_linear | 101  | 50   | 156         |
| eight_schools       | 243  | 239  | 238         |

Each run of one version varies a lot (CRAN's on `linear` range from 34 to 1022); every run is in the write-up. At equal iterations this branch also takes about 30% longer in wall time. It runs twice as many warmup steps and keeps twice as many draws, and the R-side work between calls to TensorFlow is per step and per draw; that is the likely cause, not yet measured on its own.

https://github.com/greta-dev/greta.benchmarks/blob/main/2026-10-01-iterations-and-efficiency-i318/results.md

- Each new test fails on main: draw counts across bursts, one iteration per `one_by_one` burst, every gap between draws measured across burst boundaries (without the `num_burnin_steps` change it measures gaps of 1, 3, 1, 3 at `thin = 3`), and the progress bar reaching its total.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
