# MoonWren

MoonWren is a Wren-compatible scripting language implementation written in
MoonBit. It is designed as an embeddable interpreter with a small public API, a
standalone command-line runner, and behavior-focused compatibility tests.

The project is under active development. The first milestone covers source
locations, lexical analysis, expressions, variables, control flow, and a
minimal interpreter. Classes, fibers, modules, and foreign methods follow in
later milestones.

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

## Project status

MoonWren is not yet a complete Wren implementation. See
[`docs/compatibility.md`](docs/compatibility.md) for the current feature
matrix and planned order of implementation.

## License and references

MoonWren is licensed under Apache-2.0. The implementation uses the public Wren
language documentation as a behavioral reference. See [`NOTICE`](NOTICE) for
attribution and project-boundary details.
