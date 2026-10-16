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
declarations, blocks, `if` statements, and `while` statements. Unsupported
syntax is rejected rather than ignored.

## Runtime

Primitive values are represented by one tagged value type. An environment is
a stack of lexical scopes, so lookup and assignment select the nearest visible
binding. The interpreter applies a configurable execution-step budget to stop
unbounded loops in embedded use.

## Extension path

The next runtime layer will add callable values and method dispatch. Classes,
closures, modules, fibers, and foreign bindings can then build on the same
source spans, diagnostics, environments, and execution limits without coupling
those features to the scanner.
