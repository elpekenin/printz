count: usize,
wrapped: *Writer,
wrapper: Writer,

fn countingDrain(w: *Writer, data: []const []const u8, splat: usize) Writer.Error!usize {
    const self: *CountingWriter = @fieldParentPtr("wrapper", w);
    const count = try self.wrapped.vtable.drain(self.wrapped, data, splat);
    self.count += count;
    self.wrapper.end = self.wrapped.end;
    return count;
}

fn countingFlush(w: *Writer) Writer.Error!void {
    const self: *CountingWriter = @fieldParentPtr("wrapper", w);
    try self.wrapped.vtable.flush(self.wrapped);
    self.wrapper.end = self.wrapped.end;
}

pub fn init(w: *Writer) CountingWriter {
    return .{
        .count = 0,
        .wrapped = w,
        .wrapper = .{
            .buffer = w.buffer,
            .vtable = &.{
                .drain = countingDrain,
                .flush = countingFlush,
            },
        },
    };
}

pub fn writer(self: *CountingWriter) *Writer {
    return &self.wrapper;
}

const std = @import("std");
const Writer = std.io.Writer;

const CountingWriter = @This();
