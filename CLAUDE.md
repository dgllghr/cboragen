# cboragen

Schema-driven CBOR code generator. Users define types once in `.cbg` schema files and get type-safe encoders/decoders for multiple languages. Generated code produces valid RFC 8949 CBOR.

## Architecture

```
parser/                          Shared Zig library — lexer, parser, AST
languages/
  <lang>/
    codegen/                     Zig executable — reads .cbg, writes generated code to stdout
    runtime/                     Target-language library with CBOR encode/decode primitives
    tools/                       (optional) Build system integrations, CLI wrappers, plugins
SPEC.md                          Wire format specification
```

The **parser** is a reusable Zig module consumed by every language codegen. Each codegen is a standalone CLI binary that reads a `.cbg` file, resolves imports, and writes generated source code to stdout. Runtimes are separate libraries in the target language that provide low-level CBOR read/write primitives — generated code imports and calls into the runtime.

## Building

Requires Zig 0.15+. Each component builds independently:

```sh
cd parser && zig build                          # parser library + cboragen-parse CLI
cd languages/typescript/codegen && zig build     # cboragen-ts binary
cd languages/fsharp/codegen && zig build         # cboragen-fs binary
```

Release builds: `zig build -Doptimize=ReleaseFast`

## Testing

```sh
cd parser && zig build test                                  # parser unit + integration tests
cd languages/typescript/codegen/test && bun test             # TS roundtrip tests (encode/decode)
cd languages/typescript/codegen && zig build test             # TS codegen unit tests
cd languages/fsharp/codegen && zig build test                 # F# codegen unit tests
```

Test schemas live in `parser/src/testdata/` and `languages/typescript/codegen/test/`.

## Zig 0.15 API notes

- **ArrayList is UNMANAGED**: `std.ArrayList(T)` — pass allocator to every method (`.append(gpa, item)`, `.deinit(gpa)`, `.toOwnedSlice(gpa)`). Init: `var list: std.ArrayList(T) = .{};`
- **AutoHashMap is MANAGED**: `std.AutoHashMap(K, V).init(allocator)` — stores allocator, no allocator arg on methods.
- **File I/O**: `std.fs.File.stdout().deprecatedWriter()` to get a writer.
- **StaticStringMap**: `std.StaticStringMap(V).initComptime(.{...})`
- **Path dependencies**: `build.zig.zon` uses `.parser = .{ .path = "../../parser" }`, then `build.zig` uses `b.dependency("parser", .{}).module("parser")`

## Schema language

Types in `.cbg` files: `bool`, `u8`–`u64`, `i8`–`i64`, `uvarint`, `ivarint`, `f16`/`f32`/`f64`, `string`, `?T` (optional), `[]T` / `[N]T` / `[.field]T` (arrays), `struct`, `enum`, `union`. `[]u8` encodes as CBOR byte string. Imports: `ns = @import("path.cbg")` then `ns.Type`.

Field/variant numbers are stable wire identifiers — never reused, never renumbered.

## Parser public API

Defined in `parser/src/root.zig`:

- `parse(allocator, source) → ParseResult` — returns `{ schema: ?Ast.Schema, diagnostics, arena }`
- `renderDiagnostics(writer, source, filename, diagnostics, use_color)` — pretty-print errors
- AST types in `parser/src/ast.zig`: `Schema`, `TypeDef`, `TypeExpr` (union of all type forms), `StructDef`, `EnumDef`, `UnionDef`, `ArrayDef`, `OptionDef`
- Strings in the AST are slices into the source buffer (zero-copy). Caller must keep source alive.

## Adding a new language

### 1. Codegen binary (`languages/<lang>/codegen/`)

Create a Zig executable that depends on the parser module. The binary:

- Accepts a `.cbg` file path as argument
- Parses it (and resolves `@import` chains)
- Walks the AST and emits target-language code to **stdout**
- Reports parse errors to **stderr** and exits with code 1
- Supports `--varint-as-number` flag (map varints to native int instead of bigint/int64)

The codegen should emit:
- **Type definitions** for every schema type (structs, enums, unions, aliases)
- **Encode function** per type — takes a typed value, returns encoded bytes
- **Decode function** per type — takes encoded bytes, returns a typed value
- An import of the runtime library

Convention: the binary is named `cboragen-<lang>` (e.g., `cboragen-ts`, `cboragen-fs`).

#### Build setup

`build.zig.zon` declares a dependency on the parser:

```zon
.dependencies = .{
    .parser = .{ .path = "../../parser" },
},
```

`build.zig` wires up the module:

```zig
const parser_dep = b.dependency("parser", .{});
const parser_mod = parser_dep.module("parser");
// add parser_mod as import to your executable's root module
```

#### Code generation patterns

- **Structs** encode as CBOR arrays indexed by field rank. Gaps are null-filled. The encoder writes `WriteArrayHeader(max_rank + 1)` then each field in rank order.
- **Enums** encode as unsigned varints. Generate a match/switch on each variant.
- **Unions** use CBOR tags for payload variants, plain unsigned ints for unit variants. The decoder peeks at the major type to distinguish.
- **Optionals** (`?T`) are `union { 0 none, 1 some: T }` — byte `0x00` for none, tag 1 wrapping T for some.
- **Arrays** (`[]T`) encode as CBOR arrays. `[]u8` special-cases to CBOR byte string.
- **Inline types** (anonymous structs/enums/unions inside fields or payloads) need synthetic names derived from the parent type and field/variant name.
- **Recursive types** need special handling — F# uses `let rec ... and ...`, TypeScript uses function hoisting.
- **Imports** are resolved transitively. All imported types get codecs generated too.

#### Type mapping config (optional)

If the target language has common types that should replace schema types (e.g., `Uuid` → `System.Guid`), support a `--config` flag that reads a mapping file. See `languages/fsharp/codegen/src/config.zig` for an example (TOML format with `schema_type`, `fsharp_type`, `codec_module` fields).

### 2. Runtime library (`languages/<lang>/runtime/`)

A library in the target language that provides CBOR encode/decode primitives. Generated code imports this. The runtime should provide:

**Encoder:**
- Buffer management (growable byte buffer)
- `WriteBool`, `WriteNull`
- `WriteU8/16/32/64`, `WriteI8/16/32/64` — fixed-width, always full-width encoding
- `WriteUvarint`, `WriteIvarint` — minimal CBOR encoding
- `WriteF16/32/64`
- `WriteString`, `WriteBytes`
- `WriteArrayHeader(len)`, `WriteTagHeader(tag)`
- `Finish() → bytes` — return the encoded buffer

**Decoder:**
- `ReadBool`, `ReadU8/16/32/64`, `ReadI8/16/32/64`
- `ReadUvarint`, `ReadIvarint`
- `ReadF16/32/64`
- `ReadString`, `ReadBytes`
- `ReadArrayHeader() → int`
- `PeekByte()` — look-ahead without consuming
- `Skip()` — skip an arbitrary CBOR value (for forward compatibility)

Key: fixed-width integers always use their declared width on the wire. `u8` is always 2 bytes (`0x18` + 1 byte), never packed into the initial byte. This makes wire sizes constant per field.

### 3. Build system integration (`languages/<lang>/tools/`)

For languages with package managers and build tools, provide integration packages:

- **CLI wrapper** — discovers the platform-specific codegen binary, provides `generate` and `watch` commands
- **Config file** — `cboragen.config.<ext>` listing schemas and output paths
- **Bundler/build plugins** — transform `.cbg` imports on-the-fly (e.g., Vite plugin, Bun plugin)
- **Platform packages** — distribute the pre-built codegen binary per OS/arch as optional dependencies

See `languages/typescript/tools/` for the reference implementation: CLI (`cli.ts`), config loading (`config.ts`), binary resolution (`binary.ts`), and plugins (`plugins/bun.ts`, `plugins/vite.ts`).

### Checklist for a new language

- [ ] `languages/<lang>/codegen/build.zig` + `build.zig.zon` with parser dependency
- [ ] `languages/<lang>/codegen/src/main.zig` — CLI that reads `.cbg`, writes to stdout
- [ ] `languages/<lang>/codegen/src/<Lang>Gen.zig` — code generation logic
- [ ] `languages/<lang>/runtime/` — CBOR encode/decode library in target language
- [ ] Test schema + roundtrip tests (encode then decode, verify equality)
- [ ] (optional) `languages/<lang>/codegen/src/topo.zig` — topological sort if language requires declaration order
- [ ] (optional) `languages/<lang>/codegen/src/config.zig` — type mapping config
- [ ] (optional) `languages/<lang>/tools/` — package manager integration
