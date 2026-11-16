const std = @import("std");

// objects have a user-defined type name
pub const ObjectType = []const u8;

// type of a value
pub const Type = union(enum) { number: void, object: ObjectType };

pub fn typesEqual(t0: Type, t1: Type) bool {
    switch (t0) {
        .number => switch (t1) {
            .number => return true,
            .object => return false,
        },
        .object => |o0| switch (t1) {
            .number => return false,
            .object => |o1| {
                return std.mem.eql(u8, o0, o1);
            },
        },
    }
}

// variable is user-defined name
pub const Variable = []const u8;

// variable path allows indexing into contained objects
pub const VariablePath = []const Variable;

pub fn variablePathsEqual(vp0: VariablePath, vp1: VariablePath) bool {
    if (vp0.len != vp1.len) {
        return false;
    }

    for (vp0, vp1) |v0, v1| {
        if (!std.mem.eql(u8, v0, v1)) return false;
    }

    return true;
}

pub fn dupeVariablePath(allocator: std.mem.Allocator, vp: VariablePath) error{OutOfMemory}!VariablePath {
    var new_vp = try allocator.alloc(Variable, vp.len);
    for (vp, 0..) |v, n| {
        new_vp[n] = try allocator.dupe(u8, v);
    }

    return new_vp;
}

// value is either a raw number, or variable path
// can have a variable path point to a number
pub const Value = union(enum) {
    number: f64,
    path: VariablePath,
};

pub fn valuesEqual(v0: Value, v1: Value) bool {
    switch (v0) {
        .number => |n0| {
            switch (v1) {
                .number => |n1| return n0 == n1,
                .path => return false,
            }
        },
        .path => |p0| {
            switch (v1) {
                .number => return false,
                .path => |p1| return variablePathsEqual(p0, p1),
            }
        },
    }
}

// constraints
pub const Constraint = union(enum) { equals: struct { Value, Value } };

// parameters
pub const Parameter = struct { name: Variable, type: Type };

// object definitions
pub const Object = struct { name: ObjectType, public_parameters: []const Parameter, private_parameters: []const Parameter, constraints: []const Constraint, traits: []const ObjectType };

// programs
pub const Program = []const (Object);

// helper functions

const LookupError = error{VariablePathNotFound, NumberIsNotObject, ObjectNotFound};

pub fn findObject(object_type: ObjectType, env: Program) LookupError!Object {
    for (env) |obj| {
        if (std.mem.eql(u8, object_type, obj.name)) {
            return obj;
        }
    }
    return LookupError.ObjectNotFound;
}

fn findParameter(name: Variable, obj: Object) LookupError!Parameter {
    // std.debug.print("{s} in {s}\n", .{name, obj.name});
    for (obj.public_parameters) |param| {
        if (std.mem.eql(u8, name, param.name)) {
            return param;
        }
    }
    for (obj.private_parameters) |param| {
        if (std.mem.eql(u8, name, param.name)) {
            return param;
        }
    }
    return LookupError.VariablePathNotFound;
}

pub fn lookupVariablePathType(vp: VariablePath, obj: Object, env: Program) LookupError!Type {
    if (vp.len == 0) {
        return .{ .object = obj.name };
    } else {
        const param = try findParameter(vp[0], obj);
        switch (param.type) {
            .number => {
                if (vp.len == 1) {
                    // if do not need to desend any further into the path
                    return .{ .number = {} };
                } else {
                    // otherwise cannot descend further into the path
                    return LookupError.NumberIsNotObject;
                }
            },
            .object => |object_type| {
                return try lookupVariablePathType(vp[1..], try findObject(object_type, env), env);
            },
        }
        // return LookupError.VariablePathNotFound;
    }
}

pub fn lookupValueType(v: Value, obj: Object, env: Program) LookupError!Type {
    switch (v) {
        .number => {
            return .{ .number = {} };
        },
        .path => |variable_path| {
            return try lookupVariablePathType(variable_path, obj, env);
        },
    }
}

// tests

const expect = std.testing.expect;

const examples = @import("examples.zig");

test {
    std.testing.refAllDecls(@This());
}

test "typesEqual" {
    try expect(typesEqual(.{ .number = {} }, .{ .number = {} }));
    try expect(typesEqual(.{ .object = "Resistor" }, .{ .object = "Resistor" }));

    try expect(!typesEqual(.{ .number = {} }, .{ .object = "Resistor" }));
    try expect(!typesEqual(.{ .object = "Resistor" }, .{ .number = {} }));
    try expect(!typesEqual(.{ .object = "Resistor" }, .{ .object = "Transistor" }));
}

test "variablePathsEqual" {
    try expect(variablePathsEqual(&.{ "a", "b", "c" }, &.{ "a", "b", "c" }));
    try expect(!variablePathsEqual(&.{ "a", "b", "c" }, &.{ "x", "y", "z" }));
}

test "valuesEqual" {
    try expect(valuesEqual(.{ .number = 5.0 }, .{ .number = 5.0 }));
    try expect(valuesEqual(.{ .path = &.{ "a", "b", "c" } }, .{ .path = &.{ "a", "b", "c" } }));

    try expect(!valuesEqual(.{ .number = 5.0 }, .{ .number = 5.1 }));
    try expect(!valuesEqual(.{ .number = 5.0 }, .{ .path = &.{ "a", "b", "c" } }));
    try expect(!valuesEqual(.{ .path = &.{ "a", "b", "c" } }, .{ .number = 5.0 }));
    try expect(!valuesEqual(.{ .path = &.{ "a", "b", "c" } }, .{ .path = &.{ "a", "b", "d" } }));
}

test "lookup resistor junction" {
    try expect(typesEqual(try lookupVariablePathType(&.{"0"}, examples.resistor, examples.resistor_square_program), .{ .object = "Junction" }));
}
