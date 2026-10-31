# MoonWren validation guide

This is the shortest independent path for release reviewers. It deliberately
starts from public artifacts instead of trusting the repository build.

## 1. Confirm the scope

MoonWren targets Wren 0.4.0 source-language and embedding behavior. Read
[`docs/project-boundary.md`](docs/project-boundary.md) for supported paths,
experimental surfaces, non-goals, and the security boundary.

## 2. Confirm the published artifact

```text
moon view wdgodghl/moonwren
./tools/check-published-package.ps1 -Version 0.9.4
```

The second command creates an unrelated project under the operating system's
temporary directory, resolves the immutable Mooncakes version, checks all
targets, exercises one-shot and persistent APIs, installs the native CLI, and
compares exact output. It does not use this checkout as a dependency.

## 3. Run the repository quality gate

```text
./tools/check-quality.ps1 -WrenRoot C:/path/to/wren-0.4.0
```

The command verifies formatting, static checks, public API stability, repository
hygiene, 331 MoonBit tests on four targets, native process behavior, real
browsers, coverage, performance smoke tests, differential fixtures, and the
official Wren suite.

The same gate checks the machine-readable compatibility contract and runs the
short persistent-VM resource soak. The scheduled `Persistent VM Soak` workflow
runs the 10,000-operation profile, while `Differential Fuzzing` runs every day
with retained seed summaries and minimized mismatch artifacts.

## 4. Confirm a real embedding application

The separate `moonwren-json-pipeline` project depends on
`wdgodghl/moonwren@0.9.4` through Mooncakes and has no source-tree dependency.
From that checkout run:

```text
./tools/check.ps1
```

It checks all MoonBit targets and executes a JSONL rules pipeline through a
persistent VM, cached method binding, host audit callback, GC policy, and
resource-limit failure case. The behavior and proof obligations are documented
in [`docs/real-application.md`](docs/real-application.md).
From the MoonWren checkout, the equivalent command is
`./tools/check-real-application.ps1` when both projects are adjacent.

## 5. Inspect compatibility evidence

- [`docs/wren-0.4-conformance.md`](docs/wren-0.4-conformance.md) defines done.
- [`docs/compatibility.md`](docs/compatibility.md) records the implemented matrix.
- CI uploads the official-suite JSON report, browser traces on failure, and the
  coverage summary.

The expected official-suite result is 779 passed, 0 failed, and 22 files marked
`skip` or `nontest` by upstream.

## 6. Exercise the browser path

After GitHub Pages is enabled, the `Playground Pages` workflow deploys the
static playground and tests the public URL with Chromium. The main CI also runs
the complete local playground and Worker contract in Chromium, Firefox, and
WebKit.

## 7. Check release identity

The version in Mooncakes, `moon.mod`, the JavaScript SDK, README installation
commands, CHANGELOG, Git tag, and GitHub Release must agree. The release process
and required evidence are in [`RELEASING.md`](RELEASING.md).
