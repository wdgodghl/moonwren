# Compatibility roadmap

MoonWren targets source-level compatibility with Wren while keeping the
implementation idiomatic to MoonBit.

| Area | Status | Notes |
| --- | --- | --- |
| Source spans and diagnostics | Implemented | File, line, column, and cross-module call frames |
| Lexical analysis | Implemented | Punctuation, literals, comments, and keywords |
| Primitive expressions | Implemented | Precedence, arithmetic, comparison, logic, ranges |
| Variables and blocks | Implemented | Declaration, assignment, lexical environments |
| Branching and loops | Implemented subset | `if`, `while`, protocol-based `for`, `break`, `continue` |
| Method and getter calls | Partial | Chaining, signatures by arity, user getters, core type metadata |
| Core class model | Implemented subset | `Object`, `Bool`, `Class`, `Fn`, `List`, `Map`, `Null`, `Num`, `Range`, `Sequence`, and `String` globals; `type`, `name`, `supertype`, and `is` |
| Core `System` class | Partial | Captured `print`, `write`, `printAll`, `writeAll`; no-op `gc`; `clock` pending |
| Core `Range` class | Partial | Bounds, endpoint mode, text conversion, numeric iteration |
| Core `String` class | Partial | Unicode character indexes, slices, iteration, search, split, replace, trim, bytes/code points, static scalar construction |
| Core `List` class | Partial | Construction, negative indexes, slices, mutation/search, sorting, concatenation, repetition, iteration |
| Core `Map` class | Partial | Construction, immutable keys, mutation, entry iteration, key/value sequence views |
| Core `Num` class | Implemented subset | Parsing, constants, predicates, rounding, trigonometry, logs, powers, min/max/clamp |
| Core `Sequence` class | Implemented subset | Aggregation, predicates, joining, reduction, lazy `map`/`where`/`skip`/`take`, materialization |
| Functions and closures | Partial | Construction, arity, multiline bodies, `return`, calls, recursion, captured cells |
| Classes | Partial | Instance/static members, inheritance, overriding, `this`, `super` |
| Fibers | Implemented subset | Lazy creation, nested block/branch/loop suspension, direct called-function suspension, `current`, `call`, `try`, `yield`, `suspend`, main-fiber `transfer`, abort/error/completion state |
| Modules | Implemented subset | Explicit imports, aliases, isolated scopes, caching, cycle detection, loader API |
| Foreign methods | Implemented | Instance/static methods and getters, canonical module binding, values and structured host failures |
| Foreign classes | Implemented subset | Host allocation handles, handle-aware methods, mixed Wren methods, shutdown finalization; reachability GC pending |

Unsupported syntax must produce a structured diagnostic. The parser and
runtime should never report success after discarding an unsupported construct.

Function execution currently supports implicit last-expression results for
compact closures as well as explicit value and bare `return` statements.
Returns propagate through nested blocks, conditionals, and loops. A top-level
`return` is rejected with a source-located runtime diagnostic.

Class declarations create runtime class values with lexically captured method
environments. Constructors allocate independent instances, instance fields are
created on first assignment and default to `null` when unread, and dispatch
selects methods by name and arity. Closures returned from methods retain both
the receiving `this` value and access to its fields. Duplicate signatures are
rejected.

Subclass declarations resolve their superclass when executed. Instance method
and getter lookup walks the superclass chain, constructors call a matching
parent constructor explicitly through `super(...)`, and overridden members can
use `super.member`. The `is` operator recognizes both instance and class
inheritance relationships. Constructors are intentionally not inherited.

Static methods and getters dispatch on class values and support inheritance,
overriding, dynamic `this`, and `super`. Static `__fields` are owned by the
method's declaring class, initialized on first assignment, and shared by calls
through subclasses. Instance and static signatures may coexist.

`break` and `continue` propagate through nested blocks and conditionals until
the nearest loop consumes them. Function and method calls form hard control-flow
boundaries, preventing a callee from changing its caller's loop state.

List and Map values use runtime identity, so two separately allocated
collections are not equal even when their contents match. Map lookup is
deterministic and returns `null` for a missing key. Keys must be immutable core
values or class values, and a repeated literal key replaces the earlier value.
Map iteration yields key/value entry objects in deterministic insertion order;
its `keys` and `values` getters preserve the same order in immutable sequence
snapshots. List iteration snapshots the elements present when the loop begins,
which prevents mutation during a loop from silently extending that loop.
Collection text conversion has a depth bound so recursive structures remain
printable.

`for` uses the same `iterate(iterator)` and `iteratorValue(iterator)` protocol
for built-in and user-defined objects. Range, List, String, Map, and lazy
Sequence values implement this protocol. Sequence transformations keep their
source and callback until iteration, and each traversal receives independent
iterator state. Predicates and membership checks short-circuit. String indexes
and `count` deliberately operate on Unicode characters instead of Wren's raw
UTF-8 byte offsets; slices and iteration therefore never split a character.
`String.fromByte` currently covers scalar-safe byte values rather than creating
arbitrary invalid UTF-8. These two documented differences remain compatibility
work rather than silent behavior.

Fiber bodies keep a persistent captured environment and resume values through
statement continuations. Suspension preserves lexical scopes and execution
positions inside blocks, conditionals, `while`, and `for`, including repeated
loop yields without replaying earlier side effects. A directly called function
may suspend when the call is an expression statement, variable initializer, or
return value; arbitrary nested method and operator call stacks remain future
work. Transfers between the main Fiber and a worker preserve resume values.
Worker-to-worker `transfer` currently uses the same synchronous return path as
`call`, while `transferError` marks its target aborted without a full non-local
stack transfer.

Foreign methods are resolved using the canonical module name, class name,
static flag, and Wren signature. Callbacks receive the receiver separately from
the ordered arguments and may return any `Value` or a structured failure.
Bindings are immutable for one run and callbacks execute while the interpreter
is suspended, so the runtime is deliberately non-reentrant. A foreign class
binding allocates an opaque integer handle from constructor arguments. Its
foreign instance methods receive that handle, while methods written in Wren
continue to dispatch normally on the same object. Finalizers run exactly once
when the interpreter run shuts down. Reachability-based collection and
mid-execution finalization remain tied to the planned garbage collector.

Imports support `import "module"`, explicit names using `for`, and local aliases
using `as`. Every canonical module owns an isolated top-level environment and
executes at most once. Loader callbacks decide how an importer/specifier pair
maps to canonical source, while the in-memory helper matches names exactly.
Missing modules, missing imported names, duplicate local bindings, parse errors,
and circular imports retain source locations. Import, function, and method
frames are included when a runtime error crosses module boundaries.
