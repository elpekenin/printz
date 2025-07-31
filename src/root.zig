pub export fn printf(format: [*c]const u8, ...) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);

    var stdout: File.Writer = .init(.stdout(), &.{});

    return impl(&stdout.interface, format, &ap);
}

pub export fn fprintf(file: *FILE, format: [*c]const u8, ...) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);

    var c_writer: CWriter = .{ .context = file };
    var writer = c_writer.adaptToNewApi().new_interface;
    return impl(&writer, format, &ap);
}

pub export fn dprintf(fd: fd_t, format: [*c]const u8, ...) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);

    var file: File.Writer = .init(.{ .handle = fd }, &.{});
    return impl(&file.interface, format, &ap);
}

pub export fn sprintf(buffer: [*c]u8, format: [*c]const u8, ...) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);

    var writer: Writer = .fixed(buffer[0..std.math.maxInt(usize)]);
    return impl(&writer, format, &ap);
}

pub export fn snprintf(buffer: [*c]u8, len: usize, format: [*c]const u8, ...) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);

    var writer: Writer = .fixed(buffer[0..len]);
    return impl(&writer, format, &ap);
}

pub export fn vprintf(format: [*c]const u8, ap: *VaList) c_int {
    var stdout: File.Writer = .init(.stdout(), &.{});
    return impl(&stdout.interface, format, ap);
}

pub export fn vfprintf(file: *FILE, format: [*c]const u8, ap: *VaList) c_int {
    var c_writer: CWriter = .{ .context = file };
    var writer = c_writer.adaptToNewApi().new_interface;
    return impl(&writer, format, ap);
}

pub export fn vdprintf(fd: fd_t, format: [*c]const u8, ap: *VaList) c_int {
    var file: File.Writer = .init(.{ .handle = fd }, &.{});
    return impl(&file.interface, format, ap);
}

pub export fn vsprintf(buffer: [*c]u8, format: [*c]const u8, ap: *VaList) c_int {
    var writer: Writer = .fixed(buffer[0..std.math.maxInt(usize)]);
    return impl(&writer, format, ap);
}

pub export fn vsnprintf(buffer: [*c]u8, len: usize, format: [*c]const u8, ap: *VaList) c_int {
    var writer: Writer = .fixed(buffer[0..len]);
    return impl(&writer, format, ap);
}

//
// private
//

fn impl(writer: *Writer, format: [*c]const u8, ap: *VaList) callconv(.c) c_int {
    return implInner(writer, format, ap) catch -1;
}

/// zig's calling convention for error handling (using `try`)
inline fn implInner(writer: *Writer, format: [*c]const u8, ap: *VaList) !c_int {
    const slice: [:0]const u8 = std.mem.sliceTo(format, 0);
    var parser: Parser = .init(slice);

    var counting: CountingWriter = .init(writer);
    var w = counting.writer();

    while (try parser.next()) |token| {
        const argument = switch (token) {
            .argument => |argument| argument,
            .text => |text| {
                _ = try w.write(text);
                continue;
            },
        };

        switch (argument.specifier) {
            .char => {
                const value = @cVaArg(ap, c_char);
                try w.writeByte(@intCast(value));
            },
            .number => |number| {
                // TODO: alignment and fill

                const precision: ?usize = if (argument.options.precision) |precision|
                    switch (precision) {
                        .fixed => |val| val,
                        .arg => @intCast(@cVaArg(ap, c_int)),
                    }
                else
                    null;

                const width: ?usize = if (argument.options.width) |width|
                    switch (width) {
                        .fixed => |val| val,
                        .arg => @intCast(@cVaArg(ap, c_int)),
                    }
                else
                    null;

                switch (number.type) {
                    .float => {
                        const value = @cVaArg(ap, f32); // FIXME: f64
                        try w.printFloat(value, .{
                            .mode = number.fmt.mode,
                            .case = number.fmt.case,
                            .precision = precision,
                            .width = width,
                        });
                    },
                    .integer => |signedness| {
                        const base: u8 = switch (number.fmt.mode) {
                            .decimal => 10,
                            .binary => unreachable,
                            .octal => 8,
                            .hex => 16,
                            .scientific => unreachable,
                        };

                        const case = number.fmt.case;
                        const options: std.fmt.Options = .{
                            .precision = precision,
                            .width = width,
                        };

                        switch (signedness) {
                            .signed => {
                                const value = @cVaArg(ap, c_int);
                                try w.printInt(value, base, case, options);
                            },
                            .unsigned => {
                                const value = @cVaArg(ap, c_uint);
                                try w.printInt(value, base, case, options);
                            },
                        }
                    },
                }
            },
            .pointer => {
                const value = @cVaArg(ap, *void);
                try w.printAddress(value);
            },
            .string => {
                const value = @cVaArg(ap, [*c]u8);
                _ = try w.print("{s}", .{value}); // is this OK?
            },
            .percent => {
                try w.writeByte('%');
            },
        }
    }

    // dump buffer, return count of bytes written
    try w.flush();
    return @intCast(counting.count);
}

const std = @import("std");
const fd_t = std.c.fd_t;
const CWriter = std.io.CWriter;
const FILE = std.c.FILE;
const File = std.fs.File;
const VaList = std.builtin.VaList;
const Writer = std.io.Writer;

pub const Argument = @import("Argument.zig");
const CountingWriter = @import("CountingWriter.zig");
pub const Token = @import("token.zig").Token;
pub const Parser = @import("Parser.zig");
