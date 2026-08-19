# greta.distributions #25 — the four missing README examples

[#25](https://github.com/greta-dev/greta.distributions/issues/25) is "add
example distributions in README". It is **not done**, contrary to what the
`greta-distributions.qmd` chapter records — that was written when 0.1.0 was
scoped at two distributions.

Current state of `README.Rmd`: six distributions listed at lines 32-37, example
sections for **two**.

| distribution | README example |
| --- | --- |
| `zero_inflated_poisson()` | yes, line 115 |
| `zero_inflated_negative_binomial()` | yes, line 128 |
| `discrete_normal()` | **no** |
| `discrete_lognormal()` | **no** |
| `conditional_bernoulli()` | **no** |
| `ordered_logit()` | **no** |

Below are drafts for the four, cut down from each function's own `@examples` so
they stay consistent with the help pages. All are `eval = FALSE`, matching the
two that are already there, so knitting needs no Python.

Paste after the "Zero inflated negative binomial" section.

---

````
### Discrete normal

A normal distribution observed only to the nearest whole unit, so the density is
a difference of normal CDFs.

```{r discrete-normal, eval = FALSE}
y <- floor(rnorm(50, mean = 2, sd = 3))

mu <- normal(0, 10)
sigma <- lognormal(0, 1)
distribution(y) <- discrete_normal(mu, sigma)

m <- model(mu, sigma)
draws <- mcmc(m, n_samples = 500, warmup = 500)
```

### Discrete lognormal

The same idea for positive, right-skewed measurements — counts recorded to the
nearest unit whose underlying quantity is lognormal.

```{r discrete-lognormal, eval = FALSE}
y <- floor(rlnorm(50, meanlog = 1, sdlog = 0.5))

mu <- normal(0, 10)
sigma <- lognormal(0, 1)
distribution(y) <- discrete_lognormal(mu, sigma)

m <- model(mu, sigma)
draws <- mcmc(m, n_samples = 500, warmup = 500)
```

### Conditional Bernoulli

A multivariate distribution over binary outcomes with imperfect detection: each
site is occupied or not, and each visit detects occupancy with some probability.

```{r conditional-bernoulli, eval = FALSE}
# 30 sites, 3 visits each
n_sites <- 30
n_visits <- 3
occupied <- rbinom(n_sites, 1, 0.7)
y <- t(sapply(
  seq_len(n_sites),
  function(i) rbinom(n_visits, 1, occupied[i] * c(0.4, 0.6, 0.5))
))

psi <- beta(1, 1)                    # occupancy probability
p <- t(beta(1, 1, dim = n_visits))   # per-visit detection probability
distribution(y) <- conditional_bernoulli(p = p, psi = psi, dim = n_sites)

m <- model(psi, p)
draws <- mcmc(m, n_samples = 500, warmup = 500)
```

### Ordered logit

For ordinal outcomes — categories with a meaningful order but no scale. `cuts`
gives the cutpoints, so `k` cutpoints means `k + 1` categories, numbered from 1.

```{r ordered-logit, eval = FALSE}
n <- 100
x <- rnorm(n)
cuts_true <- c(-1, 0.5)
probs <- t(sapply(1.5 * x, function(e) diff(c(0, plogis(cuts_true - e), 1))))
y <- apply(probs, 1, function(p) sample(seq_along(p), 1, prob = p))

beta_x <- normal(0, 5)
cuts <- normal(0, 5, dim = length(cuts_true))
distribution(y) <- ordered_logit(eta = beta_x * x, cuts = cuts)

m <- model(beta_x, cuts)
draws <- mcmc(m, n_samples = 500, warmup = 500)
```
````

---

## Two things to check before pasting

**1. The `ordered_logit` cutpoints need an ordering constraint.** The draft above
puts an unconstrained `normal(0, 5)` prior on `cuts`, which lets the sampler
propose cutpoints out of order. The function's own tests include
`check_cuts_increasing()`, so an unordered draw will error rather than silently
misbehave — but that makes the README example unreliable, which is worse than
omitting it. Options: fix `cuts` at known values in the example, or use an
ordered construction. **I have not run this example**, so this needs settling
first.

**2. None of the four is verified.** They are cut down from the `@examples`
blocks, which are themselves wrapped in `\dontrun{}` and so never execute in
`R CMD check`. Before these go in the README, each should be run once — which
needs `greta.distributions` installed, and right now it is not, because the
tree is uncommitted.

## Related

Do the ZINB `@param pi` documentation fix at the same time
(`distributions-zinb-pi-documentation.R`) — that also touches
`zero_inflated_poisson()`, and both example sections in the README describe
`pi` in passing.
