# Compatibility roadmap

MoonWren targets source-level compatibility with Wren while keeping the
implementation idiomatic to MoonBit.

| Area | Status | Notes |
| --- | --- | --- |
| Source spans and diagnostics | Implemented | Line and column tracking |
| Lexical analysis | Implemented | Punctuation, literals, comments, and keywords |
| Primitive expressions | Implemented | Precedence, arithmetic, comparison, logic, ranges |
| Variables and blocks | Implemented | Declaration, assignment, lexical environments |
| Branching and loops | Partial | `if`, `while`, and numeric range `for`; general sequences planned |
| Method and getter calls | Partial | Chaining, signatures by arity, user getters, range getters, `System.print` |
| Core `System` class | Partial | `print()` and `print(object)` with captured output |
| Core `Range` class | Partial | Bounds, endpoint mode, text conversion, numeric iteration |
| Functions and closures | Partial | Multiline bodies, `return`, parameters, calls, recursion, captured cells |
| Classes | Partial | Constructors, instances, fields, methods, getters, `this`; inheritance planned |
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
rejected. Static members, inheritance, and `super` remain unsupported.
