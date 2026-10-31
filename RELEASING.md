# Releasing MoonWren

Mooncakes versions are immutable. A release is complete only after both the
source checkout and the published artifact have independent evidence.

## Prepare

1. Choose the version and update `moon.mod`, `CHANGELOG.md`, README installation
   commands, `docs/getting-started.md`, and the JavaScript SDK version together.
2. Review `pkg.generated.mbti`; document intentional API changes and update the
   API baseline.
3. Run the complete quality gate without skip switches.
4. Confirm the working tree contains no generated bundle, credential, personal
   data, local path, or unrelated change.

## Publish

```text
moon publish --dry-run
moon publish
moon view wdgodghl/moonwren
```

Verify the CLI identity is `wdgodghl` before the publish command. Never reuse a
login code as a password or commit authentication material.

## Verify the immutable artifact

Run `tools/check-published-package.ps1 -Version <version>` or trigger the
`Published Package Acceptance` workflow with that version. Do not create the
release tag until this external-consumer test passes.

## Record evidence

1. Create signed or annotated tag `v<version>` at the verified commit.
2. Create a GitHub Release using the matching CHANGELOG entry.
3. Add `docs/release-evidence/<version>.md` from the template.
4. Link the successful CI, published-package workflow, Mooncakes page, and
   public playground deployment.
5. Record compiler versions, test counts, official-suite accounting, browser
   matrix, coverage result, and known limitations.
