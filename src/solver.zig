
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
        if (a.len != b.len) {
            return false;
        }
        for (a, b) |x, y| {
            if (!std.mem.eql(u8, x, y)) return false;
        }
        return true;
    }
};

pub const Substitution = std.HashMapUnmanaged(
    ast.VariablePath,
    ast.Value,
    VariablePathContext,
    std.hash_map.default_max_load_percentage
);

// tests

const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

test {
    std.testing.refAllDecls(@This());
}

test "VariablePathContext.hash" {
    const vpc: VariablePathContext = .{};

    try expectEqual(
        vpc.hash(&.{"a", "b", "c"}),
        vpc.hash(&.{"a", "b", "c"})
    );

    try expect(vpc.hash(&.{"a", "b", "c"}) != vpc.hash(&.{"x", "y", "z"}));
}

test "VariablePathContext.eql" {
    const vpc: VariablePathContext = .{};

    try expect(vpc.eql(&.{"a", "b", "c"}, &.{"a", "b", "c"}));
    try expect(!vpc.eql(&.{"a", "b", "c"}, &.{"x", "y", "z"}));
}
