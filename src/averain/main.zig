const orb = @import("orb");
const map = @import("map.zig");
const player_mod = @import("player.zig");
const entity = @import("entity.zig");
const dialogue = @import("dialogue.zig");

/// Averain game cartridge. Pwyll's Forest vertical slice.
pub const Game = struct {
    pub const resolution = orb.Resolution.@"320x180";
    pub const width = resolution.width();
    pub const height = resolution.height();
    pub const window_width: u32 = 1280;
    pub const window_height: u32 = 720;

    const pal = orb.gpl.parse(@embedFile("assets/palette.gpl"));
    const player_spr = orb.ase.parse(@embedFile("assets/player.ase"));
    const tiles = orb.ase.parse(@embedFile("assets/tiles.ase"));
    const arawn_spr = orb.ase.parse(@embedFile("assets/arawn.ase"));
    const stone_spr = orb.ase.parse(@embedFile("assets/stone.ase"));

    pub const transparent = 0;
    pub const black = 1;
    pub const light_grey = 2;
    pub const purple = 3;
    pub const dark_green = 4;
    pub const dark_grey = 5;
    pub const indigo = 6;
    pub const brown = 7;
    pub const dark_blue = 8;
    pub const white = 9;
    pub const red = 10;
    pub const gold = 11;

    const Mode = enum(u2) { explore, dialogue, choice };

    const Flags = packed struct {
        examined_stone: bool = false,
        chose_exchange: bool = false,
        _pad: u6 = 0,
    };

    player: player_mod.Player,
    mode: Mode = .explore,
    box: dialogue.Box = .{},
    choice_menu: orb.ui.Menu(2) = .{ .count = 0 },
    flags: Flags = .{},

    /// Create initial game state. Player spawns on the path at bottom.
    pub fn init() Game {
        return .{ .player = player_mod.Player.init(9, 7) };
    }

    /// Advance game logic one tick.
    pub fn update(state: *Game, input: orb.InputState) void {
        switch (state.mode) {
            .explore => state.explore(input),
            .dialogue => state.do_dialogue(input),
            .choice => state.do_choice(input),
        }
    }

    fn explore(state: *Game, input: orb.InputState) void {
        state.player.update(input, &entity.is_blocked);

        if (input.pressed.a and state.player.walk_timer == 0) {
            const target = state.player.facing_tile();
            if (entity.at(target[0], target[1])) |idx| {
                const e = &entity.entities[idx];
                var start_node = e.dialogue_id;
                // Arawn stone-aware variant
                if (idx == 0 and state.flags.examined_stone) {
                    start_node = 7;
                }
                state.box.start(start_node);
                state.mode = .dialogue;
            }
        }
    }

    fn do_dialogue(state: *Game, input: orb.InputState) void {
        if (state.box.update(input)) |ev| {
            switch (ev) {
                .show_choice => {
                    const n = &dialogue.nodes[state.box.node];
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

    fn do_choice(state: *Game, input: orb.InputState) void {
        if (state.choice_menu.update(input)) |result| {
            switch (result) {
                .selected => |sel| {
                    const n = &dialogue.nodes[state.box.node];
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
        gfx.pal = pal;
        gfx.clear(black);

        // Tilemap
        map.render(gfx, tiles);

        // Entities
        entity.render(gfx, arawn_spr, stone_spr);

        // Player
        gfx.blit(player_spr, state.player.screen_x(), state.player.screen_y());

        // Dialogue box
        if (state.mode == .dialogue or state.mode == .choice) {
            state.box.draw(gfx, black, light_grey, white);
        }

        // Choice menu
        if (state.mode == .choice) {
            state.choice_menu.draw(gfx, 8, 120, black, light_grey, white, gold);
        }
    }
};
