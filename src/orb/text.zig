/// Text utilities. Word wrapping.

/// Find the byte offset to break text at for word wrap.
/// Returns text.len if it fits within width, otherwise breaks at last space.
pub fn wrap(txt: []const u8, width: usize) usize {
    if (txt.len <= width) return txt.len;
    var i: usize = width;
    while (i > 0) : (i -= 1) {
        if (txt[i] == ' ') return i;
    }
    return width;
}

const std = @import("std");

test "wrap fits within width" {
    try std.testing.expectEqual(@as(usize, 5), wrap("hello", 10));
}

test "wrap breaks at last space" {
    try std.testing.expectEqual(@as(usize, 5), wrap("hello world", 8));
}

test "wrap no space falls back to width" {
    try std.testing.expectEqual(@as(usize, 5), wrap("helloworld", 5));
}

test "wrap exact width returns full length" {
    try std.testing.expectEqual(@as(usize, 5), wrap("hello", 5));
}
