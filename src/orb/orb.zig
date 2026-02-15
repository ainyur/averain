const sdl3 = @import("platform/sdl3.zig");
const game = @import("game");
const graphics = @import("graphics.zig");

pub const Graphics = graphics.GraphicsWith(game.Game.width, game.Game.height);
pub const Input = @import("input.zig").Input;
pub const InputState = @import("input.zig").InputState;
pub const Resolution = graphics.Resolution;
pub const ase = @import("ase.zig");
pub const font = @import("font.zig");
pub const gpl = @import("gpl.zig");
pub const ui = @import("ui.zig");

/// Platform entry point. Starts the main loop via SDL3.
pub fn main() u8 {
    return sdl3.entry();
}
