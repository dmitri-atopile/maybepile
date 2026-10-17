const std = @import("std");

const ast = @import("ast.zig");
const examples = @import("examples.zig");

const TypeError = error{
    NumberIsNotObject,
    VariablePathNotFound,
    ObjectNotFound,
    NonUnifyableTypes,
    UnmatchingTraitType,
    NonNumberType
};

fn findObject(object_type: ast.ObjectType, env: ast.Program) TypeError!ast.Object {
    for (env) |obj| {
        if (std.mem.eql(u8, object_type, obj.name)) {
            return obj;
        }
    }
    return TypeError.ObjectNotFound;
}


fn isSubtype(t0: ast.Type, t1: ast.Type, env: ast.Program) TypeError!bool {
    if (ast.types_equal(t0, t1)) {
        return true;
    } else if (t0 == .number and t1 == .object) {
        return false;
    } else if (t0 == .object and t1 == .number) {
        return false;
    } else {
        switch (t0) {
            .number => unreachable,
            .object => |object_type| {
                const obj = try findObject(object_type, env);
                for (obj.traits) |trait| {
                    if (try isSubtype(.{.object = trait}, t1, env)) {
                        return true;
                    }
                }
                return false;
            }
        }
    }
}

fn unifyableTypes(t0: ast.Type, t1: ast.Type, env: ast.Program) TypeError!bool {
    return (try isSubtype(t0, t1, env)) or (try isSubtype(t1, t0, env));
}

fn findParameter(name: ast.Variable, obj: ast.Object) TypeError!ast.Parameter {
    for (obj.public_parameters) |param| {
        if (std.mem.eql(u8, name, param[0])) {
            return param;
        }
    }
    for (obj.private_parameters) |param| {
        if (std.mem.eql(u8, name, param[0])) {
            return param;
        }
    }
    return TypeError.VariablePathNotFound;
}

fn lookupVariablePathType(vp: ast.VariablePath, obj: ast.Object, env: ast.Program) TypeError!ast.Type {
    // std.debug.print("next variable: {s}\n", .{vp[0]});
    if (vp.len == 0) {
        return .{.object = obj.name};
    } else {
        const param = try findParameter(vp[0], obj);
        switch (param[1]) {
            .number => {
                if (vp.len == 1) {
                    // if do not need to desend any further into the path
                    return .{.number = {}};
                } else {
                    // otherwise cannot descend further into the path
                    return TypeError.NumberIsNotObject;
                }
            },
            .object => |object_type| {
                return try lookupVariablePathType(vp[1..], try findObject(object_type, env), env);
            }
        }
        // return TypeError.VariablePathNotFound;
    }
}

fn lookupValueType(v: ast.Value, obj: ast.Object, env: ast.Program) TypeError!ast.Type {
    switch(v) {
        .number => return .{.number = {}},
        .path => |variable_path| return try lookupVariablePathType(variable_path, obj, env)
    }
}

fn typecheckParameters(parameters: []const (ast.Parameter), env: ast.Program) TypeError!void {
    for (parameters) |param| {
        switch (param[1]) {
            .number => {},
            .object => |object_type| {
                _ = try findObject(object_type, env);
            }
        }
    }
}

fn typecheckConstraints(obj: ast.Object, env: ast.Program) TypeError!void {
    for (obj.constraints) |c| {
        switch (c) {
            .equals => |args| {
                const t0 = try lookupValueType(args[0], obj, env);
                const t1 = try lookupValueType(args[1], obj, env);
                if (!try unifyableTypes(t0, t1, env)) {
                    // std.debug.print("non unifyable types: {}, {}\n", .{t0, t1});
                    return TypeError.NonUnifyableTypes;
                }
            },
            .gennum => |val| {
                if (!try isSubtype(try lookupValueType(val, obj, env), .{.number = {}}, env)) {
                    return TypeError.NonNumberType;
                }
            }
        }
    }
}

fn typecheckTraits(obj: ast.Object, env: ast.Program) TypeError!void {
    for (obj.traits) |trait| {
        const trait_obj = try findObject(trait, env);
        for (trait_obj.public_parameters) |public_param| {
            const obj_param_type = try lookupVariablePathType(&.{public_param[0]}, obj, env);
            if (ast.types_equal(public_param[1], obj_param_type)) {
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

fn typecheckProgram(program: ast.Program) TypeError!void {
    for (program, 0..) |obj, idx| {
        try typecheckObject(obj, program[0..idx]);
    }
}

// tests

const expect = std.testing.expect;

test {
    std.testing.refAllDecls(@This());
}

test "lookup junction id" {
    try expect(ast.types_equal(
        try lookupVariablePathType(&.{"id"}, examples.junction, examples.resistor_square_program),
        .{.number = {}}
    ));
}

test "resistor square example program typechecks" {
    try typecheckProgram(examples.resistor_square_program);
}
