import { exec } from "../binary.js";

interface BunPlugin {
  name: string;
  setup(build: { onLoad(opts: { filter: RegExp }, cb: (args: { path: string }) => { contents: string; loader: string }): void }): void;
}

interface CboragenPluginOptions {
  varintAsNumber?: boolean;
}

export function cboragenPlugin(opts?: CboragenPluginOptions): BunPlugin {
  return {
    name: "cboragen",
    setup(build) {
      build.onLoad({ filter: /\.cbg$/ }, (args) => {
        const cliArgs: string[] = [];
        if (opts?.varintAsNumber) cliArgs.push("--varint-as-number");
        cliArgs.push(args.path);

        const contents = exec(cliArgs);
        return { contents, loader: "ts" };
      });
    },
  };
}
