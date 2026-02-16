/// Player character. Grid-based movement with smooth tile-to-tile sliding.
const orb = @import("orb");
const map = @import("map.zig");

pub const Player = struct {
    tile_x: u8,
    tile_y: u8,
    px_x: i16 = 0,
    px_y: i16 = 0,
    facing: Dir = .down,
    walk_timer: u8 = 0,

    pub const Dir = enum(u2) { down, up, left, right };
    const walk_frames = 8;
    const step: i16 = @divExact(map.tile_size, walk_frames);

    /// Create player at a tile position.
    pub fn init(tx: u8, ty: u8) Player {
        return .{ .tile_x = tx, .tile_y = ty };
    }

    /// Process input and advance movement. Solid_fn checks collision.
    pub fn update(self: *Player, input: orb.InputState, solid_fn: *const fn (u8, u8) bool) void {
        if (self.walk_timer == 0) {
            var dir: ?Dir = null;
            if (input.pressed.down) dir = .down
            else if (input.pressed.up) dir = .up
            else if (input.pressed.left) dir = .left
            else if (input.pressed.right) dir = .right;

            if (dir) |d| {
                self.facing = d;
                const target = self.facing_tile();
                if (!solid_fn(target[0], target[1])) {
                    self.walk_timer = walk_frames;
                }
            }
        }

        if (self.walk_timer > 0) {
            self.walk_timer -= 1;
            switch (self.facing) {
                .down => self.px_y += step,
                .up => self.px_y -= step,
                .left => self.px_x -= step,
                .right => self.px_x += step,
            }
            if (self.walk_timer == 0) {
                self.px_x = 0;
                self.px_y = 0;
                switch (self.facing) {
                    .down => self.tile_y += 1,
                    .up => self.tile_y -= 1,
                    .left => self.tile_x -= 1,
                    .right => self.tile_x += 1,
                }
            }
        }
    }

    /// Pixel x for sprite rendering. Sprite is 32x32 centered on 16x16 tile.
    pub fn screen_x(self: *const Player) i32 {
        const base = @as(i32, self.tile_x) * map.tile_size - 8;
        return base + self.px_x;
    }

    /// Pixel y for sprite rendering.
    pub fn screen_y(self: *const Player) i32 {
        const base = @as(i32, self.tile_y) * map.tile_size - 16;
        return base + self.px_y;
    }

    /// Current animation frame index for the sprite strip.
    pub fn frame(self: *const Player, spr: orb.ase.Sprite) u32 {
        const total: u32 = spr.strip_width / spr.width;
        if (total <= 1) return 0;
        const dir: u32 = @intFromEnum(self.facing);
        const fpd: u32 = total / 4;
        if (fpd <= 1) return dir;
        const anim: u32 = if (self.walk_timer > walk_frames / 2) 0 else if (self.walk_timer > 0) 1 else 0;
        return dir * fpd + anim;
    }

    /// Grid coords of the tile the player is facing.
    pub fn facing_tile(self: *const Player) [2]u8 {
        return switch (self.facing) {
            .down => .{ self.tile_x, if (self.tile_y < map.map_h - 1) self.tile_y + 1 else self.tile_y },
            .up => .{ self.tile_x, self.tile_y -| 1 },
            .left => .{ self.tile_x -| 1, self.tile_y },
            .right => .{ if (self.tile_x < map.map_w - 1) self.tile_x + 1 else self.tile_x, self.tile_y },
        };
    }
};
