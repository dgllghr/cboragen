import { exec } from "../binary.js";

interface VitePlugin {
  name: string;
  transform(code: string, id: string): { code: string; map: null } | undefined;
}

interface CboragenPluginOptions {
  varintAsNumber?: boolean;
}

export function cboragenPlugin(opts?: CboragenPluginOptions): VitePlugin {
  return {
    name: "cboragen",
    transform(_code, id) {
      if (!id.endsWith(".cbg")) return;

      const args: string[] = [];
      if (opts?.varintAsNumber) args.push("--varint-as-number");
      args.push(id);

      const code = exec(args);
      return { code, map: null };
    },
  };
}
