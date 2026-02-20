/// Indexed framebuffer with 256 color palette. Pixels are u8 palette indices,
/// resolved to RGBA u32 for display. Fixed 320x180 resolution.
pub const Graphics = struct {
    const ase = @import("ase.zig");
    const font_mod = @import("font.zig");

    /// Framebuffer width in pixels.
    pub const WIDTH = 320;
    /// Framebuffer height in pixels.
    pub const HEIGHT = 180;

    px: [WIDTH * HEIGHT]u8 = [_]u8{0} ** (WIDTH * HEIGHT),
    pal: [256]u32 = [_]u32{0x000000FF} ** 256,

    /// Fill the entire framebuffer with a palette index.
    pub fn clear(self: *Graphics, index: u8) void {
        @memset(&self.px, index);
    }

    /// Write a palette index at (x, y). Out of bounds writes are ignored.
    pub fn set_pixel(self: *Graphics, x: u32, y: u32, index: u8) void {
        if (x >= WIDTH or y >= HEIGHT) return;
        self.px[y * WIDTH + x] = index;
    }

    /// Blit frame 0 of a sprite. Index 0 is transparent.
    /// Signed position allows partial offscreen sprites (clips to bounds).
    pub fn blit(self: *Graphics, sprite: ase.Sprite, sx: i32, sy: i32) void {
        self.blit_frame(sprite, 0, sx, sy, false);
    }

    /// Blit a specific frame from a sprite strip. Index 0 is transparent.
    /// When flip is true, the frame is mirrored horizontally.
    pub fn blit_frame(self: *Graphics, sprite: ase.Sprite, frame: u32, sx: i32, sy: i32, flip: bool) void {
        const src_x = frame * sprite.width;
        for (0..sprite.height) |row| {
            const dy = sy + @as(i32, @intCast(row));
            if (dy < 0 or dy >= HEIGHT) continue;
            const uy: u32 = @intCast(dy);
            for (0..sprite.width) |col| {
                const dx = sx + @as(i32, @intCast(col));
                if (dx < 0 or dx >= WIDTH) continue;
                const src_col = if (flip) sprite.width - 1 - col else col;
                const idx = sprite.pixels[row * sprite.strip_width + src_x + src_col];
                if (idx == 0) continue;
                const ux: u32 = @intCast(dx);
                self.px[uy * WIDTH + ux] = idx;
            }
        }
    }

    /// Filled rectangle, clips to bounds.
    pub fn rect(self: *Graphics, x: i32, y: i32, rw: u32, rh: u32, color: u8) void {
        for (0..rh) |row| {
            const dy = y + @as(i32, @intCast(row));
            if (dy < 0 or dy >= HEIGHT) continue;
            const uy: u32 = @intCast(dy);
            for (0..rw) |col| {
                const dx = x + @as(i32, @intCast(col));
                if (dx < 0 or dx >= WIDTH) continue;
                const ux: u32 = @intCast(dx);
                self.px[uy * WIDTH + ux] = color;
            }
        }
    }

    /// 1px bordered panel with fill.
    pub fn panel(self: *Graphics, x: i32, y: i32, pw: u32, ph: u32, bg: u8, border: u8) void {
        self.rect(x, y, pw, ph, bg);
        self.rect(x, y, pw, 1, border);
        self.rect(x, y + @as(i32, @intCast(ph)) - 1, pw, 1, border);
        self.rect(x, y, 1, ph, border);
        self.rect(x + @as(i32, @intCast(pw)) - 1, y, 1, ph, border);
    }

    /// Render text using 8x8 bitmap font. 8px char advance.
    pub fn text(self: *Graphics, str: []const u8, tx: i32, ty: i32, color: u8) void {
        var cx = tx;
        for (str) |ch| {
            if (font_mod.glyph(ch)) |g| {
                for (0..font_mod.CHAR_H) |row| {
                    const bits = g[row];
                    for (0..font_mod.CHAR_W) |col| {
                        if (bits & (@as(u8, 0x80) >> @intCast(col)) != 0) {
                            const px_x = cx + @as(i32, @intCast(col));
                            const px_y = ty + @as(i32, @intCast(row));
                            if (px_x < 0 or px_x >= WIDTH or px_y < 0 or px_y >= HEIGHT) continue;
                            const ux: u32 = @intCast(px_x);
                            const uy: u32 = @intCast(px_y);
                            self.px[uy * WIDTH + ux] = color;
                        }
                    }
                }
            }
            cx += font_mod.CHAR_W;
        }
    }

    /// Convert indexed pixels to RGBA through the palette lookup.
    pub fn resolve(self: *const Graphics, rgba: *[WIDTH * HEIGHT]u32) void {
        for (self.px, 0..) |index, i| {
            rgba[i] = self.pal[index];
        }
    }
};

const std = @import("std");
const W = Graphics.WIDTH;

test "resolve maps indices through palette" {
    var gfx: Graphics = .{};
    gfx.pal[1] = 0xFF0000FF;
    gfx.clear(1);
    var rgba: [W * Graphics.HEIGHT]u32 = undefined;
    gfx.resolve(&rgba);
    try std.testing.expectEqual(@as(u32, 0xFF0000FF), rgba[0]);
    try std.testing.expectEqual(@as(u32, 0xFF0000FF), rgba[W * Graphics.HEIGHT - 1]);
}

test "set_pixel writes index" {
    var gfx: Graphics = .{};
    gfx.set_pixel(2, 1, 42);
    try std.testing.expectEqual(@as(u8, 42), gfx.px[1 * W + 2]);
}

test "set_pixel out of bounds is no-op" {
    var gfx: Graphics = .{};
    gfx.set_pixel(999, 999, 1);
}

test "blit sprite onto framebuffer" {
    const ase = @import("ase.zig");
    var gfx: Graphics = .{};
    const sprite = ase.Sprite{ .width = 2, .height = 2, .strip_width = 2, .pixels = &.{ 1, 0, 0, 2 } };
    gfx.blit(sprite, 1, 1);
    try std.testing.expectEqual(@as(u8, 1), gfx.px[1 * W + 1]);
    try std.testing.expectEqual(@as(u8, 0), gfx.px[1 * W + 2]);
    try std.testing.expectEqual(@as(u8, 0), gfx.px[2 * W + 1]);
    try std.testing.expectEqual(@as(u8, 2), gfx.px[2 * W + 2]);
}

test "blit clips to bounds" {
    const ase = @import("ase.zig");
    var gfx: Graphics = .{};
    const sprite = ase.Sprite{ .width = 2, .height = 2, .strip_width = 2, .pixels = &.{ 1, 2, 3, 4 } };
    gfx.blit(sprite, 319, 179);
    try std.testing.expectEqual(@as(u8, 1), gfx.px[179 * W + 319]);
    gfx.blit(sprite, -1, -1);
    try std.testing.expectEqual(@as(u8, 4), gfx.px[0]);
}

test "blit_frame selects correct frame from strip" {
    const ase = @import("ase.zig");
    var gfx: Graphics = .{};
    const sprite = ase.Sprite{
        .width = 2,
        .height = 2,
        .strip_width = 4,
        .pixels = &.{ 1, 2, 5, 6, 3, 4, 7, 8 },
    };
    gfx.blit_frame(sprite, 1, 0, 0, false);
    try std.testing.expectEqual(@as(u8, 5), gfx.px[0]);
    try std.testing.expectEqual(@as(u8, 6), gfx.px[1]);
    try std.testing.expectEqual(@as(u8, 7), gfx.px[W]);
    try std.testing.expectEqual(@as(u8, 8), gfx.px[W + 1]);
}

test "blit_frame flip mirrors horizontally" {
    const ase = @import("ase.zig");
    var gfx: Graphics = .{};
    const sprite = ase.Sprite{
        .width = 2,
        .height = 2,
        .strip_width = 2,
        .pixels = &.{ 1, 2, 3, 4 },
    };
    gfx.blit_frame(sprite, 0, 0, 0, true);
    try std.testing.expectEqual(@as(u8, 2), gfx.px[0]);
    try std.testing.expectEqual(@as(u8, 1), gfx.px[1]);
    try std.testing.expectEqual(@as(u8, 4), gfx.px[W]);
    try std.testing.expectEqual(@as(u8, 3), gfx.px[W + 1]);
}

test "rect fills correct pixels" {
    var gfx: Graphics = .{};
    gfx.rect(2, 1, 3, 2, 5);
    try std.testing.expectEqual(@as(u8, 5), gfx.px[1 * W + 2]);
    try std.testing.expectEqual(@as(u8, 5), gfx.px[1 * W + 4]);
    try std.testing.expectEqual(@as(u8, 5), gfx.px[2 * W + 2]);
    try std.testing.expectEqual(@as(u8, 0), gfx.px[0 * W + 2]);
    try std.testing.expectEqual(@as(u8, 0), gfx.px[1 * W + 5]);
}

test "rect clips to bounds" {
    var gfx: Graphics = .{};
    gfx.rect(-1, -1, 3, 3, 7);
    try std.testing.expectEqual(@as(u8, 7), gfx.px[0]);
    try std.testing.expectEqual(@as(u8, 7), gfx.px[1]);
    try std.testing.expectEqual(@as(u8, 7), gfx.px[W]);
    try std.testing.expectEqual(@as(u8, 0), gfx.px[2]);
}

test "panel border distinct from fill" {
    var gfx: Graphics = .{};
    gfx.panel(1, 1, 6, 4, 10, 20);
    try std.testing.expectEqual(@as(u8, 20), gfx.px[1 * W + 1]);
    try std.testing.expectEqual(@as(u8, 10), gfx.px[2 * W + 3]);
    try std.testing.expectEqual(@as(u8, 20), gfx.px[4 * W + 6]);
}

test "text renders known char at known position" {
    var gfx: Graphics = .{};
    gfx.text("A", 0, 0, 3);
    try std.testing.expectEqual(@as(u8, 0), gfx.px[0]);
    try std.testing.expectEqual(@as(u8, 0), gfx.px[1]);
    try std.testing.expectEqual(@as(u8, 3), gfx.px[2]);
    try std.testing.expectEqual(@as(u8, 3), gfx.px[3]);
    try std.testing.expectEqual(@as(u8, 0), gfx.px[4]);
}
