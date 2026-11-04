const std = @import("std");

const ast = @import("ast.zig");

pub const junction: ast.Object = .{
    .name = "Junction",
    .public_parameters = &.{},
    .private_parameters = &.{},
    .constraints = &.{},
    .traits = &.{}
};

pub const resistor: ast.Object = .{
    .name = "Resistor",
    .public_parameters = &.{
        .{.name = "0", .type = .{.object = "Junction"}},
        .{.name = "1", .type = .{.object = "Junction"}},
        .{.name = "resistance", .type = .{.number = {}}}
    },
    .private_parameters = &.{},
    .constraints = &.{},
    .traits = &.{}
};

pub const resistor_square: ast.Object = .{
    .name = "ResistorSquare",
    .public_parameters = &.{
        .{.name = "0", .type = .{.object = "Junction"}},
        .{.name = "1", .type = .{.object = "Junction"}},
        .{.name = "2", .type = .{.object = "Junction"}},
        .{.name = "3", .type = .{.object = "Junction"}},
        .{.name = "resistance", .type = .{.number = {}}}
    },
    .private_parameters = &.{
        .{.name = "top", .type = .{.object = "Resistor"}},
        .{.name = "left", .type = .{.object = "Resistor"}},
        .{.name = "right", .type = .{.object = "Resistor"}},
        .{.name = "bottom", .type = .{.object = "Resistor"}},
    },
    .constraints = &.{
        .{.equals = .{.{.path = &.{"resistance"}}, .{.path = &.{"top", "resistance"}}}},
        .{.equals = .{.{.path = &.{"resistance"}}, .{.path = &.{"left", "resistance"}}}},
        .{.equals = .{.{.path = &.{"resistance"}}, .{.path = &.{"bottom", "resistance"}}}},
        .{.equals = .{.{.path = &.{"resistance"}}, .{.path = &.{"right", "resistance"}}}},
        .{.equals = .{.{.path = &.{"0"}}, .{.path = &.{"top", "0"}}}},
        .{.equals = .{.{.path = &.{"0"}}, .{.path = &.{"left", "0"}}}},
        .{.equals = .{.{.path = &.{"1"}}, .{.path = &.{"top", "1"}}}},
        .{.equals = .{.{.path = &.{"1"}}, .{.path = &.{"right", "0"}}}},
        .{.equals = .{.{.path = &.{"2"}}, .{.path = &.{"left", "1"}}}},
        .{.equals = .{.{.path = &.{"2"}}, .{.path = &.{"bottom", "0"}}}},
        .{.equals = .{.{.path = &.{"3"}}, .{.path = &.{"right", "1"}}}},
        .{.equals = .{.{.path = &.{"3"}}, .{.path = &.{"bottom", "1"}}}},
    },
    .traits = &.{}
};

pub fn nResistorLine(allocator: std.mem.Allocator, n: u64) !ast.Object {

    var parameters: std.ArrayList(ast.Parameter) = .empty;

    var constraints: std.ArrayList(ast.Constraint) = .empty;

    try parameters.append(allocator, .{.name = "r0", .type = .{.object = "Resistor"}});
    
    try constraints.append(allocator, .{.equals = .{.{.path = &.{"0"}}, .{.path = &.{"r0", "0"}}}});
    try constraints.append(allocator, .{.equals = .{.{.path = &.{"r0", "resistance"}}, .{.path = &.{"resistance"}}}});

    for (1..n) |i| {
        const resistor_name = try std.fmt.allocPrint(allocator, "r{d}", .{i});

        try parameters.append(allocator, .{.name = resistor_name, .type = .{.object = "Resistor"}});

        const prev_resistor_name = try std.fmt.allocPrint(allocator, "r{d}", .{i - 1});
        try constraints.append(allocator, .{.equals = .{
            .{.path = try allocator.dupe(ast.Variable, &.{prev_resistor_name, "1"})},
            .{.path = try allocator.dupe(ast.Variable, &.{resistor_name, "0"})}
        }});

        try constraints.append(allocator, .{.equals = .{
            .{.path = &.{"resistance"}},
            .{.path = try allocator.dupe(ast.Variable, &.{resistor_name, "resistance"})}
        }});
    }

    const last_resistor_name = try std.fmt.allocPrint(allocator, "r{d}", .{n - 1});
    try constraints.append(allocator, .{.equals = .{
        .{.path = try allocator.dupe(ast.Variable, &.{last_resistor_name, "1"})},
        .{.path = &.{"1"}}
    }});
    // try constraints.append(allocator, .{.equals = .{.{.path = &.{"r0", "1"}}, .{.path = &.{"1"}}}});

    const resistor_line: ast.Object = .{
        .name = try std.fmt.allocPrint(allocator, "{d}ResistorLine", .{n}),
        .public_parameters = &.{
            .{.name = "0", .type = .{.object = "Junction"}},
            .{.name = "1", .type = .{.object = "Junction"}},
            .{.name = "resistance", .type = .{.number = {}}}
        },
        .private_parameters = try parameters.toOwnedSlice(allocator),
        .constraints = try constraints.toOwnedSlice(allocator),
        .traits = &.{"Resistor"}
    };

    return resistor_line;
}

pub const resistor_square_program: ast.Program = &.{
    junction, resistor, resistor_square
};

test {
    std.testing.refAllDecls(@This());
}

