# Node representation: R6 today vs the flat registry

A working note for the `node-registry` section of `plan.qmd`. Everything
in the "R6 today" column is quoted from greta's real source at the commit
on branch `submit-cran-060-i805`, with `file:line` references so the
comparison can be checked against the code rather than a sketch. The
"flat registry" column is the staged-migration idea from
[#247](https://github.com/greta-dev/greta/issues/247), written as
runnable R.

## 1. What the real R6 code does today

### Nodes are R6 objects that store links on both ends

Every greta array is an array with a `"node"` attribute pointing at an R6
`node` object (`R/greta_array_class.R:89-94`, `get_node()` at
`R/greta_array_class.R:233-235`). The node itself keeps two lists,
`parents` and `children`, declared as public fields on the class:

```r
# R/node_class.R:2-7
node <- R6Class(
  "node",
  public = list(
    unique_name = "",
    parents = list(),
    children = list(),
```

The graph is **doubly linked**: a link is written into both the child and
the parent in a single call, and the two writes are done by mutating the
live R6 objects in place. This is the actual `add_parent()` /`add_child()`
pair:

```r
# R/node_class.R:60-64
add_parent = function(node) {
  # add to list of parents
  self$parents <- c(self$parents, node)
  node$add_child(self)
},
```

```r
# R/node_class.R:96-99
add_child = function(node) {
  # add to list of children
  self$children <- c(self$children, node)
},
```

`add_parent()` appends `node` to `self$parents` **and** reaches into
`node` and appends `self` to *its* `children`. Removal is symmetric and
also mutates both ends (`R/node_class.R:65-70` and `100-104`). The
entries stored are the R6 objects themselves, not copies or ids — so after
`x$add_parent(y)`, `y$children[[1]]` *is* `x` in the pointer sense
(`identical()` is true). Because the links point both ways, the entire
connected component is reachable from any single node in it.

Nodes are entered into the graph by the constructors: an operation coerces
each argument to a node and calls `add_parent()` on it
(`add_argument()`, `R/node_types.R:135-139`), and a distribution adds its
target and parameters as parents the same way (`add_target()`,
`R/node_types.R:462-475`; `add_parameter()`, `R/node_types.R:501-519`).

### Identity is the R6 environment address, not a value

A node's identity is the address of its enclosing R6 environment. The
`unique_name` field exists precisely because there is no value-based
identity to fall back on — it is a random hex string minted at
construction:

```r
# R/node_class.R:262-264
create_unique_name = function() {
  self$unique_name <- glue::glue("node_{rhex()}")
},
```

(That random naming is itself a known hazard — collisions are possible;
see [#366](https://github.com/greta-dev/greta/issues/366).)

### Traversal is recursion through method calls on live objects

There is no table to index. To answer "what is upstream of this node?" the
code walks the object pointers, recursing through R6 method calls one
object at a time:

```r
# R/node_class.R:124-148 (parent_names, abridged)
parent_names = function(recursive = FALSE) {
  parents <- self$parents
  if (length(parents) > 0) {
    names <- extract_unique_names(parents)
    if (recursive) {
      their_parents <- function(x) {
        x$parent_names(recursive = TRUE)
      }
      grandparents <- lapply(parents, their_parents)
      names <- c(names, unlist(grandparents))
    }
    names <- unique(names)
  } else {
    names <- self$unique_name
  }
  names
}
```

Building the dag is the same shape: `register_family()` recursively walks
its own parents and children, registering each unregistered relative into
the dag's `node_list` (`R/node_class.R:37-59`), driven from
`dag$build_dag()` (`R/dag_class.R:82-89`). Even the adjacency matrix is
built by calling `child_names()` / `parent_names()` on every node through
the `member` helper (`R/dag_class.R:817-826`), i.e. by dispatching a
method per node rather than reading a column.

### The child links are redundant

Note that `children` carries no information that `parents` does not: every
edge is written to both ends by `add_parent()`, so the child list is
wholly derivable from the parent lists of the other nodes. It exists only
to make downward traversal a field read instead of a search. This is the
redundancy Phase A removes.

### Where the Python pointers live

The reticulate/TensorFlow handles do **not** live on nodes. They live on
the `dag_class`: `tf_environment` (a plain environment full of tensors)
and `tf_graph` (a Python `Graph` object):

```r
# R/dag_class.R:73-79
new_tf_environment = function() {
  self$tf_environment <- new.env()
  self$tf_graph <- tf$Graph()
  ...
```

Tensors for each node are `assign()`ed into `tf_environment` under
mode-prefixed names (`get_tf_object()` / `tf_name()`,
`R/dag_class.R:106-119`, `444-446`). Operation nodes additionally stash a
captured R environment, `tf_function_env = parent.frame(3)`
(`R/node_types.R:94`, used at `R/node_types.R:167-171`). So the live,
un-serialisable state is concentrated on the dag, while the graph
structure is spread across the doubly-linked nodes.

### The cloning bug (#267) falls out of both facts above

`model$dag$clone(deep = TRUE)` fails:

```
Error in py_get_attr_impl(x, name, silent):
  AttributeError: 'Graph' object has no attribute '.__enclos_env__'
```

([#267](https://github.com/greta-dev/greta/issues/267); the diagnosis
on the thread: *"R6's cloning isn't playing nicely with
reticulate's pointers. Cloning pointers will be tricky and may not be
sensible."*)

Two independent things make the R6 graph hostile to `clone(deep = TRUE)`:

1. **The dag holds Python pointers.** A deep clone recurses into every
   field, hits `tf_graph` (the `tf$Graph()` from
   `R/dag_class.R:75`), and tries to clone it as if it were an R6 object.
   It is an external pointer with no `.__enclos_env__`, hence the
   `AttributeError`.
2. **The graph is doubly linked and shares references.** Even with the
   Python handles set aside, R6's deep clone copies each field
   independently and does not dedupe shared references. Two paths to the
   same node (e.g. the same variable reached as a parent of two
   operations) would clone into two *different* objects, and because
   identity is the environment address (§ above), the `parents` /
   `children` back-links would no longer be `identical()` to their
   targets — the cloned graph would be quietly inconsistent.

### The construction overhead (#210, #247)

For-loop-style model code spools out one R6 node per operation, and each
`node$new()` runs a full R6 constructor, mints a random `unique_name`, and
does the mutate-both-ends `add_parent()` dance;
[#210](https://github.com/greta-dev/greta/issues/210) is the user-facing
symptom (loops are *"very slow to define and execute"*). The cause and
the fix are named in
[#247](https://github.com/greta-dev/greta/issues/247):

> the R6 dag construction stuff has a fair bit of overhead. This doesn't
> affect algorithm run time after the dag has been built, but can be slow
> for recursive functions and lots of loops. There may be a more efficient
> solution than recursing through R6 objects, e.g. maintaining a linear
> register of already-defined nodes and storing only names of nodes to
> which a node is connected.

That "linear register ... storing only names" *is* the flat registry.

## 2. The flat-registry equivalent

The same three-node model (`x` a variable, `y = x * 2`) as plain-data
records owned by the dag, referring to each other by id. No R6, no
back-references, no pointers on the records.

```r
# a dag owns a single flat registry of nodes
new_dag <- function() {
  dag <- new.env()
  dag$nodes <- list()
  dag
}

new_node_id <- local({
  counter <- 0
  function() {
    counter <<- counter + 1
    sprintf("node_%03d", counter)
  }
})

add_node <- function(dag, type, parents = character(), value = NULL) {
  id <- new_node_id()
  # a node is plain data: no methods, no back-references, no pointers
  dag$nodes[[id]] <- list(
    id      = id,
    type    = type,
    parents = parents,
    value   = value
  )
  id
}

# parents are stored; children are computed from parents on demand
parents_of <- function(dag, id) {
  dag$nodes[[id]]$parents
}

children_of <- function(dag, id) {
  has_parent <- vapply(
    dag$nodes,
    \(node) id %in% node$parents,
    logical(1)
  )
  names(dag$nodes)[has_parent]
}
```

```r
dag <- new_dag()
x   <- add_node(dag, "variable")
two <- add_node(dag, "data", value = 2)
y   <- add_node(dag, "operation", parents = c(x, two))

children_of(dag, x)
#> [1] "node_003"

# copying the model is an ordinary list copy - no special-casing
dag2 <- new_dag()
dag2$nodes <- dag$nodes

# serialisation is safe by construction: it is a list of lists
identical(unserialize(serialize(dag$nodes, NULL)), dag$nodes)
#> [1] TRUE
```

Three differences map directly onto the R6 facts above:

- `add_node()` writes **one** record; there is no second write into a
  parent, because there are no `children` fields to keep in sync
  (contrast `add_parent()` at `R/node_class.R:60-64`).
- ids are sequential integers-as-strings from a counter, not random hex
  from `rhex()` (`R/node_class.R:262-264`) — reproducible, and no
  collision risk ([#366](https://github.com/greta-dev/greta/issues/366)).
- `children_of()` is a `vapply()` scan of a column, replacing the R6
  method recursion in `parent_names()` / `child_names()`
  (`R/node_class.R:124-168`).

## 3. Side-by-side comparison

| | R6 today | Flat registry |
|---|---|---|
| **Edge storage** | Doubly linked: `add_parent()` writes into `self$parents` *and* the parent's `children` (`R/node_class.R:60-64`, `96-99`) | Single-ended: each record stores only `parents`; children derived on demand (`children_of()`) |
| **Node identity** | R6 environment address; `unique_name` is random hex to compensate (`R/node_class.R:262-264`) | The record's id (a table key); value-addressable |
| **Copying / cloning (#267)** | `dag$clone(deep = TRUE)` errors: it recurses into the `tf$Graph()` pointer on the dag (`R/dag_class.R:75`), and independently clones shared node references, breaking `identical()` back-links | `dag2$nodes <- dag$nodes` — an ordinary list copy; no pointers on records, no shared-identity to preserve |
| **Serialisation (`saveRDS()`)** | Structure is R6 environments cross-linked with live tensors in `tf_environment`; safe for greta arrays but the dag's Python handles break on reload (healed per-accessor by the session-portability work) | `dag$nodes` is a list of lists; `serialize()`/`unserialize()` round-trips by construction |
| **Debugging** | Step through `self$` method chains inside R6 environments (`register_family()`, `parent_names()` recursion) | `traceback()` through ordinary functions reading a table |
| **Graph traversal cost** | Recurse through R6 method calls, one object at a time (`parent_names(recursive = TRUE)`, `R/node_class.R:124-148`); `member(node, "child_names()")` dispatched per node to build the adjacency matrix (`R/dag_class.R:817-826`) | Column lookup / `vapply()` scan over `dag$nodes`; no per-node method dispatch |
| **Construction cost (#210)** | One `R6::new()` + `rhex()` + mutate-both-ends per operation; slow for loops (#210) and recursion (#247) | Append one plain record; no constructor machinery, no second write |
| **Where Python pointers live** | On the dag (`tf_environment`, `tf_graph`; `R/dag_class.R:73-79`) and captured op environments (`tf_function_env`, `R/node_types.R:94`) — **not** on nodes | Unchanged. The registry makes the *graph* plain data; it does not move the Python handles, which stay a dag concern |

The last row matters for scope: the flat registry does **not** by itself
fix session-portability of a *fitted* model — the tensors and `tf$Graph()`
are on the dag either way. What it changes is that the model's *structure*
(the thing `saveRDS()` most needs to reload faithfully) stops being a web
of cross-linked R6 environments and becomes serialisable data, so
portability becomes a property of the structure rather than a patch on top
of it.

## 4. Why it differs, and what it buys — tied to the phases

The R6 design optimises for one thing: making downward traversal
(`children`) a field read. It pays for that with a redundant link that
must be kept in sync on every edit (`add_parent()` writing both ends),
pointer identity that needs a random `unique_name` crutch, and a structure
that `clone()` and `saveRDS()` cannot handle cleanly because it is built
from live environments (and, on the dag, live Python pointers). The flat
registry inverts the trade: store the minimal thing (parents), derive the
rest, and keep every record as plain data.

The migration reaches that end state in three behaviour-preserving steps,
each mapped onto specific code above:

- **Phase A — stop storing child links; compute children on demand.**
  Delete the `children` field and the second write in `add_parent()`
  (`R/node_class.R:60-64`, `96-99`), and reimplement `child_names()` /
  `list_children()` (`R/node_class.R:105-118`, `149-168`) as a search over
  other nodes' parents — the `children_of()` function above. This removes
  the redundant back-link, which is most of the cyclic-reference weight
  that makes deep-clone and serialisation fragile, while every public
  method keeps its current signature. The existing test suite (plus the
  conformance suite landing in the same release) is the oracle.

- **Phase B — parent refs become ids resolved through a dag-owned table.**
  Replace the R6 objects held in `self$parents` with `unique_name` ids,
  resolved through `dag$node_list` (already the dag's node table,
  `R/dag_class.R:11`, `82-89`). This is the *"linear register ...
  storing only names of nodes to which a node is connected"* idea from #247.
  Once parents are ids, nothing in the graph holds a live cross-reference,
  so the shared-identity hazard behind #267 is gone and traversal is table
  lookup rather than pointer chasing.

- **Phase C — node internals become plain records.** With no back-links
  and no object references, the node no longer needs to be an R6 object at
  all; its fields (`dim`, `.value`, `distribution`, operation metadata)
  become a plain record in the registry. The R6-vs-S3-vs-S7 question then
  shrinks to a small, local, reversible choice, because it is no longer
  entangled with a mutable, doubly-linked object graph.

What it buys, each grounded in the code rather than asserted:

- **#267 dissolves.** With no Python pointers on the graph structure and
  no shared R6 references to preserve, "copy the model" is a list copy;
  the `clone(deep = TRUE)` path that trips over `tf$Graph()` is no longer
  the mechanism.
- **#210 / #247 overhead drops.** Defining a node becomes appending a
  record instead of running an R6 constructor, minting `rhex()`, and
  writing both ends of an edge — the per-node cost that makes loops slow.
- **Session-portability becomes structural.** The structure is
  serialisable by construction, narrowing the pointer-healing work to the
  genuinely un-serialisable dag state (`tf_environment`, `tf_graph`).
- **Graph-rewriting features get a workable substrate.** Marginalisation
  ([#157](https://github.com/greta-dev/greta/issues/157),
  [#344](https://github.com/greta-dev/greta/pull/344)) and automated
  decentring ([#47](https://github.com/greta-dev/greta/issues/47))
  rewrite the DAG; rewriting plain records in a table is tractable in a
  way that rewriting a doubly-linked R6 object graph is not.
