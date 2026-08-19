# checktor report — greta.distributions

Date: 2026-07-21
Package: `/Users/nick_1/github/greta-dev/greta.distributions`
Branch: `add-tf-zip-nb` (extensive uncommitted work — preserved, not disturbed)
checktor: 0.1.0
Status: **first CRAN submission**, version 0.1.0

## Headline

checktor reports **12 issues across 4 failed checks**, both before and after
my changes. **Every one of the 12 is a false positive or a deliberate,
justified choice.** None should be "fixed".

The problems actually worth fixing in this package were the two the
maintainer already identified — the README and NEWS advertising the
now-unexported authoring functions — and checktor cannot detect either,
because both are semantic (docs describing functions that no longer exist in
the public API), not structural. Fixed both, plus a factual error in
`cran-comments.md` that I found while triaging.

The unchanged issue count between runs is therefore the expected result, not
a failed remediation. Its value is as a **regression check**: the README
edits did not break `README relative links resolve to shipped files`, and no
new URL, `\value`, or example issues were introduced.

## Full findings and triage

### 1. `code.globalenv_mod` — `zzz.R:5` — FALSE POSITIVE

```r
tfp <- NULL                                            # line 1

.onLoad <- function(libname, pkgname) {
  tfp <<- reticulate::import("tensorflow_probability", delay_load = TRUE)
}
```

checktor flags `<<-` as a `.GlobalEnv` modification. It is not. Because
`tfp <- NULL` is bound at the top level of the package, `<<-` inside
`.onLoad()` walks the enclosing environments and assigns into the **package
namespace**, never the global environment. This is the documented reticulate
idiom for delay-loading a Python module, and it is exactly what greta itself
does.

**Verdict: leave.** checktor is pattern-matching `<<-` without resolving the
binding. Worth reporting upstream to checktor as a refinement: a `<<-` whose
target has a top-level binding in the same package is a namespace write, not
a global one.

### 2. `description.title_case` — "Word should be capitalized: 'greta'" — DELIBERATE

Title: `Extends Distributions Available in the 'greta' Package`

`greta` is lowercase by design — that is the package's actual name — and it
is single-quoted, which is precisely the CRAN convention for naming other
software in a Title. Capitalising it to "Greta" would name a package that
does not exist. greta 0.6.0 passed CRAN with the same lowercase quoted form.

**Verdict: leave.** checktor's title-case rule should exempt single-quoted
tokens; quoting is the signal that a word is a proper software name whose
capitalisation is fixed. Also worth reporting upstream to checktor.

### 3. `documentation.example_structure` ×6 — "potential unnecessary \dontrun" — DELIBERATE

Flagged for all six exported distributions: `conditional_bernoulli`,
`discrete_lognormal`, `discrete_normal`, `ordered_logit`,
`zero_inflated_negative_binomial`, `zero_inflated_poisson`.

Already justified in `cran-comments.md`. These examples build greta models
evaluated through TensorFlow and TensorFlow Probability via Python, none of
which is present on CRAN check machines. Note checktor's own
`\dontrun use is appropriate` check **passes** on the same files — the two
rules disagree, and the more specific one is right.

**Verdict: leave.**

### 4. `policy.file_operations` ×4 — DELIBERATE, but documentation improved

- `greta_distribution_template_test.R:93` (`file.create()`)
- `greta_distribution_template_test.R:94` (`writeLines()`)
- `new_distribution.R:46` (`file.create()`)
- `new_distribution.R:47` (`writeLines()`)

These are inside `write_distribution_test()` and `write_new_distribution()` —
two of the four authoring functions deliberately unexported and `@noRd` for
0.1.0. They are unreachable without `:::`, are called by no exported
function, example, test or vignette (verified by grep across `R/` and
`tests/`), and exist as developer tooling for this package's own source tree.

**Verdict: leave the code.** But see the `cran-comments.md` fix below — the
file did not mention them, and a reviewer grepping for `file.create` would
have found them contradicting a claim in the submission notes.

One genuine caveat for the maintainer: these functions write to relative
paths `R/` and `tests/testthat/` via `make_r_path()` / `make_test_path()`
(`R/utils.R`), i.e. into the **current working directory**, and
`create_a_directory()` will `dir.create()` there. That is correct for a
scaffolding tool run inside a package project, and harmless while unexported.
If any of these are exported in 0.2.0, they will need an explicit `path`
argument defaulting to the working directory with user confirmation, or CRAN
will object. Flagging now so it is not a surprise later.

## Checks that passed and were specifically verified

Ran the fine-grained diagnostics individually as well as the full suite. All
pass:

`diagnose_urls`, `diagnose_readme_relative_links`, `diagnose_news_file`,
`diagnose_cran_comments_file`, `diagnose_value_tags`, `diagnose_tf_usage`,
`diagnose_print_cat_usage`, `diagnose_missing_examples`,
`diagnose_package_size` (0.16 MB), `diagnose_seed_setting`.

Of note given the brief:

- **No `T`/`F` usage.** Clean.
- **No missing `@return`/`@value` tags.** Clean.
- **No `print()`/`cat()` misuse.** Clean.
- **URLs clean.** `greta-stats.org` (confirmed dead, SSL failure) appears
  **once**, in `.github/ISSUE_TEMPLATE.md:3`
  (`https://forum.greta-stats.org/`). `.github` is in `.Rbuildignore`, so it
  ships in neither the tarball nor CRAN's URL check — hence checktor's pass
  is correct for submission purposes. It is still a dead link shown to every
  person opening a GitHub issue. **I did not change it** (it is cosmetic, out
  of CRAN scope, and the correct replacement forum URL is a maintainer
  decision), but it should be fixed, and see the sibling section below —
  this is almost certainly repo-wide across greta-dev.
- `https://greta-dev.github.io/greta/` in README — live, retained.

## Changes made

### `README.Rmd` / `README.md` — genuine problem, fixed

The README is the CRAN landing page, and it instructed users to call four
functions that are not exported.

1. Removed the entire `## Helpers for adding extra distributions` section
   (old lines 79–91), which told users to call
   `greta_distribution_template()`, `greta_distribution_template_test()`,
   `write_new_distribution()` and `write_distribution_test()`, and included a
   runnable `greta_distribution_template()` example. All four are unexported;
   every one of these calls would now fail with
   `could not find function`.
2. Rewrote `## Why`. It claimed the package "exists for two reasons", the
   second being "Provide helper functions for creating new distributions" —
   no longer true. Replaced with a statement of what the package provides,
   and **a list of all six exported distributions**. The README previously
   documented only two of the six, which undersells the package on its CRAN
   landing page.
3. Added a `## Code of Conduct` section in place of the removed section.
   Deliberately linked with an **absolute** GitHub URL, not a relative
   `CODE_OF_CONDUCT.md` link — `CODE_OF_CONDUCT.md` is in `.Rbuildignore`, so
   a relative link would not resolve in the tarball and would newly fail
   checktor's `readme_relative_links` check. Confirmed still passing.
4. `## Example extra distributions` → `## Examples`, and "Both distributions
   below" → "The two distributions below", now that six exist.

`README.md` regenerated with
`rmarkdown::render(output_format = "github_document")` to match the existing
file's formatting (no YAML front matter, wrapped lines). Note: `knitr::knit()`
is **not** the right command here — it leaves the YAML header in the output.
A stray `README.html` produced by pandoc was deleted.

### `NEWS.md` — genuine problem, fixed

1. Deleted the `## Tools for writing new distributions` section (old lines
   21–27), which announced all four unexported functions as 0.1.0 features.
2. Rewrote `## Distributions` to list **all six** distributions. It previously
   announced only `zero_inflated_poisson()` and
   `zero_inflated_negative_binomial()`, omitting `discrete_normal()`,
   `discrete_lognormal()`, `conditional_bernoulli()` and `ordered_logit()` —
   four distributions shipping unannounced in a first release. Descriptions
   were written from each function's own roxygen docs, not invented.
3. Corrected the trailing note: "both distributions are discrete" → "All of
   these distributions are discrete".
4. Preserved the `zero_inflated_poisson()` / `calculate()` `pi` fix (#30),
   moved to `## Other`.

### `cran-comments.md` — factual error, fixed

Found during triage of finding 4. The file stated:

> The package exports nothing else — there is no user-facing tooling, and no
> function writes to the file system.

The second clause was **false**: `write_new_distribution()` and
`write_distribution_test()` do call `file.create()` and `writeLines()`. They
are unexported, so the spirit was right, but as written this is an inaccurate
statement in a document a CRAN reviewer reads — and CRAN's own automated
scans flag `file.create`/`writeLines` exactly as checktor just did. A reviewer
would have found the contradiction.

1. Narrowed the claim to "No **exported** function writes to the file system,
   changes the user's options, or writes to the global environment."
2. Added a `### Unexported code-generation helpers` section pre-empting the
   grep hit: naming the four functions, stating that two call `file.create()`
   and `writeLines()`, and explaining they are unexported, undocumented,
   unreachable without `:::`, and never called by any exported function,
   example, test or vignette.

This turns a discoverable contradiction into a disclosed, explained design
choice — the right posture for a first submission.

## Deliberately not changed

- **All 12 checktor findings** — see triage above.
- **`multivariate_probit`** — remains unexported. Not re-exported, not
  re-documented, code and tests untouched.
- **The four authoring functions** — remain unexported, man pages remain
  deleted.
- **`Language: en-US` with British spellings** — see below.
- **`greta-stats.org` in `.github/ISSUE_TEMPLATE.md`** — out of CRAN scope,
  correct replacement is a maintainer decision.
- **`progress` in `Imports`** — see below.

## Two things needing a maintainer decision

### `Language: en-US` vs British spellings

Audited the tree. `Language: en-US` is declared, but the docs consistently use
British spellings: `realisation`/`realisations` (heavily, throughout
`conditional-bernoulli.R` and `multivariate-probit.R`, and in
`man/conditional_bernoulli.Rd`), `discretisation` (`discrete_normal.R`,
`discrete_lognormal.R`, `man/discrete_normal.Rd`), and `parameterisation`
(`ordered_logit.R`). `inst/WORDLIST` now carries `discretisation`,
`realisation`, `realisations` purely to suppress the resulting spellcheck
failures.

**My view, stated rather than acted on:** the WORDLIST is being used to
paper over a real mismatch, and it will keep growing — every new distribution
written in the house style adds entries. Two coherent options:

1. **`Language: en-GB`.** Matches how the docs are actually written, empties
   three WORDLIST entries, and stops the accretion. CRAN accepts en-GB without
   comment.
2. **Keep `en-US` and Americanise the prose** (`realization`,
   `discretization`, `parameterization`).

What is not coherent is declaring en-US and then suppressing every en-GB word
individually. I have **not changed the field**, because the brief is explicit
that en-US is a deliberate choice matching greta itself — and consistency
across the greta family is a legitimate reason that outweighs tidiness. But
if greta itself is en-US while its docs are also British, the same mismatch
exists upstream and is worth settling once for the whole family rather than
per package. This is not a submission blocker either way.

### `progress` is an unused dependency

`progress` is listed in `Imports` (`DESCRIPTION:39`) but is **never used**.
Audited every Import for `pkg::` and `importFrom` usage:

| Import | Uses |
|---|---|
| cli | 22 |
| glue | 35 |
| **progress** | **0** |
| R6 | 9 |
| reticulate | 1 |
| rlang | 18 |
| styler | 2 |
| tensorflow | 2 |

The only `progress`-adjacent code is greta's own progress bar reached via
`.internals` (`R/internals.R:9`) and test helpers — neither uses the
`progress` package directly. This normally produces an R CMD check NOTE
("Namespaces in Imports field not imported from"), which sits oddly with the
reported 0 notes.

**I did not remove it** — dropping a declared dependency is a maintainer call
and I cannot re-run `devtools::check()` to confirm the consequence.
**Recommend removing `progress` from `Imports`, then re-running
`devtools::check()`.** If the note genuinely is not firing, worth
understanding why before submitting.

## Re-run result

```
Found 12 issues across 4 failed checks
code.globalenv_mod  description.title_case
documentation.example_structure  policy.file_operations
```

Identical to the pre-change run, as expected — all 12 are false positives or
deliberate choices, and the README/NEWS defects were outside checktor's
detection. All fine-grained diagnostics pass, confirming the README rewrite
introduced no relative-link, URL, or example regressions.

**`devtools::check()` has not been re-run** (per instructions). Nothing I
changed touches R code, `NAMESPACE`, or `DESCRIPTION`, so a re-check is not
strictly required — but if `progress` is removed from `Imports`, it will be.

## Files changed

All within `/Users/nick_1/github/greta-dev/greta.distributions/`:

- `README.Rmd` — removed unexported-function section, rewrote `## Why` with
  all six distributions, added Code of Conduct section, wording fixes
- `README.md` — regenerated from the above
- `NEWS.md` — removed unexported-function section, listed all six
  distributions, corrected "both" → "all"
- `cran-comments.md` — corrected false file-system claim, added section
  disclosing the unexported helpers

No other repo touched. **Nothing committed or pushed.**

## For the sibling packages and upstream

Things checked in parallel on greta.gp / greta.dynamics / greta should watch
for:

1. **The `<<-` in `.onLoad` false positive will recur** anywhere the
   reticulate delay-load idiom is used — which is all of them, including
   greta itself. Do not "fix" it in any of them. One upstream checktor issue
   covers the whole family.
2. **The lowercase-`greta` title-case false positive will recur** in every
   extension package, since they all name 'greta' in their Title. Same
   treatment: leave, report upstream once.
3. **The `\dontrun{}` finding will recur** in every package whose examples
   need TensorFlow — i.e. all of them. Each needs the same `cran-comments.md`
   justification greta.distributions has. Worth using identical wording
   across the family so a reviewer seeing several submissions sees a
   consistent, considered policy rather than four different excuses.
4. **`greta-stats.org` is dead (SSL failure) and is very likely in every
   repo's `.github/ISSUE_TEMPLATE.md`**, copied from a common template. Worth
   a single sweep across greta-dev rather than four separate discoveries.
   Confirm the replacement URL once (or drop the forum line) and apply
   everywhere.
5. **Audit `Imports` for unused packages in the siblings too.** `progress`
   being dead here suggests the DESCRIPTION was inherited from greta and not
   pruned; the same stale entries may exist elsewhere.
6. **Settle en-US vs en-GB once for the whole family** rather than
   accumulating divergent `inst/WORDLIST` files. See above.
7. **README/NEWS drift is the class of bug checktor cannot catch.** It found
   none of the real problems here. Any sibling that unexported or renamed
   functions late in its release prep needs the same manual pass: grep README,
   NEWS and vignettes for every name no longer in `NAMESPACE`. Quick check
   per package:

   ```sh
   # names mentioned in docs but not exported
   grep -oE '[a-z_]+\(\)' README.Rmd NEWS.md | sort -u
   # compare against NAMESPACE exports
   ```
