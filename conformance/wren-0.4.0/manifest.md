# Official comparison manifest

- Reference implementation: `wren-lang/wren`
- Release: `0.4.0`
- Commit: `4a18fc489f9ea3d253b20dd40f02c6097a8e2508`
- Compared channel: standard output, one line per `System.print`

| Input | Official Wren 0.4.0 output | MoonWren expectation |
| --- | --- | --- |
| `string-byte-offsets.wren` | `string-byte-offsets.out` | exact match |
| `fiber-callback-suspension.wren` | `fiber-callback-suspension.out` | exact match |

The `.out` files record the official 0.4.0 results, not values generated from
MoonWren. `tools/verify-official-wren.ps1` checks them against a supplied
official 0.4.0 CLI. CI runs MoonWren against the same inputs and fails on any
output difference.
