# atelier

The workshop for [greta](https://github.com/greta-dev/greta) and its extension
packages: what we plan to do, why, and the evidence behind it.

This is a working repository. It is public because the reasoning is more useful
where contributors can read it.

## What is here

**Milestones** — a Quarto book. `milestones.qmd` is the overview: thirteen
milestones covering every open issue in greta, in release order. One chapter per
milestone follows, each giving the reasoning for the milestone and a block per
issue: the finding, a proposed fix, and a priority.

Milestones are work buckets, not releases. A release is cut when a coherent
batch is ready, so one milestone may span several and milestone titles carry no
version. The thirteen milestones exist on
[greta's issue tracker](https://github.com/greta-dev/greta/milestones) and this
book is their reasoning.

**`fixes/`** — 25 proposed fixes, one per issue, in more depth than the book
chapters carry. These were originally written from source reading; a later pass
verified them by running the code, and found twelve of them wrong in specific
ways. Those twelve have been corrected in place, and where the original was
actively misleading the document says so rather than quietly changing it.

A fix document describes the engineering and names its dependencies as **issue numbers**. It does not say which milestone anything belongs to. Milestone
numbers have been renumbered three times; issue numbers never move, and the
book already owns scheduling. Keeping it out of `fixes/` is what stops the two
drifting apart.

**`drafts/`** — issue bodies written but not yet filed, and findings not yet
posted to the issues they concern. Several are for open issues in
greta.gam and greta.distributions rather than greta itself.

**`evidence/`** — what the claims rest on. CRAN check assessments for the
extension packages, pkgdown migration notes, greta.distributions surveys, and
investigations of TensorFlow 2 behaviour carried over from an older notes repo.

## What is not here

**How greta works.** That is
[greta-internal-docs](https://github.com/greta-dev/greta-internal-docs) —
bijectors, forward sampling, the design of the thing. This repository is about
what to change; that one is about what it is.

**Benchmarks.** Those are
[greta.benchmarks](https://github.com/greta-dev/greta.benchmarks), kept separate
so a speed claim can point at the code that produced it.

**Anything authoritative.** Nothing here is a promise about what will ship or
when. Where this book and the issue tracker disagree, the tracker wins.

## Reading it

```bash
quarto preview
```

Or read the rendered book at the link in the repository description.

## AI usage

Much of this book was drafted with AI assistance and then verified against
greta's source. That verification found errors in the drafts, and where it did,
the book says so rather than quietly correcting them — the "known defect"
warnings in `fixes/` are the visible part of that. Treat a claim with a file and
line number as checked, and a claim without one as a hypothesis.
