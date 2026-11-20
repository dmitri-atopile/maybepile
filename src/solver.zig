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
        self.node = .{ .prev = null, .next = null };

        return self;
    }

    pub fn create(parent_allocator: std.mem.Allocator) error{OutOfMemory}!*@This() {
        const self = try parent_allocator.create(@This());
        self.* = .init(parent_allocator);
        return self;
    }

    pub fn dupe(self: @This(), parent_allocator: std.mem.Allocator) error{OutOfMemory}!@This() {
        // so the only things allocated by the arena allocator are internally-held paths
        // the other allocator is just used for the hashmap itself
        // so we just keep a hashmap from path to pointer to the internal path
        var new: @This() = .init(parent_allocator);

        var new_allocated_paths: std.HashMap(ast.VariablePath, ast.VariablePath, VariablePathContext, std.hash_map.default_max_load_percentage) = .init(parent_allocator);
        defer new_allocated_paths.deinit();

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

        // std.debug.print("{}\n", .{new});

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
                const t = ast.lookupVariablePathType(p, obj, env) catch unreachable;
                switch (t) {
                    .number => {
                        // base type
                        return try s.lookup(p);
                    },
                    .object => |name| {
                        const o = ast.findObject(name, env) catch unreachable;
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
                        const t0 = ast.lookupVariablePathType(p0, obj, env) catch unreachable;
                        const t1 = ast.lookupVariablePathType(p1, obj, env) catch unreachable;

                        if (typechecker.isSubtype(t0, t1, env) catch unreachable) {
                            // t0 is subtype of t1
                            // so we use public members of t1

                            const obj_next = ast.findObject(t1.object, env) catch unreachable;
                            for (obj_next.public_parameters) |param| {
                                var temp_arena: std.heap.ArenaAllocator = .init(s.allocator);
                                defer temp_arena.deinit();

                                const p0_ext = try std.mem.concat(temp_arena.allocator(), ast.Variable, &.{ p0, &.{param.name} });
                                const p1_ext = try std.mem.concat(temp_arena.allocator(), ast.Variable, &.{ p1, &.{param.name} });
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

    pub fn prependVariablePath(self: *@This(), v: ast.Variable) error{OutOfMemory}!void {
        const own_v = try self.arena.allocator().dupe(u8, v);

        // hashmap from old allocated path two new allocated path
        var new_allocated_paths: std.HashMap(ast.VariablePath, ast.VariablePath, VariablePathContext, std.hash_map.default_max_load_percentage) = .init(self.allocator);

        // new map with renamed values
        // cannot modify default map in-place b/c invalidates iterator
        var new_map: std.HashMap(ast.VariablePath, ast.Value, VariablePathContext, std.hash_map.default_max_load_percentage) = .init(self.allocator);

        var it = self.map.iterator();
        while (it.next()) |e| {
            // internalize the new key
            var new_key: ast.VariablePath = undefined;
            if (new_allocated_paths.get(e.key_ptr.*)) |found_key_path| {
                new_key = found_key_path;
            } else {
                new_key = try std.mem.concat(self.arena.allocator(), ast.Variable, &.{ &.{own_v}, e.key_ptr.* });
                try new_allocated_paths.put(e.key_ptr.*, new_key);
            }

            // internalize the new value
            var new_val: ast.Value = undefined;
            switch (e.value_ptr.*) {
                .number => new_val = e.value_ptr.*,
                .path => |p| {
                    if (new_allocated_paths.get(p)) |found_val_path| {
                        new_val = .{.path = found_val_path};
                    } else {
                        const new_val_path = try std.mem.concat(self.arena.allocator(), ast.Variable, &.{ &.{own_v}, p });
                        try new_allocated_paths.put(p, new_val_path);
                        new_val = .{.path = new_val_path};

                    }
                }
            }

            // use the new paths
            try new_map.put(new_key, new_val);
            
        }

        // swap out the maps
        self.map.deinit();
        self.map = new_map;
        
    }
};

// substitution stream

pub const SubstitutionStreamIterator = struct {
    node: ?*std.DoublyLinkedList.Node,

    pub fn next(self: *@This()) ?*Substitution {
        if (self.node) |self_node| {
            const s: *Substitution = @fieldParentPtr("node", self_node);
            self.node = self_node.next;
            return s;
        } else {
            return null;
        }
    }
};

pub const SubstitutionStream = struct {
    list: std.DoublyLinkedList,

    // basic functionality

    pub const init: @This() = .{ .list = .{ .first = null, .last = null } };

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        // all Substitutions in the stream are expected to have been allocated with the passed allocator

        var self_it = self.iterator();
        while (self_it.next()) |s| {
            s.deinit();
            allocator.destroy(s);
        }

        self.list.first = null;
        self.list.last = null;
    }

    pub fn append(self: *@This(), s: *Substitution) void {
        self.list.append(&s.node);
    }

    pub fn prepend(self: *@This(), s: *Substitution) void {
        self.list.prepend(&s.node);
    }

    pub fn concat(self: *@This(), other: *@This()) void {
        self.list.concatByMoving(&other.list);
    }

    pub fn iterator(self: *@This()) SubstitutionStreamIterator {
        const it: SubstitutionStreamIterator = .{ .node = self.list.first };
        return it;
    }

    pub fn dupe(self: *@This(), allocator: std.mem.Allocator) error{OutOfMemory}!@This() {
        var new: @This() = .init;

        var self_it = self.iterator();
        while (self_it.next()) |s| {
            const s_new: *Substitution = try allocator.create(Substitution);
            s_new.* = try s.dupe(allocator);
            new.append(s_new);
        }

        return new;
    }

    pub fn merge(self: *@This(), other: *@This(), allocator: std.mem.Allocator) error{OutOfMemory}!void {

        var new_st: @This() = .init;
        
        var self_it = self.iterator();
        while (self_it.next()) |self_s| {
            var other_it = other.iterator();
            while (other_it.next()) |other_s| {
                const new_s = try allocator.create(Substitution);
                new_s.* = try self_s.dupe(allocator);
                try new_s.*.merge(other_s.*);
                new_st.append(new_s);
            }
        }
        
        self.deinit(allocator);
        other.deinit(allocator);
        
        self.* = new_st;
    }

    pub fn prependVariablePath(self: *@This(), v: ast.Variable) error{OutOfMemory}!void {
        
        var self_it = self.iterator();
        while (self_it.next()) |s| {
            try s.prependVariablePath(v);
        }
    }

};

// implementing solver

const SolverError = error{OutOfMemory, ObjectNotFound};

fn constraintEquals(st: *SubstitutionStream, c: ast.Constraint, obj: ast.Object, env: ast.Program, allocator: std.mem.Allocator) SolverError!void {
    const eqs = c.equals;

    // track what should point to current node, and last node
    var prev_next_ptr_ptr: *?*std.DoublyLinkedList.Node = &st.list.first;
    var prev_node_ptr: ?*std.DoublyLinkedList.Node = null;

    var it = st.iterator();
    while (it.next()) |s| {
        const unify_success = try s.unify(eqs[0], eqs[1], obj, env);

        if (unify_success) {
            prev_next_ptr_ptr.* = &s.node;
            s.node.prev = prev_node_ptr;

            prev_next_ptr_ptr = &s.node.next;
            prev_node_ptr = &s.node;
        } else {
            s.deinit();
            allocator.destroy(s);
        }
    }

    st.list.last = prev_node_ptr;

}

fn applyConstraint(st: *SubstitutionStream, c: ast.Constraint, obj: ast.Object, env: ast.Program, allocator: std.mem.Allocator) SolverError!void {

    switch (c) {
        .equals => try constraintEquals(st, c, obj, env, allocator),
    }

}

fn loadChildObject(st: *SubstitutionStream, name: ast.Variable, obj_type: ast.ObjectType, solutions: std.StringHashMap(SubstitutionStream), allocator: std.mem.Allocator) SolverError!void {

    if (solutions.getPtr(obj_type)) |child_stream| {
        try child_stream.prependVariablePath(name);
        try st.merge(child_stream, allocator);
    } else {
        return SolverError.ObjectNotFound;
    }

}

fn loadParameter(st: *SubstitutionStream, param: ast.Parameter, solutions: std.StringHashMap(SubstitutionStream), allocator: std.mem.Allocator) SolverError!void {
    switch (param.type) {
        .number => {},
        .object => |ot| {
            try loadChildObject(st, param.name, ot, solutions, allocator);
        }
    }

}


fn solveObject(obj: ast.Object, env: ast.Program, solutions: *std.StringHashMap(SubstitutionStream), allocator: std.mem.Allocator) SolverError!SubstitutionStream {

    var stream: SubstitutionStream = .init;

    // load child objects
    for (obj.public_parameters) |param| {
        try loadParameter(&stream, param, solutions.*, allocator);
    }
    for (obj.private_parameters) |param| {
        try loadParameter(&stream, param, solutions.*, allocator);
    }

    // apply this object's constraints from list
    for (obj.constraints) |c| {
        try applyConstraint(&stream, c, obj, env, allocator);
    }

    // apply traits
    var temp_allocator: std.heap.ArenaAllocator = .init(allocator);
    defer temp_allocator.deinit();


    for (obj.traits, 0..) |t, i| {
        const trait_obj = ast.findObject(t, env) catch return SolverError.ObjectNotFound;

        const trait_param_name = try std.fmt.allocPrint(temp_allocator.allocator(), "_{}", .{i});
        try loadChildObject(&stream, trait_param_name, t, solutions.*, allocator);

        for (trait_obj.public_parameters) |p| {
            try constraintEquals(&stream, .{.equals = .{.{.path = &.{p.name} }, .{.path = &.{trait_param_name, p.name}}}}, obj, env, allocator);
        }
    }

    return stream;
    
}

pub fn solve(program: ast.Program, allocator: std.mem.Allocator) SolverError!std.StringHashMap(SubstitutionStream) {

    var object_solutions: std.StringHashMap(SubstitutionStream) = .init(allocator);

    for (program) |object| {
        const solution = try solveObject(object, program, &object_solutions, allocator);
        try object_solutions.put(object.name, solution);
    }

    return object_solutions;

}

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

    try s0.update(&.{"a"}, .{ .number = 5 });
    try s1.update(&.{"b"}, .{ .number = 6 });

    try s0.merge(s1);

    try expect(ast.valuesEqual(try s0.lookup(&.{"b"}), .{ .number = 6 }));
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

test "SubstitutionStream" {
    const s0: *Substitution = try .create(std.testing.allocator);
    const s1: *Substitution = try .create(std.testing.allocator);
    const s2: *Substitution = try .create(std.testing.allocator);

    var st0: SubstitutionStream = .init;
    defer st0.deinit(std.testing.allocator);

    st0.append(s1);
    st0.prepend(s0);
    st0.append(s2);

    var st1 = try st0.dupe(std.testing.allocator);
    defer st1.deinit(std.testing.allocator);

    var st0_iter = st0.iterator();
    try expectEqual(st0_iter.next(), s0);
    try expectEqual(st0_iter.next(), s1);
    try expectEqual(st0_iter.next(), s2);
    try expect(st0_iter.next() == null);

    st0.concat(&st1);

    st0_iter = st0.iterator();
    try expectEqual(st0_iter.next(), s0);
    try expectEqual(st0_iter.next(), s1);
    try expectEqual(st0_iter.next(), s2);
    _ = st0_iter.next();
    _ = st0_iter.next();
    _ = st0_iter.next();
    try expect(st0_iter.next() == null);
}

test "Solver" {

    _ = try solve(examples.junction_program, std.testing.allocator);


}
