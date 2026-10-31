# Testing and release evidence

MoonWren treats tests as evidence for a specific contract, not as a raw count.
Every layer below answers a different question and is required before release.

## Test layers

| Layer | Command | Evidence |
| --- | --- | --- |
| Formatting and static checks | `moon fmt --check`; `moon check --target all --deny-warn` | Source is accepted without warnings on every supported MoonBit target. |
| MoonBit tests | `moon test --target all --deny-warn` | 331 behavioral tests pass independently on wasm, wasm-gc, JavaScript, and native, including persistent-VM combination invariants. |
| Native CLI acceptance | `tools/check-cli-acceptance.ps1` | Real process output, imports, diagnostics, and exit codes match the documented CLI contract. |
| Browser/Node smoke | `tools/build-web-demo.ps1`; `node web/sdk.test.mjs` | The generated JavaScript artifact can be consumed by Node.js. |
| Real browser acceptance | `tools/check-browser-e2e.ps1` | Chromium, Firefox, and WebKit execute the UI, diagnostics, sharing, examples, and module Worker contract. |
| Published artifact | `tools/check-published-package.ps1 -Version <version>` | A repository-external project resolves the immutable Mooncakes package and exercises library, persistent VM, and installed CLI paths. |
| Checked-in differential cases | `tools/check-conformance.ps1` | High-risk String and Fiber inputs match outputs captured from official Wren 0.4.0. |
| Scheduled differential fuzzing | `tools/fuzz-differential.ps1` | Daily deterministic generated and corpus inputs match the official Wren CLI; seeds, time budgets, summaries, and minimized failures are retained as CI artifacts. |
| Persistent VM soak | `tools/check-vm-soak.ps1` | 10,000 calls preserve cumulative state while temporary collections and foreign objects are reclaimed within a fixed reachable-object bound. CI uses `-Quick`; the daily workflow runs the full profile. |
| Independent application | run `tools/check.ps1` in `moonwren-json-pipeline` | A separate project resolves MoonWren only from Mooncakes and processes JSONL through a persistent, bounded VM with host callbacks. |
| Official upstream suite | `tools/check-official-suite.ps1 -WrenRoot <wren-0.4.0>` | All 779 adopted `language` and `core` cases pass; 22 upstream `skip`/`nontest` files are reported separately. |
| Performance smoke | `tools/check-performance.ps1 -SmokeOnly` | Six benchmark metrics execute and broad AST/bytecode sanity ratios hold. |
| Documentation and release metadata | `tools/check-doc-links.ps1`; `tools/check-release-metadata.ps1` | Local links resolve and the package, SDK, README, changelog, compiler floor, and CI pins agree. |
| Public API and repository hygiene | `tools/check-public-api.ps1`; `tools/check-repository-hygiene.ps1` | Public symbols cannot drift silently and tracked files exclude common credentials, private paths, and transcripts. |
| Coverage baseline | `tools/check-coverage.ps1` | The suite exercises at least 70% of all instrumented points and at least 74% of the lexer/parser/resolver/evaluator/interpreter/embedding execution core. |

No layer substitutes for another. Unit tests do not prove the executable can be
used, and the official suite does not prove MoonWren-specific embedding APIs.
Performance smoke checks detect broken measurements and extreme regressions;
they are not a cross-machine benchmark promise.

## One-command local gate

From the repository root with an official Wren 0.4.0 checkout available:

```powershell
./tools/check-quality.ps1 -WrenRoot C:/path/to/wren-0.4.0
```

The command verifies the installed compiler floor, then runs every layer in the
table. Use `-SkipOfficialSuite` only for an offline edit cycle. A release review
must run without that switch, and CI independently checks out the pinned Wren
commit. `-SkipBrowserE2E` and `-SkipCoverage` are likewise edit-cycle options,
not release-review options.

## Official-suite accounting

`check-official-suite.ps1` reads expectations embedded in upstream tests. It
compares output, success/compile/runtime exit categories, and expected
diagnostic lines. Files marked `skip` or `nontest` by upstream are counted as
skipped rather than silently removed. A JSON report can be retained with
`-ReportPath`; CI uploads that report for inspection.

The baseline is fixed to Wren 0.4.0 commit
`4a18fc489f9ea3d253b20dd40f4cdad0d6bb40eb`. Updating that commit is a scope
change, not routine dependency maintenance.

## Adding a regression

1. Reduce the failure to the smallest Wren source that preserves the behavior.
2. Confirm the expected result with the official Wren 0.4.0 CLI.
3. Add a focused MoonBit unit test for the responsible component.
4. Add a differential fixture when output, byte semantics, Fiber suspension, or
   diagnostic classification is externally visible.
5. Document any intentional exclusion in `project-boundary.md` and
   `wren-0.4-conformance.md`; never convert an unexplained failure into a skip.

## Release checklist

- working tree contains only intended changes;
- compiler is at least 0.10.16 and matches the CI pin used for verification;
- CI rejects a declared or installed compiler below 0.10.16 and runs the full
  suite with the reproducibly pinned release toolchain;
- the full local gate and GitHub CI pass;
- package version, SDK version, README install command, and changelog agree;
- compatibility counts and explicit exclusions remain accurate;
- examples contain expected output and can be reproduced from documented
  commands;
- no credentials, personal data, local absolute paths, generated binaries, or
  chat transcripts are tracked;
- Mooncakes dry-run succeeds before the immutable version is published.
- after publication, the repository-external library and CLI acceptance passes;
- a matching annotated Git tag, GitHub Release, and versioned release-evidence
  file link the commit, Mooncakes package, CI, browser deployment, and known
  limitations.

