/// World tilemap. Loaded from world.map at comptime, mutable at runtime.
const orb = @import("orb");

/// Tile dimensions in pixels.
pub const TILE_SIZE: u32 = 16;

/// World dimensions parsed from the map file header.
pub const WORLD_W: u32 = read16(MAP_RAW, 0);
pub const WORLD_H: u32 = read16(MAP_RAW, 2);

/// Number of distinct tile types.
pub const TILE_COUNT: u32 = read16(MAP_RAW, 4);

const MAP_RAW = @embedFile("assets/world.map");
const GRID_OFF = 8;
const PROPS_OFF = GRID_OFF + WORLD_W * WORLD_H;

/// Tile property bit flags.
pub const Prop = struct {
    pub const SOLID: u8 = 0x01;
};

/// Comptime tile properties from the map file. Index 0 unused.
pub const PROPS: *const [TILE_COUNT + 1]u8 = MAP_RAW[PROPS_OFF..][0 .. TILE_COUNT + 1];

/// Mutable runtime grid. Initialized from comptime data in init().
pub var data: [WORLD_W * WORLD_H]u8 = undefined;

/// Copy comptime grid into the mutable runtime buffer.
pub fn init() void {
    @memcpy(&data, MAP_RAW[GRID_OFF..][0 .. WORLD_W * WORLD_H]);
}

/// Check if a tile at grid coords is solid.
pub fn is_solid(tx: u8, ty: u8) bool {
    if (tx >= WORLD_W or ty >= WORLD_H) return true;
    const idx = data[@as(usize, ty) * WORLD_W + tx];
    if (idx == 0 or idx > TILE_COUNT) return false;
    return (PROPS[idx] & Prop.SOLID) != 0;
}

/// Render the tilemap to the framebuffer.
pub fn render(gfx: *orb.Graphics, sheet: orb.ase.Sprite, cam_x: i32, cam_y: i32) void {
    orb.tilemap.render(gfx, &data, WORLD_W, WORLD_H, TILE_SIZE, sheet, cam_x, cam_y);
}

fn read16(d: []const u8, off: usize) u16 {
    return @as(u16, d[off]) | @as(u16, d[off + 1]) << 8;
}
