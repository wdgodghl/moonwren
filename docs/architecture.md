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
members. Import declarations retain the module specifier and every requested
name or alias. Instance fields have dedicated syntax nodes so field access cannot be
confused with a lexical variable. Class declarations retain an optional
superclass name, while `super(...)` has a dedicated expression node so it can
only invoke the matching parent constructor. Unsupported syntax is rejected
rather than ignored.

## Runtime

Primitive values, core class objects, collection handles, and iterator handles
are represented by one tagged value type. An environment is a stack of lexical
scopes, so lookup and assignment select the nearest visible binding. Method
receivers and arguments are evaluated from left to right before dispatch.
Getter calls use a separate syntax node so `value.toString` remains distinct
from a zero-argument method such as `System.print()`. Core class objects expose
runtime type relationships without manufacturing user-defined class records.
The built-in `System` receiver captures print and write output as lines, keeping
the library independent of a particular console. Persistent VM operations apply
separate limits for execution steps, call depth, captured output, loaded
modules, runtime objects, and source size, plus an optional host cancellation
callback. These limits are shared by the complete runtime, so function and
module calls cannot bypass resource accounting. Numeric range values
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

Lazy sequences store a source plus a transformation descriptor instead of an
eager element array. A traversal allocates an independent iterator record that
tracks the source iterator, yielded count, and current value. `map`, `where`,
`skip`, and `take` therefore compose without intermediate lists and observe the
source when consumed. Eager operations reuse the same advancement helper;
`all`, `any`, `contains`, and `isEmpty` can stop before an unbounded source is
exhausted. Map traversal snapshots key/value entry objects so later mutation
cannot invalidate an active iterator.

Each Fiber owns a closure identifier, a persistent captured environment, a
statement cursor, completion/error state, and an optional continuation.
Starting or resuming a Fiber temporarily switches the runtime's active Fiber
and source module. Nested statement continuations retain block scopes, branch
selection, loop iterators, and loop positions. Internal function frames retain
their own environment while reporting the outer Fiber as `Fiber.current`, so a
callee may yield repeatedly without exposing an implementation-only Fiber. The
main Fiber remains a stable runtime value for cooperative transfers. A transfer
records the target beside the suspended continuation; the scheduler follows
worker-to-worker targets iteratively until a worker completes or transfers to
the main Fiber, avoiding native recursive growth across a transfer chain.

Foreign declarations remain ordinary class members in the syntax tree but are
marked separately from MoonWren-backed methods. Dispatch derives the canonical
Wren signature and looks it up in the run's immutable binding registry. The
callback boundary passes a receiver plus ordered values and converts host
failures into normal structured diagnostics, so module and call frames continue
to work across the boundary. Foreign class definitions also resolve an
allocator/finalizer binding when executed. Constructed instances retain the
host's opaque integer handle beside ordinary Wren fields; handle-aware foreign
methods receive it without exposing runtime registry indexes. Interpreter
shutdown walks allocated foreign instances and finalizes each handle once. An
explicit persistent-VM collection pass traces module, class, closure, Fiber,
collection, and host-handle roots. Unreachable instances are logically retired
and foreign handles are finalized immediately; suspended opaque Fiber
continuations conservatively retain instances.

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
through `super(...)`. Static members have a field table on each declaring class
and a separate superclass handle for lexical `super` dispatch; normal static
lookup does not inherit methods, matching Wren 0.4.0.

Statement execution represents normal completion, return, break, continue, and
failure as distinct results. Blocks propagate those results without guessing
their destination. Loops consume only break and continue; function and method
boundaries convert escaped loop control into structured diagnostics.

## Modules and diagnostics

The runtime owns a registry keyed by each loader-provided canonical module
name. A module enters the loading state before parsing and execution. A cyclic
back-edge reuses that partially initialized environment, so names defined before
the import are visible exactly as in Wren 0.4.0. Successful modules retain their
isolated environment and are reused without executing top-level code again.
Failed modules cannot be mistaken for a successful cached module. All modules
share output capture, object registries, call-depth accounting, and the
statement-step budget.

Closures and classes remember the module where they were defined. When an error
crosses a function or method boundary, the runtime keeps the original source
and appends the caller location. Imports add their own frames. The resulting
`Diagnostic` remains structured for embedders and can also render a readable
multi-line stack trace.

The library itself performs no file I/O: `run_with_loader` accepts a callback,
and `run_modules` provides a deterministic in-memory implementation. The CLI
uses the official `moonbitlang/x` filesystem and path packages to resolve entry
files and relative `.wren` imports.

## Extension path

The persistent `Vm` keeps one runtime generation alive across host calls.
Opaque `VmHandle` values form explicit strong roots and carry the runtime
generation so reload and close can reject stale references deterministically.
Transactional reload evaluates a complete candidate module graph before
swapping the active generation; only portable primitive globals cross that
boundary.

Future runtime work can compact non-instance registries after tracing and expose
incremental collection policies. The current explicit pass preserves live
identities, reuses retired instance slots, and prioritizes deterministic
foreign-resource finalization.
