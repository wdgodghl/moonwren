# Compatibility roadmap

MoonWren targets source-level compatibility with Wren while keeping the
implementation idiomatic to MoonBit.

| Area | Status | Notes |
| --- | --- | --- |
| Source spans and diagnostics | Implemented | Line and column tracking |
| Lexical analysis | Implemented | Punctuation, literals, comments, and keywords |
| Primitive expressions | Implemented | Precedence, arithmetic, comparison, logic, ranges |
| Variables and blocks | Implemented | Declaration, assignment, lexical environments |
| Branching and loops | Partial | `if`, `while`, range and List `for`, `break`, `continue` |
| Method and getter calls | Partial | Chaining, signatures by arity, user getters, range getters, `System.print` |
| Core `System` class | Partial | `print()` and `print(object)` with captured output |
| Core `Range` class | Partial | Bounds, endpoint mode, text conversion, numeric iteration |
| Core `List` class | Partial | Literals, subscripts, mutation methods, count, text, iteration |
| Core `Map` class | Partial | Literals, subscripts, arbitrary keys, mutation methods, count, text |
| Functions and closures | Partial | Multiline bodies, `return`, parameters, calls, recursion, captured cells |
| Classes | Partial | Instance/static members, inheritance, overriding, `this`, `super` |
| Fibers | Planned | Cooperative execution |
| Modules | Planned | Imports and module loading hooks |
| Foreign methods | Planned | Embedding boundary |

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
deterministic and returns `null` for a missing key. A repeated literal key
replaces the earlier value. List iteration snapshots the elements present when
the loop begins, which prevents mutation during a loop from silently extending
that loop. Collection text conversion has a depth bound so recursive structures
remain printable.
