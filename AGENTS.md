# Notes for agents working in the atelier

## Drafts for GitHub (`drafts/`)

Issue bodies, PR descriptions and comments are drafted here, then pasted into GitHub.

### Do not hard-wrap prose

Write each paragraph and each bullet as one line, however long. Do not wrap prose at 80 characters.

GitHub renders a single newline inside an issue body, PR description or comment as a line break, so prose wrapped at 80 characters shows up on GitHub as ragged, broken lines.

This applies to:

- `.md` drafts;
- the `#'` prose lines in a reprex `.R` file, since `reprex::reprex()` copies them into the rendered `_reprex.md` line for line. Write each `#'` paragraph as a single `#'` line;
- bullets in lists, including nested ones.

Code chunks are the exception: keep code formatted as code, since it sits inside a code block where line breaks are kept anyway.

### Link to lines of code as a bare permalink, on its own line

When pointing at lines of code, or at a commit, paste the bare URL on a line of its own:

```
`build_samplers()` groups chains by `future::nbrOfWorkers()`.

https://github.com/greta-dev/greta/blob/75decd9dda0e6c5054496884f8a9bc1bac8bfe0b/R/utils.R#L492
```

not a markdown link such as ``[`build_samplers()`](https://github.com/greta-dev/greta/blob/…/R/utils.R#L492)``.

GitHub renders a bare permalink on its own line as an embedded snippet of those lines, and a bare commit URL as the commit's short SHA, so the reader sees the code without leaving the page. A markdown link hides it behind link text.

- Use the full 40-character SHA, so the link keeps pointing at the same lines after the code moves; a branch name moves with the branch.
- Give a range, `#L88-L91`, when the point spans several lines.
- Put the prose saying what the lines show before the link, since the snippet shows code but not why it matters.
- In a reprex `.R` file, write the link as its own `#'` line, with blank `#'` lines around it. `reprex()` renders it wrapped in angle brackets, as `<https://…>`, so strip those from the rendered `_reprex.md` before posting: `sed -i '' -E 's|^<(https://github\.com/[^>]+)>$|\1|' file_reprex.md`.

## Code comments

### Say what the code does, not what changed

A comment in greta's code or tests describes the code as it is: what it does, and why. It does not describe the change that produced it, the bug it fixed, or what the code used to do.

```r
# TFP keeps one draw in num_steps_between_results + 1 iterations, so
# thin - 1 keeps one in thin
num_steps_between_results = tf$subtract(sampler_thin, 1L),
```

not

```r
# TFP keeps one draw in num_steps_between_results + 1, so passing thin
# itself ran thin + 1 iterations per draw - twice the work at thin = 1
num_steps_between_results = tf$subtract(sampler_thin, 1L),
```

The second is true, but it only makes sense to someone who saw the old code. A reader a year from now has the new line in front of them and no idea what "passing thin itself" refers to. The history belongs in the commit message, the PR description and `NEWS.md`, which are written for exactly that reader.

Tests follow the same rule. "Each case gives a burst shorter than thin unless bursts are cut in whole draws" describes what the test exercises; "each case left a burst shorter than thin" describes the bug it caught. Linking the issue, as `(#609)`, is how a test records where it came from.

Before handing a diff over, list every comment it adds and read each one on its own:

```sh
git diff <base> -- R/ tests/ | grep -E '^\+\s*#'
```

Rewrite any comment that uses the past tense about the code, or words such as *now*, *no longer*, *previously*, *used to* or *changed to*, unless it states a fact about the world rather than about the diff: "Keras 3 removed `Optimizer$minimize()`" is fine; "this used to call `minimize()`" is not.
