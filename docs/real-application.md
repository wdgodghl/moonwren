# Independent embedding application

`moonwren-json-pipeline` is a separate MoonBit project, not a package inside
the MoonWren source tree. Its `moon.mod` resolves
`wdgodghl/moonwren@0.9.3` from Mooncakes, which makes it evidence about the
published consumer experience rather than an internal example.

The application reads JSONL events, validates their primitive fields, and
passes them to a cached four-argument Wren function in one persistent VM. Wren
selects an action and invokes a MoonBit audit callback. The host emits JSONL
decisions and a summary after explicitly collecting and closing the VM.

Its acceptance suite proves:

- registry-only dependency resolution;
- persistent state across a batch;
- primitive arguments and return values across the embedding boundary;
- exactly one host audit call per accepted input record;
- bounded steps, call depth, output, modules, objects, and source text;
- automatic and explicit collection;
- stable failures for invalid JSON, invalid rule contracts, callback failures,
  and non-terminating rules.

Run `tools/check.ps1` in the companion checkout. The script checks and tests all
MoonBit targets, runs the native CLI against checked-in data, and compares its
complete output with `data/expected.jsonl`.
