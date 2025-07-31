//! Specifiers in a printf format string
//!
//! Information extracted from: https://cplusplus.com/reference/cstdio/printf/

options: Options,
specifier: Specifier,

pub fn parse(str: []const u8, len: *usize) !Argument {
    if (str[0] != '%') {
        return error.MissingPercent;
    }

    // [0] was a '%'
    var ptr = str.ptr[1..];

    defer len.* = ptr - str.ptr;
    return .{
        .options = try .parse(&ptr),
        .specifier = try .parse(&ptr),
    };
}

fn consumeNum(str: *[*]const u8) ?usize {
    var num: ?usize = null;

    while (true) {
        const char = str.*[0];
        if (char < '0' or char > '9') {
            break;
        }

        str.* += 1;

        const digit = char - '0';
        num = if (num) |n|
            (n * 10) + digit
        else
            digit;
    }

    return num;
}

const Specifier = union(enum) {
    char,
    number: struct {
        type: union(enum) {
            float,
            integer: std.builtin.Signedness,
        },
        fmt: std.fmt.Number,
    },
    pointer,
    string,
    percent,

    fn parse(str: *[*]const u8) !Specifier {
        const t: Specifier = switch (str.*[0]) {
            'd', 'i' => .{
                .number = .{
                    .type = .{
                        .integer = .signed,
                    },
                    // default options match
                    .fmt = .{},
                },
            },
            'u' => .{
                .number = .{
                    .type = .{
                        .integer = .unsigned,
                    },
                    // default options match
                    .fmt = .{},
                },
            },
            'o' => .{
                .number = .{ .type = .{
                    .integer = .signed,
                }, .fmt = .{
                    .mode = .octal,
                } },
            },
            'x', 'X' => |c| .{
                .number = .{ .type = .{
                    .integer = .signed,
                }, .fmt = .{
                    .mode = .hex,
                    .case = if (std.ascii.isUpper(c))
                        .upper
                    else
                        .lower,
                } },
            },
            'f', 'F' => |c| .{
                .number = .{ .type = .float, .fmt = .{
                    .mode = .decimal,
                    .case = if (std.ascii.isUpper(c))
                        .upper
                    else
                        .lower,
                } },
            },
            'e', 'E' => |c| .{
                .number = .{ .type = .float, .fmt = .{
                    .mode = .scientific,
                    .case = if (std.ascii.isUpper(c))
                        .upper
                    else
                        .lower,
                } },
            },
            'a', 'A' => |c| .{
                .number = .{ .type = .float, .fmt = .{
                    .mode = .hex,
                    .case = if (std.ascii.isUpper(c))
                        .upper
                    else
                        .lower,
                } },
            },
            'g', 'G' => return error.UnsupportedSpecifier,
            'c' => .char,
            's' => .string,
            'p' => .pointer,
            'n' => return error.UnsupportedSpecifier,
            '%' => .percent,
            else => return error.InvalidSpecifier,
        };

        str.* += 1;

        return t;
    }
};

const Flag = enum {
    minus,
    plus,
    space,
    hash,
    zero,

    fn parse(str: *[*]const u8) ?Flag {
        const flag: Flag = switch (str.*[0]) {
            '-' => .minus,
            '+' => .plus,
            ' ' => .space,
            '#' => .hash,
            '0' => .zero,
            else => return null,
        };

        str.* += 1;

        return flag;
    }
};

const Width = union(enum) {
    arg,
    fixed: usize,

    fn parse(str: *[*]const u8) ?Width {
        switch (str.*[0]) {
            '*' => {
                str.* += 1;
                return .arg;
            },
            '0'...'9' => return .{
                // will never be null because ptr.*.* is 0...9 in this branch
                .fixed = consumeNum(str).?,
            },
            else => return null,
        }
    }
};

const Precision = union(enum) {
    arg,
    fixed: usize,

    fn parse(str: *[*]const u8) !?Precision {
        if (str.*[0] != '.') {
            return null;
        }

        str.* += 1;

        const precision: Precision = switch (str.*[0]) {
            '*' => .arg,
            '0'...'9' => .{
                // will never be null because ptr.*.* is 0...9 in this branch
                .fixed = consumeNum(str).?,
            },
            else => return error.InvalidPrecision,
        };

        str.* += 1;

        return precision;
    }
};

const Length = enum {
    hh,
    h,
    l,
    ll,
    j,
    z,
    t,
    L,

    fn parse(str: *[*]const u8) ?Length {
        const length: Length = switch (str.*[0]) {
            'h' => blk: {
                switch (str.*[1]) {
                    'h' => {
                        str.* += 1;
                        break :blk .hh;
                    },
                    else => break :blk .h,
                }
            },
            'l' => blk: {
                switch (str.*[1]) {
                    'l' => {
                        str.* += 1;
                        break :blk .ll;
                    },
                    else => break :blk .ll,
                }
            },
            'j' => .j,
            'z' => .z,
            't' => .t,
            'L' => .L,
            else => return null,
        };

        str.* += 1;

        return length;
    }
};

const Options = struct {
    flag: ?Flag,
    width: ?Width,
    precision: ?Precision,
    length: ?Length,

    fn parse(str: *[*]const u8) !Options {
        return .{
            .flag = .parse(str),
            .width = .parse(str),
            .precision = try .parse(str),
            .length = .parse(str),
        };
    }

    pub const none: Options = .{
        .flag = null,
        .width = null,
        .precision = null,
        .length = null,
    };
};

// tests

fn expectEqual(str: []const u8, expected: Argument) !void {
    // SAFETY: not accessed
    var len: usize = undefined;
    const actual: Argument = try .parse(str, &len);
    try std.testing.expectEqual(expected, actual);
}

test parse {
    try expectEqual("%d", .{
        .options = .none,
        .specifier = .{
            .number = .{
                .type = .{
                    .integer = .signed,
                },
                .fmt = .{},
            },
        },
    });

    try expectEqual("%%", .{
        .options = .none,
        .specifier = .percent,
    });

    try expectEqual("% 10.*X", .{
        .options = .{
            .flag = .space,
            .width = .{ .fixed = 10 },
            .precision = .arg,
            .length = null,
        },
        .specifier = .{
            .number = .{
                .type = .{
                    .integer = .signed,
                },
                .fmt = .{
                    .mode = .hex,
                },
            },
        },
    });
}

// imports / constants

const std = @import("std");
const Argument = @This();
