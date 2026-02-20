const c = @cImport({
    @cDefine("SDL_MAIN_HANDLED", "1");
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_main.h");
});
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
        const AppState = struct {
            state: Game,
            gfx: Graphics,
            rgba: [Graphics.WIDTH * Graphics.HEIGHT]u32,
            prev_input: input_mod.Input,
            dev_input: input_mod.DevInput = .{},
            console: ui_mod.Console = .{},
            console_active: bool = false,
            renderer: ?*c.SDL_Renderer,
            texture: ?*c.SDL_Texture,
            window: ?*c.SDL_Window = null,
            last_ticks: u64 = 0,
            frame_count: u32 = 0,
            fps: u32 = 0,
        };

        var app: AppState = undefined;

        /// SDL_AppInit callback, called once at startup.
        fn sdl_init(
            _: [*c]?*anyopaque,
            _: c_int,
            _: [*c][*c]u8,
        ) callconv(.c) c.SDL_AppResult {
            if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return c.SDL_APP_FAILURE;

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
                c.SDL_TEXTUREACCESS_STREAMING,
                @intCast(Graphics.WIDTH),
                @intCast(Graphics.HEIGHT),
            );
            _ = c.SDL_SetTextureScaleMode(texture, c.SDL_SCALEMODE_NEAREST);

            _ = c.SDL_SetRenderVSync(renderer, 1);

            app = .{
                .state = Game.init(),
                .gfx = .{},
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
                } else if (app.console_active) {
                    if (scancode == c.SDL_SCANCODE_BACKSPACE) {
                        app.dev_input.backspace = true;
                    } else if (scancode == c.SDL_SCANCODE_RETURN) {
                        app.dev_input.enter = true;
                    }
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

        /// SDL_AppIterate callback, called once per frame.
        fn sdl_iterate(_: ?*anyopaque) callconv(.c) c.SDL_AppResult {
            const curr_input = read_keys();
            const input_state = input_mod.make(curr_input, app.prev_input);
            app.prev_input = curr_input;

            if (app.dev_input.console_toggle) {
                app.console_active = !app.console_active;
                if (app.console_active) {
                    _ = c.SDL_StartTextInput(app.window);
                } else {
                    _ = c.SDL_StopTextInput(app.window);
                }
            }

            if (app.console_active) {
                app.console.update(&app.dev_input);
                if (app.console.quit) return c.SDL_APP_SUCCESS;
            } else {
                Game.update(&app.state, input_state);
            }

            Game.render(&app.state, &app.gfx);

            app.console.draw(&app.gfx, app.console_active, Game.BLACK, Game.WHITE, Game.WHITE);

            track_fps();
            if (app.console.fps_enabled) {
                draw_fps(&app.gfx);
            }

            app.dev_input = .{};

            app.gfx.resolve(&app.rgba);
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

        /// Sample keyboard state into gamepad-style input struct.
        fn read_keys() input_mod.Input {
            var num_keys: c_int = 0;
            const keys = c.SDL_GetKeyboardState(&num_keys);
            if (keys == null) return .{};
            return .{
                .up = keys[c.SDL_SCANCODE_W] or keys[c.SDL_SCANCODE_UP],
                .down = keys[c.SDL_SCANCODE_S] or keys[c.SDL_SCANCODE_DOWN],
                .left = keys[c.SDL_SCANCODE_A] or keys[c.SDL_SCANCODE_LEFT],
                .right = keys[c.SDL_SCANCODE_D] or keys[c.SDL_SCANCODE_RIGHT],
                .a = keys[c.SDL_SCANCODE_Z],
                .b = keys[c.SDL_SCANCODE_X] or keys[c.SDL_SCANCODE_ESCAPE],
                .l = keys[c.SDL_SCANCODE_Q],
                .r = keys[c.SDL_SCANCODE_E],
                .start = keys[c.SDL_SCANCODE_RETURN],
                .select = keys[c.SDL_SCANCODE_BACKSPACE],
            };
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

        /// Upload RGBA framebuffer to GPU texture and present.
        fn present() void {
            var pixels: ?*anyopaque = null;
            var pitch: c_int = 0;
            if (c.SDL_LockTexture(app.texture, null, &pixels, &pitch)) {
                const dst: [*]u32 = @ptrCast(@alignCast(pixels));
                const stride: usize = @intCast(@divExact(pitch, 4));
                for (0..Graphics.HEIGHT) |y| {
                    const src_row = app.rgba[y * Graphics.WIDTH ..][0..Graphics.WIDTH];
                    const dst_row = dst[y * stride ..][0..Graphics.WIDTH];
                    @memcpy(dst_row, src_row);
                }
                c.SDL_UnlockTexture(app.texture);
            }
            _ = c.SDL_RenderTexture(app.renderer, app.texture, null, null);
            _ = c.SDL_RenderPresent(app.renderer);
        }
    };
}
