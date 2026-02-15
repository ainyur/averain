/// Parse GIMP .gpl palette files at comptime.
/// Supports Aseprite's RGBA extension (Channels: RGBA).
pub fn parse(comptime data: []const u8) [256]u32 {
    comptime {
        var pal = [_]u32{0x000000FF} ** 256;
        var idx: usize = 0;
        var pos: usize = 0;

        // Skip "GIMP Palette" header line
        pos = skip_line(data, pos);

        while (pos < data.len) {
            const line_start = pos;
            pos = skip_line(data, pos);
            const line = data[line_start .. pos - @as(usize, if (pos > line_start and data[pos - 1] == '\n') 1 else 0)];

            // Strip trailing \r
            const clean = if (line.len > 0 and line[line.len - 1] == '\r') line[0 .. line.len - 1] else line;

            // Skip blank lines, comments, metadata
            if (clean.len == 0) continue;
            if (clean[0] == '#') continue;
            if (starts_with(clean, "Name:")) continue;
            if (starts_with(clean, "Columns:")) continue;
            if (starts_with(clean, "Channels:")) continue;

            // Parse color line: R G B [A] [Name]
            const r = parse_component(clean) orelse continue;
            const g = parse_component(r.rest) orelse @compileError("expected G component");
            const b = parse_component(g.rest) orelse @compileError("expected B component");

            var a: u8 = 255;
            if (parse_component(b.rest)) |alpha| {
                // Check it's a number (not a name starting with a letter)
                a = alpha.value;
            }

            if (idx >= 256) @compileError("palette exceeds 256 colors");
            pal[idx] = @as(u32, r.value) << 24 | @as(u32, g.value) << 16 | @as(u32, b.value) << 8 | a;
            idx += 1;
        }

        return pal;
    }
}

const Component = struct { value: u8, rest: []const u8 };

fn parse_component(s: []const u8) ?Component {
    // Skip leading whitespace
    var i: usize = 0;
    while (i < s.len and s[i] == ' ') i += 1;
    if (i >= s.len or s[i] < '0' or s[i] > '9') return null;

    var val: u16 = 0;
    while (i < s.len and s[i] >= '0' and s[i] <= '9') {
        val = val * 10 + (s[i] - '0');
        i += 1;
    }
    if (val > 255) @compileError("color component > 255");
    return .{ .value = @intCast(val), .rest = s[i..] };
}

fn skip_line(data: []const u8, start: usize) usize {
    var i = start;
    while (i < data.len and data[i] != '\n') i += 1;
    if (i < data.len) i += 1; // skip \n
    return i;
}

fn starts_with(haystack: []const u8, needle: []const u8) bool {
    if (haystack.len < needle.len) return false;
    return eql(haystack[0..needle.len], needle);
}

fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (ca != cb) return false;
    }
    return true;
}

const std = @import("std");
const expectEqual = std.testing.expectEqual;

test "parse GPL with RGBA" {
    const pal = comptime parse(
        \\GIMP Palette
        \\Channels: RGBA
        \\#
        \\  0   0   0   0 Transparent
        \\254  91  89 255 Red
        \\  0 128 255 255 Blue
    );
    try expectEqual(@as(u32, 0x00000000), pal[0]);
    try expectEqual(@as(u32, 0xFE5B59FF), pal[1]);
    try expectEqual(@as(u32, 0x0080FFFF), pal[2]);
    try expectEqual(@as(u32, 0x000000FF), pal[3]); // default
}

test "parse GPL without alpha defaults to 255" {
    const pal = comptime parse(
        \\GIMP Palette
        \\#
        \\128  64  32
    );
    try expectEqual(@as(u32, 0x804020FF), pal[0]);
}
