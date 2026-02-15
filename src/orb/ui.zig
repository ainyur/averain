/// Immediate mode UI widgets. Menu (Shining Force style dpad) and Console (dev overlay).
const font = @import("font.zig");
const input_mod = @import("input.zig");

/// Shining Force style dpad menu. Comptime generic max_items avoids allocation.
pub fn Menu(comptime max_items: u8) type {
    return struct {
        const Self = @This();

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
        pub fn draw(self: *const Self, gfx: anytype, x: i32, y: i32, bg: u8, border: u8, text_color: u8, arrow_color: u8) void {
            // Find widest label
            var max_len: u32 = 0;
            for (0..self.count) |i| {
                const len: u32 = @intCast(self.items[i].len);
                if (len > max_len) max_len = len;
            }
            // Panel: cursor(8px) + text + 4px padding each side
            const pw = 8 + max_len * font.char_w + 8;
            const ph: u32 = @as(u32, self.count) * font.char_h + 8;
            gfx.panel(x, y, pw, ph, bg, border);

            // Draw items
            for (0..self.count) |i| {
                const iy = y + 4 + @as(i32, @intCast(i)) * @as(i32, font.char_h);
                // Arrow cursor next to selected item
                if (i == self.cursor) {
                    if (font.glyph(0x10)) |g| {
                        for (0..font.char_h) |row| {
                            const bits = g[row];
                            for (0..font.char_w) |col| {
                                if (bits & (@as(u8, 0x80) >> @intCast(col)) != 0) {
                                    const px_x = x + 2 + @as(i32, @intCast(col));
                                    const px_y = iy + @as(i32, @intCast(row));
                                    gfx.set_pixel(@intCast(@max(px_x, 0)), @intCast(@max(px_y, 0)), arrow_color);
                                }
                            }
                        }
                    }
                }
                gfx.text(self.items[i], x + 10, iy, text_color);
            }
        }
    };
}

/// Dev console overlay. Ring buffer of output lines, text input, /fps command.
/// Uses palette indices 253 (bg), 254 (border), 255 (text).
pub const Console = struct {
    const max_lines = 8;
    const max_line_len = 28;
    const input_max = 28;

    lines: [max_lines][max_line_len]u8 = [_][max_line_len]u8{[_]u8{0} ** max_line_len} ** max_lines,
    line_lens: [max_lines]u8 = [_]u8{0} ** max_lines,
    head: u8 = 0,
    count: u8 = 0,
    input_buf: [input_max]u8 = [_]u8{0} ** input_max,
    input_len: u8 = 0,
    fps_enabled: bool = false,

    /// Process dev input: append text, handle backspace, execute commands on enter.
    pub fn update(self: *Console, dev: *input_mod.DevInput) void {
        for (0..dev.text_len) |i| {
            if (self.input_len < input_max) {
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

    fn exec(self: *Console, cmd: []const u8) void {
        if (std.mem.eql(u8, cmd, "/fps")) {
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

    fn push(self: *Console, msg: []const u8) void {
        const slot = (self.head + self.count) % max_lines;
        const len: u8 = @intCast(@min(msg.len, max_line_len));
        @memcpy(self.lines[slot][0..len], msg[0..len]);
        self.line_lens[slot] = len;
        if (self.count < max_lines) {
            self.count += 1;
        } else {
            self.head = (self.head + 1) % max_lines;
        }
    }

    /// Draw console panel at top of screen.
    pub fn draw(self: *const Console, gfx: anytype, bg: u8, border: u8, text_color: u8) void {
        const ph: u32 = (max_lines + 1) * font.char_h + 10;
        gfx.panel(0, 0, @TypeOf(gfx.*).width, ph, bg, border);

        for (0..self.count) |i| {
            const idx = (self.head + i) % max_lines;
            const line = self.lines[idx][0..self.line_lens[idx]];
            gfx.text(line, 4, @as(i32, @intCast(i)) * @as(i32, font.char_h) + 4, text_color);
        }

        const input_y: i32 = @intCast(max_lines * font.char_h + 6);
        gfx.text(">", 4, input_y, text_color);
        gfx.text(self.input_buf[0..self.input_len], 4 + font.char_w, input_y, text_color);
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
