//! Recursive descent parser for the Proteus schema language.
//!
//! Produces a pointer-based, arena-allocated AST. Uses panic-mode
//! error recovery to accumulate multiple diagnostics per parse.

const std = @import("std");
const Span = @import("source_location.zig").Span;
const Token = @import("token.zig").Token;
const Tag = @import("token.zig").Tag;
const Lexer = @import("Lexer.zig");
const Ast = @import("ast.zig");
const DiagnosticList = @import("diagnostic.zig").DiagnosticList;

const Parser = @This();

const ParseError = error{ParseError};
const Error = ParseError || std.mem.Allocator.Error;

lexer: Lexer,
current: Token,
peeked: ?Token,
previous: Token,
allocator: std.mem.Allocator,
diagnostics: *DiagnosticList,
source: []const u8,
panic_mode: bool,

pub fn init(
    allocator: std.mem.Allocator,
    source: []const u8,
    diagnostics: *DiagnosticList,
) Parser {
    var lexer = Lexer.init(source, diagnostics);
    const first = lexer.next();
    return .{
        .lexer = lexer,
        .current = first,
        .peeked = null,
        .previous = .{ .tag = .eof, .span = Span.ZERO },
        .allocator = allocator,
        .diagnostics = diagnostics,
        .source = source,
        .panic_mode = false,
    };
}

// =========================================================================
// Public entry point
// =========================================================================

/// Parse a complete schema file.
pub fn parseSchema(self: *Parser) Error!Ast.Schema {
    var imports: std.ArrayList(Ast.Import) = .{};
    var definitions: std.ArrayList(Ast.TypeDef) = .{};

    self.skipNewlines();

    while (self.current.tag != .eof) {
        // Collect doc comment if present.
        const doc = self.collectDocComment() catch |err| switch (err) {
            error.ParseError => {
                self.synchronize();
                continue;
            },
            else => |e| return e,
        };

        if (self.current.tag == .eof) break;

        // Try to determine if this is an import or a typedef.
        if (self.current.tag == .identifier) {
            if (self.isImport()) {
                const imp = self.parseImport() catch |err| switch (err) {
                    error.ParseError => {
                        self.synchronize();
                        continue;
                    },
                    else => |e| return e,
                };
                try imports.append(self.allocator, imp);
                self.skipNewlines();
                continue;
            }
        }

        if (self.current.tag == .type_identifier or self.current.tag == .doc_comment) {
            const typedef = self.parseTypeDef(doc) catch |err| switch (err) {
                error.ParseError => {
                    self.synchronize();
                    continue;
                },
                else => |e| return e,
            };
            try definitions.append(self.allocator, typedef);
            self.skipNewlines();
            continue;
        }

        // Unexpected token at top level.
        self.emitError("expected type definition or import");
        self.synchronize();
    }

    return .{
        .imports = try imports.toOwnedSlice(self.allocator),
        .definitions = try definitions.toOwnedSlice(self.allocator),
    };
}

// =========================================================================
// Import parsing
// =========================================================================

/// Check if the current position looks like an import: `ident = @import(...)`.
fn isImport(self: *Parser) bool {
    if (self.current.tag != .identifier) return false;
    const tok2 = self.peekToken();
    if (tok2.tag != .equals) return false;
    // Save lexer state and peek further.
    const saved_pos = self.lexer.pos;
    const saved_peeked = self.peeked;
    // Consume the peeked token to see what's after '='.
    self.peeked = null;
    const tok3 = self.lexer.next();
    // Restore.
    self.lexer.pos = saved_pos;
    self.peeked = saved_peeked;
    return tok3.tag == .at;
}

/// Parse `namespace = @import("path")`.
fn parseImport(self: *Parser) Error!Ast.Import {
    const start = self.current.span;
    const namespace = self.current.span.slice(self.source);
    try self.expect(.identifier);

    try self.expect(.equals);
    try self.expect(.at);

    // Expect `import` identifier.
    if (self.current.tag != .identifier or !std.mem.eql(u8, self.current.span.slice(self.source), "import")) {
        self.emitError("expected 'import' after '@'");
        return error.ParseError;
    }
    self.advance_();

    try self.expect(.l_paren);

    if (self.current.tag != .string_literal) {
        self.emitError("expected string literal for import path");
        return error.ParseError;
    }
    // Strip quotes from the path.
    const path_span = self.current.span;
    const raw_path = path_span.slice(self.source);
    const path = if (raw_path.len >= 2) raw_path[1 .. raw_path.len - 1] else raw_path;
    self.advance_();

    try self.expect(.r_paren);

    return .{
        .namespace = namespace,
        .path = path,
        .span = start.merge(self.previous.span),
    };
}

// =========================================================================
// Type definition parsing
// =========================================================================

/// Parse `doc? Name = type_expr`.
fn parseTypeDef(self: *Parser, pre_doc: ?[]const u8) Error!Ast.TypeDef {
    // Doc comment may have already been collected.
    var doc = pre_doc;
    if (doc == null) {
        doc = try self.collectDocComment();
    }

    if (self.current.tag != .type_identifier) {
        self.emitError("expected type name (must start with uppercase letter)");
        return error.ParseError;
    }
    const name_span = self.current.span;
    const name = name_span.slice(self.source);
    const start = self.current.span;
    self.advance_();

    try self.expect(.equals);

    const ty = try self.parseTypeExpr();

    return .{
        .doc = doc,
        .name = name,
        .ty = ty,
        .span = start.merge(ty.getSpan()),
        .name_span = name_span,
    };
}

// =========================================================================
// Type expression parsing
// =========================================================================

/// Parse a type expression.
fn parseTypeExpr(self: *Parser) Error!Ast.TypeExpr {
    const tag = self.current.tag;
    const span = self.current.span;

    return switch (tag) {
        // Primitive types.
        .kw_bool => ret: {
            self.advance_();
            break :ret .{ .bool = span };
        },
        .kw_string => ret: {
            self.advance_();
            break :ret .{ .string = span };
        },
        .kw_u8 => ret: {
            self.advance_();
            break :ret .{ .int = .{ .kind = .u8, .span = span } };
        },
        .kw_u16 => ret: {
            self.advance_();
            break :ret .{ .int = .{ .kind = .u16, .span = span } };
        },
        .kw_u32 => ret: {
            self.advance_();
            break :ret .{ .int = .{ .kind = .u32, .span = span } };
        },
        .kw_u64 => ret: {
            self.advance_();
            break :ret .{ .int = .{ .kind = .u64, .span = span } };
        },
        .kw_i8 => ret: {
            self.advance_();
            break :ret .{ .int = .{ .kind = .i8, .span = span } };
        },
        .kw_i16 => ret: {
            self.advance_();
            break :ret .{ .int = .{ .kind = .i16, .span = span } };
        },
        .kw_i32 => ret: {
            self.advance_();
            break :ret .{ .int = .{ .kind = .i32, .span = span } };
        },
        .kw_i64 => ret: {
            self.advance_();
            break :ret .{ .int = .{ .kind = .i64, .span = span } };
        },
        .kw_f16 => ret: {
            self.advance_();
            break :ret .{ .float = .{ .kind = .f16, .span = span } };
        },
        .kw_f32 => ret: {
            self.advance_();
            break :ret .{ .float = .{ .kind = .f32, .span = span } };
        },
        .kw_f64 => ret: {
            self.advance_();
            break :ret .{ .float = .{ .kind = .f64, .span = span } };
        },
        .kw_uvarint => ret: {
            self.advance_();
            break :ret .{ .int = .{ .kind = .uvar, .span = span } };
        },
        .kw_ivarint => ret: {
            self.advance_();
            break :ret .{ .int = .{ .kind = .ivar, .span = span } };
        },

        // Option type: ?T
        .question_mark => try self.parseOptionType(),

        // Array types: []T, [N]T, [.field]T
        .l_bracket => try self.parseArrayType(),

        // Struct/enum/union.
        .kw_struct => try self.parseStructBody(),
        .kw_enum => try self.parseEnumBody(),
        .kw_union => try self.parseUnionBody(),

        // Named type reference (possibly qualified).
        .type_identifier => try self.parseNamedType(),

        // Identifier that could be a qualified name (namespace.Type).
        .identifier => ret: {
            // Check for qualified name: identifier.TypeIdentifier
            const ns = self.current.span.slice(self.source);
            const ns_span = self.current.span;
            self.advance_();
            if (self.current.tag == .dot) {
                self.advance_();
                if (self.current.tag != .type_identifier) {
                    self.emitError("expected type name after '.'");
                    break :ret error.ParseError;
                }
                const type_name = self.current.span.slice(self.source);
                const end_span = self.current.span;
                self.advance_();
                break :ret .{ .qualified = .{
                    .namespace = ns,
                    .name = type_name,
                    .span = ns_span.merge(end_span),
                } };
            }
            // Plain identifier used as type — this is an error in Proteus
            // (types must start uppercase), but we'll treat it as a named type
            // reference and let semantic analysis catch it.
            break :ret .{ .named = .{ .name = ns, .span = ns_span } };
        },

        else => {
            self.emitError("expected type expression");
            return error.ParseError;
        },
    };
}

fn parseOptionType(self: *Parser) Error!Ast.TypeExpr {
    const start = self.current.span;
    self.advance_(); // consume '?'
    const child = try self.parseTypeExpr();
    const opt = try self.allocator.create(Ast.OptionDef);
    opt.* = .{
        .child = child,
        .span = start.merge(child.getSpan()),
    };
    return .{ .option = opt };
}

fn parseArrayType(self: *Parser) Error!Ast.TypeExpr {
    const start = self.current.span;
    self.advance_(); // consume '['

    if (self.current.tag == .r_bracket) {
        // Variable-length array: []T
        self.advance_();
        const element = try self.parseTypeExpr();
        const arr = try self.allocator.create(Ast.ArrayDef);
        arr.* = .{ .variable = .{
            .element = element,
            .span = start.merge(element.getSpan()),
        } };
        return .{ .array = arr };
    }

    if (self.current.tag == .dot) {
        // External-length array: [.field]T
        self.advance_(); // consume '.'
        if (self.current.tag != .identifier and self.current.tag != .integer_literal) {
            self.emitError("expected field name after '.'");
            return error.ParseError;
        }
        const field_name = self.current.span.slice(self.source);
        self.advance_();
        try self.expect(.r_bracket);
        const element = try self.parseTypeExpr();
        const arr = try self.allocator.create(Ast.ArrayDef);
        arr.* = .{ .external_len = .{
            .len_field = field_name,
            .element = element,
            .span = start.merge(element.getSpan()),
        } };
        return .{ .array = arr };
    }

    if (self.current.tag == .integer_literal) {
        // Fixed-length array: [N]T
        const len_text = self.current.span.slice(self.source);
        const len = std.fmt.parseInt(u64, len_text, 10) catch {
            self.emitError("invalid array length");
            return error.ParseError;
        };
        self.advance_();
        try self.expect(.r_bracket);
        const element = try self.parseTypeExpr();
        const arr = try self.allocator.create(Ast.ArrayDef);
        arr.* = .{ .fixed = .{
            .len = len,
            .element = element,
            .span = start.merge(element.getSpan()),
        } };
        return .{ .array = arr };
    }

    self.emitError("expected ']', integer, or '.field' in array type");
    return error.ParseError;
}

fn parseStructBody(self: *Parser) Error!Ast.TypeExpr {
    const start = self.current.span;
    self.advance_(); // consume 'struct'
    try self.expect(.l_brace);
    self.skipNewlines();

    var fields: std.ArrayList(Ast.FieldDef) = .{};

    while (self.current.tag != .r_brace and self.current.tag != .eof) {
        const field = self.parseField() catch |err| switch (err) {
            error.ParseError => {
                self.synchronizeToFieldBoundary();
                continue;
            },
            else => |e| return e,
        };
        try fields.append(self.allocator, field);
        if (!self.parseSeparator()) {
            if (self.current.tag != .r_brace) {
                self.emitError("expected ',' or newline between fields");
                self.synchronizeToFieldBoundary();
            }
        }
    }

    const end_span = self.current.span;
    try self.expect(.r_brace);

    const s = try self.allocator.create(Ast.StructDef);
    s.* = .{
        .fields = try fields.toOwnedSlice(self.allocator),
        .span = start.merge(end_span),
    };
    return .{ .struct_ = s };
}

fn parseEnumBody(self: *Parser) Error!Ast.TypeExpr {
    const start = self.current.span;
    self.advance_(); // consume 'enum'
    try self.expect(.l_brace);
    self.skipNewlines();

    var variants: std.ArrayList(Ast.EnumVariant) = .{};

    while (self.current.tag != .r_brace and self.current.tag != .eof) {
        const variant = self.parseEnumVariant() catch |err| switch (err) {
            error.ParseError => {
                self.synchronizeToFieldBoundary();
                continue;
            },
            else => |e| return e,
        };
        try variants.append(self.allocator, variant);
        if (!self.parseSeparator()) {
            if (self.current.tag != .r_brace) {
                self.emitError("expected ',' or newline between variants");
                self.synchronizeToFieldBoundary();
            }
        }
    }

    const end_span = self.current.span;
    try self.expect(.r_brace);

    const e = try self.allocator.create(Ast.EnumDef);
    e.* = .{
        .variants = try variants.toOwnedSlice(self.allocator),
        .span = start.merge(end_span),
    };
    return .{ .enum_ = e };
}

fn parseUnionBody(self: *Parser) Error!Ast.TypeExpr {
    const start = self.current.span;
    self.advance_(); // consume 'union'
    try self.expect(.l_brace);
    self.skipNewlines();

    var variants: std.ArrayList(Ast.UnionVariant) = .{};

    while (self.current.tag != .r_brace and self.current.tag != .eof) {
        const variant = self.parseUnionVariant() catch |err| switch (err) {
            error.ParseError => {
                self.synchronizeToFieldBoundary();
                continue;
            },
            else => |e| return e,
        };
        try variants.append(self.allocator, variant);
        if (!self.parseSeparator()) {
            if (self.current.tag != .r_brace) {
                self.emitError("expected ',' or newline between variants");
                self.synchronizeToFieldBoundary();
            }
        }
    }

    const end_span = self.current.span;
    try self.expect(.r_brace);

    const u = try self.allocator.create(Ast.UnionDef);
    u.* = .{
        .variants = try variants.toOwnedSlice(self.allocator),
        .span = start.merge(end_span),
    };
    return .{ .union_ = u };
}

// =========================================================================
// Field / variant parsing
// =========================================================================

/// Parse a struct field: `doc? RANK NAME : TYPE`.
fn parseField(self: *Parser) Error!Ast.FieldDef {
    const doc = try self.collectDocComment();

    if (self.current.tag != .integer_literal) {
        self.emitError("expected field rank (integer)");
        return error.ParseError;
    }
    const rank_text = self.current.span.slice(self.source);
    const rank = std.fmt.parseInt(u64, rank_text, 10) catch {
        self.emitError("invalid field rank");
        return error.ParseError;
    };
    const start = self.current.span;
    self.advance_();

    // Field name can be identifier, type_identifier, or integer_literal
    // (numeric field names like `0 0: u64` are valid in Proteus).
    if (self.current.tag != .identifier and self.current.tag != .type_identifier and self.current.tag != .integer_literal) {
        self.emitError("expected field name");
        return error.ParseError;
    }
    const name_span = self.current.span;
    const name = name_span.slice(self.source);
    self.advance_();

    try self.expect(.colon);

    const ty = try self.parseTypeExpr();

    return .{
        .doc = doc,
        .rank = rank,
        .name = name,
        .ty = ty,
        .span = start.merge(ty.getSpan()),
        .name_span = name_span,
    };
}

/// Parse an enum variant: `doc? TAG NAME`.
fn parseEnumVariant(self: *Parser) Error!Ast.EnumVariant {
    const doc = try self.collectDocComment();

    if (self.current.tag != .integer_literal) {
        self.emitError("expected variant tag (integer)");
        return error.ParseError;
    }
    const tag_text = self.current.span.slice(self.source);
    const tag_val = std.fmt.parseInt(u64, tag_text, 10) catch {
        self.emitError("invalid variant tag");
        return error.ParseError;
    };
    const start = self.current.span;
    self.advance_();

    if (self.current.tag != .identifier and self.current.tag != .type_identifier) {
        self.emitError("expected variant name");
        return error.ParseError;
    }
    const name = self.current.span.slice(self.source);
    const end = self.current.span;
    self.advance_();

    return .{
        .doc = doc,
        .tag = tag_val,
        .name = name,
        .span = start.merge(end),
    };
}

/// Parse a union variant: `doc? TAG NAME (: TYPE)?`.
fn parseUnionVariant(self: *Parser) Error!Ast.UnionVariant {
    const doc = try self.collectDocComment();

    if (self.current.tag != .integer_literal) {
        self.emitError("expected variant tag (integer)");
        return error.ParseError;
    }
    const tag_text = self.current.span.slice(self.source);
    const tag_val = std.fmt.parseInt(u64, tag_text, 10) catch {
        self.emitError("invalid variant tag");
        return error.ParseError;
    };
    const start = self.current.span;
    self.advance_();

    if (self.current.tag != .identifier and self.current.tag != .type_identifier) {
        self.emitError("expected variant name");
        return error.ParseError;
    }
    const name = self.current.span.slice(self.source);
    var end = self.current.span;
    self.advance_();

    // Optional payload type.
    var payload: ?Ast.TypeExpr = null;
    if (self.current.tag == .colon) {
        self.advance_();
        const ty = try self.parseTypeExpr();
        end = ty.getSpan();
        payload = ty;
    }

    return .{
        .doc = doc,
        .tag = tag_val,
        .name = name,
        .payload = payload,
        .span = start.merge(end),
    };
}

/// Parse a named type reference, possibly qualified: `Name` or `ns.Name`.
fn parseNamedType(self: *Parser) Error!Ast.TypeExpr {
    const name = self.current.span.slice(self.source);
    const span = self.current.span;
    self.advance_();
    return .{ .named = .{ .name = name, .span = span } };
}

// =========================================================================
// Doc comments
// =========================================================================

/// Collect consecutive `///` doc comment lines into a single string.
/// Returns null if no doc comment is present.
fn collectDocComment(self: *Parser) Error!?[]const u8 {
    if (self.current.tag != .doc_comment) return null;

    var parts: std.ArrayList([]const u8) = .{};

    while (self.current.tag == .doc_comment) {
        const content = Lexer.docCommentContent(self.source, self.current.span);
        try parts.append(self.allocator, content);
        self.advance_();
        // Skip the newline between doc comment lines.
        if (self.current.tag == .newline) {
            self.advance_();
        }
    }

    if (parts.items.len == 0) return null;
    if (parts.items.len == 1) return parts.items[0];

    // Concatenate multiple lines with newlines.
    var total_len: usize = 0;
    for (parts.items, 0..) |part, i| {
        total_len += part.len;
        if (i < parts.items.len - 1) total_len += 1; // \n
    }

    const buf = try self.allocator.alloc(u8, total_len);
    var pos: usize = 0;
    for (parts.items, 0..) |part, i| {
        @memcpy(buf[pos..][0..part.len], part);
        pos += part.len;
        if (i < parts.items.len - 1) {
            buf[pos] = '\n';
            pos += 1;
        }
    }

    return buf;
}

// =========================================================================
// Separator handling
// =========================================================================

/// Consume optional comma and/or newlines. Returns true if any were consumed.
fn parseSeparator(self: *Parser) bool {
    var consumed = false;

    if (self.current.tag == .comma) {
        self.advance_();
        consumed = true;
    }

    if (self.current.tag == .newline) {
        self.skipNewlines();
        consumed = true;
    }

    return consumed;
}

// =========================================================================
// Token navigation
// =========================================================================

fn advance_(self: *Parser) void {
    self.previous = self.current;
    if (self.peeked) |p| {
        self.current = p;
        self.peeked = null;
    } else {
        self.current = self.lexer.next();
    }
}

fn peekToken(self: *Parser) Token {
    if (self.peeked) |p| return p;
    self.peeked = self.lexer.next();
    return self.peeked.?;
}

fn expect(self: *Parser, tag: Tag) Error!void {
    if (self.current.tag == tag) {
        self.advance_();
        return;
    }
    self.emitExpectedError(tag);
    return error.ParseError;
}

fn skipNewlines(self: *Parser) void {
    while (self.current.tag == .newline) {
        self.advance_();
    }
}

// =========================================================================
// Error handling
// =========================================================================

fn emitError(self: *Parser, message: []const u8) void {
    if (self.panic_mode) return;
    self.panic_mode = true;
    self.diagnostics.emit(.err, self.current.span, message);
}

fn emitExpectedError(self: *Parser, expected: Tag) void {
    if (self.panic_mode) return;
    self.panic_mode = true;

    // Allocate the message on the arena so it lives as long as the AST.
    const msg = std.fmt.allocPrint(
        self.allocator,
        "expected {s}, found {s}",
        .{ expected.describe(), self.current.tag.describe() },
    ) catch "expected different token";

    self.diagnostics.emit(.err, self.current.span, msg);
}

/// Synchronize at top level: advance past the problem, then stop at the
/// next type_identifier, doc_comment, or identifier-that-could-be-import
/// appearing after a newline (or eof).
fn synchronize(self: *Parser) void {
    self.panic_mode = false;

    // Always advance at least once to avoid re-triggering on the same token.
    if (self.current.tag != .eof) {
        self.advance_();
    }

    while (self.current.tag != .eof) {
        if (self.previous.tag == .newline) {
            switch (self.current.tag) {
                .type_identifier, .doc_comment, .identifier => return,
                else => {},
            }
        }
        self.advance_();
    }
}

/// Synchronize inside a struct/enum/union body: skip to next newline/comma or `}`.
fn synchronizeToFieldBoundary(self: *Parser) void {
    self.panic_mode = false;

    while (self.current.tag != .eof) {
        switch (self.current.tag) {
            .newline => {
                self.advance_();
                self.skipNewlines();
                return;
            },
            .comma => {
                self.advance_();
                self.skipNewlines();
                return;
            },
            .r_brace => return,
            else => self.advance_(),
        }
    }
}

// =============================================================================
// Tests
// =============================================================================

test "Parser - parses primitive type alias" {
    var result = try testParse("Id = u64");
    defer result.deinit();
    try std.testing.expect(!result.diags.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), result.schema.?.definitions.len);
    const def = result.schema.?.definitions[0];
    try std.testing.expectEqualStrings("Id", def.name);
    try std.testing.expectEqual(Ast.IntKind.u64, def.ty.int.kind);
}

test "Parser - parses all primitive types" {
    const types = [_][]const u8{
        "A = bool",   "B = string",
        "D = u8",     "E = u16",     "F = u32",    "G = u64",
        "H = i8",     "I = i16",     "J = i32",    "K = i64",
        "L = f16",    "M = f32",     "N = f64",
        "O = uvarint", "P = ivarint",
    };

    for (types) |src| {
        var result = try testParse(src);
        defer result.deinit();
        try std.testing.expect(!result.diags.hasErrors());
        try std.testing.expectEqual(@as(usize, 1), result.schema.?.definitions.len);
    }
}

test "Parser - parses option type" {
    var result = try testParse("X = ?string");
    defer result.deinit();
    try std.testing.expect(!result.diags.hasErrors());
    const def = result.schema.?.definitions[0];
    try std.testing.expect(def.ty == .option);
    try std.testing.expect(def.ty.option.child == .string);
}

test "Parser - parses nested option type" {
    var result = try testParse("X = ??string");
    defer result.deinit();
    try std.testing.expect(!result.diags.hasErrors());
    const def = result.schema.?.definitions[0];
    try std.testing.expect(def.ty == .option);
    try std.testing.expect(def.ty.option.child == .option);
}

test "Parser - parses variable-length array" {
    var result = try testParse("X = []u32");
    defer result.deinit();
    try std.testing.expect(!result.diags.hasErrors());
    const def = result.schema.?.definitions[0];
    try std.testing.expect(def.ty == .array);
    try std.testing.expect(def.ty.array.* == .variable);
}

test "Parser - parses fixed-length array" {
    var result = try testParse("X = [16]u8");
    defer result.deinit();
    try std.testing.expect(!result.diags.hasErrors());
    const def = result.schema.?.definitions[0];
    try std.testing.expect(def.ty == .array);
    try std.testing.expect(def.ty.array.* == .fixed);
    try std.testing.expectEqual(@as(u64, 16), def.ty.array.fixed.len);
}

test "Parser - parses external-length array" {
    var result = try testParse(
        \\X = struct {
        \\    0 len: u32
        \\    1 data: [.len]f64
        \\}
    );
    defer result.deinit();
    try std.testing.expect(!result.diags.hasErrors());
    const fields = result.schema.?.definitions[0].ty.struct_.fields;
    try std.testing.expectEqual(@as(usize, 2), fields.len);
    try std.testing.expect(fields[1].ty == .array);
    try std.testing.expect(fields[1].ty.array.* == .external_len);
    try std.testing.expectEqualStrings("len", fields[1].ty.array.external_len.len_field);
}

test "Parser - parses simple struct" {
    var result = try testParse(
        \\Point = struct {
        \\    0 x: f64
        \\    1 y: f64
        \\}
    );
    defer result.deinit();
    try std.testing.expect(!result.diags.hasErrors());
    const def = result.schema.?.definitions[0];
    try std.testing.expectEqualStrings("Point", def.name);
    try std.testing.expect(def.ty == .struct_);
    try std.testing.expectEqual(@as(usize, 2), def.ty.struct_.fields.len);
}

test "Parser - parses struct with commas" {
    var result = try testParse(
        \\Point = struct {
        \\    0 x: f64,
        \\    1 y: f64
        \\}
    );
    defer result.deinit();
    try std.testing.expect(!result.diags.hasErrors());
    try std.testing.expectEqual(@as(usize, 2), result.schema.?.definitions[0].ty.struct_.fields.len);
}

test "Parser - parses enum" {
    var result = try testParse(
        \\Status = enum {
        \\    0 active
        \\    1 inactive
        \\    2 pending
        \\}
    );
    defer result.deinit();
    try std.testing.expect(!result.diags.hasErrors());
    const def = result.schema.?.definitions[0];
    try std.testing.expect(def.ty == .enum_);
    try std.testing.expectEqual(@as(usize, 3), def.ty.enum_.variants.len);
    try std.testing.expectEqualStrings("active", def.ty.enum_.variants[0].name);
    try std.testing.expectEqual(@as(u64, 2), def.ty.enum_.variants[2].tag);
}

test "Parser - parses union" {
    var result = try testParse(
        \\Message = union {
        \\    0 text: string
        \\    1 binary: []u8
        \\    2 empty
        \\}
    );
    defer result.deinit();
    try std.testing.expect(!result.diags.hasErrors());
    const def = result.schema.?.definitions[0];
    try std.testing.expect(def.ty == .union_);
    try std.testing.expectEqual(@as(usize, 3), def.ty.union_.variants.len);
    try std.testing.expect(def.ty.union_.variants[0].payload != null);
    try std.testing.expect(def.ty.union_.variants[2].payload == null);
}

test "Parser - parses import" {
    var result = try testParse("common = @import(\"../common/types.cbg\")");
    defer result.deinit();
    try std.testing.expect(!result.diags.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), result.schema.?.imports.len);
    try std.testing.expectEqualStrings("common", result.schema.?.imports[0].namespace);
    try std.testing.expectEqualStrings("../common/types.cbg", result.schema.?.imports[0].path);
}

test "Parser - parses qualified name" {
    var result = try testParse(
        \\common = @import("types.cbg")
        \\X = struct {
        \\    0 id: common.Id
        \\}
    );
    defer result.deinit();
    try std.testing.expect(!result.diags.hasErrors());
    const field_ty = result.schema.?.definitions[0].ty.struct_.fields[0].ty;
    try std.testing.expect(field_ty == .qualified);
    try std.testing.expectEqualStrings("common", field_ty.qualified.namespace);
    try std.testing.expectEqualStrings("Id", field_ty.qualified.name);
}

test "Parser - parses doc comments" {
    var result = try testParse(
        \\/// A point in 2D space
        \\Point = struct {
        \\    /// X coordinate
        \\    0 x: f64
        \\}
    );
    defer result.deinit();
    try std.testing.expect(!result.diags.hasErrors());
    const def = result.schema.?.definitions[0];
    try std.testing.expectEqualStrings("A point in 2D space", def.doc.?);
    try std.testing.expectEqualStrings("X coordinate", def.ty.struct_.fields[0].doc.?);
}

test "Parser - parses multi-line doc comments" {
    var result = try testParse(
        \\/// Line 1
        \\/// Line 2
        \\X = u64
    );
    defer result.deinit();
    try std.testing.expect(!result.diags.hasErrors());
    try std.testing.expectEqualStrings("Line 1\nLine 2", result.schema.?.definitions[0].doc.?);
}

test "Parser - error recovery: multiple errors" {
    var result = try testParse(
        \\X = u64
        \\bad token here
        \\Y = string
    );
    defer result.deinit();
    // Should have some errors but also parse X and Y successfully.
    try std.testing.expect(result.diags.hasErrors());
    // At least one definition should have been parsed.
    try std.testing.expect(result.schema.?.definitions.len >= 1);
}

test "Parser - parses named type reference" {
    var result = try testParse(
        \\X = struct {
        \\    0 status: Status
        \\}
    );
    defer result.deinit();
    try std.testing.expect(!result.diags.hasErrors());
    const field_ty = result.schema.?.definitions[0].ty.struct_.fields[0].ty;
    try std.testing.expect(field_ty == .named);
    try std.testing.expectEqualStrings("Status", field_ty.named.name);
}

test "Parser - parses inline struct in union" {
    var result = try testParse(
        \\X = union {
        \\    0 ok: struct { 0 value: u64 }
        \\    1 err: string
        \\}
    );
    defer result.deinit();
    try std.testing.expect(!result.diags.hasErrors());
    const variants = result.schema.?.definitions[0].ty.union_.variants;
    try std.testing.expectEqual(@as(usize, 2), variants.len);
    try std.testing.expect(variants[0].payload.? == .struct_);
}

test "Parser - parses multiple definitions" {
    var result = try testParse(
        \\A = u64
        \\
        \\B = string
        \\
        \\C = bool
    );
    defer result.deinit();
    try std.testing.expect(!result.diags.hasErrors());
    try std.testing.expectEqual(@as(usize, 3), result.schema.?.definitions.len);
}

test "Parser - parses array of named type" {
    var result = try testParse(
        \\X = struct {
        \\    0 items: []OrderItem
        \\}
    );
    defer result.deinit();
    try std.testing.expect(!result.diags.hasErrors());
    const field_ty = result.schema.?.definitions[0].ty.struct_.fields[0].ty;
    try std.testing.expect(field_ty == .array);
    try std.testing.expect(field_ty.array.variable.element == .named);
}

test "Parser - parses optional named type" {
    var result = try testParse(
        \\X = struct {
        \\    0 addr: ?Address
        \\}
    );
    defer result.deinit();
    try std.testing.expect(!result.diags.hasErrors());
    const field_ty = result.schema.?.definitions[0].ty.struct_.fields[0].ty;
    try std.testing.expect(field_ty == .option);
    try std.testing.expect(field_ty.option.child == .named);
}

// =========================================================================
// Test helpers
// =========================================================================

const TestResult = struct {
    schema: ?Ast.Schema,
    diags: DiagnosticList,
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *TestResult) void {
        self.diags.deinit();
        self.arena.deinit();
    }
};

fn testParse(source: []const u8) !TestResult {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    errdefer arena.deinit();
    var diags = DiagnosticList.init(std.testing.allocator);
    // Note: don't errdefer diags.deinit() — we return them.

    var parser = Parser.init(arena.allocator(), source, &diags);
    const schema = parser.parseSchema() catch |err| switch (err) {
        error.ParseError => return .{ .schema = null, .diags = diags, .arena = arena },
        else => |e| {
            diags.deinit();
            return e;
        },
    };

    return .{ .schema = schema, .diags = diags, .arena = arena };
}
