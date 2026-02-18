//! Schema parser library for the cboragen schema language.
//!
//! Parse schema definition files into an AST suitable for
//! code generation. The AST uses arena allocation and slices into
//! the original source buffer for zero-copy string data.

const std = @import("std");
pub const Ast = @import("ast.zig");
pub const Token = @import("token.zig");
pub const Lexer = @import("Lexer.zig");
pub const Parser = @import("Parser.zig");
pub const Diagnostic = @import("diagnostic.zig");
pub const Renderer = @import("renderer.zig");
pub const SourceLocation = @import("source_location.zig");

/// Result of parsing a schema source string.
pub const ParseResult = struct {
    schema: ?Ast.Schema,
    diagnostics: Diagnostic.DiagnosticList,
    arena: std.heap.ArenaAllocator,

    /// Free all AST memory and diagnostics.
    pub fn deinit(self: *ParseResult) void {
        self.diagnostics.deinit();
        self.arena.deinit();
    }

    pub fn hasErrors(self: ParseResult) bool {
        return self.diagnostics.hasErrors();
    }
};

/// Parse a schema source string.
///
/// Caller must keep `source` alive as long as the returned ParseResult
/// is in use, since the AST contains slices into the source buffer.
pub fn parse(backing_allocator: std.mem.Allocator, source: []const u8) ParseResult {
    var arena = std.heap.ArenaAllocator.init(backing_allocator);
    var diagnostics = Diagnostic.DiagnosticList.init(backing_allocator);

    var parser = Parser.init(arena.allocator(), source, &diagnostics);
    const schema = parser.parseSchema() catch |err| switch (err) {
        error.ParseError => return .{
            .schema = null,
            .diagnostics = diagnostics,
            .arena = arena,
        },
        error.OutOfMemory => {
            diagnostics.emit(.err, SourceLocation.Span.ZERO, "out of memory");
            return .{
                .schema = null,
                .diagnostics = diagnostics,
                .arena = arena,
            };
        },
    };

    return .{
        .schema = schema,
        .diagnostics = diagnostics,
        .arena = arena,
    };
}

/// Render diagnostics to a writer with optional ANSI color.
pub fn renderDiagnostics(
    writer: std.io.AnyWriter,
    source: []const u8,
    filename: []const u8,
    diagnostics: []const Diagnostic.Diagnostic,
    use_color: bool,
) !void {
    try Renderer.render(writer, source, filename, diagnostics, use_color);
}

// =============================================================================
// Tests
// =============================================================================

test "parse - simple schema" {
    const source =
        \\/// A point
        \\Point = struct {
        \\    0 x: f64
        \\    1 y: f64
        \\}
    ;

    var result = parse(std.testing.allocator, source);
    defer result.deinit();

    try std.testing.expect(!result.hasErrors());
    try std.testing.expect(result.schema != null);
    try std.testing.expectEqual(@as(usize, 1), result.schema.?.definitions.len);
    try std.testing.expectEqualStrings("Point", result.schema.?.definitions[0].name);
}

test "parse - with imports" {
    const source =
        \\common = @import("common/types.cbg")
        \\
        \\X = struct {
        \\    0 id: common.Id
        \\}
    ;

    var result = parse(std.testing.allocator, source);
    defer result.deinit();

    try std.testing.expect(!result.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), result.schema.?.imports.len);
    try std.testing.expectEqual(@as(usize, 1), result.schema.?.definitions.len);
}

test "parse - error produces diagnostics" {
    const source = "X = {";

    var result = parse(std.testing.allocator, source);
    defer result.deinit();

    try std.testing.expect(result.hasErrors());
}

// =============================================================================
// Integration tests — parse testdata/ files
// =============================================================================

fn parseTestFile(comptime path: []const u8) !void {
    const source = @embedFile(path);
    var result = parse(std.testing.allocator, source);
    defer result.deinit();

    if (result.hasErrors()) {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        renderDiagnostics(stderr.any(), source, path, result.diagnostics.slice(), false) catch {};
    }
    try std.testing.expect(!result.hasErrors());
    try std.testing.expect(result.schema != null);
}

test "integration - primitives.cbg" {
    try parseTestFile("testdata/primitives.cbg");
}

test "integration - structs.cbg" {
    try parseTestFile("testdata/structs.cbg");
}

test "integration - enums.cbg" {
    try parseTestFile("testdata/enums.cbg");
}

test "integration - unions.cbg" {
    try parseTestFile("testdata/unions.cbg");
}

test "integration - arrays.cbg" {
    try parseTestFile("testdata/arrays.cbg");
}

test "integration - doc_comments.cbg" {
    try parseTestFile("testdata/doc_comments.cbg");
}

test "integration - complex.cbg" {
    try parseTestFile("testdata/complex.cbg");
}

test "integration - api.cbg (imports + qualified names)" {
    try parseTestFile("testdata/api.cbg");
}

test "integration - common/types.cbg" {
    try parseTestFile("testdata/common/types.cbg");
}

test "integration - models/user.cbg (imports)" {
    try parseTestFile("testdata/models/user.cbg");
}

test "integration - primitives.cbg has 17 definitions" {
    const source = @embedFile("testdata/primitives.cbg");
    var result = parse(std.testing.allocator, source);
    defer result.deinit();

    try std.testing.expect(!result.hasErrors());
    try std.testing.expectEqual(@as(usize, 16), result.schema.?.definitions.len);
}

test "integration - api.cbg has 2 imports" {
    const source = @embedFile("testdata/api.cbg");
    var result = parse(std.testing.allocator, source);
    defer result.deinit();

    try std.testing.expect(!result.hasErrors());
    try std.testing.expectEqual(@as(usize, 2), result.schema.?.imports.len);
    try std.testing.expectEqual(@as(usize, 5), result.schema.?.definitions.len);
}

test "integration - complex.cbg deeply nested optional" {
    const source = @embedFile("testdata/complex.cbg");
    var result = parse(std.testing.allocator, source);
    defer result.deinit();

    try std.testing.expect(!result.hasErrors());
    const defs = result.schema.?.definitions;
    // Last definition is MaybeOptional = ?????u64
    const last = defs[defs.len - 1];
    try std.testing.expectEqualStrings("MaybeOptional", last.name);
    // Walk 5 levels of option nesting
    var ty = last.ty;
    for (0..5) |_| {
        try std.testing.expect(ty == .option);
        ty = ty.option.child;
    }
    try std.testing.expect(ty == .int);
    try std.testing.expectEqual(Ast.IntKind.u64, ty.int.kind);
}

test {
    // Run tests in all imported modules.
    _ = @import("source_location.zig");
    _ = @import("token.zig");
    _ = @import("diagnostic.zig");
    _ = @import("Lexer.zig");
    _ = @import("ast.zig");
    _ = @import("Parser.zig");
    _ = @import("renderer.zig");
}
