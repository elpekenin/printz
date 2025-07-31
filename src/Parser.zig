//! Analyze a format string

// TODO:
//  * diagnostic on syntax error
//  * use a bit-packed struct to hold all flags, enum for type
//  * move parsing from `Argument` to here

str: []const u8,

pub fn init(str: []const u8) Parser {
    return .{
        .str = str,
    };
}

pub fn next(self: *Parser) !?Token {
    if (self.str.len == 0) return null;

    const maybe_index = std.mem.indexOf(u8, self.str, "%");
    const index = maybe_index orelse {
        const text = self.str;
        self.str = "";
        return .{
            .text = text,
        };
    };

    if (index == 0) {
        // SAFETY: initialized by .parse() before we use it
        var len: usize = undefined;
        defer self.str = self.str[len..];

        return .{
            .argument = try .parse(self.str, &len),
        };
    }

    const text = self.str[0..index];
    self.str = self.str[index..];
    return .{
        .text = text,
    };
}

const std = @import("std");
const Parser = @This();
const Token = @import("token.zig").Token;

// tests

fn expectEqual(comptime str: []const u8, expected_tokens: []const Token) !void {
    // each specifier is at least 2 chars wide, so we'll have len/2 of them at most
    var actual_buff: [str.len / 2]Token = undefined;

    var parser: Parser = .init(str);

    var i: usize = 0;
    while (try parser.next()) |token| : (i += 1) {
        actual_buff[i] = token;
    }

    const actual_tokens = actual_buff[0..i];
    for (expected_tokens, actual_tokens) |expected, actual| {
        try std.testing.expectEqualDeep(expected, actual);
    }
}

test Parser {
    try expectEqual("Hello %s %p", &.{
        .{ .text = "Hello " },
        .{
            .argument = .{
                .options = .none,
                .specifier = .string,
            },
        },
        .{ .text = " " },
        .{
            .argument = .{
                .options = .none,
                .specifier = .pointer,
            },
        },
    });
}
