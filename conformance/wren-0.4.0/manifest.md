# Official comparison manifest

- Reference implementation: `wren-lang/wren`
- Release: `0.4.0`
- Commit: `4a18fc489f9ea3d253b20dd40f4cdad0d6bb40eb`
- Compared channel: standard output, one line per `System.print`

| Input | Official Wren 0.4.0 output | MoonWren expectation |
| --- | --- | --- |
| `string-byte-offsets.wren` | `string-byte-offsets.out` | exact match |
| `fiber-callback-suspension.wren` | `fiber-callback-suspension.out` | exact match |
| `official-interpolation.wren` | `official-interpolation.out` | exact match; upstream `test/language/interpolation/interpolation.wren` |
| `official-sequence-all.wren` | `official-sequence-all.out` | exact match; upstream `test/core/sequence/all.wren` |
| `official-setter-instance.wren` | `official-setter-instance.out` | exact match; upstream `test/language/setter/instance.wren` |
| `official-setter-result.wren` | `official-setter-result.out` | exact match; upstream `test/language/setter/result.wren` |
| `official-string-bytes.wren` | `official-string-bytes.out` | exact match; upstream `test/core/string/bytes.wren` |

Files prefixed `official-` are unmodified upstream Wren 0.4.0 tests, renamed so
the flat fixture directory retains their category. The `.out` files record the
official 0.4.0 results, not values generated from MoonWren.
`tools/verify-official-wren.ps1` checks them against a supplied official 0.4.0
CLI. CI runs MoonWren against the same inputs and fails on any output difference.
