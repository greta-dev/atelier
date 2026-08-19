# Applying `greta.pkgdown` to `greta.gam` — friction log

Date: 2026-07-21. pkgdown 2.2.0, greta.pkgdown 0.1.0 (installed), greta.gam 0.2.1.

This is a record of applying the shared theme to the first sibling package, kept
as a specification for a future `use_greta_pkgdown()` helper. greta.pkgdown's
`R/` currently contains only `test.R`; no helper exists yet.

Reference implementation read first: `/Users/nick_1/github/greta-dev/greta/pkgdown/`
(`_pkgdown.yml`, `extra.scss`, `templates/navbar.html`, `assets/`, `favicon/`).

Note on the reference: greta itself does **not** consume greta.pkgdown. It
inlines its own copies of `extra.scss` and `templates/navbar.html`. Those copies
have drifted — greta.pkgdown's `extra.scss` is a reorganised superset (same
rules, split into "shared chrome" and "opt-in home-page scaffolding" sections),
and the navbar differs only in comments. Worth eventually making greta a
consumer too, so there is one copy.

---

## What was done, in order

### 1. `_pkgdown.yml` — mechanical parts

Before: `url:` plus `template: {bootstrap: 5}`. Two mechanical edits:

- `template: package: greta.pkgdown` (keep `bootstrap: 5` alongside it).
- `development: mode: auto`, copied from greta.

`url:` was already present and correct, as was `DESCRIPTION`'s `URL:` — neither
needed touching. A helper must not assume that; it should set `url:` from the
`URL:` field, and warn if neither exists (pkgdown needs it for og: tags and the
search index).

### 2. `_pkgdown.yml` — parts needing judgement

- **`home: sidebar: false`.** This is *not* optional, and that is a trap. The
  shared `extra.scss` contains an unconditional rule

  ```scss
  .template-home { aside { display: none; } main.col-md-9 { max-width: 100%; } }
  ```

  It is filed under the "opt-in home-page scaffolding" heading, but unlike the
  `#head`/`#bullets`/`#panel1` rules — which are inert without matching ids in
  `index.md` — this one matches every pkgdown home page. A consumer that omits
  `home: sidebar: false` gets its sidebar (dev status, license, citation,
  authors) **silently hidden** rather than turned off. So either the helper
  always writes `sidebar: false`, or the SCSS rule should be scoped to an opt-in
  class. I'd prefer the latter; the current coupling is invisible.
- **`home: title:` / `description:`.** Hand-written from the DESCRIPTION Title
  and Description. Judgement, but a helper could seed them from DESCRIPTION and
  let the maintainer edit.
- **Navbar `left:`.** Package-specific by definition. For greta.gam:
  `[get-started, reference, news]`, with `get-started` pointing at
  `articles/getting-started.html` and `reference` relabelled `docs` (matching
  greta's convention of lowercase nav labels and calling reference "docs").
  Inferred from greta; not documented anywhere. `right:` comes free from the
  template (`search`, `forum`, `github`).
- **`reference:` index.** greta.gam has three topics, so this was quick
  (`smooths`, `evaluate_smooths` under "Smooth terms"; `greta.gam` under
  "Package"). Genuinely package-specific; a helper can only scaffold a
  single-section stub listing every topic, which is still better than nothing
  because it gives the maintainer something to reorder.
- **`articles:`** — see the vignettes section below.

### 3. Favicons — manual copy, no way around it

pkgdown reads favicons **only** from the consuming package's own
`pkgdown/favicon/`:

```r
has_favicons  <- function(pkg) file_exists(path(pkg$src_path, "pkgdown", "favicon"))
copy_favicons <- function(pkg) dir_copy_to(path(pkg$src_path, "pkgdown", "favicon"), ...)
```

A template package cannot supply them, and `pkgdown/assets/` is not consulted
for this. So the whole seven-file set was copied by hand from greta:

```
apple-touch-icon.png  favicon-96x96.png  favicon.ico  favicon.svg
site.webmanifest  web-app-manifest-192x192.png  web-app-manifest-512x512.png
```

**This is the single most mechanical, most annoying step, and the one a helper
should absolutely automate.** Note the icons are the plain greta mark, not
package-specific, so copying verbatim is correct — but that means the bytes now
exist in N repos. Options for greta.pkgdown: ship the set under
`inst/pkgdown/favicon/` and have `use_greta_pkgdown()` copy it out (works today,
still duplicates bytes but removes the manual step), or ask pkgdown upstream to
let a template package contribute favicons.

Two incidental observations: `favicon.svg` is 219K, which is large for a
favicon and could be optimised once in greta.pkgdown; and pkgdown 2.2.0's own
`BS5/templates/head.html` emits `type="”image/svg+xml”"` with curly quotes — an
upstream cosmetic bug, harmless, not ours.

### 4. The shared opengraph image is broken for every consumer but greta

greta.pkgdown's `inst/pkgdown/BS5/_pkgdown.yml` sets

```yaml
opengraph: {image: {src: man/figures/name_icon_on_purple.png, alt: "greta"}}
```

Only greta ships that file. In greta.gam the site built with **no warning at
all** and a dead `og:image` pointing at
`https://greta-dev.github.io/greta.gam/reference/figures/name_icon_on_purple.png`
(pkgdown rewrites `man/figures/` to `reference/figures/`). Nothing in the build
log flags it; you only find it by grepping the generated `index.html`.

Fixed here by copying `name_icon_on_purple.png` from
`greta.pkgdown/man/figures/logos/` into `greta.gam/pkgdown/assets/` — assets are
copied to the site root — and overriding the src in greta.gam's `_pkgdown.yml`:

```yaml
template:
  package: greta.pkgdown
  opengraph:
    image: {src: name_icon_on_purple.png, alt: "greta.gam"}
```

Better fix, for greta.pkgdown rather than each consumer: put the image in the
template's own `inst/pkgdown/BS5/assets/` next to `name_icon_on_white.png` and
change the shared default `src:` to the bare filename. Then it works everywhere
with no consumer override, and this whole item disappears. **Recommend doing
this before theming the other two packages.**

### 5. Navbar wordmark alt text is hard-coded

`inst/pkgdown/BS5/templates/navbar.html` renders
`alt="greta"` on the brand image for every consumer, so greta.gam's navbar logo
announces itself as "greta". Minor accessibility wart. Not fixable from the
consumer side without forking the whole navbar template into
`pkgdown/templates/navbar.html`, which defeats sharing. Fix belongs in
greta.pkgdown — use `{{#package}}{{name}}{{/package}}` for the alt text.

### 6. Ignore files — nothing to do here, but check

`.Rbuildignore` already had `^_pkgdown\.yml$`, `^pkgdown$` and `^docs$`;
`.gitignore` already had `docs`. No edits needed. A helper must still check and
add all four, since a package without them ships the favicons in the tarball
and commits the built site.

### 7. `Config/Needs/website` — required, easy to miss

greta.gam's `.github/workflows/pkgdown.yaml` uses
`setup-r-dependencies` with `needs: website`. greta.pkgdown is **not on CRAN**,
so without a declaration the CI build fails to find the template package — and
it fails at *site build* time with a confusing "template package not found",
not at dependency resolution. Added:

```
Config/Needs/website: greta-dev/greta.pkgdown
```

pak resolves the `owner/repo` form. This is mandatory for every consumer and is
pure boilerplate — a helper must write it. Also worth adding to greta.pkgdown's
README, which currently documents only the `template: package:` line.

### 8. Building — and the undeclared prerequisite

`build_home()`, `build_reference_index()`, `build_reference()`, `build_news()`
and `build_articles()` all pass. `check_pkgdown()` reports no problems.

Gotcha: `build_articles()` failed first time with
`there is no package called 'greta.gam'` — the vignette calls
`library(greta.gam)` and pkgdown renders vignettes in a fresh process against
the *installed* package. Had to `R CMD INSTALL` greta.gam first. Anyone
theming a package with vignettes will hit this; it is not a theming problem but
it looks like one.

Second gotcha: `build_home()` on its own did not re-copy `pkgdown/assets/` after
I added the opengraph image; `init_site()` was needed. When iterating on assets,
call `init_site()` explicitly rather than trusting an incremental build.

---

## Specific to packages **with vignettes**

greta.gam has one (`vignettes/getting-started.Rmd`); two of the three sibling
packages do not. Things that only apply here:

- An `articles:` block in `_pkgdown.yml`. Without one, pkgdown still builds
  `articles/index.html` but ungrouped. A helper should emit an `articles:`
  section only when `vignettes/` is non-empty, seeded with every vignette under
  a single "Get started"/"Articles" title.
- **Article filenames are the vignette basenames, not their titles.** The
  `contents:` entry is `getting-started`; the nav href is
  `articles/getting-started.html`. Easy to get wrong by hand if you're reading
  the YAML `title:` ("Getting Started").
- The navbar needs a link into the articles, otherwise they are built but
  unreachable. I used a `get-started` component pointing at the single vignette,
  following greta. With more than one vignette, the right answer is probably
  pkgdown's built-in `articles` component instead — a helper should branch on
  the vignette count.
- Building requires the package to be installed (above). For a
  vignette-less package `build_articles()` is a no-op and this never bites.
- Pre-existing, **not touched** (CRAN-submission content is out of scope, but
  flagging it for the maintainer): the vignette's
  `\VignetteIndexEntry{getting-started}` does not match its YAML
  `title: "Getting Started"`, which emits a warning on every article build.

---

## What `use_greta_pkgdown()` should do

Fully automatic, no judgement required:

1. Create `_pkgdown.yml` if absent; set `template: {package: greta.pkgdown,
   bootstrap: 5}`, preserving any existing keys rather than overwriting the file.
2. Set `url:` from `DESCRIPTION`'s `URL:` (prefer the `github.io` entry); warn
   if it can't be determined.
3. Set `development: {mode: auto}`.
4. Set `home: {sidebar: false}` — required, not cosmetic (see §2).
5. Copy the favicon set into `pkgdown/favicon/` from files shipped inside
   greta.pkgdown.
6. Add `Config/Needs/website: greta-dev/greta.pkgdown` to DESCRIPTION.
7. Ensure `.Rbuildignore` has `^_pkgdown\.yml$`, `^pkgdown$`, `^docs$` and
   `.gitignore` has `docs`.
8. If `vignettes/` is non-empty, scaffold an `articles:` block from the vignette
   basenames, and add a navbar entry linking to them.

Scaffold, then tell the user to edit:

9. `home: title:`/`description:` seeded from DESCRIPTION.
10. A `reference:` index listing all topics in one section, with a comment
    saying to regroup them.
11. `navbar: structure: left:` with `[reference, news]` plus articles if any.

Fix in greta.pkgdown itself, so the helper never has to care:

12. Move `name_icon_on_purple.png` into the template's `assets/` and make the
    shared opengraph `src:` a bare filename (§4).
13. Templatise the navbar brand `alt` text (§5).
14. Either scope the `.template-home aside {display: none}` rule to an opt-in
    class, or document that `home: sidebar: false` is mandatory (§2).
15. Consider making greta itself a consumer, to kill the drifting duplicate
    `extra.scss` / `navbar.html`.

A `check`-style counterpart would also be useful: verify `og:image` resolves and
that favicons exist, since both fail silently today.

---

## Files changed in greta.gam (all uncommitted, nothing committed or pushed)

- `M _pkgdown.yml` — full theme config (was 4 lines).
- `M DESCRIPTION` — one added line, `Config/Needs/website`.
- `?? pkgdown/favicon/` — 7 files copied from greta.
- `?? pkgdown/assets/name_icon_on_purple.png` — copied from greta.pkgdown.

Untouched, as required: `R/`, `tests/`, `NEWS.md`, `cran-comments.md`,
`README.Rmd`/`README.md`, `vignettes/`, `inst/WORDLIST`, `man/figures/`. The
pre-existing CRAN-resubmission diff in the tree is undisturbed.

Side effect outside the repo: greta.gam 0.2.1 was installed into the user
library to let `build_articles()` run. `docs/` was built and is gitignored.
