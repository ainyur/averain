/// Player character. Wraps orb grid walker with game-specific sprite logic.
const orb = @import("orb");
const Dir = orb.grid.Dir;
const GridWalker = orb.grid.Walker(.{ .tile_size = @import("map.zig").TILE_SIZE });
const Sprite = orb.ase.Sprite;

pub const Player = struct {
    walker: GridWalker,

    /// Create player at a tile position.
    pub fn init(tx: u8, ty: u8) Player {
        return .{ .walker = GridWalker.init(tx, ty) };
    }

    /// Process input and advance movement.
    pub fn update(self: *Player, input: orb.InputState, solid_fn: *const fn (u8, u8) bool) void {
        self.walker.update(input, solid_fn);
    }

    /// Whether the player is standing still.
    pub fn idle(self: *const Player) bool {
        return self.walker.walk_timer == 0;
    }

    /// Grid coords of the tile the player is facing.
    pub fn facing_tile(self: *const Player) [2]u8 {
        return self.walker.facing_tile(255, 255);
    }

    /// Pixel x of the player tile.
    pub fn pixel_x(self: *const Player) i32 {
        return self.walker.pixel_x();
    }

    /// Pixel y of the player tile.
    pub fn pixel_y(self: *const Player) i32 {
        return self.walker.pixel_y();
    }

    /// Current animation frame index for the sprite strip.
    /// Layout: down, left, up (N frames each). Right uses left frames flipped.
    pub fn frame(self: *const Player, spr: Sprite) u32 {
        const total: u32 = spr.strip_width / spr.width;
        if (total <= 1) return 0;
        const group: u32 = switch (self.walker.facing) {
            .down => 0,
            .left, .right => 1,
            .up => 2,
        };
        const per_dir: u32 = total / 3;
        if (per_dir <= 1) return group;
        const walk_frames: u32 = GridWalker.WALK_FRAMES;
        const elapsed: u32 = walk_frames - self.walker.walk_timer;
        const anim: u32 = if (self.walker.walk_timer > 0) elapsed * per_dir / walk_frames else 0;
        return group * per_dir + anim;
    }

    /// Whether the sprite should be flipped horizontally.
    pub fn flipped(self: *const Player) bool {
        return self.walker.facing == .right;
    }
};
