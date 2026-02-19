import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

export interface SchemaConfig {
  schema: string;
  out: string;
  varintAsNumber?: boolean;
}

export interface CboragenConfig {
  schemas: SchemaConfig[];
}

const CONFIG_FILES = [
  "cboragen.config.ts",
  "cboragen.config.js",
  "cboragen.config.mjs",
];

export async function loadConfig(cwd?: string): Promise<CboragenConfig> {
  const dir = cwd ?? process.cwd();

  for (const name of CONFIG_FILES) {
    const file = resolve(dir, name);
    if (existsSync(file)) {
      const mod = await import(pathToFileURL(file).href);
      return mod.default as CboragenConfig;
    }
  }

  throw new Error(
    `No config file found. Create one of: ${CONFIG_FILES.join(", ")}`,
  );
}

export function defineConfig(config: CboragenConfig): CboragenConfig {
  return config;
}
