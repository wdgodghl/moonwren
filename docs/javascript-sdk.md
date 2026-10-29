# Browser and Node.js SDK

The `web/` directory is a dependency-free ES module package generated from the
same MoonBit runtime used by the native API. It works in current browsers and
Node.js without DOM shims.

```javascript
import { MoonWren } from "./web/sdk.mjs";

const runtime = new MoonWren({ maxSteps: 100_000 });
const result = runtime.evaluate("System.print(40 + 2)\n");
if (result.ok) console.log(result.output);
```

`evaluate` returns `{ ok, value, output, diagnostics }`; `runText` returns the
playground-style text rendering. Both accept a positive `maxSteps` limit.
TypeScript declarations are included in `sdk.d.ts`.

For untrusted or CPU-heavy scripts, use `createWorker()` or load `worker.mjs`
directly and send `{ id, source, options }`. Replies preserve `id` and contain
either `result` or an initialization/argument `error`. The Worker provides
process-level UI isolation while the VM's own execution limit remains the
deterministic resource boundary.

Run `tools/build-web-demo.ps1` after MoonBit changes, then execute
`node web/sdk.test.mjs`. CI performs both operations and also checks the native
runtime suite.
