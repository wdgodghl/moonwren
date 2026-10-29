import { evaluate } from "./sdk.mjs";

self.addEventListener("message", (event) => {
  const { id, source, options } = event.data ?? {};
  try {
    self.postMessage({ id, result: evaluate(source, options) });
  } catch (error) {
    self.postMessage({
      id,
      error: error instanceof Error ? error.message : String(error),
    });
  }
});
