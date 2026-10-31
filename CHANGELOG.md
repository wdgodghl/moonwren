# Changelog

## 0.9.3 - 2026-10-31

- add repository-external Mooncakes library and CLI acceptance;
- add Chromium, Firefox, and WebKit UI and Worker end-to-end tests plus a
  post-deployment Pages smoke test;
- test the MoonBit 0.10.16 floor and native CLI behavior on Windows and macOS;
- guard the public API, coverage baseline, repository hygiene, and release
  evidence in automated quality gates;
- run deterministic official-Wren differential fuzzing on a scheduled workflow;
- add validation, security, contribution, support, release, API stability, and
  Chinese quick-start documentation.

## 0.9.2 - 2026-10-30

- define a single Wren 0.4.0 embedding boundary with explicit supported,
  optional, experimental, security, and non-goal sections;
- add reproducible getting-started and testing guides, local documentation and
  release-metadata gates, and six native CLI acceptance cases;
- strengthen CI with all-target tests, CLI acceptance, documentation checks,
  consistent release metadata, and an uploaded official conformance report.

## 0.9.1 - 2026-10-30

- raise the minimum supported MoonBit compiler to 0.10.16 and verify the
  project and CI with MoonBit 0.10.18+6c83a7f62.

## 0.9.0 - 2026-10-29

- add context-aware foreign bindings that safely materialize nested List, Map,
  Range, byte String, and existing values inside the receiving VM;
- extend the capability-limited filesystem module with directory listing;
- make the hybrid bytecode backend accept classes, closures, modules, Fibers,
  and structured loop control through explicit, profiled semantic instructions;
- add named-module bytecode compilation plus loader/foreign-binding execution;
- add deterministic `MWDS1` deployment bundles with UTF-8 SHA-256, capability
  manifests, compiler-cache metadata, external signing hooks, and tamper checks;
- add a transport-neutral language service for diagnostics, symbols,
  completion, hover, definition, references, and validated rename edits;
- add a live-VM debug adapter session for breakpoints, step commands, visible
  variables, stop history, and termination;
- add a browser/Node ES module SDK with structured results, TypeScript types,
  execution limits, a Worker entrypoint, a runnable Node example, and CI smoke tests;
- add portable JSON, Base64, URL-component, SHA-256 name UUID, and
  scheduler-mediated HTTP modules with structured host request snapshots;
- add a bounded multi-tenant VM pool with opaque leases, tenant concurrency
  limits, isolated reset, use-count rotation, invalidation, and statistics;
- add deterministic scheduler record/replay with portable `MWR1` logs,
  workload binding, host-owned responses, and first-divergence diagnostics;
- add atomic multi-module hot reload with dependency ordering, cyclic state
  migration, host archive transforms, and full failure rollback;
- add bounded VM telemetry with subscribers, evaluator/resource/foreign/GC
  metrics, Prometheus exposition, and Chrome/Perfetto trace export;

## 0.8.0 - 2026-10-28

- add built-in Wren 0.4-compatible `random` and `meta` optional modules with
  isolated generator state, runtime compilation, evaluation, and module
  variable discovery;
- add a deterministic cooperative `VmScheduler` plus built-in `timer`, `task`,
  and `scheduler` modules for sleeps, child tasks, joins, races, cancellation,
  and host-delivered requests;
- add opt-in `moon/io` and `moon/env` host modules with per-VM capabilities,
  root-confined relative paths, independent read/write grants, UTF-8 byte
  limits, and explicit environment allowlists;

## 0.7.0 - 2026-10-27

- add generation-safe asynchronous host tasks that retain suspended Fibers and
  yielded request values across later VM calls and garbage collection;
- add a live interpreter debugger with source breakpoints, visible locals,
  call depth, step-into/over/out commands, and controlled termination;
- add integrity-checked `MWS1` state archives for selected module globals,
  preserving raw strings, shared List/Map identity, and cyclic graphs;
- document the production embedding patterns and add a runnable runtime-tools
  example plus focused regression tests.

## 0.6.0 - 2026-10-25

- add cached method handles, typed retained List/Map access, result-delivery
  callbacks, host probes, and safe-boundary automatic garbage collection;
- extend the bytecode backend with collections, subscripts, properties, core
  method calls, and a replay debugger with stepping and line breakpoints;
- add deterministic module archive encoding/validation and a portable polling
  file-module watcher;
- improve the browser playground with examples, keyboard execution, timing,
  share links, responsive styling, and an optional GitHub Pages workflow;
- expand differential fuzzing with semantic families, external corpora, failure
  preservation and shrinking, and run six-metric performance gates in CI.

## 0.5.0 - 2026-10-25

- expand explicit collection from foreign instances to the complete runtime
  heap and report aggregate reachable/reclaimed object statistics;
- add an optional procedural stack-bytecode compiler and VM with step limits,
  disassembly, dynamic profiling, and instruction traces;
- add checked host-value conversion, generation-safe host object tables, and a
  transactional incremental REPL API;
- add verified in-memory module bundles, change snapshots, and a root-confined
  filesystem module loader;
- add deterministic differential fuzzing, performance regression tooling, and
  a JavaScript browser playground build.

## 0.4.1 - 2026-10-25

- make the official Wren suite runner discover MoonBit native executables on
  both Windows and Linux CI hosts.

## 0.4.0 - 2026-10-25

- add a persistent VM that retains modules and script state across host calls;
- add bidirectional function, method, getter, and module-value access through
  generation-checked strong handles;
- add transactional module hot reload with primitive state migration and
  dependent-root rebuilding;
- add limits for output, modules, runtime objects, and source size alongside
  host cancellation, step budgets, and call-depth protection;
- add explicit reachability collection with deterministic finalization of
  unreachable host-backed instances.

## 0.3.0 - 2026-10-24

- complete the declared Wren 0.4.0 language and core-library compatibility
  endpoint;
- add resolver validation, runtime attributes, raw strings, cyclic imports,
  and cross-module Fiber suspension;
- align string byte behavior, numeric bitwise operations, diagnostics, and
  stress limits with the official Wren implementation;
- verify all 779 applicable official Wren 0.4.0 cases in CI, alongside the
  project test suite.

## 0.2.0 - 2026-10-23

- preserve valid and invalid UTF-8 bytes across String operations and ranges;
- resume Fibers through functions, constructors, methods, getters, operators,
  subscripts, and eager Sequence callbacks;
- parse Wren operator signatures, setters, trailing blocks, and interpolation;
- expose `System.clock`, `MapEntry`, `StringByteSequence`, and
  `StringCodePointSequence` core behavior;
- expand the differential suite with unmodified Wren 0.4.0 tests.

## 0.1.0 - 2026-10-22

- initial Mooncakes release of the MoonBit Wren interpreter and embedding API.
