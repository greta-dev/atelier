# greta.gam #16 — the original error is fixed

**Issue:** [#16](https://github.com/greta-dev/greta.gam/issues/16), "error when
including smooths term in eta: `object 'n_samples' not found`", filed 2024-02-12.

**Verdict: the reported error no longer occurs.** The reprex still fails, but on
a different and already-identified problem.

## What was reported

```
Error in self$sample_carefully(free_state = self$free_state,
  sampler_burst_length = as.integer(n_samples), :
  object 'n_samples' not found
```

An R scoping bug in **greta**, not greta.gam: `n_samples` was referenced in a
call where it had no binding.

## What happens now

Running #16's reprex verbatim on greta 0.6.0 / greta.gam 0.2.1, the error is:

```
TensorFlow hit a numerical problem that caused it to error
greta can handle these as bad proposals if you rerun `mcmc()` with the argument
`one_by_one = TRUE`.
```

and `greta_notes_tf_num_error()` gives:

```
Detected at node MatrixInverse ... Input is not invertible.
```

`grepl("not found", conditionMessage(e))` is `FALSE`. The scoping error is gone.

## Why it is fixed

greta's `sampler_class.R` now binds the name explicitly before use, with a
comment recording the rename:

```r
# legacy: previously we used `n_samples` not `sampler_burst_length`
n_samples <- sampler_burst_length
```

So the variable that was missing is now defined from `sampler_burst_length`.
This was fixed in greta, not greta.gam, and not deliberately in response to #16
as far as I can tell.

## Suggested disposition

**Close, with a note** saying:

- the reported `object 'n_samples' not found` error is resolved as of greta 0.6.0
- the reprex in the issue still fails, but on the `MatrixInverse` problem, which
  is a separate issue (link it)
- so #16 is not a duplicate that was silently fixed by luck — the specific defect
  it named is genuinely gone

Worth linking the two so that anyone arriving at #16 from a search is not sent
looking for a scoping bug that no longer exists.

## A caution on how I nearly got this wrong

My first check was:

```r
grepl("n_samples", as.character(r))   # TRUE
```

which I briefly read as "still the same bug". It is not — the error *call* is
`self$check_for_free_state_error(result, n_samples)`, so the string "n_samples"
appears in the call text regardless of what the error says. Testing
`conditionMessage()` rather than the deparsed error object gives the right
answer.
