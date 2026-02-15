const orb = @import("orb");

/// Averain game cartridge. Bouncing sprite demo with dpad menu.
pub const Game = struct {
    pub const resolution = orb.Resolution.@"320x180";
    pub const width = resolution.width();
    pub const height = resolution.height();
    pub const window_width: u32 = 1280;
    pub const window_height: u32 = 720;

    const pal = orb.gpl.parse(@embedFile("assets/palette.gpl"));
    const sprite = orb.ase.parse(@embedFile("assets/player.ase"));

    pub const transparent = 0;
    pub const black = 1;
    pub const white = 2;
    pub const red = 3;

    x: i32 = 112,
    y: i32 = 72,
    dx: i32 = 1,
    dy: i32 = 1,
    tick: u8 = 0,
    menu: orb.ui.Menu(4) = .{ .count = 0 },
    menu_open: bool = false,

    pub fn init() Game {
        return .{};
    }

    pub fn update(state: *Game, input: orb.InputState) void {
        if (state.menu_open) {
            if (state.menu.update(input)) |result| {
                switch (result) {
                    .selected, .cancelled => {
                        state.menu_open = false;
                    },
                }
            }
            return;
        }

        if (input.pressed.start) {
            state.menu = orb.ui.Menu(4).init(&.{ "Attack", "Magic", "Item", "Stay" });
            state.menu_open = true;
            return;
        }

        if (input.held.left) state.dx = -1;
        if (input.held.right) state.dx = 1;
        if (input.held.up) state.dy = -1;
        if (input.held.down) state.dy = 1;

        state.tick +%= 1;
        if (state.tick % 3 != 0) return;

        state.x += state.dx;
        state.y += state.dy;

        if (state.x <= 0) {
            state.x = 0;
            state.dx = 1;
        }
        if (state.x >= @as(i32, width - sprite.width)) {
            state.x = @intCast(width - sprite.width);
            state.dx = -1;
        }
        if (state.y <= 0) {
            state.y = 0;
            state.dy = 1;
        }
        if (state.y >= @as(i32, height - sprite.height)) {
            state.y = @intCast(height - sprite.height);
            state.dy = -1;
        }
    }

    pub fn render(state: *Game, gfx: *orb.Graphics) void {
        gfx.pal = pal;
        gfx.clear(black);
        gfx.blit(sprite.pixels, state.x, state.y, sprite.width, sprite.height);
        if (state.menu_open) {
            state.menu.draw(gfx, 8, 8, black, white, white, red);
        }
    }
};
