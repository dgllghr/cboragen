const std = @import("std");

pub const TypeMapping = struct {
    schema_type: []const u8,
    fsharp_type: []const u8,
    codec_module: []const u8,
};

pub const Config = struct {
    mappings: []const TypeMapping,

    /// Build a name → TypeMapping lookup map for use during code generation.
    pub fn toRegistry(self: Config, allocator: std.mem.Allocator) !std.StringHashMap(TypeMapping) {
        var map = std.StringHashMap(TypeMapping).init(allocator);
        for (self.mappings) |m| {
            try map.put(m.schema_type, m);
        }
        return map;
    }
};

pub const ParseError = error{
    InvalidFormat,
    OutOfMemory,
};

/// Parse a minimal TOML config file with `[[mappings]]` entries.
///
/// Supported format:
/// ```toml
/// [[mappings]]
/// schema_type = "Uuid"
/// fsharp_type = "System.Guid"
/// codec_module = "UuidCodec"
/// ```
pub fn parse(allocator: std.mem.Allocator, source: []const u8) ParseError!Config {
    var mappings: std.ArrayList(TypeMapping) = .{};
    var current: ?TypeMapping = null;

    var line_iter = std.mem.splitScalar(u8, source, '\n');
    while (line_iter.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, &.{ ' ', '\t', '\r' });

        // Skip empty lines and comments
        if (line.len == 0) continue;
        if (line[0] == '#') continue;

        // [[mappings]] — start a new entry
        if (std.mem.eql(u8, line, "[[mappings]]")) {
            if (current) |c| {
                try mappings.append(allocator, c);
            }
            current = .{
                .schema_type = "",
                .fsharp_type = "",
                .codec_module = "",
            };
            continue;
        }

        // key = "value"
        const eq_idx = std.mem.indexOfScalar(u8, line, '=') orelse return error.InvalidFormat;
        const key = std.mem.trim(u8, line[0..eq_idx], &.{ ' ', '\t' });
        const val_part = std.mem.trim(u8, line[eq_idx + 1 ..], &.{ ' ', '\t' });

        // Must be quoted string
        if (val_part.len < 2 or val_part[0] != '"' or val_part[val_part.len - 1] != '"')
            return error.InvalidFormat;
        const val = val_part[1 .. val_part.len - 1];

        var entry = &(current orelse return error.InvalidFormat);
        if (std.mem.eql(u8, key, "schema_type")) {
            entry.schema_type = val;
        } else if (std.mem.eql(u8, key, "fsharp_type")) {
            entry.fsharp_type = val;
        } else if (std.mem.eql(u8, key, "codec_module")) {
            entry.codec_module = val;
        } else {
            return error.InvalidFormat;
        }
    }

    // Flush last entry
    if (current) |c| {
        try mappings.append(allocator, c);
    }

    return .{
        .mappings = try mappings.toOwnedSlice(allocator),
    };
}
