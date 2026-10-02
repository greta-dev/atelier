# Three leftovers in `sampler_class.R`, found reviewing #834

All three are small, all are in the sampler's per-burst bookkeeping, and none
is worth an issue on its own. **1 and 2 share a cause** — state on the sampler
object that is never reset when `extra_samples()` reuses it — and could be
fixed together. **3 is independent** and can be split out if that is tidier.

All line references are pinned to
[`280dc90`](https://github.com/greta-dev/greta/commit/280dc9068b4d718ebfe9324c3b21e3a30a3950de).

---

## 1. `accept_history` grows forever, and is read only during warmup

This is #834's defect in a different field. `accept_history` gains a row per
iteration on **every** burst of **both** phases
([`L558`](https://github.com/greta-dev/greta/blob/280dc9068b4d718ebfe9324c3b21e3a30a3950de/R/sampler_class.R#L558)):

```r
self$accept_history <- rbind(self$accept_history, is_accepted)
```

Its only reader is `tune_diag_sd()`
([`L450`](https://github.com/greta-dev/greta/blob/280dc9068b4d718ebfe9324c3b21e3a30a3950de/R/sampler_class.R#L450)),
which runs only during warmup. Every row added during sampling is dead
accumulation, copied again by `rbind` on each append.

Worse, nothing resets it. The `if (from_scratch)` block
([`L129-L140`](https://github.com/greta-dev/greta/blob/280dc9068b4d718ebfe9324c3b21e3a30a3950de/R/sampler_class.R#L129-L140))
resets `traced_free_state` and `traced_values` but not `accept_history`, so
`extra_samples()` keeps growing it across every call:

```
after mcmc:   accept_history rows = 40    (20 warmup + 20 sampling)
after extra:  accept_history rows = 60
after extra2: accept_history rows = 80
```

**Fix.** Append only during warmup, and reset it alongside the other fields in
the `from_scratch` block.

## 2. `numerical_rejections` is not reset on the `extra_samples()` path

The reset lives inside `run_warmup()`'s `if (perform_warmup)` block
([`L235`](https://github.com/greta-dev/greta/blob/280dc9068b4d718ebfe9324c3b21e3a30a3950de/R/sampler_class.R#L235)),
but `extra_samples()` passes `warmup = 0L`
([`R/inference.R#L501`](https://github.com/greta-dev/greta/blob/280dc9068b4d718ebfe9324c3b21e3a30a3950de/R/inference.R#L501))
and `from_scratch = FALSE`
([`#L506`](https://github.com/greta-dev/greta/blob/280dc9068b4d718ebfe9324c3b21e3a30a3950de/R/inference.R#L506)),
so the block short-circuits and the reset never runs. The count carries over:

```
after mcmc:  numerical_rejections = 10
after extra: numerical_rejections = 20
```

Since the sampling progress bar reports `rejects = self$numerical_rejections`,
`extra_samples(verbose = TRUE)` shows a bad-proposal figure that includes the
previous run's rejections. The user sees a percentage for work that is not part
of this call.

**Fix.** Reset it once per `run_chain()` before the phases begin, rather than
as a side effect of warmup. That also makes the reset say what it means.

## 3. `run_burst()` carries an empty debug block on the hot path

[`L531-L536`](https://github.com/greta-dev/greta/blob/280dc9068b4d718ebfe9324c3b21e3a30a3950de/R/sampler_class.R#L531-L536):

```r
if (
  is.null(batch_results$all_states) && Sys.getenv("GRETA_DEBUG") == "true"
) {
  ## TODO probably need to remove this?
  # browser()
}
```

The body is empty, so this calls `Sys.getenv()` on every burst of every chain
and then does nothing. It also swallows the case it names: when `all_states`
really is `NULL`, control falls through to `as.array(NULL)` on the next line
and fails with an opaque error rather than the diagnostic this was meant to
give.

**Fix.** Delete it, or make it a real check that errors informatively when
`all_states` is `NULL`.

---

## What these are worth

Small, and none changes draws.

1. is memory and dead work, the same shape as #834 but on a logical matrix, so
   the constant is much smaller — bytes rather than doubles. The unbounded
   growth across `extra_samples()` calls is the part that could actually bite.
2. is a wrong number shown to the user, and the only one of the three that is
   visible without reading the source.
3. is cosmetic, apart from the swallowed diagnostic.

Found reviewing #834, which removes the same class of dead work from the warmup
loop. `tune_diag_sd()` counting rejections instead of acceptances came out of
the same review and is written up separately, as it is the only one of the four
that changes sampler behaviour.
