# Editor and debugger integration

`LanguageDocument` and `LanguageServer` form a transport-neutral language
service suitable for an LSP frontend. Opening or replacing a document runs the
real lexer, parser, and resolver, then builds an index used by:

- syntax and semantic diagnostics with source names and precise spans;
- document symbols for variables, classes, methods, parameters, and imports;
- Wren keyword/core-class plus document-symbol completion;
- hover descriptions, definition lookup, references, and validated rename
  edits.

Offsets are UTF-16 string offsets, matching MoonBit strings and the LSP
position model after a frontend converts line/character pairs. The current
single-document index intentionally does not guess cross-module scope; a
frontend can combine per-document locations while resolving imports with the
same module loader as the VM.

`DebugAdapterSession` is the corresponding transport-neutral DAP core. It
maintains source breakpoints, queues continue/step-into/step-over/step-out or
terminate commands, attaches to a persistent `Vm`, and retains every real
`DebugSnapshot` with visible variables and call depth. A CLI, editor extension,
or WebSocket bridge only needs to translate protocol messages to these typed
operations; execution semantics stay in the tested runtime rather than being
duplicated in the adapter.
