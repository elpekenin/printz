//! Barebones CLI to quickly test the library

/// entrypoint
pub fn main() !void {
    var args = std.process.args();
    _ = args.skip(); // exe name

    var stderr_file: std.fs.File = .stderr();

    var stderr: std.io.Writer = stderr_file.writer(&.{}).interface;

    const subcommand = args.next() orelse {
        return stderr.print("specify a subcommand\n", .{});
    };

    const Handler = *const fn (*std.process.ArgIterator, *std.io.Writer) anyerror!void;
    const handler: Handler = if (std.mem.eql(u8, subcommand, "parse"))
        parse
    else if (std.mem.eql(u8, subcommand, "sample"))
        sample
    else
        unknownSubcommand;

    try handler(&args, &stderr);
}

fn unknownSubcommand(_: *std.process.ArgIterator, stderr: *std.io.Writer) !void {
    try stderr.print("unknown subcommand\n", .{});
}

fn parse(args: *std.process.ArgIterator, stderr: *std.io.Writer) !void {
    const format = args.next() orelse {
        return stderr.print("missing <format> argument\n", .{});
    };

    if (args.next()) |_| {
        return stderr.print("a single format string is supported at the moment\n", .{});
    }

    var parser: printz.Parser = .init(format);
    while (try parser.next()) |token| {
        try stderr.print("{f}\n", .{token});
    }
}

fn sample(_: *std.process.ArgIterator, _: *std.io.Writer) !void {
    const str = "hello world";
    const int: c_int = -42;
    _ = printz.printf("%s %d\n", str, int);
}

const std = @import("std");
const printz = @import("printz");
