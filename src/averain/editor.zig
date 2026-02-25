/// In-game tile editor. Delegates to orb.editor with averain map config.
const orb = @import("orb");
const map = @import("map.zig");

pub const Editor = orb.editor.Editor(.{
    .tile_size = map.TILE_SIZE,
    .world_w = map.WORLD_W,
    .world_h = map.WORLD_H,
});
