# checktor report: greta.gp

- **Package:** `/Users/nick_1/github/greta-dev/greta.gp`
- **Version:** 0.2.3 (CRAN resubmission after 2025-09-20 archival)
- **Branch:** `submit-to-cran-i20`, HEAD `eac8755` ("initial fixes for CRAN")
- **checktor:** 0.1.0
- **Date:** 2026-07-21

> Note on package state: the brief said there was substantial *uncommitted* CRAN-prep
> work. There was not — it had already been committed as `eac8755`. The working tree
> was clean when I started, so my one-line change is the only uncommitted diff.

## Result

| Run | total_issues | failed_checks |
|---|---|---|
| Before | 4 | 3 |
| After | 4 | 3 |

The count is unchanged **because all 4 checktor findings are false positives or
deliberate choices**. The one genuine problem in the package was something checktor
does *not* check for, found by manual inspection, and it is fixed.

## Full checktor output

Everything passed except the items listed under Triage. Passing checks, for the record:

- **Code (13/13 pass):** no `T`/`F`, no hardcoded seeds, no unsuppressable
  `print()`/`cat()`, options reset properly, no home-dir writes, temp files cleaned up,
  no `.GlobalEnv` modification, no `installed.packages()`, no `options(warn = -1)`,
  no software installation in functions, core usage limited, no `library()`/`require()`
  in package code, `Sys.setenv()` calls reset.
- **DESCRIPTION (12/13 pass):** software names formatted, no unexplained acronyms,
  license formatting, title length ≤ 65, title not starting with an article, no
  redundant phrases, no single-quoted function names in Title/Description, `Authors@R`
  present, `[cph]` role present, reference formatting, description length, description
  does not start with a forbidden phrase, `'R'` quoted properly.
- **Documentation (5/7 pass):** all `\value` tags present, all exported functions have
  `\examples`, unexported examples use `:::` where needed, `\dontrun` use appropriate,
  examples guard Suggested-package usage.
- **General (4/4 pass):** package size 4.89 MB (under the 5 MB limit), no URL issues,
  NEWS file found, README relative links resolve to shipped files.
- **Policy (4/4 pass):** no `browser()`, no dangerous system calls, file operations
  safe, network operations wrapped.

## Triage

### 1. DESCRIPTION — "Title case: word should be capitalized: 'greta'" — FALSE POSITIVE

Title is `Gaussian Process Modelling in 'greta'`. `greta` is the package name, which is
lowercase by design, and it is correctly single-quoted per CRAN's rule for software
names in Titles. Capitalising it to `'Greta'` would misname the package. greta itself
is on CRAN with the lowercase quoted form. **No change.**

### 2. Documentation — "gp.Rd / kernels.Rd: potential unnecessary `\dontrun`" — DELIBERATE

Every example builds a greta model, which requires Python + TensorFlow + TensorFlow
Probability. CRAN's check machines have none of these. This is justified in
`cran-comments.md` and matches greta's own accepted CRAN pattern. Note checktor
contradicts itself here: the finer-grained check in the same run reports
`✔ \dontrun use is appropriate`. The "example structure" heuristic simply flags any
`\dontrun` block whose contents look runnable in isolation. **No change.**

### 3. Documentation — "gp.Rd: commented-out call in `\examples`" — FALSE POSITIVE

Traced to checktor's regex in `checktor:::diagnose_commented_examples`:

```r
if (grepl("^\\s*#[^'#].*\\(", ln, perl = TRUE)) { ... }
```

Any comment line containing an opening parenthesis is treated as commented-out code.
The offending line in `man/gp.Rd` is prose, not code:

```r
# or project with a different kernel (e.g. a sub-kernel)
```

The parenthesis is English, not a call. Removing or rewording this comment to satisfy
the regex would make the example less clear. **No change.** This is a checktor bug
worth reporting upstream — the regex should require a call shape (identifier
immediately followed by `(`), not merely the presence of `(` anywhere after `#`.

### 4. GENUINE — `LazyData: true` with no `data/` directory — FIXED

Not detected by checktor. `DESCRIPTION` carried `LazyData: true` while the package
ships no `data/` directory. Confirmed against R's own check logic in
`tools:::.check_packages`:

```r
if (thislazy || lazyz0) {
    checkingLog(Log, "LazyData")
    if (thislazy && !dir.exists("data")) {
        if (R_check_use_log_info) infoLog(Log) else noteLog(Log)
        printLog0(Log, "  'LazyData' is specified without a 'data' directory\n")
```

So it is a NOTE, downgraded to INFO only when `_R_CHECK_USE_LOG_INFO_` is set — which
is why the local `devtools::check()` reported 0 notes but CRAN's incoming checks may
not be so forgiving. The field is inert (there is no data to lazy-load), so removing
it is zero-risk.

Provenance: `git log -S LazyData -- DESCRIPTION` traces it to `68ab08a`
("RStudio skeleton package") — boilerplate that was never applicable.

**Fixed:** removed the line from `/Users/nick_1/github/greta-dev/greta.gp/DESCRIPTION`.

## Independent checks beyond checktor

checktor's URL check passed but does not appear to fetch, so I resolved every URL in
the package sources by hand (`curl -L`, following redirects):

| URL | Status |
|---|---|
| `https://greta-dev.github.io/greta.gp/` | 200 |
| `https://github.com/greta-dev/greta.gp` | 200 |
| `https://github.com/greta-dev/greta.gp/issues` | 200 |
| `https://greta-dev.r-universe.dev/` | 200 |
| `https://www.tensorflow.org/` | 200 |
| `https://www.tensorflow.org/probability/` | 200 |
| `https://doi.org/10.21105/joss.01601` | 200 → joss.theoj.org (normal DOI resolution) |
| `https://CRAN.R-project.org/package=greta.gp` | 200 (canonical form, correct) |

**`greta-stats.org` is not referenced anywhere in greta.gp.** I verified the apex is
indeed dead (`curl` exit 60, SSL: no alternative certificate subject name matches
`greta-stats.org`). However `https://forum.greta-stats.org/` — the only greta-stats
subdomain referenced, in `.github/ISSUE_TEMPLATE.md` — **returns 200 and is alive**.
No action needed, but worth knowing: the apex being dead does not imply the forum
subdomain is.

Other verified-clean items:

- **`T`/`F`:** none anywhere in `R/` or `tests/`.
- **`print()`/`cat()`:** exactly one `cat()`, at `R/greta_kernel_class.R:85`, inside
  `print.greta_kernel()`. That is precisely where `cat()` belongs; converting it to
  `message()` would break print-method semantics. checktor correctly ignored it.
- **`@return`/`\value`:** present in both `man/gp.Rd` and `man/kernels.Rd`.
- **`set.seed(123)`** at `tests/testthat/helpers.R:3` — in tests, which is correct and
  desirable, not package code.
- **Test skipping:** `skip_if_not(check_tf_version())` pattern in place as documented.
- **`SystemRequirements`:** legitimately names Python/TF/TFP. Correct.

## Files changed

Exactly one:

- `/Users/nick_1/github/greta-dev/greta.gp/DESCRIPTION` — removed `LazyData: true`

```diff
 Encoding: UTF-8
 Language: en-GB
-LazyData: true
 Roxygen: list(markdown = TRUE)
```

Nothing committed or pushed. `NEWS.md` was not touched — this is an invisible
DESCRIPTION hygiene fix with no user-facing effect, so a NEWS bullet would be noise,
but add one if you prefer completeness.

## Cross-cutting notes for siblings and upstream

1. **`LazyData` — greta.gp only.** Checked all four: `greta.dynamics` and
   `greta.distributions` have no `LazyData` field (clean). `greta` has
   `LazyData: true` at `DESCRIPTION:142` and *does* have `data/`
   (`greta_deps_tf_tfp.rda`), so it is legitimate there. **No sibling action needed** —
   but any package generated from the same RStudio skeleton is worth a glance.

2. **checktor false positives to expect in every sibling.** All three greta extension
   packages will trip the same two heuristics, and the triage above applies verbatim:
   - lowercase quoted `'greta'` in the Title flagged as a title-case error;
   - `\dontrun{}` flagged as "potentially unnecessary" when it is mandatory for
     TF-dependent examples.
   Sibling reviewers should not "fix" either.

3. **checktor bug worth filing upstream** (github.com/coatless-rpkg/checktor): the
   commented-example regex `^\s*#[^'#].*\(` flags ordinary prose comments containing a
   parenthesis. Any sibling with a comment like `# fit the model (slow)` will trip it.

4. **`greta:::check_tf_version()` in the vignette.** `vignettes/getting-started.Rmd:13`
   uses `eval = greta:::check_tf_version("message")` — a `:::` call into greta, which is
   a `Depends`. R CMD check's "unexported objects imported by ':::' calls" NOTE only
   scans `R/`, not vignettes, so this does not currently fail any check and I left it
   alone. But it is fragile: it will break silently if greta renames or removes that
   internal. **Suggested upstream fix in greta:** export a small, documented predicate
   (e.g. `greta::has_tf()` or export `check_tf_version()` itself) so extension packages
   can gate vignettes and tests without reaching into greta's internals. Worth checking
   whether greta.dynamics and greta.distributions do the same thing — if all three do,
   that is a strong case for the upstream export.

5. **Non-shipped link hygiene (cosmetic, greta.gp).** `.github/CONTRIBUTING.md` uses
   `http://` (not `https://`) for `style.tidyverse.org` and `reprex.tidyverse.org`, and
   uses the non-canonical `https://cran.r-project.org/web/packages/roxygen2/...` form
   that CRAN asks maintainers to avoid. `.github/` is in `.Rbuildignore`, so none of
   this reaches the tarball or CRAN's URL checker. Left unchanged to keep the diff
   minimal. If the siblings share this boilerplate CONTRIBUTING.md, a single sweep
   across all repos would be tidier than four separate fixes.

## Requests

- **`devtools::check()` needs one re-run** to confirm the `LazyData` removal keeps the
  package at 0/0/0. I did not run it per instructions. The change cannot introduce a
  problem (it deletes an inert field), but a confirming run before submission is worth
  it.
