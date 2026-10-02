# Issue #366 — `get_unique_name()` may collide

Status: fixed by greta#846, merged 2026-09-27, from branch
`unique-node-names-i366`. Decided 2026-09-26.

## The problem is worse than the issue says

Node names were minted from R's global RNG:

```r
# R/node_class.R:262-264, before
create_unique_name = function() {
  self$unique_name <- glue::glue("node_{rhex()}")
}

# R/utils.R:252-255, before
rhex <- function() {
  paste(as.raw(sample.int(256L, 4, TRUE) - 1L), collapse = "")
}
```

The issue reports random collisions: 4 bytes is a 32-bit space, so about 126
collisions per million names. Those are rare at real model sizes. The common
failure is deterministic. Because the names come from R's RNG, they repeat
after `set.seed()`:

```r
set.seed(1); a <- normal(0, 1)
set.seed(1); b <- normal(5, 2)   # same node name as a
m <- model(a, b)                  # no error, but 1 variable, not 2
opt(m)$par                        # b = 0, though its prior's mode is 5
```

Depending on the shapes, a collision gives silently merged variables (as above,
and `normal` against `lognormal`) or a misleading "model contains 2 disjoint
graphs" error. The unexplained `distrib_constructor` error in the 2022 comment
fits this mechanism, but was not reproduced.

The same RNG use has a second cost. Every node draws from the user's stream
(`normal(0, 1)` makes 8 draws, `variable()` 5, `x * 2` 3), so where `set.seed()`
sits relative to model code changes the result:

```r
set.seed(1); x <- normal(0, 1); m <- model(x); mcmc(m)   # these two differ
set.seed(1); mcmc(m)
```

The CRAN Cookbook, under "Writing to the `.GlobalEnv`": `.Random.seed` "should
not be changed at all".

## Approach

A counter, prefixed with a token made once per session:

```r
# R/greta_stash.R, in init_greta_stash()
stash$node_count <- 0L
stash$session_token <- substr(rlang::hash(list(Sys.getpid(), Sys.time())), 1, 8)

# R/node_class.R
create_unique_name = function() {
  greta_stash$node_count <- greta_stash$node_count + 1L
  self$unique_name <- glue::glue(
    "node_{greta_stash$session_token}_{greta_stash$node_count}"
  )
}
```

`rhex()` is deleted, along with its entry in `.internals`.

**Why a counter.** It is what the graph libraries do for anonymous nodes.
TensorFlow's `Graph.unique_name()` keeps a per-graph count (`Normal`,
`Normal_1`); PyTensor, under PyMC, uses `itertools.count()` for `auto_0`,
`auto_1`. Neither uses an RNG. PyMC and Turing name random variables from the
user's code instead, which greta's anonymous arrays cannot. A counter cannot
collide with itself, touches no RNG, and is cheaper than `sample.int()`, which
matters because `rhex()` was introduced to speed up building recursive models.

**Why the token.** The counter restarts every session. A greta array saved with
`saveRDS()` and read back works in a new session, and measured without the
token, it collides with the new session's arrays: both nodes named
`node_5ad96c78_8`, merged, `c2 = 0` where it should be 5. `rlang::hash()` is
already in Imports and does not touch `.Random.seed` (checked, as are `uuid`
and `ids`, which would be new dependencies).

**Superseded: keep `rhex()` as a prefix.** The earlier plan here kept `rhex()`
for "readability/back-compat" and to avoid churn in snapshot tests that match
`node_<hex>`. It would fix uniqueness but still consume R's RNG. No test pins
the name format, and none of greta.gp, greta.dynamics, greta.distributions,
greta.multivariate or greta.gam use `rhex()` or `unique_name`, so there was
nothing to keep it for.

## Checked

- names never reach the results: three fresh sessions, three different sets of
  names, bit-identical draws
- sampling unchanged: with the model built before seeding, draws are
  bit-identical to `main` for rwmh, hmc and slice
- `future` workers never name nodes: `mcmc()` and `calculate()` create none, so
  the token is for `readRDS()`, not for workers
- `document()` changes nothing; no NAMESPACE or man churn

## Tests

`tests/testthat/test-node_class.R`, both failing on the old code:

- building greta arrays leaves `.Random.seed` unchanged
- arrays built after the same seed stay distinct: `calculate(a, b, nsim = 10)`
  gives different draws for `a` and `b`. On `main` they are identical - one node,
  one set of draws. The priors are identical on purpose: a scheme that named
  nodes by hashing their contents, floated in the issue's 2024 comment, would
  merge them too
- a greta array read back from another session stays distinct: one fresh
  session saves `normal(0, 1)`, a second reads it back and builds another, and
  their draws must differ. Both halves need fresh sessions, because the test
  session has counted too far to clash, so the test would pass without the
  token. It fails with the token set to a constant. Runs through
  `in_fresh_greta()` in `helpers.R`, which loads the source tree under
  `devtools::test()` and the installed build under `R CMD check`;
  `skip_on_cran()`, and `pkgload` added to Suggests for the dev path

## Blocked by

`test_posteriors_bivariate_normal.R` fails on this branch, the same `2.52` on
two full-suite runs. Not a regression: the fix moves the RNG stream that test
inherits, and the test fails for working samplers about one run in ten. Filed
as greta#845. Fix that test on its own branch first.

## Dependencies

Independent of other open work. A step towards the flat node registry
(`evidence/node-registry-comparison.md`, #247), which already specifies counter
ids.

## User-facing change

Draws from a script that calls `set.seed()` before building its model differ
from previous versions. #838 also changes seeded draws, so the two should land
in the same release. NEWS bullet written.
