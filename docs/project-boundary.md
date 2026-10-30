# Project boundary

MoonWren has one primary job: execute Wren 0.4.0 source inside MoonBit
applications with predictable language behavior and explicit host boundaries.
This document is the scope contract for releases and reviews.

## Normative compatibility target

The source-language target is `wren-lang/wren` tag `0.4.0`, commit
`4a18fc489f9ea3d253b20dd40f4cdad0d6bb40eb`. A compatibility claim covers the
Wren grammar, language semantics, core classes, `random` and `meta` optional
modules, modules, Fibers, and source-visible error categories exercised by the
adopted official suite.

The tree-walking interpreter is the reference MoonWren execution path. The
fixed completion rules and excluded upstream files are documented in
[`wren-0.4-conformance.md`](wren-0.4-conformance.md).

## Supported contract

The following surfaces are supported and release-gated:

| Surface | Contract |
| --- | --- |
| One-shot library API | `run`, `run_with_loader`, `run_with_foreign_bindings`, and `run_modules` return structured output or diagnostics. |
| Persistent embedding API | `Vm`, `VmLimits`, handles, loader callbacks, foreign bindings, cancellation, and explicit collection retain state across host calls. |
| Native CLI | Runs one entry file with relative imports, supports `--eval`, writes program output and diagnostics, and uses documented exit codes. |
| JavaScript SDK | The generated ES module exposes bounded one-shot evaluation in browsers and Node.js. |
| Compatibility evidence | Checked-in fixtures and the adopted Wren 0.4.0 `language` and `core` suites must pass without accepted failures. |

The public behavior is the observable result, diagnostic category/location,
exit code, resource-limit failure, and documented host callback contract. The
internal object layout, registry indexes, and implementation strategy are not
part of the contract.

## Optional and experimental surfaces

These components are useful and tested, but do not widen the Wren 0.4.0
compatibility claim:

- bytecode compilation, profiles, traces, and the replay debugger;
- language-service and debug-adapter cores without LSP/DAP wire transports;
- deployment bundles, deterministic replay, observability exporters, VM pools,
  state snapshots, and multi-module hot reload;
- capability modules under `moon/*` that are MoonWren host conventions rather
  than Wren standard-library modules.

Their APIs may be refined between minor pre-1.0 releases. A release must keep
their documented safety properties and tests accurate, but compatibility with
an external protocol or another Wren implementation is not implied.

## Explicit non-goals

MoonWren does not promise:

- Wren versions newer than 0.4.0 unless the target is deliberately revised;
- the official C API or ABI, official bytecode, object layout, GC timing,
  memory use, or performance parity;
- the `wren_cli` filesystem, process, terminal, and module-search behavior;
- direct process or network access from the core runtime;
- an operating-system security sandbox for mutually hostile code;
- a complete LSP server, DAP server, editor extension, package manager, JIT, or
  native-code compiler;
- portable serialization of functions, Fibers, foreign objects, execution
  stacks, or other runtime-local identities.

Unsupported syntax or operations must fail with a structured diagnostic. They
must never be ignored while reporting success.

## Security boundary

The core package performs no filesystem, environment, process, or network I/O.
Host access is opt-in through loaders, callbacks, or the separate `host`
package. Resource limits bound interpreter work but do not replace process
isolation. Filesystem roots must be controlled by the embedding application;
the documented symlink limitation still applies.

## Scope-change rule

A proposed feature belongs in MoonWren only when it strengthens Wren 0.4.0
compatibility or a documented embedding path. Before implementation it must
name its user, failure model, public contract, tests, and documentation. A
feature that cannot meet those conditions stays out of scope.

