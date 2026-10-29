import "./moonwren.js";

const core = globalThis.MoonWrenCore;
if (!core) {
  throw new Error("MoonWren core failed to initialize");
}

export const version = core.version;

export function evaluate(source, options = {}) {
  if (typeof source !== "string") {
    throw new TypeError("MoonWren source must be a string");
  }
  return core.evaluate(source, options);
}

export function runText(source, options = {}) {
  if (typeof source !== "string") {
    throw new TypeError("MoonWren source must be a string");
  }
  return core.runText(source, options);
}

export class MoonWren {
  constructor(defaults = {}) {
    this.defaults = { ...defaults };
  }

  evaluate(source, options = {}) {
    return evaluate(source, { ...this.defaults, ...options });
  }

  runText(source, options = {}) {
    return runText(source, { ...this.defaults, ...options });
  }
}

export function createWorker(options = {}) {
  const workerUrl = options.workerUrl ?? new URL("./worker.mjs", import.meta.url);
  return new Worker(workerUrl, { type: "module", name: "moonwren" });
}
