# Open questions and caveats

Things flagged during the 29-30 July session that are unresolved, unverified, or
need a decision. Kept here so they are not lost in conversation.

Last updated: 2026-07-30.

## Needs a decision from Nick

| # | Thing | Why it needs deciding |
| --- | --- | --- |
| 1 | greta.distributions scope: **6 exports or the book's 2** | Everything else in that release depends on it. The tree exports six with correctness tests; the design book chapter describes a two-distribution 0.1.0 |
| 2 | `Authors@R` for greta.distributions | `tf_safe_cdf()` in `R/discrete-helpers.R` originates in @hrlai's PR #16. Fixed at submission, so decide before |
| 3 | `multivariate_probit` stays `@noRd`? | Complete and tested, deliberately unexported. Also fixed at submission |
| 4 | The `sp` prior fix is a **choice of three**, not a one-liner | Match jagam exactly / document the current prior as greta.gam's own / pick a better-conditioned prior. See `gam-sp-prior-rate-scale.R` |
| 5 | greta `Language: en-US` → `en-GB`? | greta.gam, greta.gp, greta.dynamics are already en-GB. greta has a 137-line WORDLIST and is on CRAN, so changing it means a release |
| 6 | Where the issue drafts live once filed | `design/notes/issues/` is a staging area. Delete after filing, or keep? Risk of the same drift we spent 29 July fixing |

## Unverified or unrun

- **`distributions-zinb-pi-documentation.R` has never been run.**
  greta.distributions is not installed, so it fails at `library()`. Only
  checkable via `pkgload::load_all()` until the tree is committed.
- **The four README example drafts have never been run**
  (`distributions-readme-examples-draft.md`). They come from `\dontrun{}` blocks
  that never execute in `R CMD check`.
- **The `ordered_logit` README draft puts an unconstrained prior on `cuts`**,
  which lets the sampler propose them out of order and hit
  `check_cuts_increasing()`. Needs fixing or replacing before it ships.
- **`gam-sp-prior-rate-scale.R` quotes stale numbers.** Prose cites RMSE 0.24 /
  2.63 / 1.05; a later run gave 0.41 / 2.26 / 0.72. The *direction* is stable
  (corrected prior ~3x worse against mgcv) but the magnitudes are not, because
  greta does not seed MCMC. Should become approximate language.
- **`gam-intercept-prior-hardcoded.R`'s test is commented out**, because drawing
  from the intercept prior currently hits the `MatrixInverse` failure. Becomes
  runnable once that is fixed.

## Unresolved mechanism

**Why the sampler reaches a singular `K`** in the `MatrixInverse` bug. Three
explanations proposed, each contradicted by measurement:

1. ill-conditioning from `sp[2]` going small — but the TF inverse returns
   cleanly at `cond(K) = 3e22`, and at exactly singular input
2. gradient overflow — but gradients of both routes overflow identically, at the
   same threshold, and neither raises
3. `sp[1]` underflowing to zero in float32 — but observed `sp` draws sit around
   1e-4 to 1e-3, thirty orders of magnitude away

What *is* established: failure depends on warmup length (0/8 at `warmup = 0`,
5/8 at 50), so it is something the sampler reaches during warmup, not the initial
values. The fix does not depend on resolving this.

**Also unexplained:** the non-monotonicity at `warmup = 200` (1/8 failures,
against 5/8 at 50). Could be noise at n = 8, or step-size adaptation moving away
from the bad region. Not investigated.

## Structural, not a bug

`K` is near-singular *by design*. `Sa` (wiggliness) is rank 8 of 9 because a
straight line has no curvature, so the linear direction is unpenalised; `Sb` is
rank 1 and covers exactly that direction (verified: `|cos angle| = 1`). So `K` is
full rank only through a single rank-1 term scaled by a free parameter the
sampler moves. Inherent to penalised smoothing.

`mgcv` rarely hits it because it *optimises* `sp` rather than sampling it.

**The deeper fix** is to never form `K^-1`: build the prior from `chol(K)`
directly, non-centred. `design/notes/greta-gam-sp-default.md` records 0 failures
in 25 runs that way, but min ESS 11 against 55-69. Worth revisiting;
`chol2inv()` is the immediate patch.

## Corrections I made to my own earlier claims

Recorded because they bear on how much to trust the rest.

- **"greta.gam is ready for CRAN"** (29 July, morning) — wrong. Based on one
  clean `R CMD check` of a vignette that fails ~50% of runs.
- **"`chol2inv(chol())` is cheaper"** — wrong twice. `bench::mark` in R said 2x
  faster; that measured the wrong language *and* a line that runs once at graph
  construction. The TF op is 8% slower, end-to-end 3% slower.
- **"`solve()` raises on ill-conditioned input"** — only true for 2x2 matrices I
  invented. With jagam's real matrices it never raises, even at exactly singular
  input.
- **"smooths() discards `sp`, contradicting #5"** — #5 was about
  `jagam2greta()`, which does forward it. The gap is in the `smooths()` wrapper.
  #5 was not wrong.

## Skill maintenance

`~/.claude/skills/reprex/SKILL.md` is **~840 lines across 33 sections**, grown by
accretion across one session. Demonstration guidance is now spread across four
sections. Needs a consolidation pass before anyone else uses it, and a check for
rules that contradict each other.
