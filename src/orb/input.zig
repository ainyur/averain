/// Developer input state for console interaction. Populated by the platform layer
/// from keyboard text events, separate from gamepad-style Input.
pub const DevInput = struct {
    backspace: bool = false,
    console_toggle: bool = false,
    editor_toggle: bool = false,
    enter: bool = false,
    mouse_click: bool = false,
    mouse_right: bool = false,
    mouse_wheel: i32 = 0,
    mouse_x: i32 = 0,
    mouse_y: i32 = 0,
    save: bool = false,
    text_buf: [32]u8 = .{0} ** 32,
    text_len: u8 = 0,
    tile_next: bool = false,
    tile_prev: bool = false,
};

/// Raw button state, one bool per button. Bit packed to u16.
pub const Input = packed struct {
    a: bool = false,
    b: bool = false,
    start: bool = false,
    select: bool = false,
    up: bool = false,
    down: bool = false,
    left: bool = false,
    right: bool = false,
    l: bool = false,
    r: bool = false,
    _pad: u6 = 0,
};

/// Per frame input with held, pressed (edge down), and released (edge up) states.
pub const InputState = struct {
    held: Input = .{},
    pressed: Input = .{},
    released: Input = .{},
};

/// Compute input edges from current and previous frame button state.
pub fn make(curr: Input, prev: Input) InputState {
    const c: u16 = @bitCast(curr);
    const p: u16 = @bitCast(prev);
    return .{
        .held = curr,
        .pressed = @bitCast(c & ~p),
        .released = @bitCast(~c & p),
    };
}

const std = @import("std");

test "pressed on first frame held" {
    var curr = Input{};
    curr.a = true;
    const state = make(curr, .{});
    try std.testing.expect(state.held.a);
    try std.testing.expect(state.pressed.a);
    try std.testing.expect(!state.released.a);
}

test "released when button goes up" {
    var prev = Input{};
    prev.a = true;
    const state = make(.{}, prev);
    try std.testing.expect(!state.held.a);
    try std.testing.expect(!state.pressed.a);
    try std.testing.expect(state.released.a);
}

test "held persists without edges" {
    var both = Input{};
    both.a = true;
    const state = make(both, both);
    try std.testing.expect(state.held.a);
    try std.testing.expect(!state.pressed.a);
    try std.testing.expect(!state.released.a);
}
