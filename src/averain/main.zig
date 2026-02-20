const std = @import("std");
const orb = @import("orb");
const assets_mod = @import("assets.zig");
const dialogue = @import("dialogue.zig");
const editor_mod = @import("editor.zig");
const entity = @import("entity.zig");
const map = @import("map.zig");
const player_mod = @import("player.zig");

const Assets = assets_mod.Assets;

/// Averain game cartridge. Pwyll's Forest vertical slice.
pub const Game = struct {
    pub const TITLE = "averain";
    pub const WINDOW_WIDTH: u32 = 1280;
    pub const WINDOW_HEIGHT: u32 = 720;

    /// Palette indices. See assets/palette.gpl for RGB values.
    pub const BLACK = 1;
    pub const BROWN = 17;
    pub const DARK_GREEN = 101;
    pub const DARK_GREY = 8;
    pub const GOLD = 73;
    pub const GREY = 11;
    pub const INDIGO = 149;
    pub const LIGHT_GREY = 12;
    pub const PURPLE = 153;
    pub const RED = 41;
    pub const TRANSPARENT = 0;
    pub const WHITE = 14;

    const DBox = orb.dialogue.Box(.{});

    /// Current game mode, controls which update/input path runs.
    const Mode = enum(u3) { choice, dialogue, editor, explore };

    /// Persistent story flags set by dialogue events.
    const Flags = packed struct {
        examined_stone: bool = false,
        chose_exchange: bool = false,
        _pad: u6 = 0,
    };

    assets: Assets,
    box: DBox = DBox.init(dialogue.NODES),
    choice_menu: orb.ui.Menu(2) = .{ .count = 0 },
    ed: editor_mod.Editor = .{},
    flags: Flags = .{},
    mode: Mode = .explore,
    player: player_mod.Player,

    /// Create initial game state. Player spawns on the path at bottom.
    pub fn init(alloc: std.mem.Allocator) !Game {
        map.init();
        return .{
            .assets = try Assets.init(alloc),
            .player = player_mod.Player.init(9, 10),
        };
    }

    /// Toggle between editor and explore modes.
    pub fn toggle_editor(state: *Game) void {
        if (state.mode == .editor) {
            state.mode = .explore;
        } else if (state.mode == .explore) {
            state.mode = .editor;
        }
    }

    /// Handle dev input (save key).
    pub fn dev_update(state: *Game, dev_input: orb.DevInput) void {
        if (state.mode == .editor and dev_input.save) {
            state.ed.save();
        }
    }

    /// Poll for asset changes. Called by platform before game ticks.
    pub fn poll_assets(state: *Game) void {
        state.assets.poll();
    }

    /// Advance game logic one tick.
    pub fn update(state: *Game, input: orb.InputState) void {
        switch (state.mode) {
            .choice => state.do_choice(input),
            .dialogue => state.do_dialogue(input),
            .editor => state.ed.update(input, state.assets.tiles),
            .explore => state.do_explore(input),
        }
        state.box.tick_slide();
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
        gfx.pal = state.assets.pal;
        gfx.clear(BLACK);

        if (state.mode == .editor) {
            state.ed.draw(gfx, state.assets.tiles);
            return;
        }

        map.render(gfx, state.assets.tiles, 0, 0);
        entity.render(gfx, state.assets.arawn, state.assets.stone);

        const p = &state.player;
        const spr = state.assets.player;
        const off = spr.center(map.TILE_SIZE);
        gfx.blit_frame(spr, p.frame(spr), p.pixel_x() + off[0], p.pixel_y() + off[1], p.flipped());

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
