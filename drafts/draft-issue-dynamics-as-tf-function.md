# DRAFT — not filed

**Repo:** greta-dev/**greta.dynamics** (not greta)
**Found:** sweeping greta's `#TF1/2` markers for greta#745. The marker at
greta's `R/utils.R:629` asks "is `as_tf_function` still needed with the new
`tf_function` from TF2?" — that question lands here, because greta.dynamics is
the only thing that calls it.

---

**Title:** Explore replacing `greta:::as_tf_function()` with TF2's `tf_function()`

greta.dynamics converts R functions on greta arrays into functions on tensors
through greta's internal `as_tf_function()`, in three places:

- `R/iterate_dynamic_matrix.R:192`
- `R/iterate_dynamic_function.R:213`
- `R/ode_solve.R:223`

all as `do.call(as_tf_function, c(args, dots))`, with the function pulled from
greta's internals at `R/internals.R:19`:

```r
as_tf_function <- .internals$utils$greta_array_operations$as_tf_function
```

`as_tf_function()` predates TF2. It was written when a graph had to be built
explicitly; TF2's `tensorflow::tf_function()` now does the tracing, and greta
uses it directly everywhere else.

## Why this is worth looking at now

**greta.dynamics is the only consumer, anywhere.** Checked across greta.gp,
greta.gam and greta.distributions: none of them call it. Inside greta itself
there are no call sites at all — it survives only because it is exposed through
`.internals`.

That means **nothing in greta's test suite exercises it** (greta#751 is open to
add tests, precisely because there is no coverage today). So a change to
`as_tf_function()` in greta would break greta.dynamics with no failing test
anywhere to warn either repository. That is the risk this issue is really about;
whether `tf_function()` is a better tool is the secondary question.

## The constraint any replacement has to satisfy

There is already a workaround for how `as_tf_function()` captures environments,
at `R/iterate_dynamic_matrix.R:234` and `R/iterate_dynamic_function.R:285`:

```r
# note we need to access the greta stash directly here, rather than including
# it in internals.R, because otherwise it makes a copy of the environment
# instead and the contents can't be accessed by greta:::as_tf_function()
assign("batch_size", batch_size, envir = greta::.internals$greta_stash)
```

So `batch_size` is written into greta's stash rather than passed, because of how
the environment is captured. Whatever replaces `as_tf_function()` has to either
keep that behaviour working or make the workaround unnecessary — and the second
would be the better outcome.

## What would settle it

1. Whether `tensorflow::tf_function()` can take the same arguments greta.dynamics
   passes, given it traces rather than building a graph explicitly.
2. Whether the `greta_stash` workaround for `batch_size` is still needed under
   it, or falls away.
3. Whether the three call sites can share one helper here, rather than each
   doing `do.call(as_tf_function, ...)`.

If the answer is that `as_tf_function()` is still the right tool, that is worth
recording too — greta's marker can then be resolved as "keep, and it has one
known consumer", which is more than is known today.
