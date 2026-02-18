//! Abstract Syntax Tree types for the Proteus schema language.
//!
//! The AST is pointer-based and arena-allocated. String data
//! is generally slices into the original source buffer (zero-copy),
//! except for multi-line doc comments which are concatenated.

const std = @import("std");
const Span = @import("source_location.zig").Span;

/// A complete schema file.
pub const Schema = struct {
    imports: []const Import,
    definitions: []const TypeDef,
};

/// An import statement: `namespace = @import("path")`.
pub const Import = struct {
    namespace: []const u8,
    path: []const u8,
    span: Span,
};

/// A top-level named type definition: `Name = type_expr`.
pub const TypeDef = struct {
    doc: ?[]const u8,
    name: []const u8,
    ty: TypeExpr,
    span: Span,
    name_span: Span,
};

/// A type expression.
pub const TypeExpr = union(enum) {
    bool: Span,
    string: Span,
    bytes: Span,
    int: IntType,
    float: FloatType,
    struct_: *const StructDef,
    enum_: *const EnumDef,
    union_: *const UnionDef,
    array: *const ArrayDef,
    option: *const OptionDef,
    named: NamedType,
    qualified: QualifiedType,

    pub const IntType = struct { kind: IntKind, span: Span };
    pub const FloatType = struct { kind: FloatKind, span: Span };
    pub const NamedType = struct { name: []const u8, span: Span };
    pub const QualifiedType = struct { namespace: []const u8, name: []const u8, span: Span };

    /// Get the span of this type expression.
    pub fn getSpan(self: TypeExpr) Span {
        return switch (self) {
            .bool, .string, .bytes => |s| s,
            .int => |i| i.span,
            .float => |f| f.span,
            .struct_ => |s| s.span,
            .enum_ => |e| e.span,
            .union_ => |u| u.span,
            .array => |a| a.getSpan(),
            .option => |o| o.span,
            .named => |n| n.span,
            .qualified => |q| q.span,
        };
    }
};

/// Integer type kinds.
pub const IntKind = enum {
    u8,
    u16,
    u32,
    u64,
    i8,
    i16,
    i32,
    i64,
    uvar,
    ivar,
};

/// Floating point type kinds.
pub const FloatKind = enum {
    f16,
    f32,
    f64,
};

/// A struct type definition.
pub const StructDef = struct {
    fields: []const FieldDef,
    span: Span,
};

/// A struct field.
pub const FieldDef = struct {
    doc: ?[]const u8,
    rank: u64,
    name: []const u8,
    ty: TypeExpr,
    span: Span,
    name_span: Span,
};

/// An enum type definition.
pub const EnumDef = struct {
    variants: []const EnumVariant,
    span: Span,
};

/// An enum variant.
pub const EnumVariant = struct {
    doc: ?[]const u8,
    tag: u64,
    name: []const u8,
    span: Span,
};

/// A union type definition.
pub const UnionDef = struct {
    variants: []const UnionVariant,
    span: Span,
};

/// A union variant.
pub const UnionVariant = struct {
    doc: ?[]const u8,
    tag: u64,
    name: []const u8,
    payload: ?TypeExpr,
    span: Span,
};

/// An option (nullable) type wrapper.
pub const OptionDef = struct {
    child: TypeExpr,
    span: Span,
};

/// An array type definition.
pub const ArrayDef = union(enum) {
    /// Variable-length array: `[]T`
    variable: struct {
        element: TypeExpr,
        span: Span,
    },
    /// Fixed-length array: `[N]T`
    fixed: struct {
        len: u64,
        element: TypeExpr,
        span: Span,
    },
    /// External-length array: `[.field]T`
    external_len: struct {
        len_field: []const u8,
        element: TypeExpr,
        span: Span,
    },

    pub fn getSpan(self: ArrayDef) Span {
        return switch (self) {
            .variable => |v| v.span,
            .fixed => |f| f.span,
            .external_len => |e| e.span,
        };
    }

    pub fn getElement(self: ArrayDef) TypeExpr {
        return switch (self) {
            .variable => |v| v.element,
            .fixed => |f| f.element,
            .external_len => |e| e.element,
        };
    }
};

// =============================================================================
// Tests
// =============================================================================

test "TypeExpr - getSpan returns correct span" {
    const span = Span{ .start = 10, .end = 20 };
    const expr = TypeExpr{ .bool = span };
    try std.testing.expectEqual(span.start, expr.getSpan().start);
    try std.testing.expectEqual(span.end, expr.getSpan().end);
}
