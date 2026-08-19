# TFP survey: what can `greta.distributions` get for free?

Survey date: 2026-07-21. Environment: R 4.6.1, greta 0.6.0, TensorFlow 2.15.1,
tensorflow_probability 0.23.0 (greta's managed `uv` environment, not a conda env —
`reticulate::import()` only resolves TFP *after* `library(greta); greta:::check_tf_version()`).

TFP 0.23.0's `tfp$distributions` namespace was introspected live (not read from docs):
**~120 public distribution classes** plus the composition wrappers `Inflated`, `Mixture`,
`MixtureSameFamily`, `TransformedDistribution`, `QuantizedDistribution`, `Sample`,
`Independent`, `Masked`, `BatchBroadcast`.

Every log-prob comparison below was run against an R reference. Agreement is at
**float32 precision (~1e-7)**, because that is the dtype used in these bare-TFP probes.
The ZINB's reported 5e-15 agreement comes from greta running in float64; expect the same
once these go through greta's own dtype handling. The precision here confirms the
*parameterisation*, which is the thing at risk.

---

## Summary table

| Wishlist item | TFP availability | Parameterisation vs R | Effort |
|---|---|---|---|
| **#14** ordered logit | `OrderedLogistic` — direct | ✅ matches `plogis(cutpoint - eta)`, diff 4.0e-08 | **XS** — cheapest win |
| **#21** zero-inflated beta | `Inflated(Beta(...))` — composition | ✅ matches `log(pi)` / `log((1-pi)*dbeta())`, diff 2.0e-07 | **XS** — same pattern as ZINB |
| **#7** discrete lognormal / normal | `QuantizedDistribution(LogNormal)` — composition | ✅ matches *ceil* convention `P(X<=k) - P(X<=k-1)`, diff 5.6e-07. ⚠️ **not** the floor convention | **S** — but see convention caveat |
| **#20** zero-inflated family | `Inflated(anything)` — composition | ✅ ZIP matches `extraDistr::dzip`, diff 6.1e-08 | **S** — generic wrapper |
| **#20** hurdle / zero-truncated | ❌ **no truncation primitive for discrete dists** | ⚠️ `QuantizedDistribution(low=)` **clamps, does not truncate** — see below | **L** — genuinely hand-rolled |
| **#18** Tweedie | ❌ **absent** from 0.23.0, incl. `tfp$experimental` | n/a | **L** — hand-rolled |
| **#19** open-ended wishlist | partial — see gap list below | mostly ✅ where present | **XS–M** per family |

---

## Evidence

### #14 ordered logit — `OrderedLogistic` (cheap win)

```
cutpoints = (-1.2, 0.3, 1.8), loc = 0.5, k = 0:3
  tfp: -1.86778607 -1.21840733 -1.09162981 -1.54100842
  R  : -1.86778603 -1.21840736 -1.09162978 -1.54100845     max abs diff 4.03e-08
```

R reference: `log(diff(c(0, plogis(cutpoints - loc), 1)))`. **The parameterisation is
exactly the R/Stan `cutpoint - eta` convention** — no sign flip, no reversal. Categories
are 0-indexed in TFP, so a greta wrapper needs to add 1 for R users (or document it).

`StoppingRatioLogistic` also exists, giving the continuation-ratio ordinal link for free
if that is ever wanted.

**⚠️ Duplicate with greta's own issue #264.** greta-dev/greta#264 ("add ordered logit
distribution") is open and explicitly undecided about where this should live: *"It's not
immediately clear to me whether this should live in the main greta package or an extension
package."* greta.distributions#14 is the same distribution, and hrlai's comment there
already points at `tfp OrderedLogistic`. **This needs one decision before either is
implemented — it must not ship in both packages.** Given the stated goal ("just want this
package to exist so people have access to more distributions"), greta.distributions is the
natural home, and greta#264 should be closed as moved.

### #21 zero-inflated beta — `Inflated(Beta)` (cheap win)

```
pi = 0.3, Beta(2, 5), x = (0, 0.1, 0.5, 0.9)
  tfp: -1.20397282  0.32049531 -0.42121345 -6.27117825
  R  : -1.20397280  0.32049528 -0.42121347 -6.27117845     max abs diff 2.04e-07
```

`inflated_loc` defaults to 0, which is what is wanted. `Inflated` emits a
`UserWarning: You have created an Inflated distribution with Beta, which is not discrete` —
this is **cosmetic and expected**; a zero-inflated continuous distribution is precisely a
mixed discrete-continuous measure, and the density is correct. The wrapper should suppress
that warning so it does not leak to greta users.

This is the identical pattern to the existing ZINB, so it is close to copy-paste from
`R/zero_inflated_negative_binomial.R`.

### #20 zero-inflated family — `Inflated` generalises

```
ZIP: lambda = 2.5, pi = 0.2, x = 0:4  vs extraDistr::dzip
  max abs diff 6.09e-08

current Inflated(NegativeBinomial) vs extraDistr::dzinb (regression check)
  max abs diff 1.59e-07
```

`Inflated` composes with any base distribution, so the whole zero-inflated half of #20 is a
single generic wrapper plus per-family argument checking. Note the existing ZINB already
encodes the key parameterisation trap: it passes `probs = 1 - prob` because **TFP's
`NegativeBinomial` `probs` is the complement of R's `prob`**. Any new inflated count
family needs the same audit — this is exactly the "TFP has it" ≠ "TFP matches R" gap.

TFP also ships a native `ZeroInflatedNegativeBinomial` (constructible, verified). It is
*not* worth switching to — the existing `Inflated(NegativeBinomial)` is already correct and
more general.

### #20 hurdle / zero-truncation — **the genuinely hard one**

There is **no discrete truncation primitive in TFP**. Only `TruncatedNormal` and
`TruncatedCauchy` exist, both continuous, both fixed-family.

The obvious candidate fails. `QuantizedDistribution(Poisson(2.5), low = 1)` **clamps**
probability mass onto the boundary rather than renormalising:

```
zero-truncated Poisson, lambda = 2.5, x = 1:4
  tfp: -1.2472371 -1.3605659 -1.5428873 -2.0128906
  R  : -1.4980588 -1.2749152 -1.4572368 -1.9272404     max abs diff 2.51e-01  ✗

  and log(ppois(1, 2.5)) = -1.247237  ==  the tfp value at x = 1, exactly.
```

That identity confirms the mechanism: `low=` makes `P(Y=1) = P(X<=1)`, i.e. the zero's mass
is *piled onto* 1, not removed and renormalised. **Using `low=` for hurdle models would
silently produce a wrong likelihood.** This is worth recording prominently — it is a trap
that looks like it works.

Hurdle therefore needs a hand-written `log_prob`: `dpois(x, lambda, log = TRUE) -
log1p(-dpois(0, lambda))` for `x >= 1`, plus the point mass at 0. Not hard maths, but real
code and real tests per family, and it does not delegate.

Note hrlai's comment on #20: `glmmTMB`'s `truncated_*` families are the hurdle ones, and
Francis Hui's `boral` uses `family = "zt*"`. Matching one of those naming conventions would
help ecologists. greta already exports `mixture()`, which may cover part of the two-part
construction at the user level.

### #18 Tweedie — absent

Grepped `tfp$distributions` and `tfp$experimental$distributions` for `tweed`,
case-insensitive: **zero matches**. The TFP PR the issue optimistically links
(tensorflow/probability#1418) is **not in 0.23.0**. Tweedie is fully hand-rolled work, and
it is the hardest density on this list — the compound Poisson-Gamma normalising constant
requires an infinite series evaluation, which needs care to make TF-differentiable and
numerically stable. This is a **research-grade task, not a low-hanging fruit**, contrary to
the issue's hope. Recommend re-scoping the issue with that note.

### #7 discrete lognormal / normal — convention caveat

```
Quantized(LogNormal(1, 0.7)), x = 1:5
  vs ceil  log(plnorm(k) - plnorm(k-1)):  max abs diff 5.62e-07   ✅
  vs floor log(plnorm(k+1) - plnorm(k)):  max abs diff 1.20e+00   ✗
```

`QuantizedDistribution` implements `Y = ceil(X)`. Golding's original implementation in
`covid19_australia_interventions` (linked from the issue) must be checked for which
convention it uses; if it is the floor convention, the wrapper needs a shift of 1 or the
change must be documented as intentional. **Another agent is working #7** — this is flagged
for overlap only; the actionable finding to pass them is the ceil-vs-floor result above and
the fact that `QuantizedDistribution` composes with *any* continuous base, so discrete
normal and discrete lognormal are one wrapper, not two.

### #19 open-ended wishlist — mapping to TFP

The issue points at `glmmTMB` families, `gamlss.dist`, and generic truncation via
`gamlss.tr`. Comparing TFP's namespace against what greta already exports, these are
**available in TFP and currently missing from greta**, verified by spot-check:

| Family | TFP class | Verified vs R | Note |
|---|---|---|---|
| Gumbel | `Gumbel` | ✅ 5.5e-08 | extreme values |
| Inverse Gaussian | `InverseGaussian` | ✅ 1.5e-07 | `glmmTMB`; `loc`/`concentration` = mu/lambda |
| Log-logistic | `LogLogistic` | ✅ 5.6e-08 | survival; `gamlss` |
| Skellam | `Skellam` | ✅ 1.2e-07 | difference of Poissons |
| Kumaraswamy | `Kumaraswamy` | ✅ 1.8e-07 | beta-like, closed-form CDF |
| Generalized Pareto | `GeneralizedPareto` | ✅ 2.3e-08 | extreme values |

Additionally present in TFP, unverified but likely cheap: `GeneralizedNormal`,
`GeneralizedExtremeValue`, `JohnsonSU`, `SinhArcsinh`, `Moyal`, `LogitNormal`,
`ContinuousBernoulli`, `Triangular`, `PERT`, `Bates`, `TwoPieceNormal`, `TwoPieceStudentT`,
`HalfNormal`, `HalfCauchy`, `HalfStudentT`, `Chi`, `NoncentralChi2`, `GammaGamma`,
`NormalInverseGaussian`, `ExponentiallyModifiedGaussian`, `VonMises`, `Geometric`, `Zipf`,
`ProbitBernoulli`, `BetaQuotient`, `DoublesidedMaxwell`.

`gamlss.tr`-style **generic truncation is not available** — same gap as the hurdle case.

**⚠️ Partial duplicate with greta's own issue #272** ("Use more tfp distributions"). That
issue is about *replacing greta's existing hand-written* Pareto, Cauchy and LKJ with TFP
equivalents — internal refactoring of distributions greta already exposes. It does **not**
overlap in user-facing surface with #19, which is about *new* families. No conflict, but
whoever picks up #272 and whoever picks up #19 are doing the same kind of work and should
share the parameterisation-audit approach.

---

## Ranked by effort-to-ship

**Tier 1 — cheap wins, ship first (hours each, pattern already proven by ZINB)**

1. **Ordered logit** (#14) — `OrderedLogistic`, direct, parameterisation confirmed exact.
   *Blocked on one decision: resolve against greta#264 first.* Caveat: 0-indexed categories.
2. **Zero-inflated beta** (#21) — `Inflated(Beta)`, near copy-paste from ZINB.
   Caveat: suppress the spurious "not discrete" warning.
3. **A handful of Tier-1 families from #19** — Gumbel, InverseGaussian, LogLogistic,
   Kumaraswamy, GeneralizedPareto, Skellam. All verified. Each is a thin wrapper; the only
   real work per family is the argument-name mapping to R conventions.

**Tier 2 — small, one design decision each**

4. **Generic zero-inflation wrapper** (#20, ZI half) — `Inflated` composes with anything;
   the work is API design, not density code. Per-family `probs` complement audits needed.
5. **Discrete lognormal / normal** (#7) — `QuantizedDistribution`, one wrapper covers both.
   Caveat: ceil convention; reconcile with Golding's original. *Another agent has this.*

**Tier 3 — genuinely hand-rolled, budget accordingly**

6. **Hurdle / zero-truncated families** (#20, hurdle half) — no TFP primitive; `low=` is a
   trap that clamps instead of truncating. Hand-written `log_prob` per family.
7. **Tweedie** (#18) — absent from TFP entirely; infinite-series normalising constant.
   The hardest item on the list, despite the issue calling it low-hanging fruit.

---

## Cross-cutting recommendation

The ZINB experience generalises into a checklist worth writing down once: for each TFP
delegation, (a) confirm the class exists in the pinned TFP version rather than in docs,
(b) compare log-prob against an R reference at several points including boundaries, and
(c) specifically check whether any probability argument is complemented (`probs` vs
`1 - prob`) or any support is index-shifted (0- vs 1-indexed categories, ceil vs floor
quantization). All three of the parameterisation traps found in this survey are instances
of (c).

## Reproducing

Probe scripts are in the session scratchpad (`verify.R`, `verify2.R`, `list.R`, `list2.R`).
They are self-contained: `library(greta); greta:::check_tf_version()` then
`reticulate::import("tensorflow_probability")`. No files in `greta.distributions` were
modified.
