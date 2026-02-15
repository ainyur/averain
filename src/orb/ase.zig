/// Comptime Aseprite .ase file parser.
/// Supports indexed (8bpp) sprites, single frame.
const deflate = @import("deflate.zig");

/// Parsed sprite data: dimensions and palette index pixels.
pub const Sprite = struct {
    width: u16,
    height: u16,
    pixels: []const u8,
};

/// Parse an embedded .ase file at comptime. Returns sprite pixel indices.
pub fn parse(comptime data: []const u8) Sprite {
    comptime {
        if (data.len < 128) @compileError("ase file too short");
        if (read16(data, 4) != 0xA5E0) @compileError("bad ase magic");

        const depth = read16(data, 12);
        if (depth != 8) @compileError("only indexed (8bpp) sprites supported");

        // Frame 0 header at offset 128
        const frame_start = 128;
        if (data.len < frame_start + 16) @compileError("missing frame header");
        if (read16(data, frame_start + 4) != 0xF1FA) @compileError("bad frame magic");

        const old_chunks = read16(data, frame_start + 6);
        const new_chunks = read32(data, frame_start + 12);
        const num_chunks = if (new_chunks != 0) new_chunks else old_chunks;

        // Walk chunks, find cel (0x2005)
        var pos: usize = frame_start + 16;
        for (0..num_chunks) |_| {
            const chunk_size = read32(data, pos);
            const chunk_type = read16(data, pos + 4);
            const chunk_data = data[pos + 6 .. pos + chunk_size];

            if (chunk_type == 0x2005) {
                return parse_cel(chunk_data);
            }

            pos += chunk_size;
        }

        @compileError("no cel chunk found in frame 0");
    }
}

fn parse_cel(comptime data: []const u8) Sprite {
    comptime {
        const cel_type = read16(data, 7);
        const cel_w = read16(data, 16);
        const cel_h = read16(data, 18);
        const pixel_count = @as(usize, cel_w) * cel_h;

        if (cel_type == 0) {
            return .{
                .width = cel_w,
                .height = cel_h,
                .pixels = data[20 .. 20 + pixel_count],
            };
        } else if (cel_type == 2) {
            const compressed = data[20..];
            const pixels = deflate.zlib(compressed, pixel_count);
            return .{
                .width = cel_w,
                .height = cel_h,
                .pixels = &pixels,
            };
        } else {
            @compileError("unsupported cel type (only raw and compressed supported)");
        }
    }
}

fn read16(data: []const u8, offset: usize) u16 {
    return @as(u16, data[offset]) | @as(u16, data[offset + 1]) << 8;
}

fn read32(data: []const u8, offset: usize) u32 {
    return @as(u32, data[offset]) |
        @as(u32, data[offset + 1]) << 8 |
        @as(u32, data[offset + 2]) << 16 |
        @as(u32, data[offset + 3]) << 24;
}

const std = @import("std");

fn le16(val: u16) [2]u8 {
    return .{ @intCast(val & 0xFF), @intCast(val >> 8) };
}

fn le32(val: u32) [4]u8 {
    return .{
        @intCast(val & 0xFF),
        @intCast((val >> 8) & 0xFF),
        @intCast((val >> 16) & 0xFF),
        @intCast(val >> 24),
    };
}

test "parse minimal ase with raw cel" {
    const sprite = comptime blk: {
        const pixels = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7 };

        const cel_data = [_]u8{0} ** 2 // layer index
        ++ le16(0) // x
        ++ le16(0) // y
        ++ [_]u8{255} // opacity
        ++ le16(0) // cel type = raw
        ++ le16(0) // z index
        ++ [_]u8{0} ** 5 // reserved
        ++ le16(4) // width
        ++ le16(2) // height
        ++ pixels;
        const cel_chunk = le32(6 + cel_data.len) ++ le16(0x2005) ++ cel_data;

        const frame_data = le32(16 + cel_chunk.len)
        ++ le16(0xF1FA)
        ++ le16(1) // 1 chunk
        ++ le16(0) // duration
        ++ [_]u8{0} ** 2 // reserved
        ++ le32(0);

        const header = [_]u8{0} ** 4
            ++ le16(0xA5E0)
            ++ le16(1) // 1 frame
            ++ le16(4) // width
            ++ le16(2) // height
            ++ le16(8) // indexed
            ++ [_]u8{0} ** (128 - 14);

        const data = header ++ frame_data ++ cel_chunk;
        break :blk parse(&data);
    };
    try std.testing.expectEqual(@as(u16, 4), sprite.width);
    try std.testing.expectEqual(@as(u16, 2), sprite.height);
    try std.testing.expectEqualSlices(u8, &.{ 0, 1, 2, 3, 4, 5, 6, 7 }, sprite.pixels);
}
