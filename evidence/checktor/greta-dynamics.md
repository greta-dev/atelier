# checktor report: greta.dynamics

- **Package:** `/Users/nick_1/github/greta-dev/greta.dynamics` (v0.2.3, branch `main`)
- **checktor:** 0.1.0
- **Date:** 2026-07-21
- **Context:** CRAN resubmission prep after the 2025-09-20 archival. Substantial uncommitted
  CRAN-prep + pkgdown work was already in the tree and was left untouched.

## Headline

checktor reported **8 issues across 3 failed checks**. On triage, **all 8 are false positives
or deliberate, already-justified decisions**. Nothing checktor flagged was fixed.

The two genuine defects in this package were things **checktor missed**, both found by
checking URLs manually after `diagnose_urls()` returned a clean pass:

1. Dead `https://greta-stats.org/` in the package-level docs (SSL failure).
2. 404 legacy R-CMD-check badge in `README.md`.

Both are fixed. Score after re-run is still 8/3 — unchanged and expected, since the
remaining 8 are all things that should stay as they are.

## checktor findings and triage

### DESCRIPTION — `description.title_case` (1 issue)

> Word should be capitalized: 'greta'

**False positive. Not changed.** Title is `Modelling Structured Dynamical Systems in 'greta'`.
`greta` is deliberately lowercase — it is the software's own name and branding, and it is
correctly single-quoted per CRAN's requirement for software names in Title/Description.
Capitalising to `'Greta'` would misname the package. greta 0.6.0 was accepted by CRAN with
the identical lowercase-quoted convention. checktor's Title Case rule has no exception for
quoted software names.

*Cross-cutting:* this will fire on every greta-family package. Recommend ignoring it
uniformly across the fleet.

### Documentation — `documentation.example_structure` (4 issues)

> potential unnecessary \dontrun — `iterate_dynamic_function.Rd`, `iterate_dynamic_matrix.Rd`,
> `iterate_matrix.Rd`, `ode_solve.Rd`

**Deliberate and required. Not changed.** All four examples construct greta models evaluated
through TensorFlow/TFP via Python. CRAN's machines have no Python/TF, so these cannot run
there. Already justified in `cran-comments.md`. Unwrapping them would guarantee example
failures on CRAN.

Note checktor contradicts itself here: the same run also reports `✔ \dontrun use is
appropriate`. The `example_structure` heuristic appears not to consider `SystemRequirements`.

### Documentation — `documentation.commented_examples` (3 issues)

> commented-out call in \examples — `iterate_dynamic_function.Rd`, `iterate_matrix.Rd`,
> `ode_solve.Rd`

**False positive. Not changed.** I read every comment line inside the `\examples` blocks of
all three files. There are **zero** commented-out calls. Every one is explanatory prose. The
heuristic is matching parenthesised English:

- `# density-dependent (logistic) growth towards a carrying capacity of 100,`
- `# conditional (on survival) probability of staying in a stage`
- `# we can use greta to solve directly, for a fixed set of parameters (the true`
- `# build the model (takes a few seconds to define the tensorflow graph)`

checktor is reading `(logistic)`, `(on survival)`, `(the true` etc. as function calls.
Acting on this would mean deleting useful explanatory comments from good examples.

*Cross-cutting:* any package with prose comments containing parentheses will trip this.
Worth reporting upstream to checktor as a heuristic bug — the rule needs to require an
identifier immediately preceding `(` and, ideally, a balanced closing paren.

### Everything else

All other checks passed: no `T`/`F`, no seed setting, no `print()`/`cat()`, all `\value`
tags present, all exported functions have `\examples`, `NEWS.md` and `cran-comments.md`
present, package size 3.73 MB, README relative links resolve, no policy violations.

Confirmed clean via standalone runs of `diagnose_value_tags()`, `diagnose_missing_examples()`,
`diagnose_print_cat_usage()`, `diagnose_readme_relative_links()`, `diagnose_tf_usage()`,
`diagnose_seed_setting()`, `diagnose_cran_comments_file()`, `diagnose_news_file()`,
`diagnose_package_size()`.

## Genuine issues — found manually, checktor missed both

`diagnose_urls()` returned `passed = TRUE` with zero issues. It does not appear to extract
URLs from `\href{}{}` in `.Rd` files or from markdown links in roxygen comments, and it does
not resolve them over the network. I extracted every URL from `R/`, `man/`, `vignettes/`,
`README.md`, `DESCRIPTION`, `NEWS.md`, `_pkgdown.yml` and resolved each with `curl -L`.

### 1. Dead URL: `https://greta-stats.org/` — FIXED

```
https://greta-stats.org/ :: curl (60) SSL: no alternative certificate subject name
                            matches target host name 'greta-stats.org'
```

Present in the package-level description:

- `R/greta.dynamics-package.R:4` — `[greta](https://greta-stats.org/)`
- `man/greta.dynamics.Rd:9` — `\href{https://greta-stats.org/}{greta}`

Replaced with `https://greta-dev.github.io/greta/` (verified 200). This is a CRAN blocker:
URL checking is part of incoming submission checks and a hard SSL failure on a `.Rd` link
draws a NOTE at minimum.

Both source and generated `.Rd` were edited by hand rather than running `roxygenise()` over
the package, to avoid churning the other `man/` files that the existing uncommitted work
already touches. **Verified no drift:** I copied `R/`, `man/`, `DESCRIPTION`, `NAMESPACE`
into a scratch dir, ran `roxygen2::roxygenise(load_code = "source")` there, and diffed —
the generated `greta.dynamics.Rd` is byte-identical to my hand-edited version.

### 2. 404 badge in README — FIXED

```
https://github.com/greta-dev/greta.dynamics/workflows/R-CMD-check/badge.svg :: 404
```

This is the pre-2020 badge URL form. The workflow is `.github/workflows/R-CMD-check.yaml`,
so the current form is `/actions/workflows/R-CMD-check.yaml/badge.svg` (verified 200).

`README.md` is **not** in `.Rbuildignore`, so it ships in the tarball and its URLs are
subject to CRAN's URL check. Updated both the image and its link target.

## Left alone deliberately

- **The 1 NOTE** (`detritus in the temp directory`: `__autograph_generated_file*.py`,
  `__pycache__`). Per instruction — TensorFlow autograph artefacts, impossible on CRAN,
  identical NOTE accepted for greta 0.6.0, declared in `cran-comments.md`. Not touched.
- **Skipped tests** guarded by `skip_if_not(check_tf_version())`. Correct and necessary.
- **`SystemRequirements`** naming Python/TF/TFP. Legitimate.
- **Codecov badges pinned to `?branch=master`** while the repo's default branch is `main`.
  Both URLs return 200 so this is not a CRAN issue, but the badge is reporting coverage for
  a branch that is no longer the default and is likely stale. Left unchanged to keep this
  diff minimal and CRAN-scoped — **flagging for the maintainer as a trivial follow-up.**
  Same fix would apply to the sibling packages.

## Pre-existing item confirmed, not fixed

`tests/testthat/test_iterate_dynamic_matrix.R` — 5 of 6 `test_that` blocks are commented out
(lines ~69 onward). Inspected: the commented blocks call `iterate_matrix()` and reference
`iterates$stable_distribution`. They look like stale copies from `test_iterate_matrix.R`
rather than tests of `iterate_dynamic_matrix`, and they reference the same non-existent
`stable_state`/`stable_distribution` return element that the uncommitted work just corrected
in the `@return` docs.

Not touched — outside a checktor pass, not a CRAN blocker, and uncommenting them would very
likely produce failures that need real design decisions about what
`iterate_dynamic_matrix()` should actually return. Recommend a separate issue.

## Notes for sibling packages and upstream

**Do not blanket-replace `greta-stats.org`.** The apex domain is dead (SSL), but the forum
subdomain **`https://forum.greta-stats.org/` is alive and returns 200**. Only apex-domain
references need changing.

| Location | Reference | Status | Action |
|---|---|---|---|
| `greta/README.md:9` | `forum.greta-stats.org` | 200 alive | leave |
| `greta/vignettes/faq.Rmd:98` | `forum.greta-stats.org/` | 200 alive | leave |
| `greta/vignettes/installation.Rmd:502` | `forum.greta-stats.org/` | 200 alive | leave |
| `greta/vignettes/webpages/contribute.Rmd:20` | `forum.greta-stats.org` | 200 alive | leave |
| `greta/pkgdown/_pkgdown.yml:67` | `forum.greta-stats.org` | 200 alive | leave |
| `greta*/.github/ISSUE_TEMPLATE.md:3` | `forum.greta-stats.org/` | 200 alive | leave |

No apex-domain `greta-stats.org` references were found in greta.gp or greta.distributions.

**Legacy 404 badge is cross-cutting — worth fixing in both:**

- `greta/README.md:40` — `https://github.com/greta-dev/greta/workflows/R-CMD-check/badge.svg` (404).
  Replacement `/actions/workflows/R-CMD-check.yaml/badge.svg` verified 200.
- `greta.distributions/README.md:12` — same legacy form (404).
  Replacement verified 200.

greta.gp's README does not use the legacy form.

**checktor heuristics worth reporting upstream:**

1. `diagnose_urls()` misses `\href{}{}` in `.Rd` and markdown links in roxygen comments,
   and does not resolve URLs over the network. It gave a clean pass on a package with a
   hard-SSL-failing link and a 404 badge. Treat its pass as non-evidence; check URLs
   manually (`urlchecker::url_check()` would be a better fit in the release workflow).
2. `documentation.commented_examples` false-positives on prose comments containing
   parentheses.
3. `documentation.example_structure` flags `\dontrun` without consulting
   `SystemRequirements`, and contradicts the `\dontrun use is appropriate` check in the
   same run.
4. Title Case rule has no exception for quoted software names.

## Files changed

| File | Change |
|---|---|
| `R/greta.dynamics-package.R` | line 4: `greta-stats.org` → `greta-dev.github.io/greta/` |
| `man/greta.dynamics.Rd` | line 9: same, in `\href{}{}` (roxygen-verified identical) |
| `README.md` | line 4: legacy 404 R-CMD-check badge → current `/actions/workflows/` form |

Three lines across three files. No commits or pushes made. The pre-existing uncommitted work
(DESCRIPTION, NEWS.md, the three `iterate_*.R` and their `.Rd`, `_pkgdown.yml`,
`cran-comments.md`, `pkgdown/`) was not touched — verified by diffing against a snapshot
taken before I started.

## Re-run result

`checktor()` after fixes: **8 issues, 3 failed checks** — identical to before, as intended.
The remaining failures are `description.title_case`,
`documentation.example_structure`, `documentation.commented_examples`, all triaged above as
false positives or deliberate choices.

`devtools::check()` was **not** run per instruction. **A re-run would be worthwhile** — the
changes are documentation-only and cannot affect code, but the `.Rd` edit means
`R CMD check`'s own URL check should get a chance to confirm the replacement link is clean.
Expectation is unchanged: 0 errors, 0 warnings, 1 NOTE (the declared temp-directory detritus).
