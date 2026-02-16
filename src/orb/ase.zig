/// Comptime Aseprite .ase file parser.
/// Supports indexed (8bpp) sprites, single and multi-frame.
/// Multi-frame files are composited into a horizontal strip.
const std = @import("std");
const deflate = @import("deflate.zig");

// .ase binary layout sizes and offsets.

const file_header_size = 128;
const frame_header_size = 16;
const chunk_header_size = 6;

/// Cel chunk data before the w/h/pixel fields:
/// layer(2) + x(2) + y(2) + opacity(1) + type(2) + z_index(2) + reserved(5).
const cel_preamble_size = 16;

/// Full cel header before pixel data: preamble(16) + width(2) + height(2).
const cel_header_size = cel_preamble_size + 4;

// File header field offsets.
const fh_magic = 4;
const fh_frames = 6;
const fh_width = 8;
const fh_height = 10;
const fh_depth = 12;

// Frame header field offsets (relative to frame start).
const frh_magic = 4;
const frh_old_chunks = 6;
const frh_new_chunks = 12;

// Cel chunk field offsets (relative to chunk data start, after chunk header).
const cel_type_off = 7;
const cel_width_off = 16;
const cel_height_off = 18;

/// Parsed sprite data: dimensions and palette index pixels.
/// For multi-frame files, pixels form a horizontal strip of all frames.
pub const Sprite = struct {
    /// Width of a single frame in pixels.
    width: u16,
    /// Height of a single frame in pixels.
    height: u16,
    /// Total pixel width of the horizontal strip (width * frame count).
    strip_width: u16,
    /// Palette index pixels, row-major, strip_width * height bytes.
    pixels: []const u8,
};

/// Parse an embedded .ase file at comptime. Returns sprite pixel indices.
/// Multi-frame files are laid out as a horizontal strip.
pub fn parse(comptime data: []const u8) Sprite {
    comptime {
        if (data.len < file_header_size) @compileError("ase file too short");
        if (read16(data, fh_magic) != 0xA5E0) @compileError("bad ase magic");

        const num_frames = read16(data, fh_frames);
        const frame_w = read16(data, fh_width);
        const frame_h = read16(data, fh_height);

        if (read16(data, fh_depth) != 8)
            @compileError("only indexed (8bpp) sprites supported");
        if (num_frames == 0) @compileError("ase file has 0 frames");

        const strip_w: usize = @as(usize, frame_w) * num_frames;
        var strip: [strip_w * frame_h]u8 = @splat(0);

        var pos: usize = file_header_size;
        for (0..num_frames) |frame_idx| {
            if (pos + frame_header_size > data.len)
                @compileError("missing frame header");
            if (read16(data, pos + frh_magic) != 0xF1FA)
                @compileError("bad frame magic");

            const frame_size = read32(data, pos);
            const old_chunks = read16(data, pos + frh_old_chunks);
            const new_chunks = read32(data, pos + frh_new_chunks);
            const num_chunks = if (new_chunks != 0) new_chunks else old_chunks;

            var chunk_pos: usize = pos + frame_header_size;
            for (0..num_chunks) |_| {
                const chunk_size = read32(data, chunk_pos);
                const chunk_type = read16(data, chunk_pos + 4);

                if (chunk_type == 0x2005) {
                    const chunk_data = data[chunk_pos + chunk_header_size .. chunk_pos + chunk_size];
                    const frame_pixels = parse_cel(chunk_data, frame_w, frame_h);

                    const x_off = frame_idx * frame_w;
                    for (0..frame_h) |y| {
                        const src_row = y * frame_w;
                        const dst_row = y * strip_w + x_off;
                        for (0..frame_w) |x| {
                            strip[dst_row + x] = frame_pixels[src_row + x];
                        }
                    }
                    break;
                }

                chunk_pos += chunk_size;
            }

            pos += frame_size;
        }

        const pixels = strip;
        return .{
            .width = frame_w,
            .height = frame_h,
            .strip_width = @intCast(strip_w),
            .pixels = &pixels,
        };
    }
}

fn parse_cel(
    comptime data: []const u8,
    comptime expected_w: u16,
    comptime expected_h: u16,
) []const u8 {
    comptime {
        const cel_type = read16(data, cel_type_off);
        const cel_w = read16(data, cel_width_off);
        const cel_h = read16(data, cel_height_off);
        const pixel_count = @as(usize, cel_w) * cel_h;

        if (cel_w != expected_w or cel_h != expected_h)
            @compileError("cel dimensions do not match frame dimensions");

        if (cel_type == 0) {
            return data[cel_header_size .. cel_header_size + pixel_count];
        } else if (cel_type == 2) {
            const compressed = data[cel_header_size..];
            const pixels = deflate.zlib(compressed, pixel_count);
            return &pixels;
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

fn build_file_header(
    comptime num_frames: u16,
    comptime w: u16,
    comptime h: u16,
) [file_header_size]u8 {
    return [_]u8{0} ** 4
        ++ le16(0xA5E0)
        ++ le16(num_frames)
        ++ le16(w)
        ++ le16(h)
        ++ le16(8) // indexed color depth
        ++ [_]u8{0} ** (file_header_size - 14);
}

/// Build a minimal .ase frame block (frame header + one raw cel chunk).
fn build_frame(
    comptime w: u16,
    comptime h: u16,
    comptime pixels: *const [@as(usize, w) * h]u8,
) [frame_header_size + chunk_header_size + cel_header_size + @as(usize, w) * h]u8 {
    const cel_data = [_]u8{0} ** cel_preamble_size
        ++ le16(w)
        ++ le16(h)
        ++ pixels.*;
    const cel_chunk = le32(chunk_header_size + cel_data.len)
        ++ le16(0x2005)
        ++ cel_data;

    const frame = le32(frame_header_size + cel_chunk.len)
        ++ le16(0xF1FA) // magic
        ++ le16(1) // old chunks
        ++ le16(0) // duration
        ++ [_]u8{0} ** 2 // reserved
        ++ le32(0); // new chunks

    return frame ++ cel_chunk;
}

test "parse minimal ase with raw cel" {
    const sprite = comptime blk: {
        const pixels = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7 };
        const frame = build_frame(4, 2, &pixels);
        const header = build_file_header(1, 4, 2);
        break :blk parse(&(header ++ frame));
    };
    try std.testing.expectEqual(@as(u16, 4), sprite.width);
    try std.testing.expectEqual(@as(u16, 2), sprite.height);
    try std.testing.expectEqual(@as(u16, 4), sprite.strip_width);
    try std.testing.expectEqualSlices(u8, &.{ 0, 1, 2, 3, 4, 5, 6, 7 }, sprite.pixels);
}

test "parse multi-frame ase into horizontal strip" {
    const sprite = comptime blk: {
        const frame0 = build_frame(2, 2, &[_]u8{ 1, 2, 3, 4 });
        const frame1 = build_frame(2, 2, &[_]u8{ 5, 6, 7, 8 });
        const header = build_file_header(2, 2, 2);
        break :blk parse(&(header ++ frame0 ++ frame1));
    };
    try std.testing.expectEqual(@as(u16, 2), sprite.width);
    try std.testing.expectEqual(@as(u16, 2), sprite.height);
    try std.testing.expectEqual(@as(u16, 4), sprite.strip_width);
    // Row 0: frame0-row0 [1,2] then frame1-row0 [5,6]
    // Row 1: frame0-row1 [3,4] then frame1-row1 [7,8]
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 5, 6, 3, 4, 7, 8 }, sprite.pixels);
}
