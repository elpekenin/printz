// TODO:
//   * different types based on specifier.length
//   * is float == f32?

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

inline fn fmtOptions(specifier: Specifier, ap: *VaList) Number {
    const mode: Number.Mode = switch (specifier.type) {
        .d,
        .i,
        .u,
        .f,
        .F,
        .g,
        .G,
        => .decimal,

        .e,
        .E,
        => .scientific,

        .o,
        => .octal,

        .x,
        .X,
        .a,
        .A,
        => .hex,

        else => unreachable,
    };

    const case: Case = switch (specifier.type) {
        .d,
        .i,
        .o,
        .u,
        .x,
        .e,
        .f,
        .g,
        .a,
        => .lower,

        .X,
        .E,
        .F,
        .G,
        .A,
        => .upper,

        else => unreachable,
    };

    const precision: ?usize = switch (specifier.precision) {
        .none => null,
        .arg => @intCast(@cVaArg(ap, c_int)),
        .number => |val| val,
    };

    const width: ?usize = switch (specifier.width) {
        .none => null,
        .arg => @intCast(@cVaArg(ap, c_int)),
        .number => |val| val,
    };

    const alignment: Alignment = if (specifier.flags.minus)
        .left
    else
        .right;

    const fill: u8 = if (!specifier.flags.minus and specifier.flags.zero)
        '0'
    else
        ' ';

    return .{
        .mode = mode,
        .case = case,
        .precision = precision,
        .width = width,
        .alignment = alignment,
        .fill = fill,
    };
}

fn impl(writer: *Writer, format: [*c]const u8, ap: *VaList) callconv(.c) c_int {
    return implInner(writer, format, ap) catch -1;
}

/// zig's calling convention for error handling (using `try`)
inline fn implInner(writer: *Writer, format: [*c]const u8, ap: *VaList) !c_int {
    const slice: [:0]const u8 = std.mem.sliceTo(format, 0);
    var parser: Parser = .init(slice);

    var counting: CountingWriter = .init(writer);
    var w = counting.writer();

    while (try parser.next()) |tok| {
        const specifier = switch (tok) {
            .specifier => |specifier| specifier,
            .text => |text| {
                _ = try w.write(text);
                continue;
            },
        };

        // handle non-number specifiers already
        switch (specifier.type) {
            .c => {
                const c = @cVaArg(ap, u8);
                try w.writeByte(c);
                continue;
            },
            .s => {
                const s = @cVaArg(ap, [*c]const u8);
                try w.print("{s}", .{s});
                continue;
            },
            .p => {
                const p = @cVaArg(ap, *void);
                const i = @intFromPtr(p);
                _ = try w.write("0x");
                try w.printInt(i, 16, .lower, .{});
                continue;
            },
            .n => {
                const n = @cVaArg(ap, *c_int);
                try w.flush();
                n.* = @intCast(counting.count);
                continue;
            },
            .@"%" => {
                try w.writeByte('%');
                continue;
            },
            else => {},
        }

        const opts = fmtOptions(specifier, ap);

        switch (specifier.type) {
            .d,
            .i,
            => {
                const base = opts.mode.base() orelse unreachable;

                const value = @cVaArg(ap, c_int);
                try w.printInt(value, base, opts.case, .{
                    .precision = opts.precision,
                    .width = opts.width,
                    .alignment = opts.alignment,
                    .fill = opts.fill,
                });
            },

            .o,
            .u,
            .x,
            .X,
            => {
                const base = opts.mode.base() orelse unreachable;

                if (specifier.flags.hash) {
                    switch (specifier.type) {
                        .o => try w.writeByte('0'),
                        .x => _ = try w.write("0x"),
                        .X => _ = try w.write("0X"),
                        else => {},
                    }
                }

                const value = @cVaArg(ap, c_uint);
                try w.printInt(value, base, opts.case, .{
                    .precision = opts.precision,
                    .width = opts.width,
                    .alignment = opts.alignment,
                    .fill = opts.fill,
                });
            },

            .e,
            .E,
            .f,
            .F,
            .a,
            .A,
            => {
                const value = @cVaArg(ap, f32);
                try w.printFloat(value, opts);
            },

            .g,
            .G,
            => @panic("NotImplementedError"),

            else => unreachable,
        }
    }

    // dump buffer, return count of bytes written
    try w.flush();
    return @intCast(counting.count);
}

const std = @import("std");
const fd_t = std.c.fd_t;
const Alignment = std.fmt.Alignment;
const CWriter = std.io.CWriter;
const Case = std.fmt.Case;
const FILE = std.c.FILE;
const File = std.fs.File;
const Number = std.fmt.Number;
const VaList = std.builtin.VaList;
const Writer = std.io.Writer;

const CountingWriter = @import("CountingWriter.zig");
const token = @import("token.zig");
pub const Parser = @import("Parser.zig");
const Specifier = token.Specifier;
