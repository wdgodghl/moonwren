# Runtime development tools

MoonWren keeps the Wren 0.4-compatible tree-walking interpreter as its default
runtime. The tools below are optional surfaces for embedders and maintainers.

## Bytecode inspection and tracing

`compile_bytecode` accepts literals, variables, assignment, arithmetic,
conditionals, blocks, `if`, `while`, logical short-circuiting, and `return`.
Object, call, collection, class, module, Fiber, and loop-control syntax is
rejected with `UnsupportedFeature` until it has bytecode semantics.

`disassemble_bytecode` returns stable instruction offsets with source lines and
columns. `profile_bytecode` reports dynamic instruction, stack, load/store,
branch, and arithmetic counts. `trace_bytecode` records every executed
instruction; a debugger can filter `instruction.span.line()` to implement
source breakpoints and single stepping.

## Differential fuzzing

Build MoonWren for the native target, build the official Wren 0.4 interpreter,
then run:

```powershell
./tools/fuzz-differential.ps1 -OfficialWren C:/path/to/wren_cli.exe -Cases 1000 -Seed 20261025
```

The generator produces deterministic arithmetic/control-flow programs and
compares exit status and output. A mismatch reports the seed, complete source,
and both results so the case is reproducible.

## Performance regression checks

```powershell
moon build --target native --release cmd/benchmark
./tools/check-performance.ps1 -WriteBaseline
./tools/check-performance.ps1
```

The baseline lives under ignored `.tmp/`. Later runs fail when either the AST
or bytecode workload exceeds the configured ratio (1.35 by default). Absolute
times are intentionally not committed because CI and developer hardware vary.

## Browser playground

```powershell
./tools/build-web-demo.ps1
```

This builds the JavaScript target, copies the ignored generated module to
`web/moonwren.js`, and leaves the source-only playground at `web/index.html`.
Serve the repository through a local static HTTP server and open that page.
The script executes entirely in the browser with a fixed step budget.

## Module deployment

Use `VerifiedModule::new` and `verified_module_loader` for source bundles.
Checksums detect accidental corruption; they are not cryptographic signatures.
For disk-backed modules, import `wdgodghl/moonwren/loaders` and construct a
`FileLoaderConfig`. The loader resolves paths canonically below one root,
rejects absolute/escaping paths, supplies a default extension, and caps source
size. Compare `ModuleSnapshot` values to feed changed names into the persistent
VM's transactional reload workflow.
