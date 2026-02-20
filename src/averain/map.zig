/// Forest tilemap. 16x16 tiles on a 20x12 grid (320x192px).
const orb = @import("orb");

/// Tile dimensions in pixels.
pub const TILE_SIZE = 16;
/// Map width in tiles.
pub const MAP_W = 20;
/// Map height in tiles.
pub const MAP_H = 12;
/// Number of distinct tile types in the tilesheet.
pub const TILE_COUNT = 12;

/// Tile type indices matching tilesheet column order.
pub const Tile = struct {
    pub const EMPTY = 0;
    pub const GROUND = 1;
    pub const GRASS_SPARSE = 2;
    pub const GRASS_DENSE = 3;
    pub const TREE_FULL = 4;
    pub const TREE_TOP = 5;
    pub const TREE_BASE = 6;
    pub const PATH = 7;
    pub const STONE = 8;
    pub const WATER = 9;
    pub const CLIFF = 10;
    pub const GROUND_ALT = 11;
};

/// Whether each tile type blocks movement.
pub const SOLID = [TILE_COUNT]bool{
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
const T = Tile.TREE_FULL;
const t = Tile.TREE_TOP;
const b = Tile.TREE_BASE;
const G = Tile.GROUND;
const g = Tile.GRASS_SPARSE;
const d = Tile.GRASS_DENSE;
const P = Tile.PATH;
const W = Tile.WATER;
const S = Tile.STONE;
const C = Tile.CLIFF;

/// Map tile data. 20 columns x 12 rows.
pub const DATA = [MAP_W * MAP_H]u8{
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
    // Row 8: dense trees, path continues
    T, T, T, T, T, T, T, T, T, P, P, T, T, T, T, T, T, T, T, T,
    // Row 9: path widens at south entrance
    T, T, T, T, T, b, T, T, g, P, P, g, T, T, b, T, T, T, T, T,
    // Row 10: player spawn row
    T, T, T, T, T, T, T, T, T, P, P, T, T, T, T, T, T, T, T, T,
    // Row 11: dense tree border at bottom
    T, T, T, T, T, T, T, T, T, T, T, T, T, T, T, T, T, T, T, T,
};

/// Check if a tile at grid coords is solid.
pub fn is_solid(tx: u8, ty: u8) bool {
    if (tx >= MAP_W or ty >= MAP_H) return true;
    const idx = DATA[@as(usize, ty) * MAP_W + tx];
    if (idx >= TILE_COUNT) return true;
    return SOLID[idx];
}

/// Render the tilemap to the framebuffer.
pub fn render(gfx: *orb.Graphics, sheet: orb.ase.Sprite) void {
    orb.tilemap.render(gfx, &DATA, MAP_W, MAP_H, TILE_SIZE, sheet);
}
