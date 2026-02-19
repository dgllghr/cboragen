import { watch as fsWatch } from "node:fs";
import { dirname, extname } from "node:path";
import { generate } from "./generate.js";
import type { CboragenConfig } from "./config.js";

export async function watch(config: CboragenConfig): Promise<void> {
  // Initial generate
  for (const schema of config.schemas) {
    await generate(schema);
  }

  const dirs = new Set(config.schemas.map((s) => dirname(s.schema)));

  for (const dir of dirs) {
    fsWatch(dir, (event, filename) => {
      if (!filename || extname(filename) !== ".cbg") return;

      const matching = config.schemas.filter(
        (s) => s.schema === `${dir}/${filename}` || s.schema.endsWith(filename),
      );

      for (const schema of matching) {
        generate(schema).then(
          (r) => console.log(`generated ${r.outputPath}`),
          (err) => console.error(`error generating ${schema.out}:`, err),
        );
      }
    });
  }

  console.log(`watching ${dirs.size} director${dirs.size === 1 ? "y" : "ies"} for .cbg changes...`);
}
