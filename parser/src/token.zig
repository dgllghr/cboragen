//! Token types for the cboragen schema lexer.

const std = @import("std");
const Span = @import("source_location.zig").Span;

/// A lexical token with its source location.
pub const Token = struct {
    tag: Tag,
    span: Span,
};

/// Token tag identifying the kind of token.
pub const Tag = enum(u8) {
    // Literals
    integer_literal,
    string_literal,

    // Identifiers
    identifier, // starts with lowercase or _
    type_identifier, // starts with uppercase

    // Keywords - types
    kw_bool,
    kw_string,
    kw_u8,
    kw_u16,
    kw_u32,
    kw_u64,
    kw_i8,
    kw_i16,
    kw_i32,
    kw_i64,
    kw_f16,
    kw_f32,
    kw_f64,
    kw_uvarint,
    kw_ivarint,

    // Keywords - compound types
    kw_struct,
    kw_enum,
    kw_union,

    // Symbols
    equals,
    colon,
    at,
    dot,
    question_mark,
    l_bracket,
    r_bracket,
    l_brace,
    r_brace,
    l_paren,
    r_paren,
    comma,

    // Whitespace
    newline,

    // Documentation
    doc_comment,

    // Special
    eof,
    invalid,

    /// Human-readable name for error messages.
    pub fn describe(self: Tag) []const u8 {
        return switch (self) {
            .integer_literal => "integer",
            .string_literal => "string literal",
            .identifier => "identifier",
            .type_identifier => "type name",
            .kw_bool => "'bool'",
            .kw_string => "'string'",
            .kw_u8 => "'u8'",
            .kw_u16 => "'u16'",
            .kw_u32 => "'u32'",
            .kw_u64 => "'u64'",
            .kw_i8 => "'i8'",
            .kw_i16 => "'i16'",
            .kw_i32 => "'i32'",
            .kw_i64 => "'i64'",
            .kw_f16 => "'f16'",
            .kw_f32 => "'f32'",
            .kw_f64 => "'f64'",
            .kw_uvarint => "'uvarint'",
            .kw_ivarint => "'ivarint'",
            .kw_struct => "'struct'",
            .kw_enum => "'enum'",
            .kw_union => "'union'",
            .equals => "'='",
            .colon => "':'",
            .at => "'@'",
            .dot => "'.'",
            .question_mark => "'?'",
            .l_bracket => "'['",
            .r_bracket => "']'",
            .l_brace => "'{'",
            .r_brace => "'}'",
            .l_paren => "'('",
            .r_paren => "')'",
            .comma => "','",
            .newline => "newline",
            .doc_comment => "doc comment",
            .eof => "end of file",
            .invalid => "invalid token",
        };
    }

    /// Returns true if this tag is a keyword that can appear as a type.
    pub fn isTypeKeyword(self: Tag) bool {
        return switch (self) {
            .kw_bool,
            .kw_string,
            .kw_u8,
            .kw_u16,
            .kw_u32,
            .kw_u64,
            .kw_i8,
            .kw_i16,
            .kw_i32,
            .kw_i64,
            .kw_f16,
            .kw_f32,
            .kw_f64,
            .kw_uvarint,
            .kw_ivarint,
            => true,
            else => false,
        };
    }
};

/// Compile-time keyword lookup.
pub fn getKeyword(text: []const u8) ?Tag {
    return KEYWORDS.get(text);
}

const KEYWORDS = std.StaticStringMap(Tag).initComptime(.{
    .{ "bool", .kw_bool },
    .{ "string", .kw_string },
    .{ "u8", .kw_u8 },
    .{ "u16", .kw_u16 },
    .{ "u32", .kw_u32 },
    .{ "u64", .kw_u64 },
    .{ "i8", .kw_i8 },
    .{ "i16", .kw_i16 },
    .{ "i32", .kw_i32 },
    .{ "i64", .kw_i64 },
    .{ "f16", .kw_f16 },
    .{ "f32", .kw_f32 },
    .{ "f64", .kw_f64 },
    .{ "uvarint", .kw_uvarint },
    .{ "ivarint", .kw_ivarint },
    .{ "struct", .kw_struct },
    .{ "enum", .kw_enum },
    .{ "union", .kw_union },
});

// =============================================================================
// Tests
// =============================================================================

test "getKeyword - finds keywords" {
    try std.testing.expectEqual(Tag.kw_struct, getKeyword("struct").?);
    try std.testing.expectEqual(Tag.kw_u64, getKeyword("u64").?);
    try std.testing.expectEqual(Tag.kw_uvarint, getKeyword("uvarint").?);
    try std.testing.expectEqual(Tag.kw_bool, getKeyword("bool").?);
}

test "getKeyword - returns null for non-keywords" {
    try std.testing.expect(getKeyword("Person") == null);
    try std.testing.expect(getKeyword("name") == null);
    try std.testing.expect(getKeyword("import") == null);
    try std.testing.expect(getKeyword("") == null);
}

test "Tag - describe returns human-readable names" {
    try std.testing.expectEqualStrings("'struct'", Tag.kw_struct.describe());
    try std.testing.expectEqualStrings("identifier", Tag.identifier.describe());
    try std.testing.expectEqualStrings("end of file", Tag.eof.describe());
}

test "Tag - isTypeKeyword" {
    try std.testing.expect(Tag.kw_bool.isTypeKeyword());
    try std.testing.expect(Tag.kw_u64.isTypeKeyword());
    try std.testing.expect(Tag.kw_f32.isTypeKeyword());
    try std.testing.expect(!Tag.kw_struct.isTypeKeyword());
    try std.testing.expect(!Tag.identifier.isTypeKeyword());
}
