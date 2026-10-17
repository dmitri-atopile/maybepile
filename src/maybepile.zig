pub const ast = @import("ast.zig");
pub const examples = @import("examples.zig");
pub const typechecker = @import("typechecker.zig");

const std = @import("std");
const expect = std.testing.expect;

test {
    std.testing.refAllDecls(@This());
}
