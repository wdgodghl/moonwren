# Release evidence

Create one file per released version after the immutable Mooncakes artifact has
passed external-consumer acceptance. Do not copy claims from an earlier version.

```markdown
# MoonWren <version> release evidence

- Commit: `<full SHA>`
- Tag: `v<version>`
- Mooncakes: `wdgodghl/moonwren@<version>`
- MoonBit: `<moon and moonc versions>`
- CI: `<URL and conclusion>`
- Published-package acceptance: `<URL and conclusion>`
- Playground deployment: `<URL and conclusion>`
- MoonBit tests: `<count per target>`
- Official Wren suite: `<passed>/<failed>/<upstream skipped>`
- Browser matrix: `<engines>`
- Coverage: `<covered>/<total and percentage>`
- Known limitations: `<links to project boundary and release-specific notes>`
```
