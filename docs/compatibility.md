# Compatibility roadmap

MoonWren targets source-level compatibility with Wren while keeping the
implementation idiomatic to MoonBit.

| Area | Status | Notes |
| --- | --- | --- |
| Source spans and diagnostics | In progress | Line and column tracking |
| Lexical analysis | In progress | Wren punctuation, literals, and keywords |
| Expressions | Planned | Pratt parser and evaluator |
| Variables and blocks | Planned | Lexical environments |
| Branching and loops | Planned | `if`, `while`, and `for` |
| Functions and closures | Planned | Arity checks and captured environments |
| Classes | Planned | Methods, constructors, inheritance |
| Fibers | Planned | Cooperative execution |
| Modules | Planned | Imports and module loading hooks |
| Foreign methods | Planned | Embedding boundary |

Unsupported syntax must produce a structured diagnostic. The parser and
runtime should never report success after discarding an unsupported construct.
