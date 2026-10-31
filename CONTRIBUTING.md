# Contributing

MoonWren accepts changes that strengthen Wren 0.4.0 compatibility or one of the
documented embedding paths. A proposal must identify its user, public contract,
failure model, tests, and documentation. Features outside that rule should not
be added merely to increase surface area.

## Before changing code

1. Read [`docs/project-boundary.md`](docs/project-boundary.md).
2. Reduce correctness bugs to a small Wren input.
3. Compare source-visible behavior with official Wren 0.4.0 when applicable.
4. Avoid committing credentials, personal data, local paths, generated browser
   bundles, build directories, or chat transcripts.

## Required checks

```text
moon fmt
moon check --target all --deny-warn
moon test --target all --deny-warn
./tools/check-quality.ps1 -WrenRoot C:/path/to/wren-0.4.0
```

Changes to a supported public API require a migration note, tests, documentation,
and an intentional update through `tools/check-public-api.ps1 -Update`.

Commits should describe one coherent change. Pull requests should state the
contract affected, exact verification commands, and any intentionally excluded
behavior.
