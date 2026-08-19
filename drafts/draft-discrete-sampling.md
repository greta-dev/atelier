# DRAFT — not filed

**Provenance:** #322 §4, "Sampling discrete variables", from the 2020 coding
sprint plan. Never lodged as its own issue. Code anchors below checked against
`origin/main`.

**Proposed milestone:** 12. Advanced modelling
**Proposed labels:** `samplers`, `enhancement`

---

**Title:** Allow discrete random variables to be sampled, not just observed

greta's discrete distributions can only ever be *data*. You can write
`distribution(y) <- poisson(lambda)` where `y` is observed, but you cannot make
a Poisson variable a free parameter and have greta sample it.

## What happens now

`check_unfixed_discrete_distributions()` (`R/checkers.R:1687`), called from
`model()` at `R/greta_model_class.R:97`, walks the DAG and aborts if any
distribution node is discrete and its target is not a data node:

> Model contains a discrete random variable that doesn't have a fixed value, so
> inference cannot be carried out.

That guard is correct given the samplers available. HMC and its variants need a
continuous, differentiable free state, and there is nothing to differentiate
through a discrete support. Nine distributions carry `discrete = TRUE` in
`R/probability_distributions.R`: `bernoulli`, `binomial`, `beta_binomial`,
`poisson`, `negative_binomial`, `hypergeometric`, `dirichlet_multinomial`,
`multinomial` and `categorical`.

## What it would take

Three pieces, in order:

1. **A latent discrete node.** Let a discrete distribution define a variable
   node rather than only accept a data target, which means relaxing the
   variable and free-state machinery where it assumes continuous support.
2. **A discrete sampler.** A categorical or Metropolis kernel over the discrete
   support, alongside `hmc()` and `adaptive_hmc()`. TFP supplies discrete
   transition kernels to build on.
3. **A Gibbs driver.** Partition the free state into discrete and continuous
   blocks and alternate: HMC on the continuous block given the current discrete
   draw, the discrete kernel on the discrete block given the current continuous
   draw.

## Relationship to marginalisation

This is the complement of #157. Marginalising a discrete variable integrates it
out so HMC can run on a smaller, smooth space; sampling it keeps it in the model
and gives it a kernel of its own. *Marginalise where you can, sample where you
must.* The two share the same free-state work, so whichever is done first should
expect to carry some of the other's cost.

## Sequencing

This is a large internals change and it wants the flat node registry
(milestone 11) underneath it — partitioning the free state and swapping kernels
per block means rewriting the graph, which is what the registry work makes
tractable. Doing it against the current doubly-linked R6 node objects is the
blocker today.

## Acceptance

Validate against discrete-latent posteriors with known answers, using the Geweke
harness (`tests/testthat/test_posteriors_geweke.R`, run with
`GRETA_GEWEKE=true`). A discrete sampler that passes Geweke on a model whose
posterior is known analytically is the bar; anything less and we will not know
whether the kernel is correct.
