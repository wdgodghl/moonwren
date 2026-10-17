# MoonWren

MoonWren is a Wren-compatible scripting language implementation written in
MoonBit. It is designed as an embeddable interpreter with a small public API, a
standalone command-line runner, and behavior-focused compatibility tests.

The project is under active development. The current milestone covers source
locations, lexical analysis, primitive expressions, variables, lexical block
scope, assignment, conditionals, `while` loops, numeric range `for` loops,
method and getter calls, captured program output, `System.print`, universal
`toString`, range metadata getters, multiline functions with lexical closures,
early `return`, classes, constructors, instances, fields, methods, getters, and
`this`. Inheritance, fibers, modules, and foreign methods follow in later
milestones.

## Goals

- implement the language runtime primarily in MoonBit;
- keep the interpreter portable across MoonBit targets;
- provide useful diagnostics with source locations;
- make embedding scripts straightforward through a small API;
- track compatibility explicitly instead of silently accepting unsupported
  syntax.

## Development

The project requires MoonBit `0.10.14` or newer.

```text
moon check
moon test
moon run cmd/main
```

Running the command without arguments executes the bundled summation example
and prints `55`. A source string can also be supplied directly:

```text
moon run cmd/main -- "var value = 40\nSystem.print(value + 2)"
```

Functions are values and capture surrounding variables by reference:

```text
moon run cmd/main -- "var count = 0\nvar next = Fn.new { count = count + 1 }\nSystem.print(next.call())\nSystem.print(next.call())"
```

Function bodies may contain declarations and control flow. A `return` exits
through nested blocks and loops, while a bare `return` produces `null`:

```wren
var makeCounter = Fn.new {
  var count = 0
  return Fn.new {
    count = count + 1
    return count
  }
}

var counter = makeCounter.call()
System.print(counter.call()) // 1
System.print(counter.call()) // 2
```

Classes combine persistent instance fields with constructor, method, and getter
dispatch:

```wren
class Point {
  construct new(x, y) {
    _x = x
    _y = y
  }

  move(dx, dy) {
    _x = _x + dx
    _y = _y + dy
  }

  sum { return _x + _y }
}

var point = Point.new(10, 20)
point.move(5, 7)
System.print(point.sum) // 42
```

The complete version is available in
[`examples/classes.wren`](examples/classes.wren).

The library API exposes the same pipeline:

```moonbit
match @moonwren.run("var answer = 6 * 7\nanswer\n") {
  ProgramCompleted(value, output) => {
    for line in output {
      println(line)
    }
    println("result: \{value.to_text()}")
  }
  ProgramFailed(diagnostics, _) =>
    for diagnostic in diagnostics {
      println(diagnostic.render("example.wren"))
    }
}
```

`System.print` output is returned as an array of lines instead of being written
directly by the library. Embedders can route those lines to a console, log,
editor pane, or another host-provided destination.

## Project status

MoonWren is not yet a complete Wren implementation. The method dispatcher
supports constructor signatures, overloaded instance methods by arity,
user-defined getters, the two `System.print` signatures, and the standard
`from`, `to`, `min`, `max`, and `isInclusive` range properties. Static fields,
static methods, inheritance, and `super` are not implemented yet. See
[`docs/compatibility.md`](docs/compatibility.md) for the current feature
matrix and planned order of implementation.

Program execution has both a configurable statement-step budget and a call
depth guard. These limits turn unbounded loops and runaway recursion into
structured diagnostics instead of allowing them to consume host resources.

The implementation pipeline and package boundaries are documented in
[`docs/architecture.md`](docs/architecture.md).

## License and references

MoonWren is licensed under Apache-2.0. The implementation uses the public Wren
language documentation as a behavioral reference. See [`NOTICE`](NOTICE) for
attribution and project-boundary details.
