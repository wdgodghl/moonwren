export interface RunOptions {
  maxSteps?: number;
}

export interface Diagnostic {
  message: string;
  rendered: string;
  line: number;
  column: number;
}

export interface EvaluationResult {
  ok: boolean;
  value: string | null;
  output: string[];
  diagnostics: Diagnostic[];
}

export const version: string;
export function evaluate(source: string, options?: RunOptions): EvaluationResult;
export function runText(source: string, options?: RunOptions): string;

export class MoonWren {
  constructor(defaults?: RunOptions);
  evaluate(source: string, options?: RunOptions): EvaluationResult;
  runText(source: string, options?: RunOptions): string;
}

export function createWorker(options?: { workerUrl?: string | URL }): Worker;
