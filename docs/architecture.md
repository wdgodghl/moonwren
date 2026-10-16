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
binding. Method receivers and arguments are evaluated from left to right before
dispatch. Getter calls use a separate syntax node so `value.toString` remains
distinct from a zero-argument method such as `System.print()`. The initial
built-in receiver implements both `System.print` signatures and captures output
as lines, keeping the library independent of a particular console. The
interpreter also applies a configurable execution-step budget to stop unbounded
loops in embedded use. Numeric range values preserve their direction and
endpoint mode, allowing `for` statements to support both ascending and
descending inclusive or exclusive iteration.

## Extension path

The next runtime layer will generalize the method dispatcher for class methods
and callable values. Classes, closures, modules, fibers, and foreign bindings
can then build on the same source spans, diagnostics, environments, output
capture, and execution limits without coupling those features to the scanner.
