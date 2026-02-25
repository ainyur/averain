/// World tilemap. Loaded from world.map at comptime, mutable at runtime.
const orb = @import("orb");

/// Tile dimensions in pixels.
pub const TILE_SIZE: u32 = 16;

const MAP_RAW = @embedFile("assets/world.map");

/// World dimensions parsed from the map file header.
pub const WORLD_W: u32 = @as(u32, MAP_RAW[0]) | @as(u32, MAP_RAW[1]) << 8;
pub const WORLD_H: u32 = @as(u32, MAP_RAW[2]) | @as(u32, MAP_RAW[3]) << 8;

const World = orb.map.Map(.{ .width = WORLD_W, .height = WORLD_H });

/// Tile property bit flags.
pub const Prop = struct {
    pub const SOLID: u8 = 0x01;
};

/// Runtime tile properties, built from ASE slice user_data.
pub var props: [256]u8 = [_]u8{0} ** 256;

/// The world map instance.
pub var world: World = World.init(MAP_RAW);

/// Mutable reference to world grid data.
pub var data: *[WORLD_W * WORLD_H]u8 = &world.data;

/// Check if a tile at grid coords is solid.
pub fn is_solid(tx: u8, ty: u8) bool {
    if (tx >= WORLD_W or ty >= WORLD_H) return true;
    const idx = world.data[@as(usize, ty) * WORLD_W + tx];
    return (props[idx] & Prop.SOLID) != 0;
}

/// Render the tilemap to the framebuffer.
pub fn render(gfx: *orb.Graphics, sheet: orb.ase.Sprite, cam_x: i32, cam_y: i32) void {
    orb.tilemap.render(gfx, &world.data, WORLD_W, WORLD_H, TILE_SIZE, sheet, cam_x, cam_y);
}
