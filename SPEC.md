# cboragen Wire Format Specification

cboragen encodes schema-typed data as valid CBOR (RFC 8949). Any generic CBOR decoder
can read the output. Generated serialization/deserialization code exploits schema
knowledge for efficient fixed-layout encoding and single-branch validation.

## CBOR Primer

A CBOR data item begins with an **initial byte** divided into two fields:

```
  ┌───────────┬────────────────┐
  │ major (3) │ additional (5) │
  └───────────┴────────────────┘
```

**Major types:**

| Major | Meaning            |
|------:|--------------------|
| 0     | Unsigned integer   |
| 1     | Negative integer   |
| 2     | Byte string        |
| 3     | Text string (UTF-8)|
| 4     | Array              |
| 5     | Map                |
| 6     | Tag                |
| 7     | Simple / float     |

**Additional info (AI) encodes the argument:**

| AI    | Meaning                              |
|------:|--------------------------------------|
| 0–23  | Value is the AI itself               |
| 24    | 1-byte unsigned integer follows      |
| 25    | 2-byte unsigned integer follows      |
| 26    | 4-byte unsigned integer follows      |
| 27    | 8-byte unsigned integer follows      |
| 31    | Indefinite length (majors 2–5) / break (major 7) |

All multi-byte integers are big-endian.

## Type Encoding

### Scalar Types

| Schema Type | CBOR Encoding               | Initial Byte(s) | Wire Size |
|-------------|-----------------------------|------------------|-----------|
| `bool`      | Simple value false/true     | `0xf4` / `0xf5`  | 1         |
| `u8`        | Major 0, AI 24, 1 byte      | `0x18`           | 2         |
| `u16`       | Major 0, AI 25, 2 bytes     | `0x19`           | 3         |
| `u32`       | Major 0, AI 26, 4 bytes     | `0x1a`           | 5         |
| `u64`       | Major 0, AI 27, 8 bytes     | `0x1b`           | 9         |
| `i8`        | Major 0 or 1, AI 24, 1 byte | `0x18` or `0x38` | 2         |
| `i16`       | Major 0 or 1, AI 25, 2 bytes| `0x19` or `0x39` | 3         |
| `i32`       | Major 0 or 1, AI 26, 4 bytes| `0x1a` or `0x3a` | 5         |
| `i64`       | Major 0 or 1, AI 27, 8 bytes| `0x1b` or `0x3b` | 9         |
| `uvarint`   | Major 0, minimal encoding   | varies           | 1–9       |
| `ivarint`   | Major 0 or 1, minimal       | varies           | 1–9       |
| `f16`       | Major 7, AI 25, 2 bytes     | `0xf9`           | 3         |
| `f32`       | Major 7, AI 26, 4 bytes     | `0xfa`           | 5         |
| `f64`       | Major 7, AI 27, 8 bytes     | `0xfb`           | 9         |
| `string`    | Major 3, length-prefixed UTF-8 | `0x60`–`0x7b` | 1–9 + len |
| `bytes`     | Major 2, length-prefixed    | `0x40`–`0x5b`   | 1–9 + len |

**Key rules:**

- **Fixed-width integers always use their full width.** A `u8` value `5` encodes as
  `0x18 0x05` (2 bytes), never as `0x05` (1 byte). This makes the wire size of every
  fixed-width field constant regardless of value.
- **Signed integers** use major 0 for non-negative values, major 1 for negative values.
  Major 1 encodes the value -1-n, following CBOR convention: -1 → `0x38 0x00`,
  -128 → `0x38 0x7f`.
- **Varints** use standard CBOR minimal encoding — values 0–23 pack into the initial
  byte, larger values promote to 1/2/4/8-byte arguments.
- **Floats always use their specified width.** An `f32` is never compressed to `f16`,
  even if the value would fit.

### Structs

Encoded as a **CBOR definite-length array** (major type 4). Field numbers are array
indices.

- Gaps between field numbers are filled with CBOR null (`0xf6`).
- Trailing null values MAY be omitted (the array length is shortened accordingly).
- The decoder uses the encoded array length to determine which fields are present.
- Fields beyond what the decoder recognizes are skipped.

**Example:** `struct { 0 x: u32, 2 y: bool }` with x=1, y=true:

```
83          -- array(3)
  1a 00000001  -- u32(1)      [field 0: x]
  f6           -- null         [field 1: gap]
  f5           -- true         [field 2: y]
```

With trailing null omission — if only x is set:

```
81          -- array(1)
  1a 00000001  -- u32(1)      [field 0: x]
```

### Enums

Encoded as an **unsigned varint** (major type 0, minimal encoding). The value is the
variant's numeric tag from the schema.

**Example:** `enum { 0 Read, 1 Write, 2 Admin }` with value `Write`:

```
01          -- unsigned(1)
```

### Unions

Two encodings depending on whether the variant carries a payload:

- **With payload:** CBOR tag (major type 6) where tag number = variant's schema tag,
  wrapping the encoded payload.
- **Without payload:** Unsigned integer (major type 0) with the variant's schema tag
  value.

The decoder knows from the schema whether each variant has a payload, so there is no
ambiguity.

**Example:** `union { 0 none, 1 ok: string, 2 err: u32 }`:

- `none` → `0x00` (unsigned integer 0)
- `ok("hi")` → `0xc1 0x62 0x68 0x69` (tag 1 wrapping string "hi")
- `err(42)` → `0xc2 0x1a 0x0000002a` (tag 2 wrapping u32 42)

### Optionals

`?T` is sugar for `union { 0 none, 1 some: T }`:

- `none` → unsigned integer 0 (one byte: `0x00`)
- `some(value)` → CBOR tag 1 wrapping the encoded value (`0xc1` + encoded T)

Nested optionals (`??T`) nest naturally:

- `some(none)` → `0xc1 0x00`
- `some(some(v))` → `0xc1 0xc1` + encoded v
- `none` → `0x00`

### Arrays

**Variable-length `[]T`:** Definite-length CBOR array (major type 4). Length prefix
followed by N encoded elements.

```
[]u8 with values [10, 20]:
82          -- array(2)
  18 0a     -- u8(10)
  18 14     -- u8(20)
```

**Fixed-length `[N]T`:** Definite-length CBOR array (major type 4) with length N. The
decoder verifies the length matches.

```
[3]bool with values [true, false, true]:
83          -- array(3)
  f5        -- true
  f4        -- false
  f5        -- true
```

**External-length `[.field]T`:** Indefinite-length CBOR array (initial byte `0x9f`).
Elements followed by break code (`0xff`). The decoder uses the previously-decoded
field value to know the expected element count, and validates the break code at the end.

```
struct { 0 count: u8, 1 items: [.count]u32 }
with count=2, items=[1, 2]:

82          -- array(2)          [struct]
  18 02     -- u8(2)             [field 0: count]
  9f        -- array(*)          [field 1: items, indefinite]
    1a 00000001 -- u32(1)
    1a 00000002 -- u32(2)
  ff        -- break
```

## Deserialization Strategy

Since types are known from the schema, generated deserializers **validate** the CBOR
initial byte rather than switching on it. This turns type dispatch into a single
equality check per field.

| Type          | Validation                                              |
|---------------|---------------------------------------------------------|
| `u32`         | `assert(byte == 0x1a)`, read 4 bytes                    |
| `i32`         | `assert(byte == 0x1a \|\| byte == 0x3a)`, read 4 bytes  |
| `f64`         | `assert(byte == 0xfb)`, read 8 bytes                    |
| `bool`        | `assert(byte == 0xf4 \|\| byte == 0xf5)`               |
| `[3]T`        | `assert(byte == 0x83)`, decode 3 elements               |
| `?T`          | `byte == 0x00` → none; `byte == 0xc1` → decode T       |
| `string`      | Check major type 3, switch on AI to decode length       |
| `bytes`       | Check major type 2, switch on AI to decode length       |
| `[]T`         | Check major type 4, switch on AI to decode length       |
| `[.field]T`   | `assert(byte == 0x9f)`, decode N elements, `assert(byte == 0xff)` |
| Union         | Switch on tag number or integer value per schema        |
| Enum          | Decode varint, validate against known variants          |

For variable-length types (strings, bytes, variable arrays), the deserializer checks
the major type then switches on the additional info to determine argument size:

```
major_ok = (byte >> 5) == expected_major;
ai = byte & 0x1f;
switch (ai) {
    0..23 => length = ai,
    24    => length = read(1),
    25    => length = read(2),
    26    => length = read(4),
    27    => length = read(8),
    else  => error,
}
```

## Forward and Backward Compatibility

**Structs:** Field numbers are stable identifiers. New fields get new (higher)
numbers. Old decoders see a longer array than expected and ignore trailing fields. New
decoders see a shorter array than expected and treat missing trailing fields as absent.

**Unions:** New variants can be added with new tag numbers. Old decoders encountering
unknown tag numbers should treat the value as unrecognized.

**Enums:** New variants can be added. Old decoders encountering unknown values should
treat them as unrecognized.

Fields MUST NOT be renumbered or change type. Removed fields should have their numbers
retired, not reused.

## CBOR Tag Namespace

cboragen does **not** use CBOR tags for their IANA-registered purposes (date/time,
bignum, etc.). The only use of CBOR tags (major type 6) is for union/optional variants
with payloads, where the tag number is the variant's schema tag — not an IANA
identifier.

This is intentional. The schema defines semantics, not the IANA registry. Any CBOR
decoder can still parse the data; it just won't know the semantic meaning without the
schema.
