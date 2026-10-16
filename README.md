# MoonWren

MoonWren is a Wren-compatible scripting language implementation written in
MoonBit. It is designed as an embeddable interpreter with a small public API, a
standalone command-line runner, and behavior-focused compatibility tests.

The project is under active development. The current milestone covers source
locations, lexical analysis, primitive expressions, variables, lexical block
scope, assignment, conditionals, loops, and a minimal interpreter. Classes,
fibers, modules, and foreign methods follow in later milestones.

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
moon run cmd/main -- "var value = 40\nvalue = value + 2\nvalue"
```

The library API exposes the same pipeline:

```moonbit
match @moonwren.run("var answer = 6 * 7\nanswer\n") {
  ProgramCompleted(value) => println(value.to_text())
  ProgramFailed(diagnostics) =>
    for diagnostic in diagnostics {
      println(diagnostic.render("example.wren"))
    }
}
```

## Project status

MoonWren is not yet a complete Wren implementation. In particular, method
calls and `System.print` are not available in the current milestone. See
[`docs/compatibility.md`](docs/compatibility.md) for the current feature
matrix and planned order of implementation.

## License and references

MoonWren is licensed under Apache-2.0. The implementation uses the public Wren
language documentation as a behavioral reference. See [`NOTICE`](NOTICE) for
attribution and project-boundary details.
