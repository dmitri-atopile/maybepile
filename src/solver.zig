
const std = @import("std");

const ast = @import("ast.zig");

// substitutions

const VariablePathContext = struct {
    pub fn hash(self: @This(), a: ast.VariablePath) u64 {
        _ = self;
        // looking at implementation, probably shouldn't use 0 or 1 as seed
        var wyhash = std.hash.Wyhash.init(2);
        for (a) |x| {
            wyhash.update(x);
        }
        return wyhash.final();
    }

    pub fn eql(self: @This(), a: ast.VariablePath, b: ast.VariablePath) bool {
        _ = self;
        return ast.variablePathsEqual(a, b);
    }
};

pub const Substitution = struct {
    arena: std.heap.ArenaAllocator,
    map: std.HashMap(ast.VariablePath, ast.Value, VariablePathContext, std.hash_map.default_max_load_percentage),

    pub fn init(parent_allocator: std.mem.Allocator) @This() {

        var self: @This() = undefined;

        self.arena = .init(parent_allocator);
        self.map = .init(parent_allocator);

        return self;
    }

    pub fn dupe(self: @This(), parent_allocator: std.mem.Allocator) error{OutOfMemory}!@This() {
        // so the only things allocated by the arena allocator are internally-held paths
        // the other allocator is just used for the hashmap itself
        // so we just keep a hashmap from path to pointer to the internal path
        var new: @This() = undefined;

        new.arena = .init(parent_allocator);
        new.map = .init(parent_allocator);

        var new_allocated_paths: std.HashMap(ast.VariablePath, ast.VariablePath, VariablePathContext, std.hash_map.default_max_load_percentage) = .init(parent_allocator);
        
        var self_map_iterator = self.map.iterator();
        while (self_map_iterator.next()) |entry| {
            var p_key: ast.VariablePath = undefined;
            if (new_allocated_paths.get(entry.key_ptr.*)) |p_found| {
                p_key = p_found;
            } else {
                p_key = try ast.dupeVariablePath(new.arena.allocator(), entry.key_ptr.*);
                try new_allocated_paths.put(p_key, p_key);
            }
            switch (entry.value_ptr.*) {
                .number => {
                    try new.map.put(p_key, entry.value_ptr.*);
                },
                .path => |p| {
                    if (new_allocated_paths.get(p)) |p_new| {
                        try new.map.put(p_key, .{.path = p_new});
                    } else {
                        const p_new = try ast.dupeVariablePath(new.arena.allocator(), p);
                        try new_allocated_paths.put(p_new, p_new);
                        try new.map.put(p_key, .{.path = p_new});
                    }
                }
            }
        }

        new_allocated_paths.deinit();

        return new;
    }

    pub fn deinit(self: *@This()) void {
        self.map.deinit();
        self.arena.deinit();
    }

    pub fn lookup(self: *@This(), vp: ast.VariablePath) error{OutOfMemory}!ast.Value {
        const v_op = self.map.get(vp);

        if (v_op) |v| {
            switch (v) {
                .number => {
                    return v;
                },
                .path => |p| {
                    if (ast.variablePathsEqual(vp, p)) {
                        return v;
                    } else {
                        const v_deep = try self.lookup(p);
                        try self.map.put(vp, v_deep);
                        return v_deep;
                    }
                }
            }
        } else {
            // by default, map variable path to itself
            const vp_internal = try ast.dupeVariablePath(self.arena.allocator(), vp);
            const v: ast.Value = .{.path = vp_internal};
            try self.map.put(vp_internal, v);
            return v;
        }
    }

    pub fn update(self: *@This(), vp: ast.VariablePath, v: ast.Value) error{OutOfMemory}!void {
        if (self.map.getKey(vp)) |vp_internal| {
            try self.map.put(vp_internal, v);
        } else {
            const vp_internal = try ast.dupeVariablePath(self.arena.allocator(), vp);
            try self.map.put(vp_internal, v);
        }
    }

};

// substitution stream

pub const SubstitutionStream = std.ArrayList(Substitution);

// unifcation

fn unify(
    vp0: ast.VariablePath,
    vp1: ast.VariablePath,
    s: Substitution
) ?Substitution {
    const v0 = s.lookup(vp0);
    const v1 = s.lookup(vp1);

    // might be better to do v0 == v1, then only switch on one of them

    switch (v0) {
        .number => |n0| {
            switch (v1) {
                .number => |n1| {
                    if (n0 == n1) {
                        return s;
                    } else {
                        return null;
                    }
                },
                .path => |p1| {
                    s.updateAll(p1, v0);
                    return s;
                }
            }
        },
        .path => |p0| {
            switch (v1) {
                .number => {
                    s.updateAll(p0, v1);
                    return s;
                },
                .path => {
                    s.updateAll(p0, v1);
                    return s;
                }
            }
        }

    }

}

// tests

const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(Substitution);
}

test "VariablePathContext" {
    const vpc: VariablePathContext = .{};

    try expectEqual(
        vpc.hash(&.{"a", "b", "c"}),
        vpc.hash(&.{"a", "b", "c"})
    );

    try expect(vpc.hash(&.{"a", "b", "c"}) != vpc.hash(&.{"x", "y", "z"}));
}

test "Substitution" {
    var s0: Substitution = .init(std.testing.allocator);

    try expect(ast.valuesEqual(try s0.lookup(&.{"a", "b", "c"}), try s0.lookup(&.{"a", "b", "c"})));
    try expect(!ast.valuesEqual(try s0.lookup(&.{"a", "b", "c"}), try s0.lookup(&.{"x", "y", "z"})));
    
    try s0.update(&.{"a", "b", "c"}, .{.number = 5});
    try expect(!ast.valuesEqual(try s0.lookup(&.{"a", "b", "c"}), try s0.lookup(&.{"x", "y", "z"})));

    try s0.update(&.{"x", "y", "z"}, .{.number = 5});
    try expect(ast.valuesEqual(try s0.lookup(&.{"a", "b", "c"}), try s0.lookup(&.{"x", "y", "z"})));

    try s0.update(&.{"a", "b", "c"}, .{.path = &.{"d", "e", "f"}});
    try expect(ast.valuesEqual(try s0.lookup(&.{"a", "b", "c"}), try s0.lookup(&.{"d", "e", "f"})));

    try s0.update(&.{"d", "e", "f"}, .{.number = 6});
    try expect(ast.valuesEqual(try s0.lookup(&.{"a", "b", "c"}), try s0.lookup(&.{"d", "e", "f"})));

    var s1 = try s0.dupe(std.testing.allocator);
    defer s1.deinit();

    s0.deinit();

    try expect(ast.valuesEqual(try s1.lookup(&.{"a", "b", "c"}), try s1.lookup(&.{"d", "e", "f"})));

}
