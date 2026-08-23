# Give `compute_options` a structured object, so it can carry more than a device

## What I expect

That `compute_options` can express TensorFlow settings that are not "which
device", since several of them affect results rather than just placement.

## What happens instead

[`gpu_only()`](https://github.com/greta-dev/greta/blob/280dc906/R/utils.R#L863-L865) and
[`cpu_only()`](https://github.com/greta-dev/greta/blob/280dc906/R/utils.R#L869-L871) return the bare strings `"GPU"` and
`"CPU"`, which go straight to `tf$device()`. There is nowhere to put anything
else.

Two things want a home there.

**1. Op determinism on GPU.** Seeding fixes the random numbers, not the
arithmetic: some TensorFlow ops accumulate in a non-deterministic order on GPU,
so a seeded run can still vary. TensorFlow offers
`tf.config.experimental.enable_op_determinism()`, at a performance cost, which
is exactly the sort of trade-off a user should opt into rather than have chosen
for them. After #285, `set.seed()` makes `mcmc()` reproducible on CPU; on GPU it
gets you most of the way and no further, with nothing to reach for.

**2. `calculate()` disables the GPU for the whole session.** At
[`calculate.R#L217-L220`](https://github.com/greta-dev/greta/blob/280dc906/R/calculate.R#L217-L220) and
[`#L224-L227`](https://github.com/greta-dev/greta/blob/280dc906/R/calculate.R#L224-L227) it calls
`tensorflow::set_random_seed(disable_gpu = is_using_cpu(compute_options))`. That
function sets `CUDA_VISIBLE_DEVICES = -1` and **never puts it back**, so a single
`calculate(nsim = )` on the default `cpu_only()` hides the GPU from everything
later in the session:

```r
Sys.getenv("CUDA_VISIBLE_DEVICES")           # ""
calculate(x, nsim = 1)                        # default cpu_only()
Sys.getenv("CUDA_VISIBLE_DEVICES")           # "-1" - GPU now invisible
mcmc(m, compute_options = gpu_only())         # silently runs on CPU
```

`mcmc()` had the same problem briefly while fixing #285 and now seeds the Python
side directly instead. `calculate()` still needs a proper answer, and "which
device did the user actually ask for, and may we turn the GPU off" is
information that belongs in `compute_options`.

## Fix

Make `cpu_only()` and `gpu_only()` return a structured object rather than a
string, with arguments for the settings above — something like
`gpu_only(enable_op_determinism = TRUE)`.

Consumers that currently treat it as a string need updating:
`tf$device(compute_options)`, `compute_options == "CPU"`, `is_using_cpu()`,
`compute_text()`.

## This is not a breaking change

The constructor functions exist precisely so this could be added later, and the
string form was never part of the documented interface — `compute_options = "CPU"`
appears nowhere in `R/`, `tests/`, `vignettes/` or `inst/`. The `@param` has
promised this since it was written:

> *"Default is to use CPU only with `cpu_only()`. Use `gpu_only()` to use only
> GPU. [**In the future we will add more options for specifying CPU and GPU
> use.**](https://github.com/greta-dev/greta/blob/280dc906/R/inference.R#L42-L44)"*

## Related

Split out of #285, which is scoped to making `mcmc()` respect `set.seed()`.
