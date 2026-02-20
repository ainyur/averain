/// Comptime Aseprite .ase file parser.
/// Supports indexed (8bpp) sprites, single and multi-frame.
/// Multi-frame files are composited into a horizontal strip.
const std = @import("std");
const deflate = @import("deflate.zig");

// .ase binary layout sizes and offsets.

const FILE_HEADER_SIZE = 128;
const FRAME_HEADER_SIZE = 16;
const CHUNK_HEADER_SIZE = 6;

/// Cel chunk data before the w/h/pixel fields:
/// layer(2) + x(2) + y(2) + opacity(1) + type(2) + z_index(2) + reserved(5).
const CEL_PREAMBLE_SIZE = 16;

/// Full cel header before pixel data: preamble(16) + width(2) + height(2).
const CEL_HEADER_SIZE = CEL_PREAMBLE_SIZE + 4;

// File header field offsets.
const FH_MAGIC = 4;
const FH_FRAMES = 6;
const FH_WIDTH = 8;
const FH_HEIGHT = 10;
const FH_DEPTH = 12;

// Frame header field offsets (relative to frame start).
const FRH_MAGIC = 4;
const FRH_OLD_CHUNKS = 6;
const FRH_NEW_CHUNKS = 12;

// Layer chunk field offsets (relative to chunk data start, after chunk header).
const LAYER_FLAGS_OFF = 0;

// Cel chunk field offsets (relative to chunk data start, after chunk header).
const CEL_LAYER_OFF = 0;
const CEL_X_OFF = 2;
const CEL_Y_OFF = 4;
const CEL_TYPE_OFF = 7;
const CEL_WIDTH_OFF = 16;
const CEL_HEIGHT_OFF = 18;

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
/// Hidden layers are skipped; visible layers are composited bottom-to-top.
pub fn parse(comptime data: []const u8) Sprite {
    comptime {
        @setEvalBranchQuota(data.len * 10);
        if (data.len < FILE_HEADER_SIZE) @compileError("ase file too short");
        if (read16(data, FH_MAGIC) != 0xA5E0) @compileError("bad ase magic");

        const num_frames = read16(data, FH_FRAMES);
        const frame_w = read16(data, FH_WIDTH);
        const frame_h = read16(data, FH_HEIGHT);

        if (read16(data, FH_DEPTH) != 8)
            @compileError("only indexed (8bpp) sprites supported");
        if (num_frames == 0) @compileError("ase file has 0 frames");

        // Scan frame 0 for layer visibility.
        const visible = scan_layers(data);

        const strip_w: usize = @as(usize, frame_w) * num_frames;
        var strip: [strip_w * frame_h]u8 = @splat(0);

        var pos: usize = FILE_HEADER_SIZE;
        for (0..num_frames) |frame_idx| {
            if (pos + FRAME_HEADER_SIZE > data.len)
                @compileError("missing frame header");
            if (read16(data, pos + FRH_MAGIC) != 0xF1FA)
                @compileError("bad frame magic");

            const frame_size = read32(data, pos);
            const old_chunks = read16(data, pos + FRH_OLD_CHUNKS);
            const new_chunks = read32(data, pos + FRH_NEW_CHUNKS);
            const num_chunks = if (new_chunks != 0) new_chunks else old_chunks;

            var chunk_pos: usize = pos + FRAME_HEADER_SIZE;
            for (0..num_chunks) |_| {
                const chunk_size = read32(data, chunk_pos);
                const chunk_type = read16(data, chunk_pos + 4);

                if (chunk_type == 0x2005) {
                    const chunk_data = data[chunk_pos + CHUNK_HEADER_SIZE .. chunk_pos + chunk_size];
                    const layer = read16(chunk_data, CEL_LAYER_OFF);

                    if (visible.len == 0 or (layer < visible.len and visible[layer])) {
                        const cel = parse_cel(chunk_data);
                        const x_off = frame_idx * frame_w;
                        blit_cel(&strip, strip_w, frame_w, frame_h, x_off, &cel);
                    }
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

/// Scan frame 0 chunks for layer visibility flags.
fn scan_layers(comptime data: []const u8) []const bool {
    comptime {
        // Count layers.
        var count: usize = 0;
        var pos: usize = FILE_HEADER_SIZE + FRAME_HEADER_SIZE;
        const old_chunks = read16(data, FILE_HEADER_SIZE + FRH_OLD_CHUNKS);
        const new_chunks = read32(data, FILE_HEADER_SIZE + FRH_NEW_CHUNKS);
        const num_chunks = if (new_chunks != 0) new_chunks else old_chunks;

        for (0..num_chunks) |_| {
            const chunk_size = read32(data, pos);
            if (read16(data, pos + 4) == 0x2004) count += 1;
            pos += chunk_size;
        }

        // Collect visibility (bit 0 of flags).
        var visible: [count]bool = undefined;
        var li: usize = 0;
        pos = FILE_HEADER_SIZE + FRAME_HEADER_SIZE;
        for (0..num_chunks) |_| {
            const chunk_size = read32(data, pos);
            if (read16(data, pos + 4) == 0x2004) {
                const flags = read16(data, pos + CHUNK_HEADER_SIZE + LAYER_FLAGS_OFF);
                visible[li] = (flags & 1) != 0;
                li += 1;
            }
            pos += chunk_size;
        }

        const result = visible;
        return &result;
    }
}

/// Composite a cel onto the strip at the given x offset.
fn blit_cel(
    strip: anytype,
    strip_w: usize,
    frame_w: u16,
    frame_h: u16,
    x_off: usize,
    cel: *const Cel,
) void {
    for (0..cel.h) |cy| {
        const sy = @as(i32, cel.oy) + @as(i32, @intCast(cy));
        if (sy < 0 or sy >= frame_h) continue;
        const dy: usize = @intCast(sy);
        for (0..cel.w) |cx| {
            const sx = @as(i32, cel.ox) + @as(i32, @intCast(cx));
            if (sx < 0 or sx >= frame_w) continue;
            const dx: usize = @intCast(sx);
            const pixel = cel.pixels[cy * cel.w + cx];
            if (pixel != 0) {
                strip[(dy * strip_w) + x_off + dx] = pixel;
            }
        }
    }
}

/// Decoded cel: position offset and pixel data within a single frame.
const Cel = struct {
    ox: i16,
    oy: i16,
    w: usize,
    h: usize,
    pixels: []const u8,
};

/// Decode a cel chunk into offset, dimensions, and pixel data.
fn parse_cel(comptime data: []const u8) Cel {
    comptime {
        const cel_type = read16(data, CEL_TYPE_OFF);
        const cel_w = read16(data, CEL_WIDTH_OFF);
        const cel_h = read16(data, CEL_HEIGHT_OFF);
        const pixel_count = @as(usize, cel_w) * cel_h;

        const pixels: []const u8 = switch (cel_type) {
            0 => data[CEL_HEADER_SIZE .. CEL_HEADER_SIZE + pixel_count],
            2 => blk: {
                const decompressed = deflate.zlib(data[CEL_HEADER_SIZE..], pixel_count);
                break :blk &decompressed;
            },
            else => @compileError("unsupported cel type (only raw and compressed supported)"),
        };

        return .{
            .ox = @bitCast(read16(data, CEL_X_OFF)),
            .oy = @bitCast(read16(data, CEL_Y_OFF)),
            .w = cel_w,
            .h = cel_h,
            .pixels = pixels,
        };
    }
}

/// Read a little-endian u16 from data at offset.
fn read16(data: []const u8, offset: usize) u16 {
    return @as(u16, data[offset]) | @as(u16, data[offset + 1]) << 8;
}

/// Read a little-endian u32 from data at offset.
fn read32(data: []const u8, offset: usize) u32 {
    return @as(u32, data[offset]) |
        @as(u32, data[offset + 1]) << 8 |
        @as(u32, data[offset + 2]) << 16 |
        @as(u32, data[offset + 3]) << 24;
}

/// Encode u16 as little-endian bytes. Used in test scaffolding.
fn le16(val: u16) [2]u8 {
    return .{ @intCast(val & 0xFF), @intCast(val >> 8) };
}

/// Encode u32 as little-endian bytes. Used in test scaffolding.
fn le32(val: u32) [4]u8 {
    return .{
        @intCast(val & 0xFF),
        @intCast((val >> 8) & 0xFF),
        @intCast((val >> 16) & 0xFF),
        @intCast(val >> 24),
    };
}

/// Build a minimal .ase file header for testing.
fn build_file_header(
    comptime num_frames: u16,
    comptime w: u16,
    comptime h: u16,
) [FILE_HEADER_SIZE]u8 {
    return [_]u8{0} ** 4
        ++ le16(0xA5E0)
        ++ le16(num_frames)
        ++ le16(w)
        ++ le16(h)
        ++ le16(8) // indexed color depth
        ++ [_]u8{0} ** (FILE_HEADER_SIZE - 14);
}

/// Build a minimal .ase frame block (frame header + one raw cel chunk).
fn build_frame(
    comptime w: u16,
    comptime h: u16,
    comptime pixels: *const [@as(usize, w) * h]u8,
) [FRAME_HEADER_SIZE + CHUNK_HEADER_SIZE + CEL_HEADER_SIZE + @as(usize, w) * h]u8 {
    const cel_data = [_]u8{0} ** CEL_PREAMBLE_SIZE
        ++ le16(w)
        ++ le16(h)
        ++ pixels.*;
    const cel_chunk = le32(CHUNK_HEADER_SIZE + cel_data.len)
        ++ le16(0x2005)
        ++ cel_data;

    const frame = le32(FRAME_HEADER_SIZE + cel_chunk.len)
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
