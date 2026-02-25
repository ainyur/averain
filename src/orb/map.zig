/// Tile map format. 4-byte header (u16 LE width, u16 LE height) followed by
/// a flat byte grid of tile indices. Comptime init from embedded bytes,
/// runtime save to disk.
const std = @import("std");

/// Parameterized tile map with fixed dimensions.
pub fn Map(comptime cfg: struct {
    width: u32,
    height: u32,
}) type {
    const SIZE = cfg.width * cfg.height;

    return struct {
        const Self = @This();

        /// Mutable tile grid, width * height bytes.
        data: [SIZE]u8,

        /// Initialize from comptime-embedded map file bytes.
        /// Validates header dimensions match config.
        pub fn init(comptime raw: []const u8) Self {
            if (raw.len < 4 + SIZE) @compileError("map file too short");
            const w = @as(u32, raw[0]) | @as(u32, raw[1]) << 8;
            const h = @as(u32, raw[2]) | @as(u32, raw[3]) << 8;
            if (w != cfg.width) @compileError("map width mismatch");
            if (h != cfg.height) @compileError("map height mismatch");
            return .{ .data = raw[4..][0..SIZE].* };
        }

        /// Save map to disk with header.
        pub fn save(self: *const Self, comptime path: []const u8) void {
            var buf: [4 + SIZE]u8 = undefined;
            buf[0] = @intCast(cfg.width & 0xFF);
            buf[1] = @intCast((cfg.width >> 8) & 0xFF);
            buf[2] = @intCast(cfg.height & 0xFF);
            buf[3] = @intCast((cfg.height >> 8) & 0xFF);
            @memcpy(buf[4..][0..SIZE], &self.data);
            const file = std.fs.cwd().createFile(path, .{}) catch return;
            defer file.close();
            file.writeAll(&buf) catch return;
        }
    };
}
