const graphics = @import("graphics.zig");

pub const DevInput = @import("input.zig").DevInput;
pub const Graphics = graphics.Graphics;
pub const Input = @import("input.zig").Input;
pub const InputState = @import("input.zig").InputState;
pub const ase = @import("ase.zig");
pub const dialogue = @import("dialogue.zig");
pub const font = @import("font.zig");
pub const gpl = @import("gpl.zig");
pub const grid = @import("grid.zig");
pub const math = @import("math.zig");
pub const text = @import("text.zig");
pub const tilemap = @import("tilemap.zig");
pub const ui = @import("ui.zig");
pub const watcher = @import("watcher.zig");

/// Start the game loop on the SDL3 platform.
pub fn run(comptime Game: type) u8 {
    return @import("platform/sdl3.zig").start(Game);
}
