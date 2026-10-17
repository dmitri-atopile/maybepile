const std = @import("std");

const ast = @import("ast.zig");

pub const junction: ast.Object = .{
    .name = "Junction",
    .public_parameters = &.{.{"id", .{.number = {}}}},
    .private_parameters = &.{},
    .constraints = &.{},
    .traits = &.{}
};

pub const resistor: ast.Object = .{
    .name = "Resistor",
    .public_parameters = &.{
        .{"0", .{.object = "Junction"}},
        .{"1", .{.object = "Junction"}},
        .{"resistance", .{.number = {}}}
    },
    .private_parameters = &.{},
    .constraints = &.{},
    .traits = &.{}
};

pub const resistor_square: ast.Object = .{
    .name = "ResistorSquare",
    .public_parameters = &.{
        .{"0", .{.object = "Junction"}},
        .{"1", .{.object = "Junction"}},
        .{"2", .{.object = "Junction"}},
        .{"3", .{.object = "Junction"}},
        .{"resistance", .{.number = {}}}
    },
    .private_parameters = &.{
        .{"top", .{.object = "Resistor"}},
        .{"left", .{.object = "Resistor"}},
        .{"right", .{.object = "Resistor"}},
        .{"bottom", .{.object = "Resistor"}},
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

pub const resistor_square_program: ast.Program = &.{
    junction, resistor, resistor_square
};

test {
    std.testing.refAllDecls(@This());
}
