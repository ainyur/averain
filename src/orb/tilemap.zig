/// Tilemap renderer. Blits a grid of tile indices from a spritesheet.
const Graphics = @import("graphics.zig").Graphics;
const Sprite = @import("ase.zig").Sprite;

/// Render a tile grid to the framebuffer.
/// Each byte in data is a tile index into the spritesheet strip.
pub fn render(gfx: *Graphics, data: []const u8, width: u32, height: u32, tile_size: u32, sheet: Sprite) void {
    for (0..height) |row| {
        for (0..width) |col| {
            const idx = data[row * width + col];
            const dx: i32 = @intCast(col * tile_size);
            const dy: i32 = @intCast(row * tile_size);
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
    render(&gfx, &data, 2, 2, 2, sheet);

    // Top-left tile (index 0): frame 0 pixels at (0,0)
    try std.testing.expectEqual(@as(u8, 1), gfx.px[0 * W + 0]);
    try std.testing.expectEqual(@as(u8, 2), gfx.px[0 * W + 1]);
    try std.testing.expectEqual(@as(u8, 3), gfx.px[1 * W + 0]);
    try std.testing.expectEqual(@as(u8, 4), gfx.px[1 * W + 1]);

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

    // Bottom-right tile (index 0): frame 0 again at (2,2)
    try std.testing.expectEqual(@as(u8, 1), gfx.px[2 * W + 2]);
    try std.testing.expectEqual(@as(u8, 2), gfx.px[2 * W + 3]);
    try std.testing.expectEqual(@as(u8, 3), gfx.px[3 * W + 2]);
    try std.testing.expectEqual(@as(u8, 4), gfx.px[3 * W + 3]);
}
