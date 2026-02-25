const c = @cImport({
    @cDefine("SDL_MAIN_HANDLED", "1");
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_main.h");
});
const std = @import("std");
const Graphics = @import("../graphics.zig").Graphics;
const input_mod = @import("../input.zig");
const ui_mod = @import("../ui.zig");

/// Start the SDL3 main callback loop for a game. Returns exit code.
pub fn start(comptime Game: type) u8 {
    return Platform(Game).entry();
}

/// SDL3 platform layer, generic over the game type.
fn Platform(comptime Game: type) type {
    return struct {
        /// Max ticks per frame to prevent spiral of death.
        const MAX_TICKS: u32 = 4;
        /// Nanoseconds per game tick (60 Hz).
        const NS_PER_TICK: u64 = 1_000_000_000 / 60;

        const AppState = struct {
            accum: u64 = 0,
            console: ui_mod.Console = .{},
            console_active: bool = false,
            dev_input: input_mod.DevInput = .{},
            fps: u32 = 0,
            gamepad: ?*c.SDL_Gamepad = null,
            frame_count: u32 = 0,
            gfx: Graphics,
            last_ticks: u64 = 0,
            prev_input: input_mod.Input,
            prev_time: u64 = 0,
            renderer: ?*c.SDL_Renderer,
            rgba: [Graphics.WIDTH * Graphics.HEIGHT]u32,
            state: Game,
            texture: ?*c.SDL_Texture,
            window: ?*c.SDL_Window = null,
        };

        var app: AppState = undefined;

        /// SDL_AppInit callback, called once at startup.
        fn sdl_init(
            _: [*c]?*anyopaque,
            _: c_int,
            _: [*c][*c]u8,
        ) callconv(.c) c.SDL_AppResult {
            if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_GAMEPAD)) return c.SDL_APP_FAILURE;

            var window: ?*c.SDL_Window = null;
            var renderer: ?*c.SDL_Renderer = null;
            if (!c.SDL_CreateWindowAndRenderer(
                Game.TITLE,
                Game.WINDOW_WIDTH,
                Game.WINDOW_HEIGHT,
                0,
                &window,
                &renderer,
            )) return c.SDL_APP_FAILURE;

            _ = c.SDL_SetRenderLogicalPresentation(
                renderer,
                @intCast(Graphics.WIDTH),
                @intCast(Graphics.HEIGHT),
                c.SDL_LOGICAL_PRESENTATION_INTEGER_SCALE,
            );

            const texture = c.SDL_CreateTexture(
                renderer,
                c.SDL_PIXELFORMAT_RGBA8888,
                c.SDL_TEXTUREACCESS_STATIC,
                @intCast(Graphics.WIDTH),
                @intCast(Graphics.HEIGHT),
            );
            _ = c.SDL_SetTextureScaleMode(texture, c.SDL_SCALEMODE_NEAREST);

            _ = c.SDL_SetRenderVSync(renderer, 0);

            app = .{
                .state = Game.init(std.heap.page_allocator) catch return c.SDL_APP_FAILURE,
                .gfx = .{},
                .prev_time = c.SDL_GetTicksNS(),
                .rgba = undefined,
                .prev_input = .{},
                .renderer = renderer,
                .texture = texture,
                .window = window,
                .last_ticks = c.SDL_GetTicks(),
            };

            return c.SDL_APP_CONTINUE;
        }

        /// SDL_AppEvent callback, called once per event.
        fn sdl_event(
            _: ?*anyopaque,
            ev: [*c]c.SDL_Event,
        ) callconv(.c) c.SDL_AppResult {
            if (ev[0].type == c.SDL_EVENT_QUIT) return c.SDL_APP_SUCCESS;

            if (ev[0].type == c.SDL_EVENT_KEY_DOWN) {
                const scancode = ev[0].key.scancode;
                if (scancode == c.SDL_SCANCODE_GRAVE) {
                    app.dev_input.console_toggle = true;
                } else if (scancode == c.SDL_SCANCODE_F2) {
                    app.dev_input.editor_toggle = true;
                } else if (scancode == c.SDL_SCANCODE_F5) {
                    app.dev_input.save = true;
                } else if (app.console_active) {
                    if (scancode == c.SDL_SCANCODE_BACKSPACE) {
                        app.dev_input.backspace = true;
                    } else if (scancode == c.SDL_SCANCODE_RETURN) {
                        app.dev_input.enter = true;
                    }
                } else {
                    if (scancode == c.SDL_SCANCODE_LEFTBRACKET) {
                        app.dev_input.tile_prev = true;
                    } else if (scancode == c.SDL_SCANCODE_RIGHTBRACKET) {
                        app.dev_input.tile_next = true;
                    }
                }
            }

            if (ev[0].type == c.SDL_EVENT_MOUSE_BUTTON_DOWN) {
                var lx: f32 = 0;
                var ly: f32 = 0;
                _ = c.SDL_RenderCoordinatesFromWindow(app.renderer, ev[0].button.x, ev[0].button.y, &lx, &ly);
                app.dev_input.mouse_x = @intFromFloat(lx);
                app.dev_input.mouse_y = @intFromFloat(ly);
                if (ev[0].button.button == c.SDL_BUTTON_LEFT) {
                    app.dev_input.mouse_click = true;
                } else if (ev[0].button.button == c.SDL_BUTTON_RIGHT) {
                    app.dev_input.mouse_right = true;
                }
            }

            if (ev[0].type == c.SDL_EVENT_MOUSE_WHEEL) {
                app.dev_input.mouse_wheel += @intFromFloat(ev[0].wheel.y);
            }

            if (ev[0].type == c.SDL_EVENT_GAMEPAD_ADDED and app.gamepad == null) {
                app.gamepad = c.SDL_OpenGamepad(ev[0].gdevice.which);
            }

            if (ev[0].type == c.SDL_EVENT_GAMEPAD_REMOVED) {
                if (app.gamepad != null) {
                    c.SDL_CloseGamepad(app.gamepad);
                    app.gamepad = null;
                }
            }

            if (ev[0].type == c.SDL_EVENT_TEXT_INPUT and app.console_active) {
                const txt: [*c]const u8 = ev[0].text.text;
                if (txt != null) {
                    var i: u8 = 0;
                    while (i < 32 and txt[i] != 0) : (i += 1) {
                        if (app.dev_input.text_len < 32) {
                            app.dev_input.text_buf[app.dev_input.text_len] = txt[i];
                            app.dev_input.text_len += 1;
                        }
                    }
                }
            }

            return c.SDL_APP_CONTINUE;
        }

        /// SDL_AppIterate callback. Fixed 60 Hz game tick, uncapped render.
        fn sdl_iterate(_: ?*anyopaque) callconv(.c) c.SDL_AppResult {
            const now = c.SDL_GetTicksNS();
            app.accum += now - app.prev_time;
            app.prev_time = now;

            // Sample input once per frame.
            const curr_input = read_keys();
            const input_state = input_mod.make(curr_input, app.prev_input);

            if (app.dev_input.console_toggle) {
                app.console_active = !app.console_active;
                if (app.console_active) {
                    _ = c.SDL_StartTextInput(app.window);
                } else {
                    _ = c.SDL_StopTextInput(app.window);
                }
            }

            if (app.dev_input.editor_toggle and !app.console_active) {
                if (@hasDecl(Game, "toggle_editor")) {
                    Game.toggle_editor(&app.state);
                }
            }

            if (app.console_active) {
                app.console.update(&app.dev_input);
                if (app.console.quit) return c.SDL_APP_SUCCESS;
            }

            // Poll for asset hot reload.
            if (@hasDecl(Game, "poll_assets")) {
                Game.poll_assets(&app.state);
            }

            // Fixed timestep game ticks.
            var ticks: u32 = 0;
            while (app.accum >= NS_PER_TICK and ticks < MAX_TICKS) {
                if (!app.console_active) {
                    Game.update(&app.state, input_state);
                }
                app.console.tick(app.console_active);
                app.accum -= NS_PER_TICK;
                ticks += 1;
            }
            // Only consume pressed edges after a tick delivers them.
            if (ticks > 0) app.prev_input = curr_input;
            // Discard excess accumulation to prevent spiral of death.
            if (app.accum >= NS_PER_TICK) app.accum = 0;

            if (!app.console_active) {
                if (@hasDecl(Game, "dev_update")) {
                    Game.dev_update(&app.state, app.dev_input);
                }
            }

            Game.render(&app.state, &app.gfx);

            app.console.draw(&app.gfx, Game.BLACK, Game.WHITE, Game.WHITE);

            track_fps();
            if (app.console.fps_enabled) {
                draw_fps(&app.gfx);
            }

            app.dev_input = .{};

            present();

            return c.SDL_APP_CONTINUE;
        }

        /// SDL_AppQuit callback, called once at shutdown.
        fn sdl_quit(_: ?*anyopaque, _: c.SDL_AppResult) callconv(.c) void {
            c.SDL_DestroyTexture(app.texture);
            c.SDL_Quit();
        }

        /// Start the SDL3 main callback loop. Returns exit code.
        fn entry() u8 {
            const result = c.SDL_EnterAppMainCallbacks(
                0,
                null,
                &sdl_init,
                &sdl_iterate,
                &sdl_event,
                &sdl_quit,
            );
            return @intCast(result);
        }

        /// Sample keyboard and gamepad state into input struct.
        fn read_keys() input_mod.Input {
            var num_keys: c_int = 0;
            const keys = c.SDL_GetKeyboardState(&num_keys);
            if (keys == null) return .{};

            var inp = input_mod.Input{
                .up = keys[c.SDL_SCANCODE_W] or keys[c.SDL_SCANCODE_UP],
                .down = keys[c.SDL_SCANCODE_S] or keys[c.SDL_SCANCODE_DOWN],
                .left = keys[c.SDL_SCANCODE_A] or keys[c.SDL_SCANCODE_LEFT],
                .right = keys[c.SDL_SCANCODE_D] or keys[c.SDL_SCANCODE_RIGHT],
                .a = keys[c.SDL_SCANCODE_Z] or keys[c.SDL_SCANCODE_E] or keys[c.SDL_SCANCODE_RETURN],
                .b = keys[c.SDL_SCANCODE_X] or keys[c.SDL_SCANCODE_Q] or keys[c.SDL_SCANCODE_ESCAPE],
                .l = keys[c.SDL_SCANCODE_1],
                .r = keys[c.SDL_SCANCODE_2],
                .start = keys[c.SDL_SCANCODE_RETURN],
                .select = keys[c.SDL_SCANCODE_BACKSPACE],
            };

            const gp = app.gamepad orelse return inp;
            const btn = c.SDL_GetGamepadButton;
            inp.up = inp.up or btn(gp, c.SDL_GAMEPAD_BUTTON_DPAD_UP);
            inp.down = inp.down or btn(gp, c.SDL_GAMEPAD_BUTTON_DPAD_DOWN);
            inp.left = inp.left or btn(gp, c.SDL_GAMEPAD_BUTTON_DPAD_LEFT);
            inp.right = inp.right or btn(gp, c.SDL_GAMEPAD_BUTTON_DPAD_RIGHT);
            inp.a = inp.a or btn(gp, c.SDL_GAMEPAD_BUTTON_SOUTH);
            inp.b = inp.b or btn(gp, c.SDL_GAMEPAD_BUTTON_EAST);
            inp.l = inp.l or btn(gp, c.SDL_GAMEPAD_BUTTON_LEFT_SHOULDER);
            inp.r = inp.r or btn(gp, c.SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER);
            inp.start = inp.start or btn(gp, c.SDL_GAMEPAD_BUTTON_START);
            inp.select = inp.select or btn(gp, c.SDL_GAMEPAD_BUTTON_BACK);
            return inp;
        }

        /// Update FPS counter once per second.
        fn track_fps() void {
            app.frame_count += 1;
            const now = c.SDL_GetTicks();
            const elapsed = now - app.last_ticks;
            if (elapsed >= 1000) {
                app.fps = @intCast(app.frame_count * 1000 / elapsed);
                app.frame_count = 0;
                app.last_ticks = now;
            }
        }

        /// Draw FPS counter in top right corner.
        fn draw_fps(gfx: *Graphics) void {
            var buf: [8]u8 = undefined;
            const len = fmt_u32(app.fps, &buf);
            const x: i32 = @intCast(Graphics.WIDTH - len * 8 - 2);
            gfx.text(buf[0..len], x, 2, Game.WHITE);
        }

        /// Format u32 as decimal digits into buf, left-aligned. Returns digit count.
        fn fmt_u32(val: u32, buf: *[8]u8) usize {
            if (val == 0) {
                buf[0] = '0';
                return 1;
            }
            var v = val;
            var i: usize = 0;
            while (v > 0 and i < 8) : (i += 1) {
                buf[7 - i] = '0' + @as(u8, @intCast(v % 10));
                v /= 10;
            }
            const s = 8 - i;
            for (0..i) |j| {
                buf[j] = buf[s + j];
            }
            return i;
        }

        /// Resolve palette to RGBA and upload to GPU texture.
        fn present() void {
            app.gfx.resolve(&app.rgba);
            _ = c.SDL_UpdateTexture(app.texture, null, &app.rgba, Graphics.WIDTH * 4);
            _ = c.SDL_RenderTexture(app.renderer, app.texture, null, null);
            _ = c.SDL_RenderPresent(app.renderer);
        }
    };
}
