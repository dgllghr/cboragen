import { describe, expect, test } from "bun:test";
import {
  type Primitives,
  encodePrimitives,
  decodePrimitives,
  type WithOptionals,
  encodeWithOptionals,
  decodeWithOptionals,
  Color,
  encodeColor,
  decodeColor,
  type Shape,
  encodeShape,
  decodeShape,
  type Numbers,
  encodeNumbers,
  decodeNumbers,
  type Vec3,
  encodeVec3,
  decodeVec3,
  type TimeSeries,
  encodeTimeSeries,
  decodeTimeSeries,
  type ColoredShape,
  encodeColoredShape,
  decodeColoredShape,
  type Id,
  encodeId,
  decodeId,
  type Entity,
  encodeEntity,
  decodeEntity,
  type Matrix,
  encodeMatrix,
  decodeMatrix,
  type Sparse,
  encodeSparse,
  decodeSparse,
} from "./roundtrip.gen";

describe("Primitives", () => {
  test("roundtrip with typical values", () => {
    const val: Primitives = {
      b: true,
      u8v: 42,
      u16v: 1000,
      u32v: 100000,
      u64v: 9007199254740993n,
      i8v: -42,
      i16v: -1000,
      i32v: -100000,
      i64v: -9007199254740993n,
      f32v: 3.14,
      f64v: 2.718281828459045,
      uvar: 12345678901234n,
      ivar: -12345678901234n,
      str: "hello world",
      bin: new Uint8Array([0xde, 0xad, 0xbe, 0xef]),
    };
    const encoded = encodePrimitives(val);
    const decoded = decodePrimitives(encoded);
    expect(decoded.b).toBe(true);
    expect(decoded.u8v).toBe(42);
    expect(decoded.u16v).toBe(1000);
    expect(decoded.u32v).toBe(100000);
    expect(decoded.u64v).toBe(9007199254740993n);
    expect(decoded.i8v).toBe(-42);
    expect(decoded.i16v).toBe(-1000);
    expect(decoded.i32v).toBe(-100000);
    expect(decoded.i64v).toBe(-9007199254740993n);
    expect(decoded.f32v).toBeCloseTo(3.14, 2);
    expect(decoded.f64v).toBe(2.718281828459045);
    expect(decoded.uvar).toBe(12345678901234n);
    expect(decoded.ivar).toBe(-12345678901234n);
    expect(decoded.str).toBe("hello world");
    expect(decoded.bin).toEqual(new Uint8Array([0xde, 0xad, 0xbe, 0xef]));
  });

  test("roundtrip with zero/min values", () => {
    const val: Primitives = {
      b: false,
      u8v: 0,
      u16v: 0,
      u32v: 0,
      u64v: 0n,
      i8v: 0,
      i16v: 0,
      i32v: 0,
      i64v: 0n,
      f32v: 0,
      f64v: 0,
      uvar: 0n,
      ivar: 0n,
      str: "",
      bin: new Uint8Array(0),
    };
    const decoded = decodePrimitives(encodePrimitives(val));
    expect(decoded.b).toBe(false);
    expect(decoded.u8v).toBe(0);
    expect(decoded.u16v).toBe(0);
    expect(decoded.u32v).toBe(0);
    expect(decoded.u64v).toBe(0n);
    expect(decoded.i8v).toBe(0);
    expect(decoded.i16v).toBe(0);
    expect(decoded.i32v).toBe(0);
    expect(decoded.i64v).toBe(0n);
    expect(decoded.f32v).toBe(0);
    expect(decoded.f64v).toBe(0);
    expect(decoded.uvar).toBe(0n);
    expect(decoded.ivar).toBe(0n);
    expect(decoded.str).toBe("");
    expect(decoded.bin).toEqual(new Uint8Array(0));
  });

  test("roundtrip with max values", () => {
    const val: Primitives = {
      b: true,
      u8v: 255,
      u16v: 65535,
      u32v: 4294967295,
      u64v: 18446744073709551615n,
      i8v: 127,
      i16v: 32767,
      i32v: 2147483647,
      i64v: 9223372036854775807n,
      f32v: 3.4028234663852886e38,
      f64v: 1.7976931348623157e308,
      uvar: 18446744073709551615n,
      ivar: 9223372036854775807n,
      str: "a".repeat(1000),
      bin: new Uint8Array(256).fill(0xff),
    };
    const decoded = decodePrimitives(encodePrimitives(val));
    expect(decoded.u8v).toBe(255);
    expect(decoded.u16v).toBe(65535);
    expect(decoded.u32v).toBe(4294967295);
    expect(decoded.u64v).toBe(18446744073709551615n);
    expect(decoded.i8v).toBe(127);
    expect(decoded.i16v).toBe(32767);
    expect(decoded.i32v).toBe(2147483647);
    expect(decoded.i64v).toBe(9223372036854775807n);
    expect(decoded.uvar).toBe(18446744073709551615n);
    expect(decoded.ivar).toBe(9223372036854775807n);
    expect(decoded.str).toBe("a".repeat(1000));
    expect(decoded.bin.length).toBe(256);
  });

  test("roundtrip with negative extremes", () => {
    const val: Primitives = {
      b: false,
      u8v: 0,
      u16v: 0,
      u32v: 0,
      u64v: 0n,
      i8v: -128,
      i16v: -32768,
      i32v: -2147483648,
      i64v: -9223372036854775808n,
      f32v: -3.4028234663852886e38,
      f64v: -1.7976931348623157e308,
      uvar: 0n,
      ivar: -9223372036854775808n,
      str: "",
      bin: new Uint8Array(0),
    };
    const decoded = decodePrimitives(encodePrimitives(val));
    expect(decoded.i8v).toBe(-128);
    expect(decoded.i16v).toBe(-32768);
    expect(decoded.i32v).toBe(-2147483648);
    expect(decoded.i64v).toBe(-9223372036854775808n);
    expect(decoded.ivar).toBe(-9223372036854775808n);
  });
});

describe("WithOptionals", () => {
  test("all present", () => {
    const val: WithOptionals = { required: "hello", maybe: 42, maybeStr: "world" };
    const decoded = decodeWithOptionals(encodeWithOptionals(val));
    expect(decoded.required).toBe("hello");
    expect(decoded.maybe).toBe(42);
    expect(decoded.maybeStr).toBe("world");
  });

  test("all null", () => {
    const val: WithOptionals = { required: "hello", maybe: null, maybeStr: null };
    const decoded = decodeWithOptionals(encodeWithOptionals(val));
    expect(decoded.required).toBe("hello");
    expect(decoded.maybe).toBeNull();
    expect(decoded.maybeStr).toBeNull();
  });
});

describe("Color (enum)", () => {
  test("roundtrip each variant", () => {
    expect(decodeColor(encodeColor(Color.Red))).toBe(Color.Red);
    expect(decodeColor(encodeColor(Color.Green))).toBe(Color.Green);
    expect(decodeColor(encodeColor(Color.Blue))).toBe(Color.Blue);
  });
});

describe("Shape (union)", () => {
  test("payload variant: circle", () => {
    const val: Shape = { tag: "circle", value: 5.0 };
    const decoded = decodeShape(encodeShape(val));
    expect(decoded.tag).toBe("circle");
    expect((decoded as any).value).toBe(5.0);
  });

  test("payload variant: rect (inline struct)", () => {
    const val: Shape = { tag: "rect", value: { w: 10, h: 20 } };
    const decoded = decodeShape(encodeShape(val));
    expect(decoded.tag).toBe("rect");
    expect((decoded as any).value).toEqual({ w: 10, h: 20 });
  });

  test("unit variant: point", () => {
    const val: Shape = { tag: "point" };
    const decoded = decodeShape(encodeShape(val));
    expect(decoded.tag).toBe("point");
  });
});

describe("Numbers (variable-length array)", () => {
  test("empty array", () => {
    const val: Numbers = { values: [] };
    const decoded = decodeNumbers(encodeNumbers(val));
    expect(decoded.values).toEqual([]);
  });

  test("array with values", () => {
    const val: Numbers = { values: [1, -2, 3, -4, 2147483647, -2147483648] };
    const decoded = decodeNumbers(encodeNumbers(val));
    expect(decoded.values).toEqual([1, -2, 3, -4, 2147483647, -2147483648]);
  });
});

describe("Vec3 (fixed-length array)", () => {
  test("roundtrip", () => {
    const val: Vec3 = { xyz: [1.0, 2.0, 3.0] };
    const decoded = decodeVec3(encodeVec3(val));
    expect(decoded.xyz).toEqual([1.0, 2.0, 3.0]);
  });
});

describe("TimeSeries (external-length array)", () => {
  test("empty", () => {
    const val: TimeSeries = { count: 0, timestamps: [], values: [] };
    const decoded = decodeTimeSeries(encodeTimeSeries(val));
    expect(decoded.count).toBe(0);
    expect(decoded.timestamps).toEqual([]);
    expect(decoded.values).toEqual([]);
  });

  test("with data", () => {
    const val: TimeSeries = {
      count: 3,
      timestamps: [1000n, 2000n, 3000n],
      values: [1.1, 2.2, 3.3],
    };
    const decoded = decodeTimeSeries(encodeTimeSeries(val));
    expect(decoded.count).toBe(3);
    expect(decoded.timestamps).toEqual([1000n, 2000n, 3000n]);
    expect(decoded.values[0]).toBeCloseTo(1.1);
    expect(decoded.values[1]).toBeCloseTo(2.2);
    expect(decoded.values[2]).toBeCloseTo(3.3);
  });
});

describe("ColoredShape (named references)", () => {
  test("roundtrip with enum + union refs", () => {
    const val: ColoredShape = {
      color: Color.Green,
      shape: { tag: "circle", value: 7.5 },
    };
    const decoded = decodeColoredShape(encodeColoredShape(val));
    expect(decoded.color).toBe(Color.Green);
    expect(decoded.shape.tag).toBe("circle");
    expect((decoded.shape as any).value).toBe(7.5);
  });
});

describe("Id (type alias)", () => {
  test("roundtrip", () => {
    const id: Id = 42n;
    expect(decodeId(encodeId(id))).toBe(42n);
  });

  test("large value", () => {
    const id: Id = 18446744073709551615n;
    expect(decodeId(encodeId(id))).toBe(18446744073709551615n);
  });
});

describe("Entity (struct with alias ref)", () => {
  test("roundtrip", () => {
    const val: Entity = { id: 123n, name: "test" };
    const decoded = decodeEntity(encodeEntity(val));
    expect(decoded.id).toBe(123n);
    expect(decoded.name).toBe("test");
  });
});

describe("Matrix (nested arrays)", () => {
  test("empty", () => {
    const val: Matrix = { rows: [] };
    const decoded = decodeMatrix(encodeMatrix(val));
    expect(decoded.rows).toEqual([]);
  });

  test("2x3 matrix", () => {
    const val: Matrix = { rows: [[1, 2, 3], [4, 5, 6]] };
    const decoded = decodeMatrix(encodeMatrix(val));
    expect(decoded.rows).toEqual([[1, 2, 3], [4, 5, 6]]);
  });
});

describe("Sparse (struct with rank gaps)", () => {
  test("roundtrip", () => {
    const val: Sparse = { first: 1, second: "hello", third: true };
    const decoded = decodeSparse(encodeSparse(val));
    expect(decoded.first).toBe(1);
    expect(decoded.second).toBe("hello");
    expect(decoded.third).toBe(true);
  });
});

describe("encoding determinism", () => {
  test("same value produces same bytes", () => {
    const val: Primitives = {
      b: true, u8v: 1, u16v: 2, u32v: 3, u64v: 4n,
      i8v: -1, i16v: -2, i32v: -3, i64v: -4n,
      f32v: 1.5, f64v: 2.5, uvar: 100n, ivar: -100n,
      str: "test", bin: new Uint8Array([1, 2, 3]),
    };
    const a = encodePrimitives(val);
    const b = encodePrimitives(val);
    expect(a).toEqual(b);
  });
});

describe("unicode strings", () => {
  test("roundtrip with emoji and multi-byte", () => {
    const val: WithOptionals = { required: "hello \u{1F600} world \u00E9", maybe: null, maybeStr: "\u{1F4A9}" };
    const decoded = decodeWithOptionals(encodeWithOptionals(val));
    expect(decoded.required).toBe("hello \u{1F600} world \u00E9");
    expect(decoded.maybeStr).toBe("\u{1F4A9}");
  });
});
