/// Tilemap renderer. Blits a grid of tile indices from a spritesheet.
const Graphics = @import("graphics.zig").Graphics;
const Sprite = @import("ase.zig").Sprite;

/// Render a visible portion of a tile grid to the framebuffer.
/// cam_x/cam_y are pixel offsets for camera scrolling.
pub fn render(gfx: *Graphics, data: []const u8, width: u32, height: u32, tile_size: u32, sheet: Sprite, cam_x: i32, cam_y: i32) void {
    const ts: i32 = @intCast(tile_size);
    const first_col: u32 = @intCast(@max(0, @divTrunc(cam_x, ts)));
    const first_row: u32 = @intCast(@max(0, @divTrunc(cam_y, ts)));
    const vis_cols = @as(u32, @intCast(@divTrunc(@as(i32, Graphics.WIDTH), ts))) + 2;
    const vis_rows = @as(u32, @intCast(@divTrunc(@as(i32, Graphics.HEIGHT), ts))) + 2;
    const last_col = @min(first_col + vis_cols, width);
    const last_row = @min(first_row + vis_rows, height);

    for (first_row..last_row) |row| {
        for (first_col..last_col) |col| {
            const idx = data[row * width + col];
            if (idx == 0) continue;
            const dx: i32 = @as(i32, @intCast(col)) * ts - cam_x;
            const dy: i32 = @as(i32, @intCast(row)) * ts - cam_y;
            gfx.blit_frame(sheet, idx, dx, dy, false);
        }
    }
}

const std = @import("std");

test "render blits correct tile at correct position" {
    const W = Graphics.WIDTH;
    const data = [_]u8{ 0, 1, 2, 0 };
    const sheet = Sprite{
        .width = 2,
        .height = 2,
        .strip_width = 6,
        .pixels = &.{ 1, 2, 5, 6, 9, 10, 3, 4, 7, 8, 11, 12 },
    };
    var gfx: Graphics = .{};
    render(&gfx, &data, 2, 2, 2, sheet, 0, 0);

    // Top-left tile (index 0): skipped, pixels unchanged
    try std.testing.expectEqual(@as(u8, 0), gfx.px[0 * W + 0]);
    try std.testing.expectEqual(@as(u8, 0), gfx.px[0 * W + 1]);
    try std.testing.expectEqual(@as(u8, 0), gfx.px[1 * W + 0]);
    try std.testing.expectEqual(@as(u8, 0), gfx.px[1 * W + 1]);

    // Top-right tile (index 1): frame 1 pixels at (2,0)
    try std.testing.expectEqual(@as(u8, 5), gfx.px[0 * W + 2]);
    try std.testing.expectEqual(@as(u8, 6), gfx.px[0 * W + 3]);
    try std.testing.expectEqual(@as(u8, 7), gfx.px[1 * W + 2]);
    try std.testing.expectEqual(@as(u8, 8), gfx.px[1 * W + 3]);

    // Bottom-left tile (index 2): frame 2 pixels at (0,2)
    try std.testing.expectEqual(@as(u8, 9), gfx.px[2 * W + 0]);
    try std.testing.expectEqual(@as(u8, 10), gfx.px[2 * W + 1]);
    try std.testing.expectEqual(@as(u8, 11), gfx.px[3 * W + 0]);
    try std.testing.expectEqual(@as(u8, 12), gfx.px[3 * W + 1]);

    // Bottom-right tile (index 0): skipped, pixels unchanged
    try std.testing.expectEqual(@as(u8, 0), gfx.px[2 * W + 2]);
    try std.testing.expectEqual(@as(u8, 0), gfx.px[2 * W + 3]);
    try std.testing.expectEqual(@as(u8, 0), gfx.px[3 * W + 2]);
    try std.testing.expectEqual(@as(u8, 0), gfx.px[3 * W + 3]);
}
