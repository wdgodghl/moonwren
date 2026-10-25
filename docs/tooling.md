# Runtime development tools

MoonWren keeps the Wren 0.4-compatible tree-walking interpreter as its default
runtime. The tools below are optional surfaces for embedders and maintainers.

## Bytecode inspection and tracing

`compile_bytecode` accepts literals, variables, assignment, arithmetic,
conditionals, blocks, `if`, `while`, logical short-circuiting, `return`, List
and Map literals, subscripts, properties, and core method calls. User-defined
classes, closures, modules, Fibers, and loop-control syntax are rejected with
`UnsupportedFeature` until they have bytecode semantics.

`disassemble_bytecode` returns stable instruction offsets with source lines and
columns. `profile_bytecode` reports dynamic instruction, stack, load/store,
branch, and arithmetic counts. `trace_bytecode` records every executed
instruction. `BytecodeTraceDebugger` adds deterministic single-step, reset, and
continue-to-source-line-breakpoint navigation. It is a replay debugger over a
completed trace, so it does not mutate or resume the live VM.

## Differential fuzzing

Build MoonWren for the native target, build the official Wren 0.4 interpreter,
then run:

```powershell
./tools/fuzz-differential.ps1 -OfficialWren C:/path/to/wren_cli.exe -Cases 1000 -Seed 20261025
```

The generator covers arithmetic/control flow, Lists, Maps, Fibers, and UTF-8
String behavior, then compares exit status and output. `-CorpusDirectory` adds
sorted `.wren` regression seeds. On mismatch the tool removes lines while the
failure remains reproducible and saves the minimized source plus both outputs
under `.tmp/fuzz-failures` (or `-FailureDirectory`).

## Performance regression checks

```powershell
moon build --target native --release cmd/benchmark
./tools/check-performance.ps1 -WriteBaseline
./tools/check-performance.ps1
./tools/check-performance.ps1 -SmokeOnly
```

The six metrics cover parsing, procedural AST/bytecode execution, collection
AST/bytecode execution, and Fiber execution. The baseline lives under ignored
`.tmp/`; later local runs fail when a metric exceeds the configured ratio (1.35
by default). CI uses `-SmokeOnly` to validate every metric and enforce a broad
bytecode-to-AST sanity ratio without relying on runner-specific absolute time.

## Browser playground

```powershell
./tools/build-web-demo.ps1
```

This builds the JavaScript target, copies the ignored generated module to
`web/moonwren.js`, and leaves the source-only playground at `web/index.html`.
Serve the repository through a local static HTTP server and open that page.
The script executes entirely in the browser with a fixed step budget. The UI
includes runnable examples, Ctrl/Command+Enter execution, timing, reset, and
URL-fragment share links. The manual `Playground Pages` GitHub Actions workflow
builds and publishes the same static assets after repository Pages is enabled.

## Module deployment

Use `VerifiedModule::new` and `verified_module_loader` for source bundles.
`encode_module_archive` and `decode_module_archive` persist a deterministic
`MWA1` archive and reject unsafe names, duplicate entries, malformed lengths,
trailing data, and checksum mismatches. Checksums detect accidental corruption;
they are not cryptographic signatures.
For disk-backed modules, import `wdgodghl/moonwren/loaders` and construct a
`FileLoaderConfig`. The loader resolves paths canonically below one root,
rejects absolute/escaping paths, supplies a default extension, and caps source
size. `FileModuleWatcher` polls an explicit module set portably and returns
verified contents plus changed names for the persistent VM's transactional
reload workflow.
