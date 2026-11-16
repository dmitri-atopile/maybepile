const std = @import("std");

const ast = @import("ast.zig");
const typechecker = @import("typechecker.zig");

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
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    map: std.HashMap(ast.VariablePath, ast.Value, VariablePathContext, std.hash_map.default_max_load_percentage),
    node: std.DoublyLinkedList.Node,

    // core operations

    pub fn init(parent_allocator: std.mem.Allocator) @This() {
        var self: @This() = undefined;

        self.allocator = parent_allocator;
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
                        try new.map.put(p_key, .{ .path = p_new });
                    } else {
                        const p_new = try ast.dupeVariablePath(new.arena.allocator(), p);
                        try new_allocated_paths.put(p_new, p_new);
                        try new.map.put(p_key, .{ .path = p_new });
                    }
                },
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
                },
            }
        } else {
            // by default, map variable path to itself
            const vp_internal = try ast.dupeVariablePath(self.arena.allocator(), vp);
            const v: ast.Value = .{ .path = vp_internal };
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

    pub fn merge(self: *@This(), other: @This()) error{OutOfMemory}!void {
        var other_map_iterator = other.map.iterator();
        while (other_map_iterator.next()) |entry| {
            try self.update(entry.key_ptr.*, entry.value_ptr.*);
        }
    }

    // unification

    fn normalize(s: *@This(), v: ast.Value, obj: ast.Object, env: ast.Program) error{OutOfMemory}!ast.Value {
        // looks up value if it's a base or concrete value
        // otherwise just returns path
        switch (v) {
            .number => {
                // nothing to look up
                return v;
            },
            .path => |p| {
                const t = typechecker.lookupVariablePathType(p, obj, env) catch unreachable;
                switch (t) {
                    .number => {
                        // base type
                        return try s.lookup(p);
                    },
                    .object => |name| {
                        const o = typechecker.findObject(name, env) catch unreachable;
                        if (o.public_parameters.len > 0) {
                            // not base type
                            return v;
                        } else {
                            // base type
                            return s.lookup(p);
                        }
                    },
                }
            },
        }
    }

    pub fn unify(s: *@This(), v_raw0: ast.Value, v_raw1: ast.Value, obj: ast.Object, env: ast.Program) error{OutOfMemory}!bool {
        const v0 = try s.normalize(v_raw0, obj, env);
        const v1 = try s.normalize(v_raw1, obj, env);

        // std.debug.print("v0: {}\n", .{v0});
        // std.debug.print("v1: {}\n", .{v1});

        switch (v0) {
            .number => |n0| {
                switch (v1) {
                    .number => |n1| {
                        return n0 == n1;
                    },
                    .path => |p1| {
                        try s.update(p1, v0);
                        return true;
                    },
                }
            },
            .path => |p0| {
                switch (v1) {
                    .number => {
                        try s.update(p0, v1);
                        return true;
                    },
                    .path => |p1| {
                        const t0 = typechecker.lookupVariablePathType(p0, obj, env) catch unreachable;
                        const t1 = typechecker.lookupVariablePathType(p1, obj, env) catch unreachable;

                        if (typechecker.isSubtype(t0, t1, env) catch unreachable) {
                            // t0 is subtype of t1
                            // so we use public members of t1

                            const obj_next = typechecker.findObject(t1.object, env) catch unreachable;
                            for (obj_next.public_parameters) |param| {
                                var temp_arena: std.heap.ArenaAllocator = .init(s.allocator);
                                defer temp_arena.deinit();

                                const p0_ext = try std.mem.concat(temp_arena.allocator(), []const u8, &.{ p0, &.{param.name} });
                                const p1_ext = try std.mem.concat(temp_arena.allocator(), []const u8, &.{ p1, &.{param.name} });
                                if (try s.unify(.{ .path = p0_ext }, .{ .path = p1_ext }, obj, env)) {
                                    continue;
                                } else {
                                    return false;
                                }
                            }
                            return true;
                        } else if (typechecker.isSubtype(t1, t0, env) catch unreachable) {
                            // p1 is subtype of p0 (guaranteed by typechecker)
                            return try s.unify(v1, v0, obj, env); // swap arguments to avoid duplicate code
                        } else {
                            unreachable;
                        }
                    },
                }
            },
        }
    }
};

// substitution stream

pub const SubstitutionStream = struct {
    node: std.DoublyLinkedList,

};


// tests

const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

const examples = @import("examples.zig");

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(Substitution);
}

test "VariablePathContext" {
    const vpc: VariablePathContext = .{};

    try expectEqual(vpc.hash(&.{ "a", "b", "c" }), vpc.hash(&.{ "a", "b", "c" }));

    try expect(vpc.hash(&.{ "a", "b", "c" }) != vpc.hash(&.{ "x", "y", "z" }));
}

test "Substitution init,update,lookup,dupe" {
    var s0: Substitution = .init(std.testing.allocator);

    try expect(ast.valuesEqual(try s0.lookup(&.{ "a", "b", "c" }), try s0.lookup(&.{ "a", "b", "c" })));
    try expect(!ast.valuesEqual(try s0.lookup(&.{ "a", "b", "c" }), try s0.lookup(&.{ "x", "y", "z" })));

    try s0.update(&.{ "a", "b", "c" }, .{ .number = 5 });
    try expect(!ast.valuesEqual(try s0.lookup(&.{ "a", "b", "c" }), try s0.lookup(&.{ "x", "y", "z" })));

    try s0.update(&.{ "x", "y", "z" }, .{ .number = 5 });
    try expect(ast.valuesEqual(try s0.lookup(&.{ "a", "b", "c" }), try s0.lookup(&.{ "x", "y", "z" })));

    try s0.update(&.{ "a", "b", "c" }, .{ .path = &.{ "d", "e", "f" } });
    try expect(ast.valuesEqual(try s0.lookup(&.{ "a", "b", "c" }), try s0.lookup(&.{ "d", "e", "f" })));

    try s0.update(&.{ "d", "e", "f" }, .{ .number = 6 });
    try expect(ast.valuesEqual(try s0.lookup(&.{ "a", "b", "c" }), try s0.lookup(&.{ "d", "e", "f" })));

    var s1 = try s0.dupe(std.testing.allocator);
    defer s1.deinit();

    s0.deinit();

    try expect(ast.valuesEqual(try s1.lookup(&.{ "a", "b", "c" }), try s1.lookup(&.{ "d", "e", "f" })));
}

test "Substitution merge" {

    var s0: Substitution = .init(std.testing.allocator);
    defer s0.deinit();

    var s1: Substitution = .init(std.testing.allocator);
    defer s1.deinit();

    try s0.update(&.{"a"}, .{.number = 5});
    try s1.update(&.{"b"}, .{.number = 6});

    try s0.merge(s1);

    try expect(ast.valuesEqual(try s0.lookup(&.{"b"}), .{.number = 6}));
}

test "Substitution unify" {
    var s: Substitution = .init(std.testing.allocator);
    defer s.deinit();

    try expect(try s.unify(.{ .number = 5.0 }, .{ .number = 5.0 }, examples.f, examples.abcdef_program));
    try expect(!try s.unify(.{ .number = 5.0 }, .{ .number = 6.0 }, examples.f, examples.abcdef_program));
    try expect(try s.unify(.{ .path = &.{ "a", "b", "c" } }, .{ .number = 5.0 }, examples.f, examples.abcdef_program));
    try expect(!try s.unify(.{ .path = &.{ "a", "b", "c" } }, .{ .number = 6.0 }, examples.f, examples.abcdef_program));
    try expect(try s.unify(.{ .path = &.{ "a", "b", "c" } }, .{ .path = &.{ "d", "e", "c" } }, examples.f, examples.abcdef_program));
    try expect(!try s.unify(.{ .number = 6.0 }, .{ .path = &.{ "d", "e", "c" } }, examples.f, examples.abcdef_program));
}
