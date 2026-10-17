
const std = @import("std");

// objects have a user-defined type name
pub const ObjectType = []const u8;

// type of a value
pub const Type = union(enum) {
    number: void,
    object: ObjectType
};

pub fn types_equal(t0: Type, t1: Type) bool {
    switch(t0) {
        .number => switch(t1) {
            .number => return true,
            .object => return false
        },
        .object => |o0| switch(t1) {
            .number => return false,
            .object => |o1| {
                return std.mem.eql(u8, o0, o1);
            }
        }
    }
}

// variable is user-defined name
pub const Variable = []const u8;

// variable path allows indexing into contained objects
pub const VariablePath = []const Variable;

// value is either a raw number, or variable path
// can have a variable path point to a number
pub const Value = union(enum) {
    number: f64,
    path: VariablePath,
};

// constraints
pub const Constraint = union(enum) {
    equals: struct {Value, Value},
    gennum: Value
};

// parameters
pub const Parameter = struct {name: Variable, type: Type};

// object definitions
pub const Object = struct {
    name: ObjectType,
    public_parameters: []const Parameter,
    private_parameters: []const Parameter,
    constraints: []const Constraint,
    traits: []const ObjectType
};

// programs
pub const Program = []const (Object);

// tests

const expect = std.testing.expect;

test {
    std.testing.refAllDecls(@This());
}

test "types_equal" {
    try expect(types_equal(.{.number = {}}, .{.number = {}}));
    try expect(types_equal(.{.object = "Resistor"}, .{.object = "Resistor"}));

    try expect(!types_equal(.{.number = {}}, .{.object = "Resistor"}));
    try expect(!types_equal(.{.object = "Resistor"}, .{.number = {}}));
    try expect(!types_equal(.{.object = "Resistor"}, .{.object = "Transistor"}));
}

