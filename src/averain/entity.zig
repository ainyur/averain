/// NPCs and interactable objects in the scene.
const orb = @import("orb");
const map = @import("map.zig");

pub const Entity = struct {
    tile_x: u8,
    tile_y: u8,
    kind: Kind,
    dialogue_id: u8,

    pub const Kind = enum(u8) { npc, object };
};

/// Scene entities. Arawn and the standing stone.
pub const entities = [2]Entity{
    .{ .tile_x = 13, .tile_y = 4, .kind = .npc, .dialogue_id = 0 },
    .{ .tile_x = 4, .tile_y = 3, .kind = .object, .dialogue_id = 5 },
};

/// Check if any entity occupies a tile.
pub fn at(tx: u8, ty: u8) ?usize {
    for (&entities, 0..) |*e, i| {
        if (e.tile_x == tx and e.tile_y == ty) return i;
    }
    return null;
}

/// Collision check combining map solids and entity positions.
pub fn is_blocked(tx: u8, ty: u8) bool {
    if (map.is_solid(tx, ty)) return true;
    return at(tx, ty) != null;
}

/// Render entity sprites.
pub fn render(gfx: *orb.Graphics, arawn_spr: orb.ase.Sprite, stone_spr: orb.ase.Sprite) void {
    for (&entities) |*e| {
        switch (e.kind) {
            .npc => {
                const sx: i32 = @as(i32, e.tile_x) * map.tile_size - 8;
                const sy: i32 = @as(i32, e.tile_y) * map.tile_size - 16;
                gfx.blit(arawn_spr, sx, sy);
            },
            .object => {
                const sx: i32 = @as(i32, e.tile_x) * map.tile_size;
                const sy: i32 = @as(i32, e.tile_y) * map.tile_size - @as(i32, stone_spr.height) + map.tile_size;
                gfx.blit(stone_spr, sx, sy);
            },
        }
    }
}
