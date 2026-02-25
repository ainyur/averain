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
    /// Pre-clips to screen bounds so inner loop has no bounds checks.
    pub fn blit_frame(self: *Graphics, sprite: ase.Sprite, frame: u32, sx: i32, sy: i32, flip: bool) void {
        const sw: i32 = @intCast(sprite.width);
        const sh: i32 = @intCast(sprite.height);

        // Out-of-range frame: nothing to draw.
        if (frame * sprite.width >= sprite.strip_width) return;

        // Visible row range.
        const row0: u32 = @intCast(@max(0, -sy));
        const row1_i = @min(sh, @as(i32, HEIGHT) - sy);
        if (row1_i <= 0 or row0 >= @as(u32, @intCast(row1_i))) return;
        const row1: u32 = @intCast(row1_i);

        // Visible column range.
        const col0: u32 = @intCast(@max(0, -sx));
        const col1_i = @min(sw, @as(i32, WIDTH) - sx);
        if (col1_i <= 0 or col0 >= @as(u32, @intCast(col1_i))) return;
        const col1: u32 = @intCast(col1_i);

        const src_x = frame * sprite.width;
        // Screen pixel for first visible row/col. Guaranteed non-negative by clipping.
        const dx0: u32 = @intCast(sx + @as(i32, @intCast(col0)));
        const dy0: u32 = @intCast(sy + @as(i32, @intCast(row0)));
        const vis_w = col1 - col0;

        for (row0..row1) |row| {
            const dst_off = (dy0 + row - row0) * WIDTH + dx0;
            const dst = self.px[dst_off..][0..vis_w];
            const src_row = row * sprite.strip_width + src_x;

            if (flip) {
                // Reversed source: process per pixel.
                var src_col = sprite.width - 1 - col0;
                for (dst) |*d| {
                    const idx = sprite.pixels[src_row + src_col];
                    if (idx != 0) d.* = idx;
                    src_col -%= 1;
                }
            } else {
                const src = sprite.pixels[src_row + col0 ..][0..vis_w];
                // Process 4 pixels at a time. Skip fully transparent quads.
                var i: u32 = 0;
                const count4 = vis_w / 4;
                while (i < count4 * 4) : (i += 4) {
                    const quad: u32 = @bitCast(src[i..][0..4].*);
                    if (quad == 0) continue;
                    if (src[i] != 0) dst[i] = src[i];
                    if (src[i + 1] != 0) dst[i + 1] = src[i + 1];
                    if (src[i + 2] != 0) dst[i + 2] = src[i + 2];
                    if (src[i + 3] != 0) dst[i + 3] = src[i + 3];
                }
                // Remaining pixels.
                while (i < vis_w) : (i += 1) {
                    if (src[i] != 0) dst[i] = src[i];
                }
            }
        }
    }

    /// Blit a rectangular region from a sprite's pixel data.
    /// src_x/src_y are pixel coordinates within the sprite's strip.
    pub fn blit_region(self: *Graphics, sprite: ase.Sprite, src_x: u32, src_y: u32, w: u32, h: u32, dx: i32, dy: i32) void {
        const sw: i32 = @intCast(w);
        const sh: i32 = @intCast(h);

        // Visible row range.
        const row0: u32 = @intCast(@max(0, -dy));
        const row1_i = @min(sh, @as(i32, HEIGHT) - dy);
        if (row1_i <= 0 or row0 >= @as(u32, @intCast(row1_i))) return;
        const row1: u32 = @intCast(row1_i);

        // Visible column range.
        const col0: u32 = @intCast(@max(0, -dx));
        const col1_i = @min(sw, @as(i32, WIDTH) - dx);
        if (col1_i <= 0 or col0 >= @as(u32, @intCast(col1_i))) return;
        const col1: u32 = @intCast(col1_i);

        const dx0: u32 = @intCast(dx + @as(i32, @intCast(col0)));
        const dy0: u32 = @intCast(dy + @as(i32, @intCast(row0)));
        const vis_w = col1 - col0;

        for (row0..row1) |row| {
            const dst_off = (dy0 + row - row0) * WIDTH + dx0;
            const dst = self.px[dst_off..][0..vis_w];
            const src_row = (src_y + @as(u32, @intCast(row))) * sprite.strip_width + src_x;
            const src = sprite.pixels[src_row + col0 ..][0..vis_w];

            var i: u32 = 0;
            const count4 = vis_w / 4;
            while (i < count4 * 4) : (i += 4) {
                const quad: u32 = @bitCast(src[i..][0..4].*);
                if (quad == 0) continue;
                if (src[i] != 0) dst[i] = src[i];
                if (src[i + 1] != 0) dst[i + 1] = src[i + 1];
                if (src[i + 2] != 0) dst[i + 2] = src[i + 2];
                if (src[i + 3] != 0) dst[i + 3] = src[i + 3];
            }
            while (i < vis_w) : (i += 1) {
                if (src[i] != 0) dst[i] = src[i];
            }
        }
    }

    /// Filled rectangle, clips to bounds.
    pub fn rect(self: *Graphics, x: i32, y: i32, rw: u32, rh: u32, color: u8) void {
        const iw: i32 = @intCast(rw);
        const ih: i32 = @intCast(rh);
        const cx0 = @max(@as(i32, 0), x);
        const cy0 = @max(@as(i32, 0), y);
        const cx1 = @min(@as(i32, WIDTH), x + iw);
        const cy1 = @min(@as(i32, HEIGHT), y + ih);
        if (cx0 >= cx1 or cy0 >= cy1) return;
        const x0: u32 = @intCast(cx0);
        const y0: u32 = @intCast(cy0);
        const x1: u32 = @intCast(cx1);
        const y1: u32 = @intCast(cy1);
        const w = x1 - x0;
        for (y0..y1) |py| {
            @memset(self.px[py * WIDTH + x0 ..][0..w], color);
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
    pub fn resolve(self: *const Graphics, rgba: []u32) void {
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
