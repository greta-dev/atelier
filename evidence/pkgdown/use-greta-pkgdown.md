# `use_greta_pkgdown()` and the greta.pkgdown template fixes

Date: 2026-07-21. Follows the three friction logs in this directory
(`greta-gp.md`, `greta-gam.md`, `greta-dynamics.md`).

Everything below is **uncommitted** in
`/Users/nick_1/github/greta-dev/greta.pkgdown`. No other repo was modified.

---

## Part 1 — template defects fixed

All four were confirmed by more than one friction log. Fixing them in the
template removed work the helper would otherwise have had to automate around.

### 1. Broken opengraph image

The shared config pointed at `man/figures/name_icon_on_purple.png`, a file only
greta ships. Consumers built with no warning and a dead `og:image`.

**Fix:** `name_icon_on_purple.png` now ships in
`inst/pkgdown/BS5/assets/`, and the shared `src:` is the bare filename
`name_icon_on_purple.png` — the same mechanism the navbar wordmark already used
correctly. `pkgdown:::copy_assets()` copies the template package's `assets/` to
every consumer's site root, so `data_open_graph()` resolves it to
`<site url>/name_icon_on_purple.png` for everyone with zero consumer config.

Consequence: the per-consumer `template: opengraph:` override that all three
agents wrote by hand is now **unnecessary and should be deleted** from
greta.gp's and greta.gam's `_pkgdown.yml`.

The shared `alt:` stays `"greta"`, deliberately — it describes the image, which
is the greta wordmark, and re-introducing a per-package override would put back
exactly the boilerplate this fix removes.

### 2. `.template-home aside { display: none }` fired unconditionally

Documented as opt-in, but gated on nothing, so every consumer's home sidebar was
rendered by pkgdown and then silently hidden by CSS.

**Fix (gated, per the logs' preference):**

```scss
.template-home:has(#head),
.template-home:has(aside.col-md-3:not(:has(*))) { aside { display: none; } ... }
```

Two conditions, both genuine opt-ins:

1. `#head` — the page actually uses the greta hero scaffolding;
2. an aside with no element children — i.e. the consumer set
   `home: sidebar: false`, so pkgdown emitted the aside but put nothing in it.
   Without this the empty aside still eats a third of the page.

Verified against a real build: with `home:` sidebar left at its default, the
sidebar renders *and is visible*; with `sidebar: false`, pkgdown emits a
literally empty `<aside class="col-md-3"></aside>` and the rule fires.

Because consumers now have a real choice, `use_greta_pkgdown()` deliberately
does **not** write `home: sidebar: false`. That reverses the recommendation in
all three logs, which was conditional on this defect existing.

### 3. Hard-coded navbar brand `alt="greta"`

**Fix:** `alt="{{#package}}{{name}}{{/package}}"` in
`inst/pkgdown/BS5/templates/navbar.html`. `pkgdown:::data_template()` puts
`package$name` in the mustache context, so this resolves to the consuming
package. Verified: greta.dynamics' built navbar now renders
`alt="greta.dynamics"`, greta.pkgdown's own renders `alt="greta.pkgdown"`.

### 4. `bootstrap: 5` had to be restated by every consumer

The logs concluded the template "cannot" set this. **It can** — reading
`pkgdown:::as_pkgdown()` shows why:

```r
bs_version_local  <- get_bootstrap_version(pkg, pkg$meta$template)
template_meta     <- find_template_config(template_package, bs_version_local)
if (is.null(bs_version_local))
  bs_version_remote <- get_bootstrap_version(pkg, template_meta$template, template_package)
```

When the consumer omits it, `bs_version_local` is `NULL`, so
`path_package_pkgdown()` is called with no version and looks at the
**unversioned** `inst/pkgdown/_pkgdown.yml`. It never looks in `BS5/` — which is
exactly why the template's config was invisible at that moment.

**Fix:** the shared config moved from `inst/pkgdown/BS5/_pkgdown.yml` to
`inst/pkgdown/_pkgdown.yml` and now sets `bootstrap: 5`. This works down both
paths, with no duplicated file:

- consumer omits `bootstrap:` → unversioned path is read → `bootstrap: 5`
  applies **and** `template_meta` is that same file, so the bslib theme, the
  opengraph default and the shared `right:` navbar all still merge in;
- consumer states `bootstrap: 5` → pkgdown looks for `BS5/_pkgdown.yml`, does
  not find it, and `path_package_pkgdown()` falls back to the unversioned path.

`assets/`, `extra.scss` and `templates/` are looked up *after* the version is
resolved, so they correctly stay under `BS5/`.

Covered by a regression test that asserts `bs_version == 5` for a consumer whose
`_pkgdown.yml` omits it. The helper still always writes `bootstrap: 5` anyway.

---

## Part 2 — the favicon contradiction, resolved

`greta-dynamics.md` said the set should live in greta.pkgdown's `inst/`.
`greta-gam.md` said it must live in the consumer's `pkgdown/favicon/` because
pkgdown never reads it from a template package.

**Both are right, about different ends.** Verified by reading pkgdown 2.2.0:

```r
pkgdown:::has_favicons  <- function(pkg) file_exists(path_favicons(pkg))
pkgdown:::copy_favicons <- function(pkg) dir_copy_to(path(pkg$src_path, "pkgdown", "favicon"), ...)
```

`pkg$src_path` is the **consuming package's** source tree, unconditionally.
There is no template-package branch anywhere in the favicon path — unlike
`copy_assets()`, which does have one. So:

- **destination** must be the consumer's `pkgdown/favicon/` (greta-gam.md);
- **canonical source** should be greta.pkgdown, so consumers stop raiding
  greta's copy (greta-dynamics.md);
- therefore **copying is a job for the helper**, which is what both logs were
  reaching for.

Implemented: the seven-file set now lives in `inst/pkgdown/favicon/`, and
`use_greta_pkgdown()` stamps it into `pkgdown/favicon/`, skipping any file the
consumer already has.

`site.webmanifest` is copied verbatim; its `"name"`/`"short_name"` are empty and
so package-neutral, as greta-dynamics.md noted. If anyone ever fills them in for
greta, this copy must diverge.

---

## Part 3 — the helper

`greta.pkgdown::use_greta_pkgdown(path = ".", overwrite = FALSE)`.

Idempotent, non-destructive, reports every action with cli. Re-running it on an
edited `_pkgdown.yml` adds only the top-level keys that are still missing, by
**appending text** rather than round-tripping through YAML — so existing
comments and formatting survive byte-for-byte. `template:` is the one key it
patches in place, inserting missing sub-keys under the existing heading, because
"already has `template: {bootstrap: 5}`" is the normal starting state.

Automatic:

- `_pkgdown.yml`: `template: {package, bootstrap: 5}`; `url:` (preferring the
  `github.io` entry in `DESCRIPTION`'s `URL:`, else derived from the GitHub repo,
  else guessed with a warning); `development: {mode: auto}`.
- `pkgdown/favicon/` from greta.pkgdown's `inst/`.
- `Config/Needs/website: greta-dev/greta.pkgdown`, appended to any existing
  value rather than replacing it.
- `.Rbuildignore` (`^_pkgdown\.yml$`, `^pkgdown$`, `^docs$`) and `.gitignore`
  (`docs`).
- `articles:` globbed from `vignettes/*.Rmd`, plus a navbar entry that scales
  with vignette count: none → `left: [reference, news]`; one → a `get started`
  component; many → an `examples` dropdown.

Stubbed with `TODO`, per the logs' "don't automate — stub it":

- `home: title:`/`description:`, seeded from `DESCRIPTION`;
- `reference:`, one `All functions` section listing every topic. A stub is
  necessary rather than merely nice: pkgdown hard-errors on an index that does
  not cover every topic. Internal topics (`\keyword{internal}`) are excluded and
  the package-level topic is emitted as its `<pkg>-package` alias, which was the
  gotcha two logs hit by hand.

Never copies `extra.scss`, `assets/` or `templates/`.

Prints the vignette-safe smoke-test recipe
(`build_reference_index()` then `build_home()`) rather than `build_site()`.

Not done, though the logs suggested it: offering to install the r-lib actions v2
pkgdown workflow. Rewriting a consumer's `.github/` is a bigger, more opinionated
change than the rest of the function and belongs in its own helper.

---

## Part 4 — validation

Against scratch copies in the session scratchpad; the real repos were not
touched.

`greta.dynamics` (2 vignettes), started from the two-line `_pkgdown.yml`
recorded in its friction log:

- helper reported 7 actions, all correct;
- `pkgdown::check_pkgdown()` → "No problems found";
- `build_reference_index()` + `build_home()` clean;
- `alt="greta.dynamics"`; `og:image` resolves to a file that exists at the site
  root; `#A379CC` compiled into the bundled CSS; shared `right:` navbar merged;
  all 7 favicons copied to `docs/`.

`greta.gp` (1 vignette), `_pkgdown.yml` deleted first so the from-scratch path
was exercised: config written, `check_pkgdown()` clean.

greta.pkgdown's own site rebuilt as a self-test: `alt="greta.pkgdown"`, working
`og:image`.

`R CMD check`: **Status: OK**. 43 tests pass.

### Divergence from the three hand-built configs

| Hand-built | Generated | Why |
| --- | --- | --- |
| per-package `template: opengraph:` override | none | template fix 1 makes it redundant; **delete it from greta.gp and greta.gam** |
| `home: sidebar: false` | not written | template fix 2 makes it a real choice |
| `home: title:`/`description:` prose | seeded from DESCRIPTION, marked TODO | judgement |
| grouped `reference:` sections | one `All functions` section, marked TODO | judgement |
| navbar article labels ("solving ODEs") | vignette basenames, marked TODO | judgement |

Everything else — `url:`, `development:`, `template:`, navbar structure and
components, `articles:` — is byte-comparable to what the three agents wrote by
hand.

---

## Files changed in greta.pkgdown (all uncommitted)

    M  DESCRIPTION                                   Imports: cli/desc/fs/yaml; Suggests: testthat/withr/pkgdown
    M  NAMESPACE                                     export(use_greta_pkgdown)
    M  README.md                                     helper docs + full consumer contract
    M  inst/pkgdown/BS5/extra.scss                   gated .template-home rule
    M  inst/pkgdown/BS5/templates/navbar.html        templated brand alt text
    R  inst/pkgdown/BS5/_pkgdown.yml -> inst/pkgdown/_pkgdown.yml   + bootstrap: 5, bare opengraph src
    ?? inst/pkgdown/BS5/assets/name_icon_on_purple.png
    ?? inst/pkgdown/favicon/                         7 files, canonical set
    ?? R/use-greta-pkgdown.R
    ?? man/use_greta_pkgdown.Rd
    ?? tests/testthat.R
    ?? tests/testthat/helper-fake-package.R
    ?? tests/testthat/test-use-greta-pkgdown.R

`R/test.R` and `man/test.Rd` were left alone.

## Follow-ups not done

- Delete the now-redundant `opengraph:` overrides and `home: sidebar: false`
  from greta.gp / greta.gam / greta.dynamics (their repos were out of scope).
- `favicon.svg` is 219K; worth optimising once, now that there is one copy.
- No test that `templates/navbar.html` has not drifted from the pkgdown release
  it was forked from.
- Make greta itself a consumer, killing its drifting inline `extra.scss` and
  `navbar.html`.
- pkgdown 2.2.0's `BS5/templates/head.html` uses typographic quotes in the SVG
  favicon `<link>`. Upstream, out of scope, do not re-debug.
