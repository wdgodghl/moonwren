# Public API stability

MoonWren is pre-1.0, but supported entry points do not change accidentally.
This document assigns a stability level to every user-facing surface. The
generated root-package interface is guarded by `api/public-api.sha256`; a
change requires review, documentation, a changelog entry, and an intentional
baseline update.

## Stability levels

| Level | Promise |
| --- | --- |
| Supported | Release-gated behavior. Incompatible changes require an explicit migration note and version change. |
| Experimental | Tested and useful, but signatures may change between pre-1.0 minor releases. |
| Internal | No compatibility promise. Not a documented consumer entry point. |

## Supported surfaces

| Surface | Main API | Targets | Failure contract |
| --- | --- | --- | --- |
| One-shot evaluation | `run`, `run_with_limit`, `run_with_loader`, `run_with_foreign_bindings`, `run_modules` | wasm, wasm-gc, JavaScript, native | `ProgramCompleted` or structured `ProgramFailed` |
| Persistent embedding | `Vm`, `VmLimits`, handles, loader and foreign bindings | wasm, wasm-gc, JavaScript, native | Structured diagnostics; explicit handle and VM lifetime |
| Root-confined loading | package `wdgodghl/moonwren/loaders` | native | Structured load failure; caller controls the root |
| Capability host modules | package `wdgodghl/moonwren/host` | supported package targets | Explicit `HostAccessPolicy` and structured host failure |
| Native CLI | package `cmd/main` | native | Documented stdout/stderr and exit categories |
| JavaScript SDK | `evaluate`, `runText`, `MoonWren`, `createWorker` | current module-capable browsers and Node.js | Result object or JavaScript type/worker error |

Observable results, output, diagnostics, exit categories, resource-limit
failures, callback order, and documented lifetime rules form the contract.
Object layout, allocation strategy, internal continuations, and registry
indexes do not.

## Experimental surfaces

Bytecode tooling, language/debug service cores, scheduling helpers, deployment
bundles, replay, telemetry exporters, VM pools, snapshots, and hot reload are
experimental. Their safety properties and tests are maintained, but they do
not expand the Wren 0.4.0 compatibility claim and may be refined before 1.0.

## Reviewing an API change

1. Run `moon info` and inspect `pkg.generated.mbti`.
2. Decide whether the change belongs to a supported or experimental surface.
3. Add or update contract tests and user documentation.
4. Record the compatibility effect and migration in `CHANGELOG.md`.
5. Run `tools/check-public-api.ps1 -Update` only after that review.

The hash is a tripwire, not a substitute for reviewing the readable generated
interface.
