/// Dialogue node graph and typewriter text box.
const Graphics = @import("graphics.zig").Graphics;
const InputState = @import("input.zig").InputState;
const Slide = @import("ui.zig").Slide;
const text = @import("text.zig");

/// Sentinel meaning "no next node" or "no flag".
pub const NONE: u8 = 255;

/// A single dialogue node: text, link to next, optional choice branch.
pub const Node = struct {
    text: []const u8,
    next: u8 = NONE,
    choice: ?Choice = null,
    sets_flag: u8 = NONE,

    /// Binary dialogue choice: two labels mapping to two target nodes.
    pub const Choice = struct {
        labels: [2][]const u8,
        targets: [2]u8,
    };
};

/// Dialogue box events returned by update.
pub const Event = union(enum) {
    show_choice,
    set_flag: u8,
    closed,
};

/// Layout configuration for a dialogue box.
pub const Config = struct {
    width: u32 = 320,
    height: u32 = 36,
    screen_h: i32 = 180,
    chars_per_line: usize = 38,
    type_speed: u8 = 2,
};

/// Bottom-panel dialogue box with typewriter text rendering.
pub fn Box(comptime cfg: Config) type {
    return struct {
        const Self = @This();

        nodes: []const Node,
        node: u8 = NONE,
        char_idx: u8 = 0,
        tick: u8 = 0,
        slide: Slide = .{},

        /// Create a dialogue box bound to a set of nodes.
        pub fn init(nodes: []const Node) Self {
            return .{ .nodes = nodes };
        }

        /// Begin displaying a dialogue node.
        pub fn start(self: *Self, node_id: u8) void {
            self.node = node_id;
            self.char_idx = 0;
            self.tick = 0;
        }

        /// Move to next node if valid, otherwise close the dialogue.
        fn advance(self: *Self, next: u8) void {
            if (next != NONE) {
                self.start(next);
            } else {
                self.node = NONE;
            }
        }

        /// Whether the box is currently showing dialogue.
        pub fn active(self: *const Self) bool {
            return self.node != NONE;
        }

        /// Advance typewriter. Returns an event when something happens.
        pub fn update(self: *Self, input: InputState) ?Event {
            if (!self.active()) return null;

            const n = &self.nodes[self.node];
            const text_len: u8 = @intCast(n.text.len);

            if (input.pressed.a) {
                if (self.char_idx < text_len) {
                    self.char_idx = text_len;
                    return null;
                }
                if (n.choice != null) return .show_choice;
                if (n.sets_flag != NONE) {
                    const flag = n.sets_flag;
                    self.advance(n.next);
                    return .{ .set_flag = flag };
                }
                if (n.next != NONE) {
                    self.start(n.next);
                    return null;
                }
                self.node = NONE;
                return .closed;
            }

            self.tick +%= 1;
            if (self.tick % cfg.type_speed == 0 and self.char_idx < text_len) {
                self.char_idx += 1;
            }

            return null;
        }

        /// Advance slide animation one fixed tick.
        pub fn tick_slide(self: *Self) void {
            self.slide.tick(self.active());
        }

        /// Render the dialogue panel with slide animation.
        pub fn draw(self: *Self, gfx: *Graphics, bg: u8, border: u8, color: u8) void {
            if (!self.slide.visible()) return;

            const h: i32 = @intCast(cfg.height);
            const y: i32 = cfg.screen_h - self.slide.pos(h);
            gfx.panel(0, y, cfg.width, cfg.height, bg, border);

            if (!self.active()) return;

            const n = &self.nodes[self.node];
            const visible = n.text[0..self.char_idx];

            const text_y = y + 6;
            const line2_y = y + 16;
            const split = text.wrap(visible, cfg.chars_per_line);
            gfx.text(visible[0..split], 6, text_y, color);
            if (split < visible.len) {
                const line2_start = if (visible[split] == ' ') split + 1 else split;
                gfx.text(visible[line2_start..], 6, line2_y, color);
            }
        }
    };
}

const std = @import("std");

test "box start sets node and resets state" {
    const nodes: []const Node = &.{
        .{ .text = "Hello." },
    };
    var box = Box(.{}).init(nodes);
    box.start(0);
    try std.testing.expectEqual(@as(u8, 0), box.node);
    try std.testing.expectEqual(@as(u8, 0), box.char_idx);
    try std.testing.expect(box.active());
}

test "box A press completes text then closes" {
    const nodes: []const Node = &.{
        .{ .text = "Hi." },
    };
    var box = Box(.{ .type_speed = 1 }).init(nodes);
    box.start(0);

    var input = InputState{};
    input.pressed.a = true;

    // First A: completes text instantly
    const ev1 = box.update(input);
    try std.testing.expect(ev1 == null);
    try std.testing.expectEqual(@as(u8, 3), box.char_idx);

    // Second A: closes dialogue
    const ev2 = box.update(input);
    try std.testing.expectEqual(Event.closed, ev2.?);
    try std.testing.expect(!box.active());
}

test "box advances to next node" {
    const nodes: []const Node = &.{
        .{ .text = "One.", .next = 1 },
        .{ .text = "Two." },
    };
    var box = Box(.{ .type_speed = 1 }).init(nodes);
    box.start(0);

    var input = InputState{};
    input.pressed.a = true;

    // Complete text
    _ = box.update(input);
    // Advance to next node
    const ev = box.update(input);
    try std.testing.expect(ev == null);
    try std.testing.expectEqual(@as(u8, 1), box.node);
}

test "box choice node returns show_choice" {
    const nodes: []const Node = &.{
        .{ .text = "Pick.", .choice = .{
            .labels = .{ "Yes", "No" },
            .targets = .{ 1, 2 },
        } },
        .{ .text = "Good." },
        .{ .text = "Bad." },
    };
    var box = Box(.{ .type_speed = 1 }).init(nodes);
    box.start(0);

    var input = InputState{};
    input.pressed.a = true;

    // Complete text
    _ = box.update(input);
    // Should trigger choice
    const ev = box.update(input);
    try std.testing.expectEqual(Event.show_choice, ev.?);
}

test "box set_flag returns flag event" {
    const nodes: []const Node = &.{
        .{ .text = "Flag.", .sets_flag = 0 },
    };
    var box = Box(.{ .type_speed = 1 }).init(nodes);
    box.start(0);

    var input = InputState{};
    input.pressed.a = true;

    // Complete text
    _ = box.update(input);
    // Should return set_flag
    const ev = box.update(input);
    try std.testing.expectEqual(@as(u8, 0), ev.?.set_flag);
}
