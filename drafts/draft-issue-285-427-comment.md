# DRAFT comment for greta#285 / #427 — not posted

Found sweeping the `#TF1/2` markers for #745. `R/sampler_class.R:486` asked
"how do TF2 and TFP use seeds?". Through the sampler path, they don't.

**[`set_tf_seed()` is inert](https://github.com/greta-dev/greta/blob/280dc906/R/inference_class.R#L86-L91).** It writes [`dag$tf_environment$rng_seed <- self$seed`](https://github.com/greta-dev/greta/blob/280dc906/R/inference_class.R#L90) and nothing else:

```r
# set RNG seed for a tensorflow graph. Must be done before definition of a
# random tensor
set_tf_seed = function() {
  dag <- self$model$dag
  dag$tf_environment$rng_seed <- self$seed
}
```

`rng_seed` is written here and **read nowhere** in the package. The only other
mention is a [commented-out `# REFACTOR: check_rng_seed(...)`](https://github.com/greta-dev/greta/blob/280dc906/R/calculate.R#L199). The comment above it describes TF1 semantics — build a
graph, then run a session — which is why setting a seed "before definition of a
random tensor" was once meaningful.

**And greta never passes a seed to [`sample_chain()`](https://github.com/greta-dev/greta/blob/280dc906/R/sampler_class.R#L492-L502).** The call passes
`num_results`, `current_state`, `kernel`, `trace_fn`, `num_burnin_steps`,
`num_steps_between_results` and `parallel_iterations` — no `seed`. Note
`tfp$mcmc$sample_chain` **does** accept `seed=` in TFP 0.25.0; greta simply does
not use it. (An earlier version of this note, and a source comment, said the
argument did not exist. Both were wrong, and it matters: passing it is the route
a fix would take.)

## It already works if you set both seeds

Measured 2026-08-20. `mcmc()` is reproducible today, provided the **TensorFlow**
seed is set as well as R's:

```r
set.seed(1)
tf$random$set_seed(1L)
```

- `set.seed()` alone: draws differ between runs
- `tf$random$set_seed()` alone: draws differ between runs
- both: **bit-identical** draws, and different seed pairs give different draws

So the machinery is all present; what is missing is greta calling
`tf$random$set_seed()`. `set_tf_seed()` is the obvious place, and today it
assigns to a field nothing reads.

This was used to prove an unrelated change inert — two chains, 150 draws, five
parameters, max absolute difference 0 — so it is a practical technique for any
greta change that should not alter the draws, not just a curiosity.

## Starting points

1. Have [`set_tf_seed()`](https://github.com/greta-dev/greta/blob/280dc906/R/inference_class.R#L86-L91) call `tf$random$set_seed()`. Smallest change, and the
   measurement above says it is sufficient for reproducibility.
2. Or thread a stateless seed through to [`sample_chain(seed = )`](https://github.com/greta-dev/greta/blob/280dc906/R/sampler_class.R#L492-L502). More work, but
   TFP's stateless seeds are also what a JAX substrate would need, and it does
   not rely on global state.
3. Or delete `set_tf_seed()` and document that seeding is R-side only — now
   clearly the wrong option, since the measurement shows R-side alone does not
   reproduce.

(The source comment at the `sample_chain()` call has since been corrected; it
used to claim the `seed` argument was already passed.)
