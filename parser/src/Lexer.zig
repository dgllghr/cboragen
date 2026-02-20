//! On-demand lexer (tokenizer) for the Proteus schema language.
//!
//! The lexer is an iterator: call `next()` to get the next token.
//! It handles whitespace skipping, newline collapsing, comments,
//! doc comments, identifiers/keywords, integers, and string literals.

const std = @import("std");
const Span = @import("source_location.zig").Span;
const Token = @import("token.zig").Token;
const Tag = @import("token.zig").Tag;
const getKeyword = @import("token.zig").getKeyword;
const DiagnosticList = @import("diagnostic.zig").DiagnosticList;

const Lexer = @This();

source: []const u8,
pos: u32,
diagnostics: *DiagnosticList,

pub fn init(source: []const u8, diagnostics: *DiagnosticList) Lexer {
    return .{
        .source = source,
        .pos = 0,
        .diagnostics = diagnostics,
    };
}

/// Returns the next token from the source.
pub fn next(self: *Lexer) Token {
    // Skip horizontal whitespace (spaces, tabs) and regular comments.
    self.skipWhitespaceAndComments();

    if (self.isAtEnd()) {
        return .{ .tag = .eof, .span = .{ .start = self.pos, .end = self.pos } };
    }

    const start = self.pos;
    const c = self.advance();

    return switch (c) {
        '\n' => self.scanNewline(start),
        '\r' => blk: {
            // Handle \r\n as a single newline.
            if (!self.isAtEnd() and self.peek() == '\n') _ = self.advance();
            break :blk self.scanNewline(start);
        },
        '=' => .{ .tag = .equals, .span = .{ .start = start, .end = self.pos } },
        ':' => .{ .tag = .colon, .span = .{ .start = start, .end = self.pos } },
        '@' => .{ .tag = .at, .span = .{ .start = start, .end = self.pos } },
        '.' => .{ .tag = .dot, .span = .{ .start = start, .end = self.pos } },
        '?' => .{ .tag = .question_mark, .span = .{ .start = start, .end = self.pos } },
        '[' => .{ .tag = .l_bracket, .span = .{ .start = start, .end = self.pos } },
        ']' => .{ .tag = .r_bracket, .span = .{ .start = start, .end = self.pos } },
        '{' => .{ .tag = .l_brace, .span = .{ .start = start, .end = self.pos } },
        '}' => .{ .tag = .r_brace, .span = .{ .start = start, .end = self.pos } },
        '(' => .{ .tag = .l_paren, .span = .{ .start = start, .end = self.pos } },
        ')' => .{ .tag = .r_paren, .span = .{ .start = start, .end = self.pos } },
        ',' => .{ .tag = .comma, .span = .{ .start = start, .end = self.pos } },
        '"' => self.scanString(start),
        '/' => self.scanSlash(start),
        '0'...'9' => self.scanInteger(start),
        'a'...'z', '_' => self.scanIdentifier(start),
        'A'...'Z' => self.scanIdentifier(start),
        else => blk: {
            self.diagnostics.emit(.err, .{ .start = start, .end = self.pos }, "unexpected character");
            break :blk .{ .tag = .invalid, .span = .{ .start = start, .end = self.pos } };
        },
    };
}

// =========================================================================
// Scanning helpers
// =========================================================================

fn scanNewline(self: *Lexer, start: u32) Token {
    // Collapse consecutive newlines (including blank lines with only whitespace).
    while (!self.isAtEnd()) {
        const c = self.peek();
        if (c == '\n') {
            _ = self.advance();
        } else if (c == '\r') {
            _ = self.advance();
            if (!self.isAtEnd() and self.peek() == '\n') _ = self.advance();
        } else if (c == ' ' or c == '\t') {
            // Might be whitespace before another newline — peek ahead.
            const saved = self.pos;
            self.skipHorizontalWhitespace();
            if (!self.isAtEnd() and (self.peek() == '\n' or self.peek() == '\r')) {
                continue; // The whitespace-then-newline will be handled next iteration.
            } else {
                self.pos = saved;
                break;
            }
        } else {
            break;
        }
    }
    return .{ .tag = .newline, .span = .{ .start = start, .end = self.pos } };
}

fn scanString(self: *Lexer, start: u32) Token {
    while (!self.isAtEnd()) {
        const c = self.advance();
        if (c == '"') {
            return .{ .tag = .string_literal, .span = .{ .start = start, .end = self.pos } };
        }
        if (c == '\\') {
            // Skip escaped character.
            if (!self.isAtEnd()) _ = self.advance();
        }
        if (c == '\n') {
            self.diagnostics.emit(.err, .{ .start = start, .end = self.pos }, "unterminated string literal");
            return .{ .tag = .string_literal, .span = .{ .start = start, .end = self.pos } };
        }
    }
    self.diagnostics.emit(.err, .{ .start = start, .end = self.pos }, "unterminated string literal");
    return .{ .tag = .string_literal, .span = .{ .start = start, .end = self.pos } };
}

fn scanSlash(self: *Lexer, start: u32) Token {
    // We already consumed one '/'. If next is also '/', it's a comment.
    if (!self.isAtEnd() and self.peek() == '/') {
        _ = self.advance(); // consume second '/'
        // Check for doc comment: `///`
        if (!self.isAtEnd() and self.peek() == '/') {
            _ = self.advance(); // consume third '/'
            return self.scanDocComment(start);
        }
        // Regular comment — skip to end of line (don't consume the newline).
        while (!self.isAtEnd() and self.peek() != '\n' and self.peek() != '\r') {
            _ = self.advance();
        }
        // Recurse to get the next meaningful token.
        // But first skip any more whitespace.
        self.skipWhitespaceAndComments();
        if (self.isAtEnd()) {
            return .{ .tag = .eof, .span = .{ .start = self.pos, .end = self.pos } };
        }
        return self.next();
    }
    // Single '/' is invalid in this language.
    self.diagnostics.emit(.err, .{ .start = start, .end = self.pos }, "unexpected '/'");
    return .{ .tag = .invalid, .span = .{ .start = start, .end = self.pos } };
}

fn scanDocComment(self: *Lexer, start: u32) Token {
    // Skip optional single leading space after `///`.
    if (!self.isAtEnd() and self.peek() == ' ') {
        _ = self.advance();
    }
    const content_start = self.pos;
    // Scan to end of line.
    while (!self.isAtEnd() and self.peek() != '\n' and self.peek() != '\r') {
        _ = self.advance();
    }
    _ = content_start;
    return .{ .tag = .doc_comment, .span = .{ .start = start, .end = self.pos } };
}

fn scanInteger(self: *Lexer, start: u32) Token {
    while (!self.isAtEnd() and isDigit(self.peek())) {
        _ = self.advance();
    }
    return .{ .tag = .integer_literal, .span = .{ .start = start, .end = self.pos } };
}

fn scanIdentifier(self: *Lexer, start: u32) Token {
    while (!self.isAtEnd() and isIdentContinue(self.peek())) {
        _ = self.advance();
    }
    const text = self.source[start..self.pos];

    // Check if it's a keyword.
    if (getKeyword(text)) |kw_tag| {
        return .{ .tag = kw_tag, .span = .{ .start = start, .end = self.pos } };
    }

    // Determine if it's a type identifier (starts uppercase) or regular identifier.
    const tag: Tag = if (text[0] >= 'A' and text[0] <= 'Z') .type_identifier else .identifier;
    return .{ .tag = tag, .span = .{ .start = start, .end = self.pos } };
}

// =========================================================================
// Character helpers
// =========================================================================

fn skipWhitespaceAndComments(self: *Lexer) void {
    while (!self.isAtEnd()) {
        const c = self.peek();
        if (c == ' ' or c == '\t') {
            _ = self.advance();
        } else {
            break;
        }
    }
}

fn skipHorizontalWhitespace(self: *Lexer) void {
    while (!self.isAtEnd()) {
        const c = self.peek();
        if (c == ' ' or c == '\t') {
            _ = self.advance();
        } else {
            break;
        }
    }
}

fn peek(self: *Lexer) u8 {
    return self.source[self.pos];
}

fn advance(self: *Lexer) u8 {
    const c = self.source[self.pos];
    self.pos += 1;
    return c;
}

fn isAtEnd(self: *Lexer) bool {
    return self.pos >= self.source.len;
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isIdentStart(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

fn isIdentContinue(c: u8) bool {
    return isIdentStart(c) or isDigit(c);
}

/// Extract the content of a doc comment token (text after `/// `).
pub fn docCommentContent(source: []const u8, span: Span) []const u8 {
    const text = span.slice(source);
    // Skip the `///` prefix and optional space.
    if (text.len >= 4 and text[3] == ' ') {
        return text[4..];
    }
    if (text.len >= 3) {
        return text[3..];
    }
    return "";
}

// =============================================================================
// Tests
// =============================================================================

test "Lexer - basic symbols" {
    var diags = DiagnosticList.init(std.testing.allocator);
    defer diags.deinit();
    var lexer = Lexer.init("= : @ . ? [ ] { } ( ) ,", &diags);

    const expected = [_]Tag{
        .equals, .colon, .at, .dot, .question_mark,
        .l_bracket, .r_bracket, .l_brace, .r_brace,
        .l_paren, .r_paren, .comma, .eof,
    };

    for (expected) |exp| {
        const tok = lexer.next();
        try std.testing.expectEqual(exp, tok.tag);
    }
}

test "Lexer - keywords" {
    var diags = DiagnosticList.init(std.testing.allocator);
    defer diags.deinit();
    var lexer = Lexer.init("struct enum union bool string u8 u64 i32 f64 uvarint ivarint", &diags);

    const expected = [_]Tag{
        .kw_struct, .kw_enum, .kw_union,
        .kw_bool, .kw_string,
        .kw_u8, .kw_u64, .kw_i32, .kw_f64,
        .kw_uvarint, .kw_ivarint, .eof,
    };

    for (expected) |exp| {
        const tok = lexer.next();
        try std.testing.expectEqual(exp, tok.tag);
    }
}

test "Lexer - identifiers and type identifiers" {
    var diags = DiagnosticList.init(std.testing.allocator);
    defer diags.deinit();
    var lexer = Lexer.init("name Person _private Type123", &diags);

    var tok = lexer.next();
    try std.testing.expectEqual(Tag.identifier, tok.tag);
    try std.testing.expectEqualStrings("name", tok.span.slice(lexer.source));

    tok = lexer.next();
    try std.testing.expectEqual(Tag.type_identifier, tok.tag);
    try std.testing.expectEqualStrings("Person", tok.span.slice(lexer.source));

    tok = lexer.next();
    try std.testing.expectEqual(Tag.identifier, tok.tag);
    try std.testing.expectEqualStrings("_private", tok.span.slice(lexer.source));

    tok = lexer.next();
    try std.testing.expectEqual(Tag.type_identifier, tok.tag);
    try std.testing.expectEqualStrings("Type123", tok.span.slice(lexer.source));
}

test "Lexer - integer literals" {
    var diags = DiagnosticList.init(std.testing.allocator);
    defer diags.deinit();
    var lexer = Lexer.init("0 42 12345", &diags);

    var tok = lexer.next();
    try std.testing.expectEqual(Tag.integer_literal, tok.tag);
    try std.testing.expectEqualStrings("0", tok.span.slice(lexer.source));

    tok = lexer.next();
    try std.testing.expectEqual(Tag.integer_literal, tok.tag);
    try std.testing.expectEqualStrings("42", tok.span.slice(lexer.source));

    tok = lexer.next();
    try std.testing.expectEqual(Tag.integer_literal, tok.tag);
    try std.testing.expectEqualStrings("12345", tok.span.slice(lexer.source));
}

test "Lexer - string literals" {
    var diags = DiagnosticList.init(std.testing.allocator);
    defer diags.deinit();
    var lexer = Lexer.init("\"hello\" \"world\"", &diags);

    var tok = lexer.next();
    try std.testing.expectEqual(Tag.string_literal, tok.tag);
    try std.testing.expectEqualStrings("\"hello\"", tok.span.slice(lexer.source));

    tok = lexer.next();
    try std.testing.expectEqual(Tag.string_literal, tok.tag);
}

test "Lexer - doc comments" {
    var diags = DiagnosticList.init(std.testing.allocator);
    defer diags.deinit();
    var lexer = Lexer.init("/// A doc comment\n/// Another line", &diags);

    var tok = lexer.next();
    try std.testing.expectEqual(Tag.doc_comment, tok.tag);
    try std.testing.expectEqualStrings("A doc comment", docCommentContent(lexer.source, tok.span));

    tok = lexer.next();
    try std.testing.expectEqual(Tag.newline, tok.tag);

    tok = lexer.next();
    try std.testing.expectEqual(Tag.doc_comment, tok.tag);
    try std.testing.expectEqualStrings("Another line", docCommentContent(lexer.source, tok.span));
}

test "Lexer - regular comments are skipped" {
    var diags = DiagnosticList.init(std.testing.allocator);
    defer diags.deinit();
    var lexer = Lexer.init("// regular comment\nfoo", &diags);

    // The regular comment is skipped; we should get the newline and then identifier.
    const tok = lexer.next();
    try std.testing.expectEqual(Tag.newline, tok.tag);

    const tok2 = lexer.next();
    try std.testing.expectEqual(Tag.identifier, tok2.tag);
}

test "Lexer - newline collapsing" {
    var diags = DiagnosticList.init(std.testing.allocator);
    defer diags.deinit();
    var lexer = Lexer.init("a\n\n\nb", &diags);

    var tok = lexer.next();
    try std.testing.expectEqual(Tag.identifier, tok.tag);

    tok = lexer.next();
    try std.testing.expectEqual(Tag.newline, tok.tag);

    tok = lexer.next();
    try std.testing.expectEqual(Tag.identifier, tok.tag);
    try std.testing.expectEqualStrings("b", tok.span.slice(lexer.source));
}

test "Lexer - unterminated string emits diagnostic" {
    var diags = DiagnosticList.init(std.testing.allocator);
    defer diags.deinit();
    var lexer = Lexer.init("\"unterminated", &diags);

    const tok = lexer.next();
    try std.testing.expectEqual(Tag.string_literal, tok.tag);
    try std.testing.expect(diags.hasErrors());
}

test "Lexer - invalid character emits diagnostic" {
    var diags = DiagnosticList.init(std.testing.allocator);
    defer diags.deinit();
    var lexer = Lexer.init("#", &diags);

    const tok = lexer.next();
    try std.testing.expectEqual(Tag.invalid, tok.tag);
    try std.testing.expect(diags.hasErrors());
}

test "Lexer - complete token stream for simple schema" {
    var diags = DiagnosticList.init(std.testing.allocator);
    defer diags.deinit();
    var lexer = Lexer.init("Point = struct {\n    0 x: f64\n}", &diags);

    const expected = [_]Tag{
        .type_identifier, // Point
        .equals, // =
        .kw_struct, // struct
        .l_brace, // {
        .newline, // \n
        .integer_literal, // 0
        .identifier, // x
        .colon, // :
        .kw_f64, // f64
        .newline, // \n
        .r_brace, // }
        .eof,
    };

    for (expected) |exp| {
        const tok = lexer.next();
        try std.testing.expectEqual(exp, tok.tag);
    }
    try std.testing.expect(!diags.hasErrors());
}
