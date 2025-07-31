/// Type of tokens found in a format string
pub const Token = union(enum) {
    text: []const u8,
    argument: Argument,

    pub fn format(
        self: Token,
        writer: *std.io.Writer,
    ) std.io.Writer.Error!void {
        switch (self) {
            .text => |text| try writer.print("text = '{s}'", .{text}),
            .argument => |argument| try writer.print("argument = {}", .{argument}),
        }
    }
};

const std = @import("std");
const Argument = @import("Argument.zig");
