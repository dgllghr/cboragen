//! CLI tool for parsing Proteus schema files.
//!
//! Usage:
//!   cboragen-parse <file>              Parse and dump AST summary
//!   cboragen-parse --tokens <file>     Lex-only mode, print token stream
//!   cboragen-parse --no-color <file>   Disable ANSI colors

const std = @import("std");
const parser = @import("parser");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var filename: ?[]const u8 = null;
    var tokens_only = false;
    var use_color = true;

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--tokens")) {
            tokens_only = true;
        } else if (std.mem.eql(u8, arg, "--no-color")) {
            use_color = false;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printUsage();
            return;
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

    if (tokens_only) {
        try dumpTokens(source, file_path, use_color);
        return;
    }

    var result = parser.parse(allocator, source);
    defer result.deinit();

    if (result.hasErrors()) {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        try parser.renderDiagnostics(stderr.any(), source, file_path, result.diagnostics.slice(), use_color);
        std.process.exit(1);
    }

    // Dump AST summary to stdout.
    const stdout = std.fs.File.stdout().deprecatedWriter();
    if (result.schema) |schema| {
        try dumpSchema(stdout, schema);
    }
}

fn printUsage() !void {
    const stdout = std.fs.File.stdout().deprecatedWriter();
    try stdout.writeAll(
        \\Usage: cboragen-parse [options] <file>
        \\
        \\Options:
        \\  --tokens     Lex-only mode: print token stream
        \\  --no-color   Disable ANSI color output
        \\  --help, -h   Show this help
        \\
    );
}

fn dumpTokens(source: []const u8, filename: []const u8, use_color: bool) !void {
    _ = use_color;
    const stdout = std.fs.File.stdout().deprecatedWriter();
    var diags = parser.Diagnostic.DiagnosticList.init(std.heap.page_allocator);
    defer diags.deinit();

    var lexer = parser.Lexer.init(source, &diags);

    while (true) {
        const tok = lexer.next();
        try stdout.print("{d}..{d}  {s}", .{
            tok.span.start,
            tok.span.end,
            @tagName(tok.tag),
        });

        // Print token text for identifiers, keywords, literals.
        switch (tok.tag) {
            .identifier, .type_identifier, .integer_literal, .string_literal, .doc_comment => {
                try stdout.print("  \"{s}\"", .{tok.span.slice(source)});
            },
            else => {},
        }
        try stdout.writeByte('\n');

        if (tok.tag == .eof) break;
    }

    if (diags.hasErrors()) {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        try parser.renderDiagnostics(stderr.any(), source, filename, diags.slice(), true);
    }
}

fn dumpSchema(writer: anytype, schema: parser.Ast.Schema) !void {
    if (schema.imports.len > 0) {
        try writer.writeAll("Imports:\n");
        for (schema.imports) |imp| {
            try writer.print("  {s} = @import(\"{s}\")\n", .{ imp.namespace, imp.path });
        }
        try writer.writeByte('\n');
    }

    try writer.writeAll("Definitions:\n");
    for (schema.definitions) |def| {
        if (def.doc) |doc| {
            try writer.print("  /// {s}\n", .{doc});
        }
        try writer.print("  {s} = ", .{def.name});
        try dumpTypeExpr(writer, def.ty, 2);
        try writer.writeByte('\n');
    }
}

fn dumpTypeExpr(writer: anytype, ty: parser.Ast.TypeExpr, indent: usize) !void {
    switch (ty) {
        .bool => try writer.writeAll("bool"),
        .string => try writer.writeAll("string"),
        .bytes => try writer.writeAll("bytes"),
        .int => |i| try writer.print("{s}", .{@tagName(i.kind)}),
        .float => |f| try writer.print("{s}", .{@tagName(f.kind)}),
        .named => |n| try writer.print("{s}", .{n.name}),
        .qualified => |q| try writer.print("{s}.{s}", .{ q.namespace, q.name }),
        .option => |o| {
            try writer.writeByte('?');
            try dumpTypeExpr(writer, o.child, indent);
        },
        .array => |a| switch (a.*) {
            .variable => |v| {
                try writer.writeAll("[]");
                try dumpTypeExpr(writer, v.element, indent);
            },
            .fixed => |f_arr| {
                try writer.print("[{d}]", .{f_arr.len});
                try dumpTypeExpr(writer, f_arr.element, indent);
            },
            .external_len => |e| {
                try writer.print("[.{s}]", .{e.len_field});
                try dumpTypeExpr(writer, e.element, indent);
            },
        },
        .struct_ => |s| {
            try writer.writeAll("struct {");
            if (s.fields.len == 0) {
                try writer.writeByte('}');
                return;
            }
            try writer.writeByte('\n');
            for (s.fields) |field| {
                for (0..indent + 2) |_| try writer.writeByte(' ');
                try writer.print("{d} {s}: ", .{ field.rank, field.name });
                try dumpTypeExpr(writer, field.ty, indent + 2);
                try writer.writeByte('\n');
            }
            for (0..indent) |_| try writer.writeByte(' ');
            try writer.writeByte('}');
        },
        .enum_ => |e| {
            try writer.writeAll("enum {");
            if (e.variants.len == 0) {
                try writer.writeByte('}');
                return;
            }
            try writer.writeByte('\n');
            for (e.variants) |v| {
                for (0..indent + 2) |_| try writer.writeByte(' ');
                try writer.print("{d} {s}\n", .{ v.tag, v.name });
            }
            for (0..indent) |_| try writer.writeByte(' ');
            try writer.writeByte('}');
        },
        .union_ => |u| {
            try writer.writeAll("union {");
            if (u.variants.len == 0) {
                try writer.writeByte('}');
                return;
            }
            try writer.writeByte('\n');
            for (u.variants) |v| {
                for (0..indent + 2) |_| try writer.writeByte(' ');
                try writer.print("{d} {s}", .{ v.tag, v.name });
                if (v.payload) |payload| {
                    try writer.writeAll(": ");
                    try dumpTypeExpr(writer, payload, indent + 2);
                }
                try writer.writeByte('\n');
            }
            for (0..indent) |_| try writer.writeByte(' ');
            try writer.writeByte('}');
        },
    }
}
