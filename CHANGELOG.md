# Changelog

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
