#!/usr/bin/env node

import { resolve } from "node:path";
import { generate } from "./generate.js";
import { loadConfig } from "./config.js";
import { watch as runWatch } from "./watch.js";

const args = process.argv.slice(2);
const command = args[0];

function printHelp() {
  console.log(`Usage: cboragen <command> [options]

Commands:
  generate [schema.cbg -o out.ts]   Generate TypeScript from schema(s)
  watch                             Watch schema files and regenerate on change

Options:
  --varint-as-number                Map uvarint/ivarint to number instead of bigint
  -o, --out <file>                  Output file path
  -h, --help                        Show this help`);
}

async function runGenerate() {
  const schemaArg = args[1];

  // If a positional schema file is given, use CLI args instead of config
  if (schemaArg && !schemaArg.startsWith("-")) {
    let out: string | undefined;
    let varintAsNumber = false;

    for (let i = 2; i < args.length; i++) {
      if (args[i] === "-o" || args[i] === "--out") {
        out = args[++i];
      } else if (args[i] === "--varint-as-number") {
        varintAsNumber = true;
      }
    }

    if (!out) {
      console.error("error: -o <output> is required");
      process.exit(1);
    }

    const result = await generate({
      schema: resolve(schemaArg),
      out: resolve(out),
      varintAsNumber,
    });
    console.log(`generated ${result.outputPath}`);
    return;
  }

  // Otherwise, load config
  const config = await loadConfig();
  for (const schema of config.schemas) {
    const result = await generate({
      schema: resolve(schema.schema),
      out: resolve(schema.out),
      varintAsNumber: schema.varintAsNumber,
    });
    console.log(`generated ${result.outputPath}`);
  }
}

async function main() {
  if (!command || command === "-h" || command === "--help") {
    printHelp();
    return;
  }

  if (command === "generate") {
    await runGenerate();
  } else if (command === "watch") {
    const config = await loadConfig();
    await runWatch(config);
  } else {
    console.error(`unknown command: ${command}`);
    printHelp();
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err.message ?? err);
  process.exit(1);
});
