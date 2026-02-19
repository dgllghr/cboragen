import { writeFile, mkdir } from "node:fs/promises";
import { dirname } from "node:path";
import { execAsync } from "./binary.js";

export interface GenerateOptions {
  schema: string;
  out: string;
  varintAsNumber?: boolean;
}

export interface GenerateResult {
  outputPath: string;
  source: string;
}

export async function generate(
  options: GenerateOptions,
): Promise<GenerateResult> {
  const args: string[] = [];
  if (options.varintAsNumber) args.push("--varint-as-number");
  args.push(options.schema);

  const source = await execAsync(args);

  await mkdir(dirname(options.out), { recursive: true });
  await writeFile(options.out, source);

  return { outputPath: options.out, source };
}
