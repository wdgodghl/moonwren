# Compatibility roadmap

MoonWren targets source-level compatibility with Wren while keeping the
implementation idiomatic to MoonBit.

| Area | Status | Notes |
| --- | --- | --- |
| Source spans and diagnostics | Implemented | Line and column tracking |
| Lexical analysis | Implemented | Punctuation, literals, comments, and keywords |
| Primitive expressions | Implemented | Precedence, arithmetic, comparison, logic |
| Variables and blocks | Implemented | Declaration, assignment, lexical environments |
| Branching and loops | Partial | `if` and `while`; `for` remains planned |
| Method calls | Planned | Required for `System.print` and user methods |
| Functions and closures | Planned | Arity checks and captured environments |
| Classes | Planned | Methods, constructors, inheritance |
| Fibers | Planned | Cooperative execution |
| Modules | Planned | Imports and module loading hooks |
| Foreign methods | Planned | Embedding boundary |

Unsupported syntax must produce a structured diagnostic. The parser and
runtime should never report success after discarding an unsupported construct.
