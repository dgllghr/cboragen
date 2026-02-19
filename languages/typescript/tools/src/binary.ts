import { execFileSync, execFile } from "node:child_process";
import { createRequire } from "node:module";

const PLATFORMS: Record<string, Record<string, string>> = {
  darwin: { arm64: "@cboragen/darwin-arm64", x64: "@cboragen/darwin-x64" },
  linux: { x64: "@cboragen/linux-x64" },
};

export function findBinary(): string {
  const env = process.env.CBORAGEN_BIN;
  if (env) return env;

  const platform = PLATFORMS[process.platform]?.[process.arch];
  if (!platform) {
    throw new Error(
      `Unsupported platform: ${process.platform}-${process.arch}`,
    );
  }

  const require = createRequire(import.meta.url);
  return require.resolve(`${platform}/bin/cboragen-ts`);
}

export function exec(args: string[]): string {
  return execFileSync(findBinary(), args, { encoding: "utf-8" });
}

export function execAsync(args: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile(findBinary(), args, { encoding: "utf-8" }, (err, stdout) => {
      if (err) reject(err);
      else resolve(stdout);
    });
  });
}
