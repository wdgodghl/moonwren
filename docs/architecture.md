# Architecture

MoonWren separates language recognition from execution so each phase can be
tested and evolved independently.

```text
source text
    |
    v
scanner -----> tokens + scan diagnostics
    |
    v
parser ------> syntax tree + parse diagnostics
    |
    v
interpreter -> values or runtime diagnostics
```

## Source model

Every token and syntax node carries a half-open `SourceSpan`. Diagnostics use
the same span type, which keeps command-line messages and future embedding
callbacks consistent across scan, parse, resolution, and runtime phases.

## Scanner

The scanner recognizes Wren punctuation, operators, keywords, identifiers,
instance and static fields, decimal and hexadecimal numbers, strings, and
nested block comments. It continues after recoverable errors and returns every
diagnostic accumulated during the pass.

## Parser

The expression parser follows precedence levels from unary operators through
conditional and assignment expressions. Program parsing adds variable
declarations, blocks, `if` statements, `while` statements, functions, and class
members. Instance fields have dedicated syntax nodes so field access cannot be
confused with a lexical variable. Class declarations retain an optional
superclass name, while `super(...)` has a dedicated expression node so it can
only invoke the matching parent constructor. Unsupported syntax is rejected
rather than ignored.

## Runtime

Primitive values are represented by one tagged value type. An environment is
a stack of lexical scopes, so lookup and assignment select the nearest visible
binding. Method receivers and arguments are evaluated from left to right before
dispatch. Getter calls use a separate syntax node so `value.toString` remains
distinct from a zero-argument method such as `System.print()`. The initial
built-in receiver implements both `System.print` signatures and captures output
as lines, keeping the library independent of a particular console. The
interpreter applies a configurable execution-step budget and a separate
function call-depth guard. Both limits are shared by the complete runtime, so
function calls cannot bypass resource accounting. Numeric range values
preserve their direction and endpoint mode, allowing `for` statements to
support both ascending and descending inclusive or exclusive iteration.

List and Map values also carry runtime-local identifiers. Their registries own
the mutable element arrays and map-entry tables, preserving reference identity
when a collection is assigned or passed to a function. Map lookup currently
uses a compact linear table, which keeps equality behavior explicit and is a
good fit for small script-level maps. Subscript operations validate list
indexes before mutation and return structured diagnostics for fractional or
out-of-range indexes. List loops take a shallow snapshot at loop entry, while
collection text conversion limits nesting depth to handle cycles safely.

Loop execution is expressed through an object protocol instead of a type switch.
The interpreter repeatedly calls `iterate(iterator)` and then
`iteratorValue(iterator)`, so user classes and built-in sequences follow the
same control path. List loops and Map key/value views use shallow snapshots to
make mutation during traversal deterministic. String snapshots are built from
MoonBit Unicode characters, keeping indexing, slicing, iteration, and search
positions aligned on the same character boundaries.

Function values store a runtime-local closure identifier. The closure registry
retains the statement body, parameter list, and a captured environment.
Captured environments copy the scope structure while sharing mutable variable
cells, so state changes remain visible across calls and nested closures can
outlive the call that created them. Function variables are predeclared before
their initializer runs, which also enables recursive closures. Statement
execution distinguishes normal completion, early return, and runtime failure;
this lets `return` unwind nested blocks and loops without conflating control
flow with errors.

Class values refer to runtime-local class definitions containing parsed method
declarations and a captured lexical environment. Each instance has an
independent field table and a reference to its class. Constructor and method
calls select a declaration by name and arity, bind `this` and parameters in a
fresh call scope, and reuse the same return propagation and resource guards as
functions. Because closures capture that call scope, a closure returned by a
method can continue to read and update its receiving instance.

Class definitions form an acyclic superclass chain because a superclass must
already resolve to a class value when its subclass is declared. Method lookup
returns both the declaration and its owning class. Calls bind a `super` handle
from that owner, rather than from the instance's most-derived class; this keeps
successive `super` calls correct across three or more inheritance levels.
Constructors use local-only lookup and explicitly initialize the same instance
through `super(...)`. Static members use the same resolved-owner model, with a
field table on each class definition and a separate superclass handle for
static dispatch.

Statement execution represents normal completion, return, break, continue, and
failure as distinct results. Blocks propagate those results without guessing
their destination. Loops consume only break and continue; function and method
boundaries convert escaped loop control into structured diagnostics.

## Extension path

The next runtime layer can add module loading and a host binding boundary.
Fibers can then build on the same source spans, diagnostics, environments,
output capture, iterator protocol, and execution limits without coupling those
features to the scanner.
