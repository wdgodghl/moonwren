import { MoonWren } from "../web/sdk.mjs";

const runtime = new MoonWren({ maxSteps: 100_000 });
const source = [
  "var values = [1, 2, 3]",
  "System.print(values.reduce { |sum, value| sum + value })",
  "",
].join("\n");
const result = runtime.evaluate(source);

if (!result.ok) {
  console.error(result.diagnostics.map((item) => item.rendered).join("\n"));
  process.exitCode = 1;
} else {
  console.log(result.output.join("\n"));
}
