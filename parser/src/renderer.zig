//! Diagnostic renderer producing ariadne-style error output with
//! source snippets and ANSI color support.

const std = @import("std");
const Span = @import("source_location.zig").Span;
const LineIndex = @import("source_location.zig").LineIndex;
const Diagnostic = @import("diagnostic.zig").Diagnostic;
const Severity = @import("diagnostic.zig").Severity;

/// Render a list of diagnostics to the given writer.
pub fn render(
    writer: std.io.AnyWriter,
    source: []const u8,
    filename: []const u8,
    diagnostics: []const Diagnostic,
    use_color: bool,
) !void {
    if (diagnostics.len == 0) return;

    var line_index = try LineIndex.build(std.heap.page_allocator, source);
    defer line_index.deinit();

    for (diagnostics) |diag| {
        try renderOne(writer, source, filename, &line_index, diag, use_color);
    }
}

fn renderOne(
    writer: std.io.AnyWriter,
    source: []const u8,
    filename: []const u8,
    line_index: *const LineIndex,
    diag: Diagnostic,
    use_color: bool,
) !void {
    const lc = line_index.resolve(diag.span.start);

    // Severity header: `error: message`
    if (use_color) {
        try writer.writeAll(severityColor(diag.severity));
    }
    try writer.print("{s}: ", .{diag.severity.label()});
    if (use_color) try writer.writeAll(RESET);
    if (use_color) try writer.writeAll(BOLD);
    try writer.print("{s}\n", .{diag.message});
    if (use_color) try writer.writeAll(RESET);

    // Location: `  --> filename:line:col`
    if (use_color) try writer.writeAll(BLUE);
    try writer.print("  --> ", .{});
    if (use_color) try writer.writeAll(RESET);
    try writer.print("{s}:{d}:{d}\n", .{ filename, lc.line, lc.col });

    // Source snippet.
    const line_info = line_index.getLineText(diag.span.start, source);
    const line_num = line_info.line_num;
    const line_text = line_info.text;
    const line_start_offset = line_index.line_starts[line_num - 1];

    // Gutter + source line.
    if (use_color) try writer.writeAll(BLUE);
    try writer.print("   |\n", .{});
    try writer.print("{d: >3} | ", .{line_num});
    if (use_color) try writer.writeAll(RESET);
    try writer.print("{s}\n", .{line_text});

    // Underline.
    if (use_color) try writer.writeAll(BLUE);
    try writer.print("   | ", .{});

    const col_start = if (diag.span.start >= line_start_offset)
        diag.span.start - line_start_offset
    else
        0;

    // Compute underline length, clamped to current line.
    const line_end_offset = line_start_offset + @as(u32, @intCast(line_text.len));
    const span_end_on_line = @min(diag.span.end, line_end_offset);
    const underline_len = if (span_end_on_line > diag.span.start)
        span_end_on_line - diag.span.start
    else
        1; // At least one caret.

    if (use_color) try writer.writeAll(severityColor(diag.severity));
    for (0..col_start) |_| try writer.writeByte(' ');
    for (0..underline_len) |_| try writer.writeByte('^');
    if (use_color) try writer.writeAll(RESET);
    try writer.writeByte('\n');

    // Notes.
    for (diag.notes) |note| {
        if (use_color) try writer.writeAll(BLUE);
        try writer.print("   = ", .{});
        if (use_color) try writer.writeAll(CYAN);
        try writer.print("help: ", .{});
        if (use_color) try writer.writeAll(RESET);
        try writer.print("{s}\n", .{note.message});
    }

    try writer.writeByte('\n');
}

// ANSI color codes.
const RESET = "\x1b[0m";
const BOLD = "\x1b[1m";
const RED = "\x1b[31m";
const YELLOW = "\x1b[33m";
const BLUE = "\x1b[34m";
const CYAN = "\x1b[36m";

fn severityColor(severity: Severity) []const u8 {
    return switch (severity) {
        .err => RED ++ BOLD,
        .warning => YELLOW ++ BOLD,
        .note => BLUE,
    };
}

// =============================================================================
// Tests
// =============================================================================

test "Renderer - renders basic error" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(std.testing.allocator);

    const source = "Point = struc {\n    0 x: f64\n}";
    const diag = Diagnostic{
        .severity = .err,
        .span = .{ .start = 8, .end = 13 },
        .message = "expected type expression",
        .notes = &.{},
    };

    try render(buf.writer(std.testing.allocator).any(), source, "test.proteus", &.{diag}, false);

    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "error: expected type expression") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "test.proteus:1:9") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "^^^^^") != null);
}

test "Renderer - renders with note" {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(std.testing.allocator);

    const source = "0 name string";
    const notes = [_]@import("diagnostic.zig").Note{
        .{ .span = null, .message = "field syntax is: RANK NAME ':' TYPE" },
    };
    const diag = Diagnostic{
        .severity = .err,
        .span = .{ .start = 7, .end = 13 },
        .message = "expected ':'",
        .notes = &notes,
    };

    try render(buf.writer(std.testing.allocator).any(), source, "test.proteus", &.{diag}, false);

    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "help: field syntax") != null);
}
