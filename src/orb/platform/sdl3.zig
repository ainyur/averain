const c = @cImport({
    @cDefine("SDL_MAIN_HANDLED", "1");
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_main.h");
});
const game = @import("game");
const graphics_mod = @import("../graphics.zig");
const input_mod = @import("../input.zig");
const ui_mod = @import("../ui.zig");

const Game = game.Game;
const Graphics = graphics_mod.GraphicsWith(Game.width, Game.height);
const width = Game.width;
const height = Game.height;
const window_width = Game.window_width;
const window_height = Game.window_height;

const AppState = struct {
    state: Game,
    gfx: Graphics,
    rgba: [width * height]u32,
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
/// C signature: SDL_AppResult SDL_AppInit(void **appstate, int argc, char *argv[])
pub fn init(
    _: [*c]?*anyopaque,
    _: c_int,
    _: [*c][*c]u8,
) callconv(.c) c.SDL_AppResult {
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return c.SDL_APP_FAILURE;

    var window: ?*c.SDL_Window = null;
    var renderer: ?*c.SDL_Renderer = null;
    if (!c.SDL_CreateWindowAndRenderer(
        "averain",
        window_width,
        window_height,
        0,
        &window,
        &renderer,
    )) return c.SDL_APP_FAILURE;

    _ = c.SDL_SetRenderLogicalPresentation(
        renderer,
        @intCast(width),
        @intCast(height),
        c.SDL_LOGICAL_PRESENTATION_INTEGER_SCALE,
    );

    const texture = c.SDL_CreateTexture(
        renderer,
        c.SDL_PIXELFORMAT_RGBA8888,
        c.SDL_TEXTUREACCESS_STREAMING,
        @intCast(width),
        @intCast(height),
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
/// C signature: SDL_AppResult SDL_AppEvent(void *appstate, SDL_Event *event)
pub fn event(
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
/// C signature: SDL_AppResult SDL_AppIterate(void *appstate)
pub fn iterate(_: ?*anyopaque) callconv(.c) c.SDL_AppResult {
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
    } else {
        Game.update(&app.state, input_state);
    }

    Game.render(&app.state, &app.gfx);

    if (app.console_active) {
        app.console.draw(&app.gfx, Game.black, Game.white, Game.white);
    }

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
/// C signature: void SDL_AppQuit(void *appstate, SDL_AppResult result)
pub fn quit(_: ?*anyopaque, _: c.SDL_AppResult) callconv(.c) void {
    c.SDL_DestroyTexture(app.texture);
    c.SDL_Quit();
}

/// Start the SDL3 main callback loop. Returns exit code.
pub fn entry() u8 {
    const result = c.SDL_EnterAppMainCallbacks(
        0,
        null,
        &init,
        &iterate,
        &event,
        &quit,
    );
    return @intCast(result);
}

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

fn draw_fps(gfx: *Graphics) void {
    var buf: [8]u8 = undefined;
    const len = fmt_u32(app.fps, &buf);
    gfx.text(buf[0..len], @intCast(width - len * 8 - 2), 2, Game.white);
}

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
    const start = 8 - i;
    if (start > 0) {
        for (0..i) |j| {
            buf[j] = buf[start + j];
        }
    }
    return i;
}

fn present() void {
    var pixels: ?*anyopaque = null;
    var pitch: c_int = 0;
    if (c.SDL_LockTexture(app.texture, null, &pixels, &pitch)) {
        const dst: [*]u32 = @ptrCast(@alignCast(pixels));
        const stride: usize = @intCast(@divExact(pitch, 4));
        for (0..height) |y| {
            const src_row = app.rgba[y * width ..][0..width];
            const dst_row = dst[y * stride ..][0..width];
            @memcpy(dst_row, src_row);
        }
        c.SDL_UnlockTexture(app.texture);
    }
    _ = c.SDL_RenderTexture(app.renderer, app.texture, null, null);
    _ = c.SDL_RenderPresent(app.renderer);
}
