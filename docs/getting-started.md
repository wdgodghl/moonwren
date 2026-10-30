# Getting started

This guide proves the shortest supported path from a clean MoonBit project to
a running Wren program. MoonBit 0.10.16 or newer is required; release 0.9.2 is
verified with `moonc 0.10.18+6c83a7f62`.

## Use MoonWren as a library

Create a MoonBit project and add the published package:

```text
moon new moonwren-demo
cd moonwren-demo
moon add wdgodghl/moonwren@0.9.2
```

Add `wdgodghl/moonwren` to the consumer package's `moon.pkg`, then call the
library as `@moonwren`:

```moonbit
fn main {
  let source = "var values = [10, 20, 12]\n" +
    "System.print(values.reduce { |sum, value| sum + value })\n"
  match @moonwren.run(source) {
    ProgramCompleted(_, output) =>
      for line in output {
        println(line)
      }
    ProgramFailed(diagnostics, _) =>
      for diagnostic in diagnostics {
        println(diagnostic.render("demo.wren"))
      }
  }
}
```

Running the package prints exactly:

```text
42
```

`System.print` is captured and returned to the host; the library does not
write to a console by itself.

## Run a Wren file from this repository

```text
moon run cmd/main -- examples/modules/main.wren
```

Expected output:

```text
hello from an imported module
42
```

For a source string:

```text
moon run cmd/main -- --eval "System.print(6 * 7)"
```

The native CLI contract is covered by `tools/check-cli-acceptance.ps1`,
including imports, compile errors, runtime errors, missing files, and exit
codes.

## Choose the right embedding path

- Use `run` for isolated configuration, rules, templates, and short scripts.
- Use `run_with_loader` or `run_modules` when scripts import application-owned
  modules.
- Use `Vm` when globals, closures, instances, or Fibers must survive later host
  calls.
- Use the JavaScript SDK only after generating `web/moonwren.js` with
  `tools/build-web-demo.ps1`; it is a repository artifact, not an npm release.

Do not start with bytecode, VM pooling, hot reload, or deployment bundles unless
the application has a measured need for those optional surfaces.

## Failure behavior

The CLI uses conventional, stable exit categories:

| Exit code | Meaning |
| --- | --- |
| 0 | Program completed successfully |
| 64 | Invalid CLI usage |
| 65 | Scan, parse, or resolution failure |
| 66 | Entry source file could not be read |
| 70 | Runtime failure or execution limit |

Library callers receive `ProgramFailed` and structured `Diagnostic` values
instead of process exit codes.

## Troubleshooting

- **Package cannot be resolved:** run `moon update`, then confirm the dependency
  in `moon.mod` and package import in `moon.pkg`.
- **An import cannot be loaded:** library APIs do not read the filesystem; pass
  a loader or use `run_modules`. The repository CLI supplies a relative-file
  loader.
- **A script needs files or environment values:** opt into the separate `host`
  package and define an explicit `HostAccessPolicy`.
- **A script does not terminate:** lower `VmLimits` or the one-shot step limit;
  resource exhaustion is returned as a diagnostic.
- **Behavior differs from Wren:** reproduce it with the official 0.4.0 CLI and
  the commands in [`testing.md`](testing.md), then reduce it to a fixture.

