/// Forest tilemap. 16x16 tiles on a 20x9 grid (320x144px).
/// Bottom 36px reserved for dialogue box.
const orb = @import("orb");

pub const tile_size = 16;
pub const map_w = 20;
pub const map_h = 9;
pub const tile_count = 12;

/// Tile type indices matching tilesheet column order.
pub const Tile = struct {
    pub const empty = 0;
    pub const ground = 1;
    pub const grass_sparse = 2;
    pub const grass_dense = 3;
    pub const tree_full = 4;
    pub const tree_top = 5;
    pub const tree_base = 6;
    pub const path = 7;
    pub const stone = 8;
    pub const water = 9;
    pub const cliff = 10;
    pub const ground_alt = 11;
};

/// Whether each tile type blocks movement.
pub const solid = [tile_count]bool{
    false, // empty
    false, // ground
    false, // grass_sparse
    false, // grass_dense
    true,  // tree_full
    true,  // tree_top
    true,  // tree_base
    false, // path
    true,  // stone
    true,  // water
    true,  // cliff
    false, // ground_alt
};

// T = tree_full, t = tree_top, b = tree_base
// G = ground, g = grass_sparse, d = grass_dense
// P = path, W = water, S = stone, C = cliff
const T = Tile.tree_full;
const t = Tile.tree_top;
const b = Tile.tree_base;
const G = Tile.ground;
const g = Tile.grass_sparse;
const d = Tile.grass_dense;
const P = Tile.path;
const W = Tile.water;
const S = Tile.stone;
const C = Tile.cliff;

/// Map tile data. 20 columns x 9 rows.
pub const data = [map_w * map_h]u8{
    // Row 0: dense tree border at top
    T, T, T, t, t, t, T, T, T, T, T, T, T, t, t, t, T, T, T, T,
    // Row 1: trees with path opening
    T, T, b, d, g, b, T, T, T, P, P, T, T, b, d, b, T, T, T, T,
    // Row 2: clearing opens, path runs north-south
    T, b, d, g, d, g, d, b, T, P, P, T, b, g, d, g, d, W, W, T,
    // Row 3: west clearing with stone, path continues
    T, d, g, d, S, d, g, d, g, P, P, g, d, g, g, d, g, W, W, T,
    // Row 4: main clearing, path runs through center
    T, d, g, d, g, d, g, g, P, P, P, P, g, g, d, g, d, g, b, T,
    // Row 5: east side has Arawn area, stream
    T, b, d, g, d, g, d, g, g, P, P, g, g, d, g, d, g, W, W, T,
    // Row 6: path continues south
    T, T, b, d, g, d, b, T, g, P, P, g, T, b, d, g, d, W, W, T,
    // Row 7: closing toward bottom
    T, T, T, b, d, b, T, T, T, P, P, T, T, T, b, d, b, T, T, T,
    // Row 8: player spawn row, dense trees
    T, T, T, T, T, T, T, T, T, P, P, T, T, T, T, T, T, T, T, T,
};

/// Check if a tile at grid coords is solid.
pub fn is_solid(tx: u8, ty: u8) bool {
    if (tx >= map_w or ty >= map_h) return true;
    const idx = data[@as(usize, ty) * map_w + tx];
    if (idx >= tile_count) return true;
    return solid[idx];
}

/// Render the tilemap to the framebuffer.
pub fn render(gfx: *orb.Graphics, sheet: orb.ase.Sprite) void {
    for (0..map_h) |row| {
        for (0..map_w) |col| {
            const tile_idx = data[row * map_w + col];
            const dst_x: i32 = @intCast(col * tile_size);
            const dst_y: i32 = @intCast(row * tile_size);
            gfx.blit_frame(sheet, tile_idx, dst_x, dst_y);
        }
    }
}
