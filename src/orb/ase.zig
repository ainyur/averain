/// Aseprite .ase file parser.
/// Supports indexed (8bpp) sprites, single and multi-frame.
/// Multi-frame files are composited into a horizontal strip.
/// parse() runs at comptime (raw cels only); load() runs at runtime (raw + compressed).
const std = @import("std");

const Allocator = std.mem.Allocator;
const Decompress = std.compress.flate.Decompress;
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

    /// Offset to center this sprite on a tile of the given size.
    pub fn center(self: Sprite, tile_size: u32) [2]i32 {
        const half_tile: i32 = @intCast(tile_size >> 1);
        return .{
            half_tile - @as(i32, self.width >> 1),
            half_tile - @as(i32, self.height >> 1),
        };
    }
};

/// A named rectangular region within a tilesheet image.
pub const Slice = struct {
    /// Category name from the ASE slice chunk.
    name: []const u8,
    /// Pixel origin and dimensions within the sheet image.
    x: u16,
    y: u16,
    w: u16,
    h: u16,
    /// User data text from the following 0x2020 chunk. Empty if absent.
    user_data: []const u8,
};

/// Tilesheet parsed from a single-frame .ase with slice metadata.
/// Tiles are rasterized into a horizontal strip for blit_frame compatibility.
pub const TileSheet = struct {
    /// Horizontal strip: tile_count tiles * tile_size wide, tile_size tall.
    pixels: []const u8,
    /// Strip width in pixels (tile_count * tile_size).
    strip_width: u16,
    /// Tile edge size in pixels.
    tile_size: u16,
    /// Total tiles across all slices. Tile 0 = empty (not in strip).
    tile_count: u16,
    /// Category slices from ASE slice chunks, in file order.
    slices: []const Slice,

    /// Build a Sprite suitable for blit_frame. Tile ID = frame index.
    pub fn sprite(self: TileSheet) Sprite {
        return .{
            .width = self.tile_size,
            .height = self.tile_size,
            .strip_width = self.strip_width,
            .pixels = self.pixels,
        };
    }
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

/// Parse a tilesheet .ase file at comptime. Extracts pixel data from visible
/// layers, reads slice chunks for tile categories, and rasterizes all tiles
/// from 2D slice regions into a horizontal strip.
pub fn parse_sheet(comptime data: []const u8, comptime tile_size: u16) TileSheet {
    comptime {
        @setEvalBranchQuota(data.len * 20);
        if (data.len < FILE_HEADER_SIZE) @compileError("ase file too short");
        if (read16(data, FH_MAGIC) != 0xA5E0) @compileError("bad ase magic");
        if (read16(data, FH_DEPTH) != 8)
            @compileError("only indexed (8bpp) sprites supported");

        const img_w = read16(data, FH_WIDTH);

        // Parse the image pixels using the existing parse function.
        const img = parse(data);

        // Scan all frames for slice chunks.
        const slices = scan_slices(data);

        // Count total tiles across all slices.
        var total_tiles: u16 = 0;
        for (slices) |s| {
            total_tiles += (s.w / tile_size) * (s.h / tile_size);
        }

        // Rasterize tiles from 2D slice regions into a horizontal strip.
        // Strip layout: tile 1 at x=0, tile 2 at x=tile_size, etc.
        // Tile 0 is empty (not stored). Strip holds tiles 1..total_tiles.
        const strip_w: usize = @as(usize, total_tiles) * tile_size;
        var strip: [strip_w * tile_size]u8 = @splat(0);
        var tile_idx: usize = 0;

        for (slices) |s| {
            const cols = s.w / tile_size;
            const rows = s.h / tile_size;
            for (0..rows) |tr| {
                for (0..cols) |tc| {
                    const src_x = @as(usize, s.x) + tc * tile_size;
                    const src_y = @as(usize, s.y) + tr * tile_size;
                    const dst_x = tile_idx * tile_size;

                    for (0..tile_size) |py| {
                        const src_off = (src_y + py) * img_w + src_x;
                        const dst_off = py * strip_w + dst_x;
                        for (0..tile_size) |px| {
                            strip[dst_off + px] = img.pixels[src_off + px];
                        }
                    }
                    tile_idx += 1;
                }
            }
        }

        const result_pixels = strip;
        const result_slices = slices;
        return .{
            .pixels = &result_pixels,
            .strip_width = @intCast(strip_w),
            .tile_size = tile_size,
            .tile_count = total_tiles,
            .slices = result_slices,
        };
    }
}

/// Load an .ase file at runtime. Heap-allocates the pixel strip.
/// Same logic as comptime parse() but returns errors instead of @compileError.
pub fn load(alloc: Allocator, data: []const u8) !Sprite {
    if (data.len < FILE_HEADER_SIZE) return error.InvalidHeader;
    if (read16(data, FH_MAGIC) != 0xA5E0) return error.BadMagic;

    const num_frames = read16(data, FH_FRAMES);
    const frame_w = read16(data, FH_WIDTH);
    const frame_h = read16(data, FH_HEIGHT);

    if (read16(data, FH_DEPTH) != 8) return error.UnsupportedDepth;
    if (num_frames == 0) return error.NoFrames;

    const visible = load_layers(data);

    const strip_w: usize = @as(usize, frame_w) * num_frames;
    const strip = try alloc.alloc(u8, strip_w * frame_h);
    errdefer alloc.free(strip);
    @memset(strip, 0);

    var pos: usize = FILE_HEADER_SIZE;
    for (0..num_frames) |frame_idx| {
        if (pos + FRAME_HEADER_SIZE > data.len) return error.InvalidFrame;
        if (read16(data, pos + FRH_MAGIC) != 0xF1FA) return error.BadFrameMagic;

        const frame_size = read32(data, pos);
        const old_chunks = read16(data, pos + FRH_OLD_CHUNKS);
        const new_chunks = read32(data, pos + FRH_NEW_CHUNKS);
        const num_chunks: usize = if (new_chunks != 0) new_chunks else old_chunks;

        var chunk_pos: usize = pos + FRAME_HEADER_SIZE;
        for (0..num_chunks) |_| {
            if (chunk_pos + CHUNK_HEADER_SIZE > data.len) break;
            const chunk_size = read32(data, chunk_pos);
            if (chunk_size == 0) break;
            const chunk_type = read16(data, chunk_pos + 4);

            if (chunk_type == 0x2005 and chunk_pos + chunk_size <= data.len) {
                const chunk_data = data[chunk_pos + CHUNK_HEADER_SIZE .. chunk_pos + chunk_size];
                const layer = read16(chunk_data, CEL_LAYER_OFF);

                if (layer >= 64 or visible[layer]) {
                    var tmp: ?[]u8 = null;
                    defer if (tmp) |t| alloc.free(t);
                    if (load_cel(alloc, chunk_data, &tmp)) |cel| {
                        const x_off = frame_idx * frame_w;
                        blit_cel(strip, strip_w, frame_w, frame_h, x_off, &cel);
                    } else |_| {}
                }
            }

            chunk_pos += chunk_size;
        }

        pos += frame_size;
    }

    return .{
        .width = frame_w,
        .height = frame_h,
        .strip_width = @intCast(strip_w),
        .pixels = strip,
    };
}

/// Decode a cel chunk at runtime. Supports raw (type 0) and compressed (type 2).
/// For compressed cels, decompressed pixels are written to tmp.* and must be
/// freed by the caller.
fn load_cel(alloc: Allocator, data: []const u8, tmp: *?[]u8) !Cel {
    if (data.len < CEL_HEADER_SIZE) return error.InvalidCel;
    const cel_type = read16(data, CEL_TYPE_OFF);
    const cel_w = read16(data, CEL_WIDTH_OFF);
    const cel_h = read16(data, CEL_HEIGHT_OFF);
    const pixel_count = @as(usize, cel_w) * cel_h;

    const pixels: []const u8 = switch (cel_type) {
        0 => blk: {
            if (data.len < CEL_HEADER_SIZE + pixel_count) return error.InvalidCel;
            break :blk data[CEL_HEADER_SIZE .. CEL_HEADER_SIZE + pixel_count];
        },
        2 => blk: {
            const buf = try alloc.alloc(u8, pixel_count);
            errdefer alloc.free(buf);
            var input = std.Io.Reader.fixed(data[CEL_HEADER_SIZE..]);
            var window: [std.compress.flate.max_window_len]u8 = undefined;
            var decomp = Decompress.init(&input, .zlib, &window);
            decomp.reader.readSliceAll(buf) catch return error.DecompressFailed;
            tmp.* = buf;
            break :blk buf;
        },
        else => return error.UnsupportedCelType,
    };

    return .{
        .ox = @bitCast(read16(data, CEL_X_OFF)),
        .oy = @bitCast(read16(data, CEL_Y_OFF)),
        .w = cel_w,
        .h = cel_h,
        .pixels = pixels,
    };
}

/// Scan frame 0 for layer visibility at runtime. Fixed 64-slot buffer.
fn load_layers(data: []const u8) [64]bool {
    var visible: [64]bool = @splat(true);
    if (data.len < FILE_HEADER_SIZE + FRAME_HEADER_SIZE) return visible;

    const old_chunks = read16(data, FILE_HEADER_SIZE + FRH_OLD_CHUNKS);
    const new_chunks = read32(data, FILE_HEADER_SIZE + FRH_NEW_CHUNKS);
    const num_chunks: usize = if (new_chunks != 0) new_chunks else old_chunks;

    var pos: usize = FILE_HEADER_SIZE + FRAME_HEADER_SIZE;
    var li: usize = 0;
    for (0..num_chunks) |_| {
        if (pos + CHUNK_HEADER_SIZE > data.len) break;
        const chunk_size = read32(data, pos);
        if (chunk_size == 0) break;
        if (read16(data, pos + 4) == 0x2004 and li < 64) {
            if (pos + CHUNK_HEADER_SIZE + 2 <= data.len) {
                const flags = read16(data, pos + CHUNK_HEADER_SIZE + LAYER_FLAGS_OFF);
                visible[li] = (flags & 1) != 0;
            }
            li += 1;
        }
        pos += chunk_size;
    }
    return visible;
}

/// Scan all frames for slice chunks (0x2022) and their user data (0x2020).
fn scan_slices(comptime data: []const u8) []const Slice {
    comptime {
        const num_frames = read16(data, FH_FRAMES);

        // First pass: count slices across all frames.
        var count: usize = 0;
        var pos: usize = FILE_HEADER_SIZE;
        for (0..num_frames) |_| {
            const frame_size = read32(data, pos);
            const old_chunks = read16(data, pos + FRH_OLD_CHUNKS);
            const new_chunks = read32(data, pos + FRH_NEW_CHUNKS);
            const num_chunks = if (new_chunks != 0) new_chunks else old_chunks;
            var cp: usize = pos + FRAME_HEADER_SIZE;
            for (0..num_chunks) |_| {
                const cs = read32(data, cp);
                if (read16(data, cp + 4) == 0x2022) count += 1;
                cp += cs;
            }
            pos += frame_size;
        }

        if (count == 0) @compileError("tilesheet has no slice chunks");

        // Second pass: collect slices.
        var slices: [count]Slice = undefined;
        var si: usize = 0;
        pos = FILE_HEADER_SIZE;
        var prev_was_slice = false;

        for (0..num_frames) |_| {
            const frame_size = read32(data, pos);
            const old_chunks = read16(data, pos + FRH_OLD_CHUNKS);
            const new_chunks = read32(data, pos + FRH_NEW_CHUNKS);
            const num_chunks = if (new_chunks != 0) new_chunks else old_chunks;
            var cp: usize = pos + FRAME_HEADER_SIZE;

            for (0..num_chunks) |_| {
                const cs = read32(data, cp);
                const ct = read16(data, cp + 4);
                const cd = data[cp + CHUNK_HEADER_SIZE .. cp + cs];

                if (ct == 0x2022) {
                    // Slice chunk: u32 num_keys, u32 flags, u32 reserved,
                    // STRING name (u16 len + bytes),
                    // per key: u32 frame, i32 x, i32 y, u32 w, u32 h.
                    const name_len = read16(cd, 12);
                    const name = cd[14 .. 14 + name_len];
                    const key_off = 14 + name_len;

                    slices[si] = .{
                        .name = name,
                        .x = @intCast(read32(cd, key_off + 4)),
                        .y = @intCast(read32(cd, key_off + 8)),
                        .w = @intCast(read32(cd, key_off + 12)),
                        .h = @intCast(read32(cd, key_off + 16)),
                        .user_data = &.{},
                    };
                    si += 1;
                    prev_was_slice = true;
                } else if (ct == 0x2020 and prev_was_slice and si > 0) {
                    // User data chunk following a slice.
                    const flags = read32(cd, 0);
                    if (flags & 1 != 0) {
                        const text_len = read16(cd, 4);
                        slices[si - 1].user_data = cd[6 .. 6 + text_len];
                    }
                    prev_was_slice = false;
                } else {
                    prev_was_slice = false;
                }

                cp += cs;
            }
            pos += frame_size;
        }

        const result = slices;
        return &result;
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

        if (cel_type != 0) @compileError("only raw cels supported (enable 'Save Raw Cels' in Aseprite preferences)");
        const pixels: []const u8 = data[CEL_HEADER_SIZE .. CEL_HEADER_SIZE + pixel_count];

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

/// Build a slice chunk (0x2022) for testing.
fn build_slice_chunk(
    comptime name: []const u8,
    comptime x: u32,
    comptime y: u32,
    comptime w: u32,
    comptime h: u32,
) [CHUNK_HEADER_SIZE + 12 + 2 + name.len + 20]u8 {
    const cd_size = 12 + 2 + name.len + 20;
    var name_bytes: [name.len]u8 = undefined;
    @memcpy(&name_bytes, name);
    const cd = le32(1) // num_keys
    ++ le32(0) // flags
    ++ le32(0) // reserved
    ++ le16(@intCast(name.len))
    ++ name_bytes
    ++ le32(0) // frame 0
    ++ le32(x)
    ++ le32(y)
    ++ le32(w)
    ++ le32(h);
    return le32(CHUNK_HEADER_SIZE + cd_size) ++ le16(0x2022) ++ cd;
}

test "parse_sheet extracts slices and rasterizes strip" {
    const sheet = comptime blk: {
        // 4x2 image with two 2x2 tiles side by side.
        const pixels = [_]u8{ 1, 2, 5, 6, 3, 4, 7, 8 };
        const cel_data = [_]u8{0} ** CEL_PREAMBLE_SIZE
        ++ le16(4) ++ le16(2)
        ++ pixels;
        const cel_chunk = le32(CHUNK_HEADER_SIZE + cel_data.len)
        ++ le16(0x2005)
        ++ cel_data;
        const slice_a = build_slice_chunk("left", 0, 0, 2, 2);
        const slice_b = build_slice_chunk("right", 2, 0, 2, 2);
        const payload = cel_chunk ++ slice_a ++ slice_b;
        const frame = le32(FRAME_HEADER_SIZE + payload.len)
        ++ le16(0xF1FA)
        ++ le16(3) // 3 chunks
        ++ le16(0)
        ++ [_]u8{0} ** 2
        ++ le32(0)
        ++ payload;
        const header = build_file_header(1, 4, 2);
        break :blk parse_sheet(&(header ++ frame), 2);
    };

    try std.testing.expectEqual(@as(u16, 2), sheet.tile_count);
    try std.testing.expectEqual(@as(u16, 4), sheet.strip_width);
    try std.testing.expectEqual(@as(usize, 2), sheet.slices.len);
    try std.testing.expectEqualSlices(u8, "left", sheet.slices[0].name);
    try std.testing.expectEqualSlices(u8, "right", sheet.slices[1].name);

    // Strip: tile 1 (left 2x2) then tile 2 (right 2x2).
    // Row 0: [1,2, 5,6], Row 1: [3,4, 7,8]
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 5, 6, 3, 4, 7, 8 }, sheet.pixels);
}

test "load minimal ase at runtime" {
    const data = comptime blk: {
        const pixels = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7 };
        const frame = build_frame(4, 2, &pixels);
        const header = build_file_header(1, 4, 2);
        break :blk header ++ frame;
    };
    const sprite = try load(std.testing.allocator, &data);
    defer std.testing.allocator.free(@constCast(sprite.pixels));
    try std.testing.expectEqual(@as(u16, 4), sprite.width);
    try std.testing.expectEqual(@as(u16, 2), sprite.height);
    try std.testing.expectEqual(@as(u16, 4), sprite.strip_width);
    try std.testing.expectEqualSlices(u8, &.{ 0, 1, 2, 3, 4, 5, 6, 7 }, sprite.pixels);
}

test "load multi-frame ase at runtime" {
    const data = comptime blk: {
        const frame0 = build_frame(2, 2, &[_]u8{ 1, 2, 3, 4 });
        const frame1 = build_frame(2, 2, &[_]u8{ 5, 6, 7, 8 });
        const header = build_file_header(2, 2, 2);
        break :blk header ++ frame0 ++ frame1;
    };
    const sprite = try load(std.testing.allocator, &data);
    defer std.testing.allocator.free(@constCast(sprite.pixels));
    try std.testing.expectEqual(@as(u16, 2), sprite.width);
    try std.testing.expectEqual(@as(u16, 4), sprite.strip_width);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 5, 6, 3, 4, 7, 8 }, sprite.pixels);
}

test "load rejects bad magic" {
    var data: [FILE_HEADER_SIZE]u8 = @splat(0);
    try std.testing.expectError(error.BadMagic, load(std.testing.allocator, &data));
}

test "load rejects truncated file" {
    const short: [10]u8 = @splat(0);
    try std.testing.expectError(error.InvalidHeader, load(std.testing.allocator, &short));
}
