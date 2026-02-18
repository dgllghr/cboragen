const std = @import("std");
const parser = @import("parser");
const TsGen = @import("TsGen.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var filename: ?[]const u8 = null;
    var varint_as_number = false;

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printUsage();
            return;
        } else if (std.mem.eql(u8, arg, "--varint-as-number")) {
            varint_as_number = true;
        } else if (arg.len > 0 and arg[0] == '-') {
            const stderr = std.fs.File.stderr().deprecatedWriter();
            try stderr.print("unknown option: {s}\n", .{arg});
            std.process.exit(1);
        } else {
            filename = arg;
        }
    }

    const file_path = filename orelse {
        try printUsage();
        std.process.exit(1);
    };

    const source = std.fs.cwd().readFileAlloc(allocator, file_path, 10 * 1024 * 1024) catch |err| {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        try stderr.print("error: cannot read '{s}': {s}\n", .{ file_path, @errorName(err) });
        std.process.exit(1);
    };
    defer allocator.free(source);

    var result = parser.parse(allocator, source);
    defer result.deinit();

    if (result.hasErrors()) {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        try parser.renderDiagnostics(stderr.any(), source, file_path, result.diagnostics.slice(), true);
        std.process.exit(1);
    }

    const schema = result.schema orelse {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        try stderr.writeAll("error: parse produced no schema\n");
        std.process.exit(1);
    };

    var gen_arena = std.heap.ArenaAllocator.init(allocator);
    defer gen_arena.deinit();

    const stdout = std.fs.File.stdout().deprecatedWriter();
    var gen = TsGen.init(stdout.any(), schema, gen_arena.allocator(), .{
        .varint_as_number = varint_as_number,
    });
    gen.generate() catch |err| {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        try stderr.print("error: code generation failed: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}

fn printUsage() !void {
    const stdout = std.fs.File.stdout().deprecatedWriter();
    try stdout.writeAll(
        \\Usage: cboragen-ts [options] <schema.cbg>
        \\
        \\Generate TypeScript types, encoders, and decoders from a
        \\Proteus schema file. Output is written to stdout.
        \\
        \\Options:
        \\  --varint-as-number   Map uvarint/ivarint to number instead of bigint
        \\  --help, -h           Show this help
        \\
    );
}
