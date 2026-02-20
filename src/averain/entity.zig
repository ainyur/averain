/// NPCs and interactable objects in the scene.
const orb = @import("orb");
const map = @import("map.zig");

/// A placed entity: position, type, and dialogue entry point.
pub const Entity = struct {
    tile_x: u8,
    tile_y: u8,
    kind: Kind,
    dialogue_id: u8,

    /// Entity types affecting rendering and interaction.
    pub const Kind = enum(u8) { npc, object };
};

/// Scene entities. Arawn and the standing stone.
pub const ENTITIES = [2]Entity{
    .{ .tile_x = 13, .tile_y = 4, .kind = .npc, .dialogue_id = 0 },
    .{ .tile_x = 4, .tile_y = 3, .kind = .object, .dialogue_id = 5 },
};

/// Check if any entity occupies a tile. Returns entity index.
pub fn at(tx: u8, ty: u8) ?usize {
    for (ENTITIES, 0..) |e, i| {
        if (e.tile_x == tx and e.tile_y == ty) return i;
    }
    return null;
}

/// Collision check combining map solids and entity positions.
pub fn is_blocked(tx: u8, ty: u8) bool {
    if (map.is_solid(tx, ty)) return true;
    return at(tx, ty) != null;
}

/// Render entity sprites at their tile positions.
/// NPCs are 32x32 sprites centered on their tile (offset -8, -16).
/// Objects are bottom-aligned to their tile.
pub fn render(gfx: *orb.Graphics, arawn_spr: orb.ase.Sprite, stone_spr: orb.ase.Sprite) void {
    for (ENTITIES) |e| {
        const tx: i32 = @as(i32, e.tile_x) * map.TILE_SIZE;
        const ty: i32 = @as(i32, e.tile_y) * map.TILE_SIZE;
        switch (e.kind) {
            .npc => gfx.blit(arawn_spr, tx - 8, ty - 16),
            .object => gfx.blit(stone_spr, tx, ty - @as(i32, stone_spr.height) + map.TILE_SIZE),
        }
    }
}
