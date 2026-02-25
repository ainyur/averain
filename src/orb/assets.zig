/// Asset loading utilities. Dev-mode disk reader for hot reload workflows.
const std = @import("std");

const Allocator = std.mem.Allocator;

/// Read a file from disk into a heap-allocated buffer.
/// Used in dev mode for hot reload. In release mode, games use @embedFile instead.
pub fn read(alloc: Allocator, path: []const u8, max_bytes: usize) ![]const u8 {
    return std.fs.cwd().readFileAlloc(alloc, path, max_bytes) catch return error.ReadFailed;
}
