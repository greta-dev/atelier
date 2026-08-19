# greta.distributions: suggested issue and PR dispositions

Status: **suggestions only, nothing actioned.** Compiled 2026-07-29 from
reading each issue and its comments directly, plus the state of the working
tree. Where this disagrees with the `greta-distributions.qmd` chapter, the
chapter was written on 2026-07-21 against a two-distribution 0.1.0 and has
since been overtaken.

**Everything below is gated on one thing: the four new distributions exist only
as uncommitted changes in the working tree.** See "Where the work lives".

---

## Close with the release

| # | Title | Reason |
|---|---|---|
| #30 | zip and zinb don't work with MCMC and calculate | Scoping bug, fixed. `R/zero_inflated_poisson.R:62` read bare `pi`, which resolved to base R's `pi` (3.141593) and marshalled as float64 against greta's float32. Now `pi_var`. Regression tests at `tests/testthat/test_zip_zinb.R:18`. **Say in the close comment** that the second half of the issue ("`model(zip)` fails") is not a bug — greta is correctly refusing to sample a free discrete variable. |
| #32 | tfp has zero inflated negative binomial now? | The question asked is answered: TFP does expose it, and we went further by using the general `tfp$distributions$Inflated` rather than `ZeroInflatedNegativeBinomial`. **Close pointing at #20**, which already covers the truncation/hurdle variants raised in the comment, in more detail and with prior art. Do not duplicate that comment into new issues. |
| #34 | Explore TF inflated distribution as a way of adding a point mass | The exploration is complete and the answer was yes: `Inflated` is what the shipped ZINB uses. Applying it to *other* base distributions is separate work and belongs to #20/#21, not here. |
| #26 | ensure all new distributions have example usage in the helpfile | Verified done for all six exports — each has `\examples` in its Rd. The issue also asks about rendering conditionally on pkgdown but not CRAN; the standing answer is `@examplesIf` or pkgdown's own `\dontrun` handling, and the current `\dontrun{}` approach is what greta itself does and what `cran-comments.md` explains to the reviewer. Worth recording that answer in the close comment so it is not re-litigated. |
| #5 | Add conditional bernoulli | Implemented and tested in the tree. Closes when the tree lands. |
| #7 | add discrete lognormal and discrete normal | Both implemented and tested in the tree. Closes when the tree lands. |
| #14 | add ordered_logit distribution | Implemented and tested in the tree. Closes when the tree lands. Check the implementation took @hrlai's suggested route via TFP's `OrderedLogistic`; if so, say so in the close comment. |
| #27 | add conditional_bernoulli distribution | Duplicate of #5. Close together. |
| #29 | Release greta.distributions 0.1.0 | Tracking issue. **Keep open until the submission**, then close. Its checklist still lists #11 and #22 as release requirements — amend that, since both moved out of the milestone. |

## Keep open, with a note

| # | Title | What to add |
|---|---|---|
| #31 | add tests to capture error in #30 | The *testing* half is satisfied — four replacement tests are in the tree (`"has correct density"` and `"simulates and samples (#30)"` for both ZIP and ZINB). But #31's own assertions (`expect_no_error(model(example_zip))`) could never have passed, and the reason is the real content: **greta refuses to sample a free discrete variable.** Rescope to "strategies for free discrete variables in greta.distributions" and cross-reference greta [#191](https://github.com/greta-dev/greta/issues/191) (sampling from discrete distributions and prior sensitivities), [#157](https://github.com/greta-dev/greta/issues/157) (marginalising discrete random variables) and [#47](https://github.com/greta-dev/greta/issues/47) (decentring), all open and all in greta's milestone 9. |
| #25 | add example distributions in README | **Not done, contrary to the chapter.** The README lists all six distributions (lines 32-37) but carries worked examples for only two: zero-inflated Poisson and zero-inflated negative binomial. Four need adding, or the issue stays open. |
| #20 | hurdles and zero inflated distributions | Unchanged. This is the home for the truncated/hurdle variant, and #32 should point here. |

## New issue to file

| Title | Reason |
|---|---|
| `zero_inflated_negative_binomial()` documents `pi` as the "proportion of zeros", which it is not | `pi` is the mixing weight, not the proportion of zeros, because the NB component is untruncated. With the function's own example parameters, `pi = 0.10` yields `P(Y = 0) = 0.136`. Verified by simulation. Also affects `zero_inflated_poisson()`. Full write-up in `distributions-zinb-pi-documentation.md`. |

## Pull requests

| PR | Disposition | Reason |
|---|---|---|
| #35 | **Merge, with the working-tree repair squashed in** | As pushed it rewrote `tf_distrib` to use `Inflated` but deleted the `pi` parameter from `initialize()` and left the wrong name in `super$initialize()`, while the constructor still passes `pi`. Merging it unrepaired would ship a ZINB that ignores its own zero-inflation parameter. |
| #33 | **Defer to milestone 4** | Renames the four authoring functions, which are now `@noRd` and never shipped, so no deprecation is owed. Its real template bug is already fixed in the tree. |
| #31 | See above — keep open, rescoped | |
| #9 | **Assess after the tree lands** | Adds `conditional_bernoulli` on `origin/add-conditional-bernouilli`. The tree's version differs by **+180/−23 lines**, so it is a substantial rewrite, not a copy. Confirm the tree supersedes it before closing. |
| #10 | **Assess after the tree lands** | Adds multivariate probit on `origin/add-multivariate-probit-i6`. The tree's version differs by **+322/−142 lines**. Note the tree deliberately holds `multivariate_probit` back as `@noRd` for 0.1.0, with a comment in the source explaining how to export it. So #10's feature is present but unexported. |
| #16 | **Not superseded — its machinery is what ships.** Merge or credit, do not close as obsolete | Adds `discrete_lognormal`/`discrete_normal` from `hrlai:main`. **Corrected 2026-07-29:** an earlier version of this list had it down as "assess as superseded". It is not. PR #16 introduces `tf_safe_cdf(x, distribution, lower_bound, upper_bound)` in `R/tf_functions.R`, and the tree's `R/discrete-helpers.R` is that same function, same signature and same dummy-value trick, extracted into its own file with expanded comments. The shipped discrete distributions are built on hrlai's work. See "Attribution" below. |

## Attribution

`R/discrete-helpers.R` is uncommitted work in the tree, on no branch, and its
`tf_safe_cdf()` originates in @hrlai's PR #16. The technique it carries — swap
out-of-support inputs for an in-support dummy, evaluate the CDF, then mask the
result back to its analytic value — is what stops `cdf()` returning a correct
value with a `NaN` *gradient* and silently poisoning HMC. That is a real
contribution, not boilerplate, and both shipped discretised distributions
depend on it.

Two things follow, and both should be settled before the first release, since
`Authors@R` is fixed at submission:

- **@hrlai should almost certainly be `ctb` in `Authors@R`.** Currently the
  field lists only Nick Golding (`aut`, `cph`) and Nicholas Tierney
  (`aut`, `cre`).
- **PR #16 should not be closed as superseded.** Either merge it and build the
  refactor on top, or close it with an explicit statement that its machinery
  was carried into `R/discrete-helpers.R`, so the record is not misleading.

The same question applies less sharply to #9 and #10, where the tree's versions
diverge much further from the PRs (+180/−23 and +322/−142), but worth asking
whether the original authors of those should be credited too.

## Where the work lives

The four new distributions are **not on any branch.** `git log --all` finds
nothing for them. They are uncommitted, staged changes in the working tree,
sitting on top of `add-tf-zip-nb`:

| file | working tree | on a remote branch? |
|---|---|---|
| `R/ordered_logit.R` | added, uncommitted | no |
| `R/discrete_normal.R` | added, uncommitted | no |
| `R/discrete_lognormal.R` | added, uncommitted | no |
| `R/conditional-bernoulli.R` | added, uncommitted | `origin/add-conditional-bernouilli`, but +180/−23 different |
| `R/multivariate-probit.R` | added, uncommitted | `origin/add-multivariate-probit-i6`, but +322/−142 different |

Along with their Rd files, five test files and two snapshot files — 41 changed
files, roughly 3,000 added lines in total.

**This is the single point of failure for everything above.** `ordered_logit`,
`discrete_normal` and `discrete_lognormal` exist nowhere else at all. Landing
the branch is the prerequisite for closing #5, #7, #14 and #27, for assessing
#9, #10 and #16, and for filling the README gap in #25.
