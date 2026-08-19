# PR #16 — discrete_normal and discrete_lognormal

Status: **both distributions landed and passing numerical correctness tests.**
Nothing committed. `devtools::document()` not run (see "Handover" below).

## Summary

The incoming assessment was half right, and its two halves were right for the
wrong reasons. Both distributions turned out shippable, and `discrete_lognormal`
— the one written off as "has always failed" — needed a real fix, not deletion.

| Claim in brief | Verdict | What is actually true |
|---|---|---|
| `discrete_normal` works end-to-end including MCMC | **Partly wrong** | Its *density* is correct, but `sample()` is broken — `self$breaks` is never assigned, so `calculate(nsim=)` dies with a TF `GatherV2` error |
| `discrete_lognormal` calls 4-arg `tf_safe_cdf` with 2 args and has always failed | **Right, but shallow** | True and reproduced, but the arity error is a *surface* symptom. The substantive blocker is a NaN gradient at the lognormal boundary |
| Ship the half that works, drop the other | **Rejected** | Both now work. The lognormal fix was ~10 lines once diagnosed |

## What I verified empirically

### 1. `discrete_lognormal` fails as reported (surface level)

Ran PR #16's code verbatim:

```
Error in eval(cl, parent.frame()) :
  argument "lower_bound" is missing, with no default
```

Cause is visible in the PR's own commit history: commit `15cc772c` ("remove hard
fix of lower and upper bounds in `tf_safe_cdf`") widened `tf_safe_cdf` from 2
arguments to 4 while updating only `discrete_normal`'s call sites.
`discrete_lognormal` was written against the 2-argument version and was never
updated. So hrlai's "`discrete_lognormal` now seems to work" was true *when
written* and was silently broken later in the same PR. Both statements in the
thread are correct; they just refer to different commits.

### 2. PR #16's `discrete_normal` density is correct — but uses the **round** convention

This resolves the "off by 0.5" that the PR thread never got to the bottom of
(njtierney, 2022-08-03: *"Regarding the distribution being off by 0.5"*).

PR #16, mean = 1, sd = 2, at `x = c(-2, 0, 1, 3, 5)`:

```
PR16 discrete_normal   -2.724323 -1.744878 -1.622459 -2.112150 -3.581472
round F(x+.5)-F(x-.5)  -2.724323 -1.744878 -1.622459 -2.112150 -3.581472   <- exact match
floor F(x+1)-F(x)      -2.387620 -1.653064 -1.653064 -2.387620 -4.101945   <- extraDistr::ddnorm
```

The implementation was never wrong; it answered a different question than the
reference njtierney proposed in 2024 (`extraDistr::ddnorm`, which is floor). A
test against `ddnorm` would have "failed" a correct implementation.

The `breaks`/`edges` machinery is in fact sound and general: feeding it
*integer* edges rather than half-integer edges reproduces `extraDistr::ddnorm`
to the last digit. The convention is entirely a property of where the user puts
the edges, which is exactly why it was so easy to get confused.

### 3. PR #16's `discrete_normal` sampling is broken

`initialize()` has the `self$breaks <- breaks` assignment commented out, but
`tf_distrib()` still reads `self$breaks` for the `sample()` path:

```
self$breaks after initialize():  NA
calculate(d, nsim = 5):  InvalidArgumentError: params must be at least
                         1 dimensional [Op:GatherV2]
```

So `discrete_normal` was *not* working end-to-end. Density yes; simulation no.

### 4. The real `discrete_lognormal` blocker: NaN gradient at zero

tfp's `LogNormal$cdf(0)` returns `0` — the correct value — but its **gradient
with respect to `scale` is NaN**:

```
cdf(0)              = 0
grad wrt meanlog    = 0.7766535
grad wrt sdlog      = NaN
```

Any dataset containing a zero therefore poisons every gradient evaluation and
breaks HMC, while the log density itself still looks perfectly fine. This is
what `tf_safe_cdf` exists for, and it is why Golding's original had the
`pmax(breaks, .Machine$double.eps)` line — the guard was in the right spirit but
applied to the breaks vector rather than to the CDF call.

Guarded vs unguarded, same inputs:

```
unguarded d/d sdlog:  NaN
guarded   d/d sdlog:  8.445579
```

## What I landed

New files (all previously untracked; no existing file was modified):

- `R/discrete-helpers.R` — shared machinery
- `R/discrete_normal.R`
- `R/discrete_lognormal.R`
- `tests/testthat/test-discrete_normal.R`
- `tests/testthat/test-discrete_lognormal.R`

### Design decisions

**Floor convention, `F(x + 1) - F(x)`, for both.** Matches `extraDistr::ddnorm`
(the reference njtierney asked for), matches the brief, and makes the two
distributions mutually consistent. Documented explicitly in roxygen, including
how to get the round convention (`discrete_normal(mean - 0.5, sd)`).

**Dropped the `breaks`/`edges` arguments.** The signatures are now
`discrete_normal(mean, sd, dim)` and `discrete_lognormal(meanlog, sdlog, dim)`.
The PR required users to pass *both* `breaks` and `edges` and to keep them
mutually consistent by hand, with no validation; getting them wrong silently
changes the discretisation convention. Arbitrary-bin censoring is a genuinely
useful but *different* feature — it is interval-censoring, not discretisation —
and belongs in its own distribution if wanted later.

**One shared helper, as the brief anticipated.** `tf_discretised_log_prob()` in
`R/discrete-helpers.R` computes `log(F(x+1) - F(x))` and is the entire body of
both distributions' `log_prob`. The only differences between the two
distributions are which tfp distribution supplies `F`, the central value used to
pick the stable tail form, and the support's lower bound.

**Numerical stability.** The naive CDF difference cancels catastrophically in
the upper tail, so the helper switches to a difference of *survival* functions
above the distribution's centre. Both branches are computed and selected with
`tf$where`, which propagates NaN from the branch it discards — so both branches
go through the masking helpers (`tf_safe_cdf`, and a new mirror
`tf_safe_survival`) to guarantee neither can produce a NaN anywhere.

**`tf_safe_cdf` kept at its 4-argument signature**, unchanged from the PR, and
now genuinely used by both distributions. For `discrete_normal` the bounds are
`-Inf`/`Inf` and it degrades to a plain `cdf()` call. For `discrete_lognormal`
the lower bound is `.Machine$double.eps`, which routes `x = 0` around the CDF
call entirely and fills in its analytic value of `0`.

### Evidence the landed code is correct

Density vs R reference, max absolute difference over the tested grid:

```
discrete_normal    vs extraDistr::ddnorm            2.6e-13
discrete_lognormal vs plnorm(x+1) - plnorm(x)       2.5e-13
```

MCMC recovery — checked against the **exact MLE for the same dataset**, not
against the true parameters, so that sampling noise cannot be mistaken for an
implementation error:

```
discrete_normal, n = 400, true mu = 2, sd = 3
  exact MLE    mu 1.767   sigma 3.096
  greta MCMC   mu 1.765   sigma 3.110
```

(An earlier run showed `mu = 1.570` against a true `2.0`, which looked like
bias. It was not — that dataset's own MLE was 1.767 with a posterior SD of
0.217. This is precisely the trap the 2022 thread fell into when it concluded
`discrete_normal` "does not recover the mean and sd well".)

```
discrete_lognormal, n = 300, true meanlog = -0.5, sdlog = 1
  67% of observations are zeros — exercises the boundary path on nearly
  every gradient evaluation
  greta MCMC   meanlog -0.440   sdlog 1.011
```

Test suite: **13 tests, 24 assertions, 0 failures, 0 skips.** Every density
assertion is a numerical comparison against an R reference; there are no
`expect_error(..., NA)` smoke tests.

## Two findings worth propagating

**`extraDistr::ddnorm` is itself unreliable in the upper tail.** It forms the
CDF difference directly. At `mean = 0, sd = 1` it is already wrong in the 4th
decimal at `x = 8` and underflows to `-Inf` by `x = 12`:

```
x      greta        extraDistr    stable R reference
8     -35.013619    -34.945041    -35.013619
12    -75.410676         -Inf     -75.410676
```

My tail test therefore uses a stable hand-rolled reference and says why in a
comment. Worth knowing generally: **`extraDistr` is not a trustworthy oracle in
the tails**, and other distributions in this package that test against it may be
comparing correct code to a degraded reference.

**`QuantizedDistribution` is not a drop-in.** Checked per the coordinator's
intel and independently confirmed: it implements the **ceil** convention,
matching `F(x) - F(x-1)` exactly and differing from floor by a one-unit shift. I
did not adopt it — it would have had to be shifted to match the chosen
convention, and it is unverified against the `cdf(0)` NaN-gradient problem,
which is the actual hard part of `discrete_lognormal`. The hand-rolled helper is
~40 lines, matches the R reference to 1e-13, and its stability behaviour is
known. The test `"discrete normal uses the floor convention, not ceil or round"`
pins this: swapping to `QuantizedDistribution` would fail it loudly.

## Handover

- **`devtools::document()` has not been run**, per instructions. Both new
  distributions carry `@export`, so NAMESPACE needs regenerating before they are
  user-visible. This does *not* conflict with the deliberate un-exporting of the
  four template-creator helpers — the exports here are the distributions
  themselves, which is the point of the package.
- `extraDistr` is already in `Suggests`; no DESCRIPTION change is needed.
- Unrelated pre-existing failures in `test-conditional-bernoulli.R` (2 errors)
  belong to a sibling agent's concurrent work, not to this change.
- PR #16 should be closed as superseded rather than merged: the shipped
  signatures differ, and its `breaks`/`edges` design was deliberately not
  carried over.
