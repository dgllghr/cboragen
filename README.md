# cboragen

Schema-driven CBOR code generator. Define types once in `.cbg` schema files, get type-safe encoders and decoders for TypeScript, Rust, and F#.

Generated code produces valid [RFC 8949](https://www.rfc-editor.org/rfc/rfc8949.html) CBOR — any generic CBOR decoder can read the output. Schema knowledge enables fixed-layout encoding and single-branch validation, so generated serializers are fast and predictable.

## Schema language

Schemas use a compact definition syntax in `.cbg` files:

```
/// A user profile
User = struct {
    0 id: u64
    1 name: string
    2 email: ?string
    3 role: Role
    4 tags: []string
}

Role = enum {
    0 Viewer
    1 Editor
    2 Admin
}

/// API response envelope
Response = union {
    0 ok: User
    1 notFound
    2 error: string
}
```

### Types

| Category | Types |
|----------|-------|
| Boolean | `bool` |
| Integers | `u8` `u16` `u32` `u64` `i8` `i16` `i32` `i64` |
| Varints | `uvarint` `ivarint` (minimal CBOR encoding) |
| Floats | `f16` `f32` `f64` |
| Text | `string` (UTF-8) |
| Optional | `?T` |
| Arrays | `[]T` (variable), `[N]T` (fixed), `[.field]T` (external length) — `[]u8` encodes as CBOR byte string |
| Composites | `struct` `enum` `union` |
| Imports | `common = @import("common/types.cbg")` then `common.SomeType` |

Field numbers in structs are stable wire identifiers — new fields get new numbers, old numbers are never reused. This gives forward and backward compatibility for free.

### Wire format

See [SPEC.md](SPEC.md) for the full wire format specification.

Key properties:

- Structs encode as CBOR arrays indexed by field number
- Fixed-width integers always use their full width (constant wire size per field)
- Enums encode as unsigned varints
- Unions use CBOR tags for payload variants, plain integers for unit variants
- Optionals are sugar for `union { 0 none, 1 some: T }`

## TypeScript

### Install

```sh
npm install -D cboragen
npm install @cboragen/runtime
```

`cboragen` is a dev dependency (code generation tooling). `@cboragen/runtime` is a runtime dependency (imported by generated code).

### Generate

**CLI with explicit paths:**

```sh
npx cboragen generate schema.cbg -o src/schema.gen.ts
```

**Config file** (`cboragen.config.ts`):

```ts
import { defineConfig } from "cboragen";

export default defineConfig({
  schemas: [
    { schema: "schemas/user.cbg", out: "src/gen/user.ts" },
    { schema: "schemas/api.cbg", out: "src/gen/api.ts", varintAsNumber: true },
  ],
});
```

Then run:

```sh
npx cboragen generate
npx cboragen watch     # regenerate on file changes
```

### Use

Generated code exports TypeScript types and `encode`/`decode` functions for each schema definition:

```ts
import type { User } from "./schema.gen.ts";
import { encodeUser, decodeUser } from "./schema.gen.ts";

const user: User = {
  id: 1n,
  name: "Alice",
  email: "alice@example.com",
  role: Role.Admin,
  tags: ["staff"],
};

const bytes: Uint8Array = encodeUser(user);
const decoded: User = decodeUser(bytes);
```

### Bundler plugins

**Bun:**

```ts
// bunfig.toml or build script
import { cboragenPlugin } from "cboragen/bun";

Bun.build({
  plugins: [cboragenPlugin()],
  // ...
});
```

**Vite:**

```ts
// vite.config.ts
import { cboragenPlugin } from "cboragen/vite";

export default {
  plugins: [cboragenPlugin()],
};
```

Both plugins transform `.cbg` imports directly — no separate generate step needed.

### Options

| Option | Effect |
|--------|--------|
| `varintAsNumber` | Map `uvarint`/`ivarint` to `number` instead of `bigint` |

## Rust

The Rust code generator produces types with `impl` blocks for encoding and decoding, using the `cboragen-runtime` crate.

### Generate

```sh
cboragen-rs schema.cbg > src/schema.rs
```

### Use

Generated types have `encode`, `encode_with`, `decode`, and `decode_with` methods:

```rust
use cboragen_runtime::{Writer, Reader};

let user = User {
    id: 1,
    name: "Alice".to_string(),
    email: Some("alice@example.com".to_string()),
    role: Role::Admin,
    tags: vec!["staff".to_string()],
};

let bytes: Vec<u8> = user.encode();
let decoded: User = User::decode(&bytes);

// Or use a shared Writer/Reader for multiple values:
let mut w = Writer::new();
user.encode_with(&mut w);
let data = w.finish();
```

The runtime crate is at `languages/rust/runtime/`. Add it as a dependency:

```toml
[dependencies]
cboragen-runtime = { path = "path/to/cboragen/languages/rust/runtime" }
```

## F#

The F# code generator produces modules that use `Cboragen.Cbor` for encoding and decoding.

```sh
cd languages/fsharp/codegen
zig build
zig build run -- --namespace MyApp --config mapping.json schema.cbg > Schema.fs
```

The F# runtime library is at `languages/fsharp/runtime/Cbor.fs`.

## Project structure

```
parser/                          Zig library — schema parser (shared across all targets)
languages/
  typescript/
    codegen/                     Zig executable — reads .cbg, emits TypeScript
    runtime/                     @cboragen/runtime npm package
    tools/                       cboragen npm package (CLI, config, bundler plugins)
    benchmark/                   Browser-based encode/decode benchmarks
  rust/
    codegen/                     Zig executable — reads .cbg, emits Rust
    runtime/                     cboragen-runtime Rust crate
  fsharp/
    codegen/                     Zig executable — reads .cbg, emits F#
    runtime/                     Cboragen.Cbor F# module
SPEC.md                          Wire format specification
```

## Building from source

Requires [Zig 0.15+](https://ziglang.org/download/).

```sh
# Parser
cd parser && zig build

# TypeScript code generator
cd languages/typescript/codegen && zig build

# Rust code generator
cd languages/rust/codegen && zig build

# F# code generator
cd languages/fsharp/codegen && zig build
```

Run the TypeScript generator directly:

```sh
cd languages/typescript/codegen
zig build run -- path/to/schema.cbg > output.ts
```

### Tests

```sh
# Parser tests
cd parser && zig build test

# TypeScript roundtrip tests (requires Bun)
cd languages/typescript/codegen/test
bun test
```
