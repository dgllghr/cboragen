const std = @import("std");
const parser = @import("parser");
const FsGen = @import("FsGen.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var filename: ?[]const u8 = null;
    var namespace: ?[]const u8 = null;
    var varint_as_number = false;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printUsage();
            return;
        } else if (std.mem.eql(u8, arg, "--namespace")) {
            i += 1;
            if (i >= args.len) {
                const stderr = std.fs.File.stderr().deprecatedWriter();
                try stderr.writeAll("error: --namespace requires a value\n");
                std.process.exit(1);
            }
            namespace = args[i];
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

    const ns = namespace orelse {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        try stderr.writeAll("error: --namespace is required\n\n");
        try printUsage();
        std.process.exit(1);
    };

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

    // Resolve imports transitively
    var imports = std.StringHashMap(parser.Ast.Schema).init(gen_arena.allocator());
    var import_results: std.ArrayList(parser.ParseResult) = .{};
    defer {
        for (import_results.items) |*r| r.deinit();
        import_results.deinit(allocator);
    }
    var import_sources: std.ArrayList([]const u8) = .{};
    defer {
        for (import_sources.items) |s| allocator.free(s);
        import_sources.deinit(allocator);
    }

    const base_dir = std.fs.path.dirname(file_path) orelse ".";
    try resolveImports(allocator, &imports, &import_results, &import_sources, base_dir, schema.imports);

    const stdout = std.fs.File.stdout().deprecatedWriter();
    var gen = FsGen.init(stdout.any(), schema, imports, gen_arena.allocator(), .{
        .varint_as_number = varint_as_number,
        .namespace = ns,
    });
    gen.generate() catch |err| {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        try stderr.print("error: code generation failed: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}

fn resolveImports(
    allocator: std.mem.Allocator,
    imports: *std.StringHashMap(parser.Ast.Schema),
    import_results: *std.ArrayList(parser.ParseResult),
    import_sources: *std.ArrayList([]const u8),
    base_dir: []const u8,
    schema_imports: []const parser.Ast.Import,
) !void {
    for (schema_imports) |imp| {
        if (imports.contains(imp.namespace)) continue;

        // Resolve relative import path against base directory
        const import_path = try std.fs.path.resolve(allocator, &.{ base_dir, imp.path });
        defer allocator.free(import_path);

        const imp_source = std.fs.cwd().readFileAlloc(allocator, import_path, 10 * 1024 * 1024) catch |err| {
            const stderr = std.fs.File.stderr().deprecatedWriter();
            stderr.print("warning: cannot read import '{s}': {s}\n", .{ imp.path, @errorName(err) }) catch {};
            continue;
        };
        try import_sources.append(allocator, imp_source);

        var imp_result = parser.parse(allocator, imp_source);
        if (imp_result.hasErrors()) {
            const stderr = std.fs.File.stderr().deprecatedWriter();
            parser.renderDiagnostics(stderr.any(), imp_source, imp.path, imp_result.diagnostics.slice(), true) catch {};
            imp_result.deinit();
            continue;
        }

        if (imp_result.schema) |imp_schema| {
            try imports.put(imp.namespace, imp_schema);
            try import_results.append(allocator, imp_result);

            // Recursively resolve transitive imports
            const imp_base_dir = std.fs.path.dirname(import_path) orelse ".";
            try resolveImports(allocator, imports, import_results, import_sources, imp_base_dir, imp_schema.imports);
        } else {
            imp_result.deinit();
        }
    }
}

fn printUsage() !void {
    const stdout = std.fs.File.stdout().deprecatedWriter();
    try stdout.writeAll(
        \\Usage: cboragen-fs [options] <schema.cbg>
        \\
        \\Generate F# types, encoders, and decoders from a
        \\Proteus schema file. Output is written to stdout.
        \\
        \\Options:
        \\  --namespace <name>   F# namespace for generated code (required)
        \\  --varint-as-number   Map uvarint/ivarint to int instead of uint64/int64
        \\  --help, -h           Show this help
        \\
    );
}
