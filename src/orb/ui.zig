/// Immediate mode UI widgets. Menu, Console, and Slide animation.
const Graphics = @import("graphics.zig").Graphics;
const font = @import("font.zig");
const input_mod = @import("input.zig");
const math = @import("math.zig");

/// Animated slide for UI panels. Ticks a linear counter, applies easing.
pub const Slide = struct {
    t: i32 = 0,
    dur: i32 = 16,

    /// Advance one frame toward open (true) or closed (false).
    pub fn tick(self: *Slide, open: bool) void {
        if (open and self.t < self.dur) {
            self.t += 1;
        } else if (!open and self.t > 0) {
            self.t -= 1;
        }
    }

    /// Eased pixel offset, 0 when closed, height when fully open.
    pub fn pos(self: *const Slide, height: i32) i32 {
        return math.smooth(self.t, self.dur, height);
    }

    /// Whether the panel is at least partially visible.
    pub fn visible(self: *const Slide) bool {
        return self.t > 0;
    }
};

/// Dpad menu. Comptime generic max_items avoids allocation.
pub fn Menu(comptime max_items: u8) type {
    return struct {
        const Self = @This();

        /// Menu interaction outcome: item selected or cancelled.
        pub const Result = union(enum) {
            selected: u8,
            cancelled,
        };

        items: [max_items][]const u8 = undefined,
        count: u8 = 0,
        cursor: u8 = 0,

        /// Create a menu from a slice of label strings.
        pub fn init(labels: []const []const u8) Self {
            var self: Self = .{};
            for (labels, 0..) |label, i| {
                if (i >= max_items) break;
                self.items[i] = label;
            }
            self.count = @intCast(@min(labels.len, max_items));
            return self;
        }

        /// Process dpad input. Returns selected index on A, cancelled on B.
        pub fn update(self: *Self, input: input_mod.InputState) ?Result {
            if (input.pressed.down) {
                self.cursor = if (self.cursor + 1 >= self.count) 0 else self.cursor + 1;
            }
            if (input.pressed.up) {
                self.cursor = if (self.cursor == 0) self.count -| 1 else self.cursor - 1;
            }
            if (input.pressed.a) return .{ .selected = self.cursor };
            if (input.pressed.b) return .cancelled;
            return null;
        }

        /// Draw bordered panel auto-sized to content with arrow cursor.
        pub fn draw(self: *const Self, gfx: *Graphics, x: i32, y: i32, bg: u8, border: u8, text_color: u8, arrow_color: u8) void {
            var max_len: u32 = 0;
            for (0..self.count) |i| {
                const len: u32 = @intCast(self.items[i].len);
                if (len > max_len) max_len = len;
            }
            const pw = 8 + max_len * font.CHAR_W + 8;
            const ph: u32 = @as(u32, self.count) * font.CHAR_H + 8;
            gfx.panel(x, y, pw, ph, bg, border);

            for (0..self.count) |i| {
                const iy = y + 4 + @as(i32, @intCast(i)) * @as(i32, font.CHAR_H);
                if (i == self.cursor) {
                    gfx.text(&[_]u8{0x10}, x + 2, iy, arrow_color);
                }
                gfx.text(self.items[i], x + 10, iy, text_color);
            }
        }
    };
}

/// Dev console overlay. Ring buffer of output lines, text input, /fps command.
/// Uses palette indices 253 (bg), 254 (border), 255 (text).
pub const Console = struct {
    const MAX_LINES = 8;
    const MAX_LINE_LEN = 28;
    const INPUT_MAX = 28;

    lines: [MAX_LINES][MAX_LINE_LEN]u8 = [_][MAX_LINE_LEN]u8{[_]u8{0} ** MAX_LINE_LEN} ** MAX_LINES,
    line_lens: [MAX_LINES]u8 = [_]u8{0} ** MAX_LINES,
    head: u8 = 0,
    count: u8 = 0,
    input_buf: [INPUT_MAX]u8 = [_]u8{0} ** INPUT_MAX,
    input_len: u8 = 0,
    fps_enabled: bool = false,
    quit: bool = false,
    slide: Slide = .{},

    /// Process dev input: append text, handle backspace, execute commands on enter.
    pub fn update(self: *Console, dev: *input_mod.DevInput) void {
        for (0..dev.text_len) |i| {
            if (self.input_len < INPUT_MAX) {
                self.input_buf[self.input_len] = dev.text_buf[i];
                self.input_len += 1;
            }
        }

        if (dev.backspace and self.input_len > 0) {
            self.input_len -= 1;
        }

        if (dev.enter) {
            const cmd = self.input_buf[0..self.input_len];
            self.exec(cmd);
            self.input_len = 0;
        }
    }

    /// Execute a console command string.
    fn exec(self: *Console, cmd: []const u8) void {
        if (std.mem.eql(u8, cmd, "/quit")) {
            self.quit = true;
        } else if (std.mem.eql(u8, cmd, "/fps")) {
            self.fps_enabled = !self.fps_enabled;
            if (self.fps_enabled) {
                self.push("FPS display on");
            } else {
                self.push("FPS display off");
            }
        } else if (cmd.len > 0) {
            self.push(cmd);
        }
    }

    /// Append a message to the output ring buffer.
    fn push(self: *Console, msg: []const u8) void {
        const slot = (self.head + self.count) % MAX_LINES;
        const len: u8 = @intCast(@min(msg.len, MAX_LINE_LEN));
        @memcpy(self.lines[slot][0..len], msg[0..len]);
        self.line_lens[slot] = len;
        if (self.count < MAX_LINES) {
            self.count += 1;
        } else {
            self.head = (self.head + 1) % MAX_LINES;
        }
    }

    /// Advance slide animation one fixed tick.
    pub fn tick(self: *Console, active: bool) void {
        self.slide.tick(active);
    }

    /// Draw console panel at top of screen with slide animation.
    pub fn draw(self: *Console, gfx: *Graphics, bg: u8, border: u8, text_color: u8) void {
        if (!self.slide.visible()) return;

        const ph: i32 = (MAX_LINES + 1) * font.CHAR_H + 10;
        const y: i32 = self.slide.pos(ph) - ph;
        gfx.panel(0, y, Graphics.WIDTH, @intCast(ph), bg, border);

        for (0..self.count) |i| {
            const idx = (self.head + i) % MAX_LINES;
            const line = self.lines[idx][0..self.line_lens[idx]];
            gfx.text(line, 4, y + @as(i32, @intCast(i)) * @as(i32, font.CHAR_H) + 4, text_color);
        }

        const input_y: i32 = y + @as(i32, @intCast(MAX_LINES * font.CHAR_H + 6));
        gfx.text(">", 4, input_y, text_color);
        gfx.text(self.input_buf[0..self.input_len], 4 + font.CHAR_W, input_y, text_color);
    }
};

const std = @import("std");

test "menu cursor wraps down" {
    var menu = Menu(4).init(&.{ "A", "B", "C" });
    var input = input_mod.InputState{};
    input.pressed.down = true;
    _ = menu.update(input);
    try std.testing.expectEqual(@as(u8, 1), menu.cursor);
    _ = menu.update(input);
    try std.testing.expectEqual(@as(u8, 2), menu.cursor);
    // Wraps back to 0
    _ = menu.update(input);
    try std.testing.expectEqual(@as(u8, 0), menu.cursor);
}

test "menu cursor wraps up" {
    var menu = Menu(4).init(&.{ "A", "B", "C" });
    var input = input_mod.InputState{};
    input.pressed.up = true;
    // From 0, wraps to 2
    _ = menu.update(input);
    try std.testing.expectEqual(@as(u8, 2), menu.cursor);
}

test "menu A selects current item" {
    var menu = Menu(4).init(&.{ "Attack", "Magic", "Item" });
    var input = input_mod.InputState{};
    input.pressed.down = true;
    _ = menu.update(input);
    // Now on item 1
    input.pressed.down = false;
    input.pressed.a = true;
    const result = menu.update(input);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u8, 1), result.?.selected);
}

test "menu B cancels" {
    var menu = Menu(4).init(&.{ "Attack", "Magic" });
    var input = input_mod.InputState{};
    input.pressed.b = true;
    const result = menu.update(input);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(Menu(4).Result.cancelled, result.?);
}

test "console /fps toggles fps_enabled" {
    var con = Console{};
    var dev = input_mod.DevInput{};
    const cmd = "/fps";
    @memcpy(dev.text_buf[0..cmd.len], cmd);
    dev.text_len = cmd.len;
    con.update(&dev);
    dev = .{};
    dev.enter = true;
    con.update(&dev);
    try std.testing.expect(con.fps_enabled);
}

test "console backspace removes last char" {
    var con = Console{};
    var dev = input_mod.DevInput{};
    dev.text_buf[0] = 'a';
    dev.text_buf[1] = 'b';
    dev.text_len = 2;
    con.update(&dev);
    try std.testing.expectEqual(@as(u8, 2), con.input_len);
    dev = .{};
    dev.backspace = true;
    con.update(&dev);
    try std.testing.expectEqual(@as(u8, 1), con.input_len);
}

test "console ring buffer wraps" {
    var con = Console{};
    for (0..10) |i| {
        var dev = input_mod.DevInput{};
        dev.text_buf[0] = 'A' + @as(u8, @intCast(i));
        dev.text_len = 1;
        con.update(&dev);
        dev = .{};
        dev.enter = true;
        con.update(&dev);
    }
    try std.testing.expectEqual(@as(u8, 8), con.count);
}
