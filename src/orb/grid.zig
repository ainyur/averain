/// Grid-based movement with smooth tile-to-tile sliding.
const FixedPoint = @import("math.zig").FixedPoint;
const InputState = @import("input.zig").InputState;

/// Cardinal facing direction.
pub const Dir = enum(u2) { down, up, left, right };

/// Movement tuning for a grid walker.
pub const Config = struct {
    tile_size: u32,
    walk_frames: u8 = 16,
};

/// Tile-based walker with fixed-point interpolation and blend smoothing.
pub fn Walker(comptime cfg: Config) type {
    return struct {
        const Self = @This();

        /// Walk duration in frames.
        pub const WALK_FRAMES = cfg.walk_frames;

        const DECAY = FixedPoint.init(0.8);
        const SNAP = FixedPoint.init(0.5);
        const TILE_FP = FixedPoint.init(@as(i32, cfg.tile_size));
        const FRAMES_FP = FixedPoint.init(@as(i32, cfg.walk_frames));

        tile_x: u8,
        tile_y: u8,
        facing: Dir = .down,
        walk_timer: u8 = 0,
        blend_ox: FixedPoint = FixedPoint.ZERO,
        blend_oy: FixedPoint = FixedPoint.ZERO,

        /// Create a walker at a tile position.
        pub fn init(tx: u8, ty: u8) Self {
            return .{ .tile_x = tx, .tile_y = ty };
        }

        /// Process input and advance movement. Solid_fn checks collision.
        pub fn update(self: *Self, input: InputState, solid_fn: *const fn (u8, u8) bool) void {
            var dir: ?Dir = null;
            if (input.held.down) dir = .down
            else if (input.held.up) dir = .up
            else if (input.held.left) dir = .left
            else if (input.held.right) dir = .right;

            self.decay_blend();

            if (dir) |d| {
                if (self.walk_timer > 0 and d != self.facing) {
                    const old_fx = self.fp_x();
                    const old_fy = self.fp_y();
                    self.commit_tile();
                    self.walk_timer = 0;
                    self.try_walk(d, solid_fn);

                    self.blend_ox = old_fx.sub(self.fp_x());
                    self.blend_oy = old_fy.sub(self.fp_y());
                    return;
                }

                if (self.walk_timer == 0) {
                    self.try_walk(d, solid_fn);
                }
            }

            if (self.walk_timer > 0) {
                self.walk_timer -= 1;
                if (self.walk_timer == 0) {
                    self.commit_tile();
                }
            }
        }

        /// Pixel x of the tile origin plus walk interpolation.
        pub fn pixel_x(self: *const Self) i32 {
            return self.fp_x().round();
        }

        /// Pixel y of the tile origin plus walk interpolation.
        pub fn pixel_y(self: *const Self) i32 {
            return self.fp_y().round();
        }

        /// Grid coords of the tile ahead in the facing direction.
        pub fn facing_tile(self: *const Self, map_w: u8, map_h: u8) [2]u8 {
            return switch (self.facing) {
                .down => .{ self.tile_x, @min(self.tile_y + 1, map_h - 1) },
                .up => .{ self.tile_x, self.tile_y -| 1 },
                .left => .{ self.tile_x -| 1, self.tile_y },
                .right => .{ @min(self.tile_x + 1, map_w - 1), self.tile_y },
            };
        }

        /// Face a direction and begin walking if the target tile is clear.
        fn try_walk(self: *Self, d: Dir, solid_fn: *const fn (u8, u8) bool) void {
            self.facing = d;
            const target = self.facing_tile(255, 255);
            if (!solid_fn(target[0], target[1])) {
                self.walk_timer = cfg.walk_frames;
            }
        }

        /// Decay blend offsets toward zero for smooth direction changes.
        fn decay_blend(self: *Self) void {
            self.blend_ox = self.blend_ox.mul(DECAY);
            self.blend_oy = self.blend_oy.mul(DECAY);
            if (self.blend_ox.abs().lt(SNAP)) self.blend_ox = FixedPoint.ZERO;
            if (self.blend_oy.abs().lt(SNAP)) self.blend_oy = FixedPoint.ZERO;
        }

        /// Advance tile position one step in the current facing direction.
        fn commit_tile(self: *Self) void {
            switch (self.facing) {
                .down => self.tile_y += 1,
                .up => self.tile_y -= 1,
                .left => self.tile_x -= 1,
                .right => self.tile_x += 1,
            }
        }

        /// Sub-pixel offset along the walk axis. Zero when idle.
        fn walk_offset(self: *const Self) FixedPoint {
            if (self.walk_timer == 0) return FixedPoint.ZERO;
            const elapsed = FixedPoint.init(@as(i32, cfg.walk_frames) - @as(i32, self.walk_timer));
            return elapsed.mul(TILE_FP).div(FRAMES_FP);
        }

        /// Sub-pixel x position for blending.
        fn fp_x(self: *const Self) FixedPoint {
            const base = FixedPoint.init(@as(i32, self.tile_x) * @as(i32, cfg.tile_size));
            const walk: FixedPoint = switch (self.facing) {
                .right => self.walk_offset(),
                .left => self.walk_offset().neg(),
                .down, .up => FixedPoint.ZERO,
            };
            return base.add(walk).add(self.blend_ox);
        }

        /// Sub-pixel y position for blending.
        fn fp_y(self: *const Self) FixedPoint {
            const base = FixedPoint.init(@as(i32, self.tile_y) * @as(i32, cfg.tile_size));
            const walk: FixedPoint = switch (self.facing) {
                .down => self.walk_offset(),
                .up => self.walk_offset().neg(),
                .left, .right => FixedPoint.ZERO,
            };
            return base.add(walk).add(self.blend_oy);
        }
    };
}

const std = @import("std");

fn never_solid(_: u8, _: u8) bool {
    return false;
}

fn always_solid(_: u8, _: u8) bool {
    return true;
}

test "walker starts at tile position" {
    const w = Walker(.{ .tile_size = 16 }).init(5, 3);
    try std.testing.expectEqual(@as(i32, 80), w.pixel_x());
    try std.testing.expectEqual(@as(i32, 48), w.pixel_y());
}

test "walker begins walking on input" {
    var w = Walker(.{ .tile_size = 16 }).init(5, 5);
    var input = InputState{};
    input.held.down = true;
    w.update(input, &never_solid);
    try std.testing.expect(w.walk_timer > 0);
    try std.testing.expectEqual(Dir.down, w.facing);
}

test "walker blocked by solid tile" {
    var w = Walker(.{ .tile_size = 16 }).init(5, 5);
    var input = InputState{};
    input.held.down = true;
    w.update(input, &always_solid);
    try std.testing.expectEqual(@as(u8, 0), w.walk_timer);
}

test "walker facing_tile respects bounds" {
    const w = Walker(.{ .tile_size = 16 }).init(0, 0);
    const t = w.facing_tile(20, 12);
    // Facing down from (0,0), should be (0,1)
    try std.testing.expectEqual(@as(u8, 0), t[0]);
    try std.testing.expectEqual(@as(u8, 1), t[1]);
}

test "walker facing_tile clamps at map edge" {
    var w = Walker(.{ .tile_size = 16 }).init(0, 0);
    var input = InputState{};
    input.held.up = true;
    w.update(input, &always_solid);
    const t = w.facing_tile(20, 12);
    // Up from (0,0) clamps to (0,0)
    try std.testing.expectEqual(@as(u8, 0), t[0]);
    try std.testing.expectEqual(@as(u8, 0), t[1]);
}

test "walker completes walk and commits tile" {
    var w = Walker(.{ .tile_size = 16, .walk_frames = 4 }).init(5, 5);
    var input = InputState{};
    input.held.down = true;
    w.update(input, &never_solid);

    // Tick through remaining frames with no input
    input = .{};
    for (0..4) |_| {
        w.update(input, &never_solid);
    }
    try std.testing.expectEqual(@as(u8, 0), w.walk_timer);
    try std.testing.expectEqual(@as(u8, 6), w.tile_y);
}
