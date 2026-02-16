/// Supported display resolutions.
pub const Resolution = enum {
    @"240x160",
    @"320x180",
    @"320x240",
    @"640x360",
    @"640x480",
    @"800x600",
    @"960x540",

    pub fn width(self: Resolution) u32 {
        return switch (self) {
            .@"240x160" => 240,
            .@"320x180" => 320,
            .@"320x240" => 320,
            .@"640x360" => 640,
            .@"640x480" => 640,
            .@"800x600" => 800,
            .@"960x540" => 960,
        };
    }

    pub fn height(self: Resolution) u32 {
        return switch (self) {
            .@"240x160" => 160,
            .@"320x180" => 180,
            .@"320x240" => 240,
            .@"640x360" => 360,
            .@"640x480" => 480,
            .@"800x600" => 600,
            .@"960x540" => 540,
        };
    }
};

/// Indexed framebuffer with 256 color palette. Pixels are u8 palette indices,
/// resolved to RGBA u32 for display.
pub fn GraphicsWith(comptime w: u32, comptime h: u32) type {
    return struct {
        const Self = @This();
        const ase = @import("ase.zig");
        const font_mod = @import("font.zig");

        pub const width = w;
        pub const height = h;

        px: [w * h]u8 = [_]u8{0} ** (w * h),
        pal: [256]u32 = [_]u32{0x000000FF} ** 256,

        /// Fill the entire framebuffer with a palette index.
        pub fn clear(self: *Self, index: u8) void {
            @memset(&self.px, index);
        }

        /// Write a palette index at (x, y). Out of bounds writes are ignored.
        pub fn set_pixel(self: *Self, x: u32, y: u32, index: u8) void {
            if (x >= w or y >= h) return;
            self.px[y * w + x] = index;
        }

        /// Blit frame 0 of a sprite. Index 0 is transparent.
        /// Signed position allows partial offscreen sprites (clips to bounds).
        pub fn blit(self: *Self, sprite: ase.Sprite, sx: i32, sy: i32) void {
            self.blit_frame(sprite, 0, sx, sy);
        }

        /// Blit a specific frame from a sprite strip. Index 0 is transparent.
        pub fn blit_frame(self: *Self, sprite: ase.Sprite, frame: u32, sx: i32, sy: i32) void {
            const src_x = frame * sprite.width;
            for (0..sprite.height) |row| {
                const dy = sy + @as(i32, @intCast(row));
                if (dy < 0 or dy >= h) continue;
                const uy: u32 = @intCast(dy);
                for (0..sprite.width) |col| {
                    const dx = sx + @as(i32, @intCast(col));
                    if (dx < 0 or dx >= w) continue;
                    const idx = sprite.pixels[row * sprite.strip_width + src_x + col];
                    if (idx == 0) continue;
                    const ux: u32 = @intCast(dx);
                    self.px[uy * w + ux] = idx;
                }
            }
        }

        /// Filled rectangle, clips to bounds.
        pub fn rect(self: *Self, x: i32, y: i32, rw: u32, rh: u32, color: u8) void {
            for (0..rh) |row| {
                const dy = y + @as(i32, @intCast(row));
                if (dy < 0 or dy >= h) continue;
                const uy: u32 = @intCast(dy);
                for (0..rw) |col| {
                    const dx = x + @as(i32, @intCast(col));
                    if (dx < 0 or dx >= w) continue;
                    const ux: u32 = @intCast(dx);
                    self.px[uy * w + ux] = color;
                }
            }
        }

        /// 1px bordered panel with fill.
        pub fn panel(self: *Self, x: i32, y: i32, pw: u32, ph: u32, bg: u8, border: u8) void {
            self.rect(x, y, pw, ph, bg);
            // Top and bottom borders
            self.rect(x, y, pw, 1, border);
            self.rect(x, y + @as(i32, @intCast(ph)) - 1, pw, 1, border);
            // Left and right borders
            self.rect(x, y, 1, ph, border);
            self.rect(x + @as(i32, @intCast(pw)) - 1, y, 1, ph, border);
        }

        /// Render text using 8x8 bitmap font. 8px char advance.
        pub fn text(self: *Self, str: []const u8, tx: i32, ty: i32, color: u8) void {
            var cx = tx;
            for (str) |ch| {
                if (font_mod.glyph(ch)) |g| {
                    for (0..font_mod.char_h) |row| {
                        const bits = g[row];
                        for (0..font_mod.char_w) |col| {
                            if (bits & (@as(u8, 0x80) >> @intCast(col)) != 0) {
                                const px_x = cx + @as(i32, @intCast(col));
                                const px_y = ty + @as(i32, @intCast(row));
                                if (px_x < 0 or px_x >= w or px_y < 0 or px_y >= h) continue;
                                const ux: u32 = @intCast(px_x);
                                const uy: u32 = @intCast(px_y);
                                self.px[uy * w + ux] = color;
                            }
                        }
                    }
                }
                cx += font_mod.char_w;
            }
        }

        /// Convert indexed pixels to RGBA through the palette lookup.
        pub fn resolve(self: *const Self, rgba: *[w * h]u32) void {
            for (self.px, 0..) |index, i| {
                rgba[i] = self.pal[index];
            }
        }
    };
}

const std = @import("std");

test "resolve maps indices through palette" {
    var gfx: GraphicsWith(4, 2) = .{};
    gfx.pal[0] = 0x000000FF;
    gfx.pal[1] = 0xFF0000FF;
    gfx.clear(1);
    var rgba: [8]u32 = undefined;
    gfx.resolve(&rgba);
    for (rgba) |pixel| {
        try std.testing.expectEqual(@as(u32, 0xFF0000FF), pixel);
    }
}

test "set_pixel writes index" {
    var gfx: GraphicsWith(4, 4) = .{};
    gfx.set_pixel(2, 1, 42);
    try std.testing.expectEqual(@as(u8, 42), gfx.px[1 * 4 + 2]);
}

test "set_pixel out of bounds is no-op" {
    var gfx: GraphicsWith(4, 4) = .{};
    gfx.set_pixel(99, 99, 1);
}

test "blit sprite onto framebuffer" {
    const ase = @import("ase.zig");
    var gfx: GraphicsWith(4, 4) = .{};
    const sprite = ase.Sprite{ .width = 2, .height = 2, .strip_width = 2, .pixels = &.{ 1, 0, 0, 2 } };
    gfx.blit(sprite, 1, 1);
    try std.testing.expectEqual(@as(u8, 1), gfx.px[1 * 4 + 1]);
    try std.testing.expectEqual(@as(u8, 0), gfx.px[1 * 4 + 2]); // transparent, unchanged
    try std.testing.expectEqual(@as(u8, 0), gfx.px[2 * 4 + 1]); // transparent
    try std.testing.expectEqual(@as(u8, 2), gfx.px[2 * 4 + 2]);
}

test "blit clips to bounds" {
    const ase = @import("ase.zig");
    var gfx: GraphicsWith(4, 4) = .{};
    const sprite = ase.Sprite{ .width = 2, .height = 2, .strip_width = 2, .pixels = &.{ 1, 2, 3, 4 } };
    gfx.blit(sprite, 3, 3); // only top left pixel visible
    try std.testing.expectEqual(@as(u8, 1), gfx.px[3 * 4 + 3]);
    // Negative position
    gfx.blit(sprite, -1, -1); // only bottom right pixel visible
    try std.testing.expectEqual(@as(u8, 4), gfx.px[0 * 4 + 0]);
}

test "blit_frame selects correct frame from strip" {
    const ase = @import("ase.zig");
    var gfx: GraphicsWith(4, 4) = .{};
    // 2-frame strip: frame 0 = [1,2,3,4], frame 1 = [5,6,7,8], each 2x2
    const sprite = ase.Sprite{
        .width = 2,
        .height = 2,
        .strip_width = 4,
        .pixels = &.{ 1, 2, 5, 6, 3, 4, 7, 8 },
    };
    gfx.blit_frame(sprite, 1, 0, 0);
    try std.testing.expectEqual(@as(u8, 5), gfx.px[0]);
    try std.testing.expectEqual(@as(u8, 6), gfx.px[1]);
    try std.testing.expectEqual(@as(u8, 7), gfx.px[4]);
    try std.testing.expectEqual(@as(u8, 8), gfx.px[5]);
}

test "rect fills correct pixels" {
    var gfx: GraphicsWith(8, 8) = .{};
    gfx.rect(2, 1, 3, 2, 5);
    try std.testing.expectEqual(@as(u8, 5), gfx.px[1 * 8 + 2]);
    try std.testing.expectEqual(@as(u8, 5), gfx.px[1 * 8 + 4]);
    try std.testing.expectEqual(@as(u8, 5), gfx.px[2 * 8 + 2]);
    try std.testing.expectEqual(@as(u8, 0), gfx.px[0 * 8 + 2]); // above rect
    try std.testing.expectEqual(@as(u8, 0), gfx.px[1 * 8 + 5]); // right of rect
}

test "rect clips to bounds" {
    var gfx: GraphicsWith(4, 4) = .{};
    gfx.rect(-1, -1, 3, 3, 7);
    try std.testing.expectEqual(@as(u8, 7), gfx.px[0]);
    try std.testing.expectEqual(@as(u8, 7), gfx.px[1]);
    try std.testing.expectEqual(@as(u8, 7), gfx.px[4]);
    try std.testing.expectEqual(@as(u8, 0), gfx.px[2]); // outside rect
}

test "panel border distinct from fill" {
    var gfx: GraphicsWith(16, 16) = .{};
    gfx.panel(1, 1, 6, 4, 10, 20);
    // Border pixel (top-left corner)
    try std.testing.expectEqual(@as(u8, 20), gfx.px[1 * 16 + 1]);
    // Interior pixel
    try std.testing.expectEqual(@as(u8, 10), gfx.px[2 * 16 + 3]);
    // Border pixel (bottom-right corner)
    try std.testing.expectEqual(@as(u8, 20), gfx.px[4 * 16 + 6]);
}

test "text renders known char at known position" {
    var gfx: GraphicsWith(16, 16) = .{};
    gfx.text("A", 0, 0, 3);
    // A row 0: ..##.... = pixels at (2,0) and (3,0)
    try std.testing.expectEqual(@as(u8, 0), gfx.px[0 * 16 + 0]);
    try std.testing.expectEqual(@as(u8, 0), gfx.px[0 * 16 + 1]);
    try std.testing.expectEqual(@as(u8, 3), gfx.px[0 * 16 + 2]);
    try std.testing.expectEqual(@as(u8, 3), gfx.px[0 * 16 + 3]);
    try std.testing.expectEqual(@as(u8, 0), gfx.px[0 * 16 + 4]);
}