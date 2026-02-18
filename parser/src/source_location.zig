//! Source location tracking for diagnostic rendering.
//!
//! Provides byte-offset spans and lazy line-index computation for
//! resolving offsets to line:column pairs.

const std = @import("std");

/// A half-open byte range `[start, end)` in source text.
pub const Span = struct {
    start: u32,
    end: u32,

    pub const ZERO = Span{ .start = 0, .end = 0 };

    /// Extract the slice of source text covered by this span.
    pub fn slice(self: Span, source: []const u8) []const u8 {
        const s = @min(self.start, @as(u32, @intCast(source.len)));
        const e = @min(self.end, @as(u32, @intCast(source.len)));
        return source[s..e];
    }

    /// Merge two spans into the smallest span covering both.
    pub fn merge(self: Span, other: Span) Span {
        return .{
            .start = @min(self.start, other.start),
            .end = @max(self.end, other.end),
        };
    }

    /// Length of the span in bytes.
    pub fn len(self: Span) u32 {
        return self.end - self.start;
    }
};

/// A resolved line:column position (both 1-based).
pub const LineCol = struct {
    line: u32,
    col: u32,
};

/// Lazily-built index mapping byte offsets to line numbers.
///
/// Constructed on first use and cached. The line starts array stores
/// the byte offset of the first character on each line.
pub const LineIndex = struct {
    /// Byte offset of the start of each line (0-indexed line number).
    line_starts: []const u32,
    allocator: std.mem.Allocator,

    pub fn build(allocator: std.mem.Allocator, source: []const u8) std.mem.Allocator.Error!LineIndex {
        var starts: std.ArrayList(u32) = .{};
        errdefer starts.deinit(allocator);

        try starts.append(allocator, 0); // Line 0 starts at offset 0.

        for (source, 0..) |byte, i| {
            if (byte == '\n') {
                try starts.append(allocator, @intCast(i + 1));
            }
        }

        return .{
            .line_starts = try starts.toOwnedSlice(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *LineIndex) void {
        self.allocator.free(self.line_starts);
        self.* = undefined;
    }

    /// Resolve a byte offset to a 1-based line:column pair.
    pub fn resolve(self: LineIndex, offset: u32) LineCol {
        // Binary search for the line containing this offset.
        const line = self.lineForOffset(offset);
        const col = offset - self.line_starts[line] + 1;
        return .{ .line = @intCast(line + 1), .col = col };
    }

    /// Get the text of the line containing the given byte offset.
    pub fn getLineText(self: LineIndex, offset: u32, source: []const u8) struct { text: []const u8, line_num: u32 } {
        const line = self.lineForOffset(offset);
        const start = self.line_starts[line];
        const end = if (line + 1 < self.line_starts.len)
            self.line_starts[line + 1]
        else
            @as(u32, @intCast(source.len));

        // Strip trailing newline if present.
        var text_end = end;
        if (text_end > start and source[text_end - 1] == '\n') {
            text_end -= 1;
        }
        if (text_end > start and source[text_end - 1] == '\r') {
            text_end -= 1;
        }

        return .{
            .text = source[start..text_end],
            .line_num = @intCast(line + 1),
        };
    }

    fn lineForOffset(self: LineIndex, offset: u32) usize {
        // Binary search: find the last line_start <= offset.
        var lo: usize = 0;
        var hi: usize = self.line_starts.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.line_starts[mid] <= offset) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
        return if (lo > 0) lo - 1 else 0;
    }
};

// =============================================================================
// Tests
// =============================================================================

test "Span - slice extracts correct text" {
    const source = "hello world";
    const span = Span{ .start = 6, .end = 11 };
    try std.testing.expectEqualStrings("world", span.slice(source));
}

test "Span - slice handles out of bounds gracefully" {
    const source = "hi";
    const span = Span{ .start = 0, .end = 100 };
    try std.testing.expectEqualStrings("hi", span.slice(source));
}

test "Span - merge combines spans" {
    const a = Span{ .start = 5, .end = 10 };
    const b = Span{ .start = 2, .end = 7 };
    const merged = a.merge(b);
    try std.testing.expectEqual(@as(u32, 2), merged.start);
    try std.testing.expectEqual(@as(u32, 10), merged.end);
}

test "LineIndex - single line" {
    var idx = try LineIndex.build(std.testing.allocator, "hello");
    defer idx.deinit();

    const lc = idx.resolve(3);
    try std.testing.expectEqual(@as(u32, 1), lc.line);
    try std.testing.expectEqual(@as(u32, 4), lc.col);
}

test "LineIndex - multiple lines" {
    const source = "line1\nline2\nline3";
    var idx = try LineIndex.build(std.testing.allocator, source);
    defer idx.deinit();

    // Start of line 1
    const lc1 = idx.resolve(0);
    try std.testing.expectEqual(@as(u32, 1), lc1.line);
    try std.testing.expectEqual(@as(u32, 1), lc1.col);

    // Start of line 2
    const lc2 = idx.resolve(6);
    try std.testing.expectEqual(@as(u32, 2), lc2.line);
    try std.testing.expectEqual(@as(u32, 1), lc2.col);

    // Middle of line 3
    const lc3 = idx.resolve(14);
    try std.testing.expectEqual(@as(u32, 3), lc3.line);
    try std.testing.expectEqual(@as(u32, 3), lc3.col);
}

test "LineIndex - getLineText" {
    const source = "first\nsecond\nthird";
    var idx = try LineIndex.build(std.testing.allocator, source);
    defer idx.deinit();

    const info = idx.getLineText(8, source);
    try std.testing.expectEqualStrings("second", info.text);
    try std.testing.expectEqual(@as(u32, 2), info.line_num);
}
