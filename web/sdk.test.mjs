import assert from "node:assert/strict";
import { MoonWren, evaluate, runText, version } from "./sdk.mjs";

assert.match(version, /^0\./);
assert.deepEqual(evaluate("System.print(40 + 2)\n"), {
  ok: true,
  value: "42",
  output: ["42"],
  diagnostics: [],
});
assert.match(runText("1 + 2\n"), /=> 3$/);
assert.equal(new MoonWren({ maxSteps: 1 }).evaluate("while (true) {}\n").ok, false);
assert.throws(() => evaluate(42), /string/);
console.log("MoonWren browser/Node SDK smoke tests passed");
