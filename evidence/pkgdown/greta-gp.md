# Applying the greta.pkgdown theme to greta.gp — friction log

Date: 2026-07-21
Target: `/Users/nick_1/github/greta-dev/greta.gp` (v0.2.3, CRAN resubmission in flight)
Template: `greta.pkgdown` 0.1.0 (`inst/pkgdown/BS5`)
Reference implementation: `/Users/nick_1/github/greta-dev/greta/pkgdown/`
Environment: pkgdown 2.2.0, R 4.6, greta.pkgdown already installed to the site library
(installed copy byte-identical to source `inst/pkgdown/`)

This is the record of everything it took to theme one extension package, annotated
with which parts a `use_greta_pkgdown()` helper could do mechanically and which
needed a human decision.

---

## Summary of what changed in greta.gp

| Path | Change |
| --- | --- |
| `_pkgdown.yml` | rewritten: template package, opengraph override, home, navbar, reference index, articles index |
| `pkgdown/favicon/` | **new** — 7 files copied verbatim from `greta/pkgdown/favicon/` |
| `pkgdown/assets/name_icon_on_purple.png` | **new** — opengraph card image |
| `DESCRIPTION` | **one line added**: `Config/Needs/website: greta-dev/greta.pkgdown` |
| `.Rbuildignore` | no change needed — already had `^pkgdown$`, `^_pkgdown\.yml$`, `^docs$` |
| `.gitignore` | no change needed — already had `docs` |

Nothing committed. `R/`, `tests/`, `NEWS.md`, `cran-comments.md`, `man/` untouched.

---

## Step-by-step

### 1. Read the template and the reference — MANUAL, unavoidable

There is no README in `greta.pkgdown` explaining what a consumer must supply. I had to
read `inst/pkgdown/BS5/_pkgdown.yml`, `extra.scss`, `templates/navbar.html`, and the
template's own root `_pkgdown.yml` (which doubles as the only worked example of a
consumer config) to work out the contract. The `extra.scss` header comment is the most
useful documentation in the package and it is buried in a stylesheet.

**Helper should:** not need this at all, but `greta.pkgdown` should also grow a
`README`/vignette stating the consumer contract explicitly (see "Undocumented contract"
below).

### 2. Set the template — MECHANICAL

Before:
```yaml
url: https://greta-dev.github.io/greta.gp/
template:
  bootstrap: 5
```
After: added `package: greta.pkgdown` alongside `bootstrap: 5`.

`url:` was already correct, and `DESCRIPTION` already listed both the GitHub repo and
the pkgdown site under `URL:`, so nothing to do there. Do not assume this: the helper
must check and add `url:` (deriving it as
`https://greta-dev.github.io/<pkg>/` from the GitHub URL in `DESCRIPTION`) and add the
site URL to `DESCRIPTION`'s `URL:` if missing.

`bootstrap: 5` still has to be stated by the consumer. The template ships in `BS5/` but
does not itself set `bootstrap: 5`, so omitting it in the consumer silently falls back
to BS3 and the whole theme is ignored. **This is a footgun.** Either
`greta.pkgdown`'s `inst/pkgdown/BS5/_pkgdown.yml` should set `template: bootstrap: 5`
itself, or the helper must always write it.

### 3. `development: mode: auto` — JUDGEMENT

Copied from greta. Not in the shared template. It means a dev version (`0.2.3.9000`)
publishes to `/dev/` and the release version to the site root. This is greta-family
convention, so arguably it belongs in the shared template rather than being copied by
hand into every consumer.

**Helper should:** write it (or better, move it into the shared template).

### 4. Favicons — MECHANICAL, but the copy source is non-obvious

pkgdown wants favicons at `<pkg>/pkgdown/favicon/`. They are not in `greta.pkgdown` at
all — I had to copy them out of the **greta package's** `pkgdown/favicon/`:

```
apple-touch-icon.png  favicon-96x96.png  favicon.ico  favicon.svg
site.webmanifest  web-app-manifest-192x192.png  web-app-manifest-512x512.png
```

This is the single worst piece of friction: the shared theme package does not ship the
shared favicon, so every consumer must know to raid `greta/pkgdown/favicon/`. Also note
`site.webmanifest` has empty `"name"`/`"short_name"` fields and absolute (`/`-rooted)
icon paths inherited from RealFaviconGenerator — copying it verbatim propagates that.

**Fixes needed:**
- `greta.pkgdown` should ship the favicon set (e.g. `inst/pkgdown/favicon/`) as the
  canonical copy.
- `use_greta_pkgdown()` should copy it into `pkgdown/favicon/` and optionally fill
  `name`/`short_name` in `site.webmanifest` from `DESCRIPTION`.

### 5. Navbar wordmark — WORKED AUTOMATICALLY (good)

`inst/pkgdown/BS5/assets/name_icon_on_white.png` plus the `templates/navbar.html`
override are picked up by pkgdown with no consumer action. `docs/name_icon_on_white.png`
appeared and the rendered brand is `<img src="name_icon_on_white.png" class="navbar-logo" alt="greta">`.

Two latent issues worth recording:
- `alt="greta"` is hardcoded in the template, so every greta-family site claims to be
  "greta" to a screen reader. Should be `alt="{{#package}}{{package}}{{/package}}"` or similar.
- The navbar override is a fork of pkgdown 2.2.0's `navbar.html`. It will silently drift
  when pkgdown changes. The template comment already flags this; there is no test for it.

### 6. Opengraph image — BROKEN DEFAULT, needed a workaround (JUDGEMENT)

The shared `_pkgdown.yml` sets:
```yaml
opengraph:
  image:
    src: man/figures/name_icon_on_purple.png
```
greta.gp does **not** ship that file (its `man/figures/` has only `README-plotting-1.png`),
so the first build emitted a dead social card URL:
`https://greta-dev.github.io/greta.gp/reference/figures/name_icon_on_purple.png`.
pkgdown does not warn about this — it just rewrites `man/figures/` → `reference/figures/`
and emits the tag.

Two ways to fix it, and I had to choose:
1. Copy `name_icon_on_purple.png` into `man/figures/` so the shared default just works
   (this is what greta does). Cost: 142 KB added to the CRAN tarball, and it means
   touching `man/` in a package mid-CRAN-submission.
2. Put it in `pkgdown/assets/` (which is `.Rbuildignore`d, so not in the tarball) and
   override `opengraph: image: src:` to the bare filename.

I chose **(2)**, because it keeps the image out of the CRAN tarball and stays inside the
files I was allowed to touch. Verified: `og:image` now resolves to
`https://greta-dev.github.io/greta.gp/name_icon_on_purple.png`. I also set
`alt: "greta.gp"` rather than the template's `alt: "greta"`.

**Design question for the helper:** the shared default should not point at a path the
consumer is required to create. Better options, in order of preference:
- ship the card image in the template's `assets/` (as is already done for the wordmark)
  and default `src:` to the bare filename — then it works for every consumer with zero
  config, exactly like the navbar logo already does;
- failing that, `use_greta_pkgdown()` copies the PNG into `pkgdown/assets/` and writes
  the override + a per-package `alt:`.

Either way the `alt` text should default to the consuming package's name.

### 7. `home: sidebar: false` — JUDGEMENT, and a theme bug

I initially left the home sidebar at its default (on), reasoning that greta.gp's home
page is a plain README with no hero markup, so the "Links / License / Developers"
sidebar is useful there.

That was wrong, because of a bug in the shared `extra.scss`. The rule

```scss
.template-home {
  aside { display: none; }
  main.col-md-9 { flex: 0 0 100%; max-width: 100%; }
}
```

sits under a comment block headed **"HOME-PAGE SCAFFOLDING (opt-in; requires matching
ids in index.md)"**, but it is not opt-in at all — it has no dependency on `#head`,
`#main-icon` etc. and so hides the home sidebar on **every** consumer site
unconditionally. A consumer that leaves `sidebar: true` gets a sidebar that pkgdown
renders and CSS then throws away.

So I set `home: sidebar: false` to make the config match what is actually displayed.
Confirmed in the output: pkgdown still emits `<aside class="col-md-3"></aside>` (empty),
which is exactly the case the CSS rule exists to mop up.

**Two things follow:**
- `use_greta_pkgdown()` must write `home: sidebar: false`, because the theme currently
  gives no choice.
- OR — better — `greta.pkgdown` should scope that rule so it only fires on pages that
  actually use the hero scaffolding, and then the consumer genuinely gets a choice. If
  the intent really is "all greta sites are full-width", the comment claiming it is
  opt-in should be corrected.

I also added `home: title:` and `home: description:` by hand, mirroring greta. These are
per-package prose and cannot be generated well.

**Helper should:** write `sidebar: false`, and stub `title:`/`description:` from
`DESCRIPTION`'s `Title`/`Description` for the author to edit.

### 8. Navbar `left:` and the structure merge — JUDGEMENT, but the merge worked

I wrote only:
```yaml
navbar:
  structure:
    left: [get-started, reference, news]
  components:
    get-started: {text: get started, href: articles/getting-started.html}
    reference:   {text: docs,        href: reference/index.html}
```
and confirmed the template's `right: [search, forum, github]` survives the merge —
the rendered navbar has the search box, the `fa-comments` forum link to
`https://forum.greta-stats.org`, and the auto-derived GitHub link to
`https://github.com/greta-dev/greta.gp/`. Good: partial `structure:` override works, so
consumers only state `left:`.

The `left:` entries themselves needed judgement — I mirrored greta's naming
(`get started`, `docs` rather than pkgdown's default `Articles`/`Reference`) and pointed
`get-started` at greta.gp's single vignette, `articles/getting-started.html`. Note that
the href depends on the vignette filename, which the helper can discover by listing
`vignettes/*.Rmd` but cannot name for you.

**Helper should:** write `left: [reference, news]` as a safe default, plus one entry per
vignette found, using greta's lowercase label style; leave `right:` entirely to the
template.

### 9. Reference index — JUDGEMENT, unavoidably manual

greta.gp only has three topics (`kernels`, `gp`/`project`, `greta.gp-package`), so
grouping them took two minutes. For a larger package this is the most labour-intensive
part and cannot be automated beyond a stub.

One gotcha: the package doc topic is `greta.gp-package`, not `greta.gp`. Using the
latter is an easy mistake; `pkgdown::check_pkgdown()` catches it.

**Helper should:** if no `reference:` section exists, write a single stub section
containing every exported topic, so the site builds, with a comment telling the author
to split it up. Do not attempt clever grouping.

### 10. `articles:` index — MECHANICAL

One vignette, one section. Generatable from `vignettes/`.

### 11. `.Rbuildignore` / `.gitignore` — NO-OP HERE, but must be checked

greta.gp already ignored `^_pkgdown\.yml$`, `^pkgdown$`, `^docs$` (build) and `docs`
(git). A helper must add these; without `^pkgdown$` in `.Rbuildignore` the favicons and
the 142 KB opengraph PNG go into the CRAN tarball, which is exactly the outcome the
`pkgdown/assets/` choice in step 6 was made to avoid.

### 12. `Config/Needs/website` — REQUIRED, and easy to forget

greta.gp's `.github/workflows/pkgdown.yaml` uses
`r-lib/actions/setup-r-dependencies@v2` with `needs: website`. That resolves
`Config/Needs/website` in `DESCRIPTION`. `greta.pkgdown` is **not on CRAN**, so without

```
Config/Needs/website: greta-dev/greta.pkgdown
```

the CI site build would fail with a missing-template error even though it builds
locally. I added the line. It is inert for `R CMD check` and CRAN, but it is the one
line I touched in `DESCRIPTION` beyond what was strictly scoped — flagging it here and
in the handover so the maintainer can review or drop it.

**Helper must:** add this. It is invisible locally and only bites in CI.

Related: greta.gp's `pkgdown.yaml` is an old revision (`actions/checkout@v2`,
`JamesIves/github-pages-deploy-action@4.1.4` rather than the current
`upload-pages-artifact` flow). Not touched — out of scope — but worth a follow-up.

---

## Verification performed

Full `build_site()` was avoided: the vignette loads greta and therefore TensorFlow, which
is slow and not needed to check theming. Instead:

```r
pkgdown::init_site()             # deps, favicons, assets, compiled SCSS
pkgdown::build_reference_index()
pkgdown::build_home()
pkgdown::build_news()
pkgdown::check_pkgdown()         # -> "No problems found."
```

Checks made on the output:
- `docs/deps/bootstrap-5.3.8/bootstrap.min.css` contains the purple primary
  (`#A379CC`), the `.navbar-logo` rule, and the `#main-icon` home scaffolding — so the
  template's `bslib` variables *and* `extra.scss` both compiled in.
- Roboto and Roboto Mono webfonts present under `docs/deps/`.
- navbar renders the wordmark image, `get started` / `docs` / `Changelog` on the left and
  search / forum / GitHub on the right.
- all 7 favicon files copied to `docs/`; `<link rel="manifest">` and icon tags emitted.
- `og:image` resolves to a file that exists.
- reference index renders three titled sections with descriptions.

Untested, because they need a full build: `articles/getting-started.html` (and therefore
the `get started` navbar link resolving), and `build_reference()` running examples.

Unrelated upstream nit spotted: pkgdown 2.2.0 emits
`<link rel="icon" type="”image/svg+xml”" ...>` with curly quotes. Comes from pkgdown's
own head template, not from anything here.

---

## Specification: what `use_greta_pkgdown()` should do

Ordered roughly by how much it saves.

**Must do (pure mechanism, no judgement):**
1. Create `pkgdown/favicon/` and copy the canonical greta favicon set into it —
   *conditional on greta.pkgdown actually shipping that set, which it currently does not*.
2. Add `Config/Needs/website: greta-dev/greta.pkgdown` to `DESCRIPTION`.
3. Add `^_pkgdown\.yml$`, `^pkgdown$`, `^docs$` to `.Rbuildignore` and `docs` to
   `.gitignore` if absent.
4. Write/patch `_pkgdown.yml` with:
   - `url:` derived from the GitHub URL in `DESCRIPTION` (and add the site URL to
     `DESCRIPTION`'s `URL:` if missing);
   - `template: {package: greta.pkgdown, bootstrap: 5}` — **`bootstrap: 5` is mandatory**;
   - `development: mode: auto`;
   - `home: sidebar: false`, with `title:`/`description:` stubbed from `DESCRIPTION`;
   - `navbar: structure: left:` with `reference`, `news` and one entry per vignette,
     using greta's lowercase labels; never touch `right:`.
5. Generate an `articles:` index from `vignettes/*.Rmd`.
6. Generate a single stub `reference:` section listing every topic, commented "split
   these into sections".
7. Run `pkgdown::check_pkgdown()` at the end and report.
8. Be idempotent and non-destructive: on an existing `_pkgdown.yml`, only add missing
   keys and report what it changed rather than overwriting the author's navbar and
   reference index.

**Should fix in `greta.pkgdown` rather than paper over in the helper:**
- Ship the favicon set in `inst/pkgdown/` — the theme package should own the shared brand.
- Ship the opengraph card image in `inst/pkgdown/BS5/assets/` and default `src:` to the
  bare filename, exactly as the navbar wordmark already works, instead of pointing at
  `man/figures/…` in the consumer.
- Default the opengraph `alt:` and the navbar `<img alt>` to the consuming package's name,
  not the literal string `greta`.
- Set `bootstrap: 5` inside the template's own `_pkgdown.yml`, or document loudly that
  omitting it silently disables the entire theme.
- Either scope `.template-home aside {display: none}` to pages that use the hero
  scaffolding, or correct the comment that calls it opt-in and document that
  `home: sidebar: false` is required.
- Consider moving `development: mode: auto` into the shared template.
- Add a README/vignette stating the consumer contract; right now the best documentation
  is a comment block inside `extra.scss`.
- Add a check (test or CI job) that `templates/navbar.html` has not drifted from the
  pkgdown release it was forked from.

**Should not try to automate:** reference-index grouping, home `title:`/`description:`
prose, and navbar labels for vignettes. Stub them and let the author edit.
