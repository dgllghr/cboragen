const std = @import("std");
const parser = @import("parser");
const Ast = parser.Ast;

const Allocator = std.mem.Allocator;

/// A group of types that must be emitted together.
/// If `is_recursive` is true, the group forms a mutually recursive cycle
/// and types must be joined with `and` in F#.
pub const TypeGroup = struct {
    names: []const []const u8,
    is_recursive: bool,
};

/// Information about a single type for the dependency graph.
pub const TypeInfo = struct {
    name: []const u8,
    def: Ast.TypeDef,
};

/// Topologically sort types, detecting mutually recursive groups via Tarjan's SCC.
/// Returns groups in dependency order (dependencies come first).
pub fn sort(arena: Allocator, all_types: []const TypeInfo) ![]const TypeGroup {
    const n = all_types.len;
    if (n == 0) return &.{};

    // Build name → index map
    var name_to_idx = std.StringHashMap(usize).init(arena);
    for (all_types, 0..) |ti, i| {
        try name_to_idx.put(ti.name, i);
    }

    // Build adjacency lists: edges[i] = set of indices that type i depends on
    var edges: std.ArrayList(std.ArrayList(usize)) = .{};
    for (0..n) |_| {
        try edges.append(arena, std.ArrayList(usize){});
    }

    for (all_types, 0..) |ti, i| {
        try collectDeps(arena, &edges.items[i], ti.def.ty, &name_to_idx);
    }

    // Tarjan's SCC algorithm
    var state = TarjanState{
        .index_counter = 0,
        .stack = .{},
        .on_stack = try arena.alloc(bool, n),
        .indices = try arena.alloc(i32, n),
        .lowlinks = try arena.alloc(i32, n),
        .sccs = .{},
        .arena = arena,
        .edges = edges.items,
    };
    @memset(state.on_stack, false);
    @memset(state.indices, -1);
    @memset(state.lowlinks, -1);

    for (0..n) |i| {
        if (state.indices[i] == -1) {
            try state.strongconnect(i);
        }
    }

    // Tarjan's produces SCCs such that dependencies come before dependents.
    // This is already the correct order for F# (define before use).
    const sccs = state.sccs.items;

    // Build TypeGroup list
    var groups: std.ArrayList(TypeGroup) = .{};
    for (sccs) |scc| {
        var names: std.ArrayList([]const u8) = .{};
        for (scc) |idx| {
            try names.append(arena, all_types[idx].name);
        }
        const is_recursive = if (scc.len > 1) true else blk: {
            // Single-element SCC: check for self-reference
            const idx = scc[0];
            for (edges.items[idx].items) |dep| {
                if (dep == idx) break :blk true;
            }
            break :blk false;
        };
        try groups.append(arena, .{
            .names = try names.toOwnedSlice(arena),
            .is_recursive = is_recursive,
        });
    }

    return try groups.toOwnedSlice(arena);
}

const TarjanState = struct {
    index_counter: i32,
    stack: std.ArrayList(usize),
    on_stack: []bool,
    indices: []i32,
    lowlinks: []i32,
    sccs: std.ArrayList([]usize),
    arena: Allocator,
    edges: []std.ArrayList(usize),

    fn strongconnect(self: *TarjanState, v: usize) !void {
        self.indices[v] = self.index_counter;
        self.lowlinks[v] = self.index_counter;
        self.index_counter += 1;
        try self.stack.append(self.arena, v);
        self.on_stack[v] = true;

        for (self.edges[v].items) |w| {
            if (self.indices[w] == -1) {
                try self.strongconnect(w);
                self.lowlinks[v] = @min(self.lowlinks[v], self.lowlinks[w]);
            } else if (self.on_stack[w]) {
                self.lowlinks[v] = @min(self.lowlinks[v], self.indices[w]);
            }
        }

        if (self.lowlinks[v] == self.indices[v]) {
            var scc: std.ArrayList(usize) = .{};
            while (true) {
                const w = self.stack.pop().?;
                self.on_stack[w] = false;
                try scc.append(self.arena, w);
                if (w == v) break;
            }
            try self.sccs.append(self.arena, try scc.toOwnedSlice(self.arena));
        }
    }
};

/// Collect type name dependencies from a TypeExpr.
fn collectDeps(
    arena: Allocator,
    deps: *std.ArrayList(usize),
    ty: Ast.TypeExpr,
    name_to_idx: *std.StringHashMap(usize),
) !void {
    switch (ty) {
        .bool, .string, .int, .float => {},
        .struct_ => |s| {
            for (s.fields) |field| {
                try collectDeps(arena, deps, field.ty, name_to_idx);
            }
        },
        .enum_ => {},
        .union_ => |u| {
            for (u.variants) |v| {
                if (v.payload) |payload| {
                    try collectDeps(arena, deps, payload, name_to_idx);
                }
            }
        },
        .array => |a| {
            try collectDeps(arena, deps, a.getElement(), name_to_idx);
        },
        .option => |o| {
            try collectDeps(arena, deps, o.child, name_to_idx);
        },
        .named => |n| {
            if (name_to_idx.get(n.name)) |idx| {
                // Avoid duplicate edges
                for (deps.items) |existing| {
                    if (existing == idx) return;
                }
                try deps.append(arena, idx);
            }
        },
        .qualified => |q| {
            // Qualified types (imports) are resolved externally, not in our graph
            if (name_to_idx.get(q.name)) |idx| {
                for (deps.items) |existing| {
                    if (existing == idx) return;
                }
                try deps.append(arena, idx);
            }
        },
    }
}
