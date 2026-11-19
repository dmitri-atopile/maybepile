const std = @import("std");

const ast = @import("ast.zig");

const TypeError = error{ NumberIsNotObject, VariablePathNotFound, ObjectNotFound, NonUnifyableTypes, UnmatchingTraitType, NonNumberType };

pub fn isSubtype(t0: ast.Type, t1: ast.Type, env: ast.Program) TypeError!bool {
    if (ast.typesEqual(t0, t1)) {
        return true;
    } else if (t0 == .number and t1 == .object) {
        return false;
    } else if (t0 == .object and t1 == .number) {
        return false;
    } else {
        switch (t0) {
            .number => unreachable,
            .object => |object_type| {
                const obj = try ast.findObject(object_type, env);
                for (obj.traits) |trait| {
                    if (try isSubtype(.{ .object = trait }, t1, env)) {
                        return true;
                    }
                }
                return false;
            },
        }
    }
}

fn unifyableTypes(t0: ast.Type, t1: ast.Type, env: ast.Program) TypeError!bool {
    return (try isSubtype(t0, t1, env)) or (try isSubtype(t1, t0, env));
}

fn typecheckParameters(parameters: []const (ast.Parameter), env: ast.Program) TypeError!void {
    for (parameters) |param| {
        switch (param.type) {
            .number => {},
            .object => |object_type| {
                _ = try ast.findObject(object_type, env);
            },
        }
    }
}

fn typecheckConstraints(obj: ast.Object, env: ast.Program) TypeError!void {
    for (obj.constraints) |c| {
        switch (c) {
            .equals => |args| {
                const t0 = try ast.lookupValueType(args[0], obj, env);
                const t1 = try ast.lookupValueType(args[1], obj, env);
                if (!try unifyableTypes(t0, t1, env)) {
                    return TypeError.NonUnifyableTypes;
                }
            },
        }
    }
}

fn typecheckTraits(obj: ast.Object, env: ast.Program) TypeError!void {
    for (obj.traits) |trait| {
        const trait_obj = try ast.findObject(trait, env);
        for (trait_obj.public_parameters) |public_param| {
            const obj_param_type = try ast.lookupVariablePathType(&.{public_param.name}, obj, env);
            if (!ast.typesEqual(public_param.type, obj_param_type)) {
                return TypeError.UnmatchingTraitType;
            }
        }
    }
}

fn typecheckObject(obj: ast.Object, env: ast.Program) TypeError!void {
    try typecheckParameters(obj.public_parameters, env);
    try typecheckParameters(obj.private_parameters, env);
    try typecheckConstraints(obj, env);
    try typecheckTraits(obj, env);
}

pub fn typecheckProgram(program: ast.Program) TypeError!void {
    for (program, 0..) |obj, idx| {
        try typecheckObject(obj, program[0..idx]);
    }
}

// tests

const examples = @import("examples.zig");
const expect = std.testing.expect;

test {
    std.testing.refAllDecls(@This());
}

test "resistor square example program typechecks" {
    try typecheckProgram(examples.resistor_square_program);
}

test "small resistor lines typecheck" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const one_resistor_line = try examples.nResistorLine(allocator, 1);

    try typecheckProgram(&.{ examples.junction, examples.resistor, one_resistor_line });

    const five_resistor_line = try examples.nResistorLine(allocator, 5);
    try typecheckProgram(&.{ examples.junction, examples.resistor, five_resistor_line });
}

test "big resistor line typechecks" {

    // var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    // defer arena.deinit();
    // const allocator = arena.allocator();

    // const big_resistor_line = try examples.nResistorLine(allocator, 250000);
    // try typecheckProgram(&.{examples.junction, examples.resistor, big_resistor_line});
}
