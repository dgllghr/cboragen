//! Diagnostic types for parser error reporting.

const std = @import("std");
const Span = @import("source_location.zig").Span;

pub const Severity = enum {
    err,
    warning,
    note,

    pub fn label(self: Severity) []const u8 {
        return switch (self) {
            .err => "error",
            .warning => "warning",
            .note => "note",
        };
    }
};

/// An additional note attached to a diagnostic.
pub const Note = struct {
    span: ?Span,
    message: []const u8,
};

/// A single diagnostic message with location and optional notes.
pub const Diagnostic = struct {
    severity: Severity,
    span: Span,
    message: []const u8,
    notes: []const Note,
};

/// A collection of diagnostics accumulated during parsing.
pub const DiagnosticList = struct {
    items: std.ArrayList(Diagnostic) = .{},
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DiagnosticList {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *DiagnosticList) void {
        // Free any heap-allocated note slices.
        for (self.items.items) |d| {
            if (d.notes.len > 0) {
                self.allocator.free(d.notes);
            }
        }
        self.items.deinit(self.allocator);
    }

    /// Emit a diagnostic with no notes.
    pub fn emit(self: *DiagnosticList, severity: Severity, span: Span, message: []const u8) void {
        self.items.append(self.allocator, .{
            .severity = severity,
            .span = span,
            .message = message,
            .notes = &.{},
        }) catch {};
    }

    /// Emit a diagnostic with a single note.
    pub fn emitWithNote(
        self: *DiagnosticList,
        severity: Severity,
        span: Span,
        message: []const u8,
        note_span: ?Span,
        note_message: []const u8,
    ) void {
        const notes = self.allocator.alloc(Note, 1) catch return;
        notes[0] = .{ .span = note_span, .message = note_message };
        self.items.append(self.allocator, .{
            .severity = severity,
            .span = span,
            .message = message,
            .notes = notes,
        }) catch {};
    }

    pub fn hasErrors(self: DiagnosticList) bool {
        for (self.items.items) |d| {
            if (d.severity == .err) return true;
        }
        return false;
    }

    pub fn errorCount(self: DiagnosticList) usize {
        var count: usize = 0;
        for (self.items.items) |d| {
            if (d.severity == .err) count += 1;
        }
        return count;
    }

    pub fn slice(self: DiagnosticList) []const Diagnostic {
        return self.items.items;
    }
};

// =============================================================================
// Tests
// =============================================================================

test "DiagnosticList - emit and count errors" {
    var diags = DiagnosticList.init(std.testing.allocator);
    defer diags.deinit();

    diags.emit(.err, .{ .start = 0, .end = 5 }, "something went wrong");
    diags.emit(.warning, .{ .start = 10, .end = 15 }, "heads up");
    diags.emit(.err, .{ .start = 20, .end = 25 }, "another error");

    try std.testing.expect(diags.hasErrors());
    try std.testing.expectEqual(@as(usize, 2), diags.errorCount());
    try std.testing.expectEqual(@as(usize, 3), diags.slice().len);
}

test "DiagnosticList - emitWithNote" {
    var diags = DiagnosticList.init(std.testing.allocator);
    defer diags.deinit();

    diags.emitWithNote(
        .err,
        .{ .start = 0, .end = 5 },
        "expected ':'",
        .{ .start = 0, .end = 3 },
        "field syntax is: RANK NAME ':' TYPE",
    );

    try std.testing.expectEqual(@as(usize, 1), diags.slice().len);
    try std.testing.expectEqual(@as(usize, 1), diags.slice()[0].notes.len);
    try std.testing.expectEqualStrings("field syntax is: RANK NAME ':' TYPE", diags.slice()[0].notes[0].message);
}

test "DiagnosticList - no errors initially" {
    var diags = DiagnosticList.init(std.testing.allocator);
    defer diags.deinit();

    try std.testing.expect(!diags.hasErrors());
    try std.testing.expectEqual(@as(usize, 0), diags.errorCount());
}
