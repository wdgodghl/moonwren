# MoonWren

MoonWren is a Wren-compatible scripting language implementation written in
MoonBit. It is designed as an embeddable interpreter with a small public API, a
standalone command-line runner, and behavior-focused compatibility tests.

The project is under active development. The current milestone covers source
locations, lexical analysis, primitive expressions, variables, lexical block
scope, assignment, conditionals, `while` loops, protocol-based `for` loops,
method and getter calls, captured program output, the core class model,
universal `toString`, range metadata getters, multiline functions with lexical closures,
early `return`, classes, constructors, instances, fields, methods, getters, and
`this`, inheritance, method overriding, `super`, class relationship checks,
static members, and structured `break`/`continue` control flow. Core values
include mutable List and Map collections, Unicode-aware String operations,
negative indexes, range slices, MapEntry iteration, eager sequence aggregations,
and composable lazy `map`/`where`/`skip`/`take` pipelines. Named modules,
explicit imports, loader callbacks, module caching,
cross-module stack traces, multi-file CLI execution, cooperative Fiber values,
and host-bound foreign methods are also available. Fully nested Fiber
continuations and foreign classes follow in later milestones.

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
and prints `55`. Use `--eval` to execute a source string directly:

```text
moon run cmd/main -- --eval "var value = 40\nSystem.print(value + 2)"
```

Functions are values and capture surrounding variables by reference:

```text
moon run cmd/main -- --eval "var count = 0\nvar next = Fn.new { count = count + 1 }\nSystem.print(next.call())\nSystem.print(next.call())"
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

Subclass lookup supports inherited methods and getters, explicit superclass
constructor calls, overriding, and `super` dispatch:

```wren
class NamedPoint is Point {
  construct new(x, y) { super(x, y) }

  sum {
    return super.sum + 2
  }
}

var point = NamedPoint.new(19, 21)
System.print(point.sum)       // 42
System.print(point is Point)  // true
```

See [`examples/inheritance.wren`](examples/inheritance.wren) for a complete
multi-level example.

Static methods and getters share class-owned `__fields`, participate in
inheritance, and support dynamic `this` plus declaring-class `super` dispatch.
See [`examples/static_members.wren`](examples/static_members.wren).

Both `while` and range `for` loops support `break` and `continue`. Loop control
can cross nested blocks and conditionals, but a called function or method cannot
accidentally break or continue its caller's loop. See
[`examples/loop_control.wren`](examples/loop_control.wren).

Lists and maps are mutable reference values. Lists support positive and negative
indexes, range slices, construction and filling, `add`, `addAll`, `insert`,
`remove`, `removeAt`, `contains`, `indexOf`, `swap`, `sort`, concatenation,
repetition, `clear`, `count`, and stable `for` iteration. Maps accept immutable
keys and provide indexed lookup and update, `containsKey`, `remove`, `clear`,
`count`, snapshot `keys` and `values` views, and entry iteration:

```wren
var scores = {"Ada": 38, "Lin": 40}
scores["Ada"] = scores["Ada"] + 4

var values = [scores["Ada"], scores["Lin"]]
values.add(0)

var total = 0
for (value in values) total = total + value
System.print(total) // 82
```

See [`examples/collections.wren`](examples/collections.wren) for a complete
example including nested collections and removal.

Strings expose character-based indexing, slicing, counting, and iteration, so
surrogate pairs are never returned as partial characters. The core methods
include `contains`, `startsWith`, `endsWith`, `indexOf`, `split`, `replace`,
trimming, UTF-8 byte views, and code-point views. `Num` provides parsing,
constants, predicates, rounding, trigonometry, logarithms, powers, and clamping.
Any class can participate in a `for` loop by implementing `iterate(iterator)`
and `iteratorValue(iterator)`. See
[`examples/iterables.wren`](examples/iterables.wren).

Every built-in iterable supports `all`, `any`, `contains`, `count`, `each`,
`join`, and seeded or unseeded `reduce`. Transformations are lazy and can be
composed before materializing with `toList`; short-circuiting operations only
consume as much input as needed:

```wren
var selected = (1..20).where(Fn.new { |n| n % 2 == 0 })
selected = selected.map(Fn.new { |n| n * n }).skip(2).take(3)

System.print(selected.toList) // [36, 64, 100]
```

See [`examples/core_library.wren`](examples/core_library.wren) for a runnable
tour of the expanded core library.

Fibers retain their local environment between calls and exchange values at
cooperative suspension points. Errors can either propagate through `call` or be
captured through `try`:

```wren
var worker = Fiber.new { |request|
  System.print(request)
  var response = Fiber.yield("waiting")
  return response
}

System.print(worker.call("start")) // waiting
System.print(worker.call("done"))  // done
```

See [`examples/fibers.wren`](examples/fibers.wren) for calls, main-fiber
transfers, completion state, and captured aborts.

Multi-file programs use explicit imports. The CLI resolves relative module
names from the importing file, automatically adds `.wren` when omitted, and
executes every canonical module once:

```wren
import "math" for Calculator
System.print(Calculator.double(21))
```

```text
moon run cmd/main -- examples/modules/main.wren
```

See [`examples/modules`](examples/modules) for the complete project.

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

Embedders can provide modules from memory, a database, an archive, or another
source through `run_with_loader`. `run_modules` is a convenience API for a
fixed in-memory collection:

```moonbit
let modules = [
  ModuleSource::new("main", "import \"answer\" for value\nvalue\n"),
  ModuleSource::new("answer", "var value = 42\n"),
]
let result = run_modules("main", modules, 100000)
```

Wren classes may declare foreign instance methods, static methods, and getters.
`run_with_foreign_methods` binds those declarations to typed MoonBit callbacks;
callbacks receive the receiver and argument array, then return either a Wren
value or a structured host failure. See
[`docs/embedding.md`](docs/embedding.md) and
[`examples/foreign_methods.wren`](examples/foreign_methods.wren).

## Project status

MoonWren is not yet a complete Wren implementation. The method dispatcher
supports constructor signatures, overloaded instance methods by arity,
user-defined getters, core class metadata and constructors, captured
`System.print`/`write` output, and the standard `from`, `to`, `min`, `max`, and
`isInclusive` range properties. Collection and
String subscripts produce structured invalid-index and bounds diagnostics, and
Map keys are checked before lookup or mutation. Inherited
lookup advances from each method's declaring class, so multi-level `super`
calls remain correct. Static methods, getters, and class-owned fields use the
same signature and superclass lookup model. See
[`docs/compatibility.md`](docs/compatibility.md) for the current feature
matrix and planned order of implementation.

Program execution has both a configurable statement-step budget and a call
depth guard. These limits turn unbounded loops and runaway recursion into
structured diagnostics instead of allowing them to consume host resources.
Diagnostics retain their defining module and accumulate function, instance,
static-method, and import frames while unwinding.

The implementation pipeline and package boundaries are documented in
[`docs/architecture.md`](docs/architecture.md).

## License and references

MoonWren is licensed under Apache-2.0. The implementation uses the public Wren
language documentation as a behavioral reference. See [`NOTICE`](NOTICE) for
attribution and project-boundary details.
