const orb = @import("orb");
const dialogue = @import("dialogue.zig");
const entity = @import("entity.zig");
const map = @import("map.zig");
const player_mod = @import("player.zig");

/// Averain game cartridge. Pwyll's Forest vertical slice.
pub const Game = struct {
    pub const TITLE = "averain";
    pub const WINDOW_WIDTH: u32 = 1280;
    pub const WINDOW_HEIGHT: u32 = 720;

    const PAL = orb.gpl.parse(@embedFile("assets/palette.gpl"));
    const PLAYER_SPR = orb.ase.parse(@embedFile("assets/player.ase"));
    const TILES_RAW = orb.ase.parse(@embedFile("assets/tiles.ase"));
    const TILES = orb.ase.Sprite{
        .width = map.TILE_SIZE,
        .height = map.TILE_SIZE,
        .strip_width = TILES_RAW.strip_width,
        .pixels = TILES_RAW.pixels,
    };
    const ARAWN_SPR = orb.ase.parse(@embedFile("assets/arawn.ase"));
    const STONE_SPR = orb.ase.parse(@embedFile("assets/stone.ase"));

    /// Palette indices. See assets/palette.gpl for RGB values.
    pub const TRANSPARENT = 0;
    pub const BLACK = 1;
    pub const LIGHT_GREY = 2;
    pub const PURPLE = 3;
    pub const DARK_GREEN = 4;
    pub const DARK_GREY = 5;
    pub const INDIGO = 6;
    pub const BROWN = 7;
    pub const DARK_BLUE = 8;
    pub const WHITE = 9;
    pub const RED = 10;
    pub const GOLD = 11;

    const DBox = orb.dialogue.Box(.{});

    /// Current game mode, controls which update/input path runs.
    const Mode = enum(u2) { explore, dialogue, choice };

    /// Persistent story flags set by dialogue events.
    const Flags = packed struct {
        examined_stone: bool = false,
        chose_exchange: bool = false,
        _pad: u6 = 0,
    };

    player: player_mod.Player,
    mode: Mode = .explore,
    box: DBox = DBox.init(dialogue.NODES),
    choice_menu: orb.ui.Menu(2) = .{ .count = 0 },
    flags: Flags = .{},

    /// Create initial game state. Player spawns on the path at bottom.
    pub fn init() Game {
        return .{ .player = player_mod.Player.init(9, 10) };
    }

    /// Advance game logic one tick.
    pub fn update(state: *Game, input: orb.InputState) void {
        switch (state.mode) {
            .explore => state.do_explore(input),
            .dialogue => state.do_dialogue(input),
            .choice => state.do_choice(input),
        }
    }

    /// Move player and handle interaction with entities.
    fn do_explore(state: *Game, input: orb.InputState) void {
        state.player.update(input, &entity.is_blocked);

        if (input.pressed.a and state.player.idle()) {
            const target = state.player.facing_tile();
            if (entity.at(target[0], target[1])) |idx| {
                const e = &entity.ENTITIES[idx];
                var start_node = e.dialogue_id;
                if (idx == 0 and state.flags.examined_stone) {
                    start_node = 7;
                }
                state.box.start(start_node);
                state.mode = .dialogue;
            }
        }
    }

    /// Advance dialogue typewriter and handle events.
    fn do_dialogue(state: *Game, input: orb.InputState) void {
        if (state.box.update(input)) |ev| {
            switch (ev) {
                .show_choice => {
                    const n = &dialogue.NODES[state.box.node];
                    if (n.choice) |c| {
                        state.choice_menu = orb.ui.Menu(2).init(&c.labels);
                        state.mode = .choice;
                    }
                },
                .set_flag => |flag| {
                    if (flag == 0) state.flags.examined_stone = true;
                    if (flag == 1) state.flags.chose_exchange = true;
                    if (!state.box.active()) state.mode = .explore;
                },
                .closed => {
                    state.mode = .explore;
                },
            }
        }
    }

    /// Process dialogue choice menu selection.
    fn do_choice(state: *Game, input: orb.InputState) void {
        if (state.choice_menu.update(input)) |result| {
            switch (result) {
                .selected => |sel| {
                    const n = &dialogue.NODES[state.box.node];
                    if (n.choice) |c| {
                        if (sel == 0) state.flags.chose_exchange = true;
                        state.box.start(c.targets[sel]);
                        state.mode = .dialogue;
                    }
                },
                .cancelled => {},
            }
        }
    }

    /// Draw the current frame.
    pub fn render(state: *Game, gfx: *orb.Graphics) void {
        gfx.pal = PAL;
        gfx.clear(BLACK);

        map.render(gfx, TILES);
        entity.render(gfx, ARAWN_SPR, STONE_SPR);

        const p = &state.player;
        gfx.blit_frame(PLAYER_SPR, p.frame(PLAYER_SPR), p.screen_x(), p.screen_y(), p.flipped());

        state.box.draw(gfx, BLACK, LIGHT_GREY, WHITE);
        if (state.mode == .choice) {
            state.choice_menu.draw(gfx, 8, 120, BLACK, LIGHT_GREY, WHITE, GOLD);
        }
    }
};

/// Entry point. Launches the game on the SDL3 platform.
pub fn main() u8 {
    return orb.run(Game);
}
