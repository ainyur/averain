/// Allocation free deflate (RFC 1951) and zlib (RFC 1950) decompressor.
/// All state in fixed arrays. Runs at comptime.

/// Decompress zlib wrapped data. Output length must be known at comptime.
pub fn zlib(comptime input: []const u8, comptime len: usize) [len]u8 {
    @setEvalBranchQuota(1000000);
    comptime {
        if (input.len < 6) @compileError("zlib input too short");

        const cmf = input[0];
        const flg = input[1];
        if (cmf & 0x0F != 8) @compileError("not deflate compression");
        if ((@as(u16, cmf) * 256 + flg) % 31 != 0) @compileError("bad zlib header check");
        if (flg & 0x20 != 0) @compileError("preset dictionary not supported");

        var state = State{ .input = input, .pos = 2 };
        var out: [len]u8 = undefined;
        var out_pos: usize = 0;

        var is_final = false;
        while (!is_final) {
            is_final = state.read(1) != 0;
            const btype: u2 = @intCast(state.read(2));

            switch (btype) {
                0 => {
                    // Stored block: discard partial byte, read len
                    state.bit_buf = 0;
                    state.bit_count = 0;
                    const blen: u16 = @as(u16, input[state.pos]) | @as(u16, input[state.pos + 1]) << 8;
                    state.pos += 4; // len + nlen
                    for (0..blen) |i| {
                        out[out_pos + i] = input[state.pos + i];
                    }
                    state.pos += blen;
                    out_pos += blen;
                },
                1 => {
                    // Fixed Huffman codes
                    var ll_lens: [288]u4 = undefined;
                    for (0..144) |i| ll_lens[i] = 8;
                    for (144..256) |i| ll_lens[i] = 9;
                    for (256..280) |i| ll_lens[i] = 7;
                    for (280..288) |i| ll_lens[i] = 8;
                    const ll = build(288, &ll_lens);

                    var d_lens: [32]u4 = [_]u4{5} ** 32;
                    const dt = build(32, &d_lens);

                    decode_block(&state, &ll, &dt, &out, &out_pos);
                },
                2 => {
                    // Dynamic Huffman codes
                    const hlit: u16 = @as(u16, @intCast(state.read(5))) + 257;
                    const hdist: u16 = @as(u16, @intCast(state.read(5))) + 1;
                    const hclen: u16 = @as(u16, @intCast(state.read(4))) + 4;

                    const order = [_]u5{ 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 };
                    var cl_lens: [19]u4 = [_]u4{0} ** 19;
                    for (0..hclen) |i| {
                        cl_lens[order[i]] = @intCast(state.read(3));
                    }
                    const cl = build(19, &cl_lens);

                    var all_lens: [288 + 32]u4 = [_]u4{0} ** (288 + 32);
                    var ai: usize = 0;
                    const total = hlit + hdist;
                    while (ai < total) {
                        const sym = cl.decode(&state);
                        if (sym < 16) {
                            all_lens[ai] = @intCast(sym);
                            ai += 1;
                        } else if (sym == 16) {
                            const rep = state.read(2) + 3;
                            const val = all_lens[ai - 1];
                            for (0..rep) |_| {
                                all_lens[ai] = val;
                                ai += 1;
                            }
                        } else if (sym == 17) {
                            ai += state.read(3) + 3;
                        } else {
                            ai += state.read(7) + 11;
                        }
                    }

                    const ll = build(hlit, all_lens[0..hlit]);
                    const dt = build(hdist, all_lens[hlit .. hlit + hdist]);
                    decode_block(&state, &ll, &dt, &out, &out_pos);
                },
                3 => @compileError("invalid block type 3"),
            }
        }

        if (out_pos != len) @compileError("deflate output size mismatch");

        // Verify adler32
        // Align to byte boundary for checksum bytes
        if (state.bit_count > 0) {
            state.bit_buf = 0;
            state.bit_count = 0;
        }
        const cs = state.pos;
        if (cs + 4 > input.len) @compileError("missing adler32 checksum");
        const expected: u32 = @as(u32, input[cs]) << 24 | @as(u32, input[cs + 1]) << 16 |
            @as(u32, input[cs + 2]) << 8 | input[cs + 3];
        if (adler32(&out) != expected) @compileError("adler32 mismatch");

        return out;
    }
}

const Table = struct {
    counts: [16]u16,
    symbols: [289]u16,

    fn decode(self: *const Table, state: *State) u16 {
        var code: u16 = 0;
        var first: u16 = 0;
        var idx: u16 = 0;

        for (1..16) |bit_len| {
            code = (code | @as(u16, @intCast(state.read(1)))) & 0x7FFF;
            const count = self.counts[bit_len];
            if (code < first + count) {
                return self.symbols[idx + code - first];
            }
            idx += count;
            first = (first + count) << 1;
            code <<= 1;
        }
        @compileError("invalid huffman code");
    }
};

fn build(comptime n: usize, lens: []const u4) Table {
    comptime {
        // Count codes per bit length
        var bl_count: [16]u16 = [_]u16{0} ** 16;
        for (0..n) |i| {
            bl_count[lens[i]] += 1;
        }
        bl_count[0] = 0;

        // Compute starting codes
        var next_code: [16]u16 = [_]u16{0} ** 16;
        var code: u16 = 0;
        for (1..16) |b| {
            code = (code + bl_count[b - 1]) << 1;
            next_code[b] = code;
        }

        // Build sorted symbol table
        // Order symbols by (bit_length, code_value)
        var symbols: [289]u16 = [_]u16{0} ** 289;
        var offsets: [16]u16 = [_]u16{0} ** 16;
        var total: u16 = 0;
        for (1..16) |b| {
            offsets[b] = total;
            total += bl_count[b];
        }

        for (0..n) |i| {
            const l = lens[i];
            if (l != 0) {
                symbols[offsets[l]] = @intCast(i);
                offsets[l] += 1;
                next_code[l] += 1;
            }
        }

        return .{ .counts = bl_count, .symbols = symbols };
    }
}

fn decode_block(state: *State, ll: *const Table, dt: *const Table, out: []u8, out_pos: *usize) void {
    while (true) {
        const sym = ll.decode(state);
        if (sym == 256) break;
        if (sym < 256) {
            out[out_pos.*] = @intCast(sym);
            out_pos.* += 1;
        } else {
            const length = read_length(sym, state);
            const dsym = dt.decode(state);
            const distance = read_distance(dsym, state);

            for (0..length) |_| {
                out[out_pos.*] = out[out_pos.* - distance];
                out_pos.* += 1;
            }
        }
    }
}

const len_base = [_]u16{ 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 };
const len_extra = [_]u4{ 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 };

fn read_length(sym: u16, state: *State) usize {
    const idx = sym - 257;
    return len_base[idx] + state.read(len_extra[idx]);
}

const dist_base = [_]u16{ 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 };
const dist_extra = [_]u4{ 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 };

fn read_distance(sym: u16, state: *State) usize {
    return dist_base[sym] + state.read(dist_extra[sym]);
}

const State = struct {
    input: []const u8,
    pos: usize = 0,
    bit_buf: u32 = 0,
    bit_count: u8 = 0,

    fn read(self: *State, n: u5) u32 {
        while (self.bit_count < n) {
            self.bit_buf |= @as(u32, self.input[self.pos]) << @intCast(self.bit_count);
            self.pos += 1;
            self.bit_count += 8;
        }
        const mask: u32 = (@as(u32, 1) << n) - 1;
        const val = self.bit_buf & mask;
        self.bit_buf >>= n;
        self.bit_count -= n;
        return val;
    }
};

fn adler32(data: []const u8) u32 {
    var a: u32 = 1;
    var b: u32 = 0;
    for (data) |byte| {
        a = (a + byte) % 65521;
        b = (b + a) % 65521;
    }
    return b << 16 | a;
}

const std = @import("std");

test "decompress zlib stored block" {
    // zlib header: CMF=0x78 FLG=0x01
    // stored block: BFINAL=1, BTYPE=00 -> byte 0x01
    // LEN=5 NLEN=0xFFFA, then "Hello"
    // adler32("Hello") = 0x058C01F5
    const compressed = [_]u8{
        0x78, 0x01, // zlib header
        0x01, // bfinal=1, btype=00, pad=00000
        0x05, 0x00, 0xFA, 0xFF, // LEN=5, NLEN
        'H', 'e', 'l', 'l', 'o', // payload
        0x05, 0x8C, 0x01, 0xF5, // adler32
    };
    const result = comptime zlib(&compressed, 5);
    try std.testing.expectEqualStrings("Hello", &result);
}

test "decompress zlib fixed huffman" {
    // "AAAAAAAAAAAAAAAA" (16 bytes) compressed with zlib level 1
    const compressed = [_]u8{ 0x78, 0x01, 0x73, 0x74, 0x44, 0x05, 0x00, 0x22, 0x98, 0x04, 0x11 };
    const result = comptime blk: {
        @setEvalBranchQuota(10000);
        break :blk zlib(&compressed, 16);
    };
    try std.testing.expectEqualStrings("AAAAAAAAAAAAAAAA", &result);
}

test "decompress zlib dynamic huffman" {
    const original = "The quick brown fox jumps over the lazy dog. The quick brown fox jumps over the lazy dog.";
    const compressed = [_]u8{
        0x78, 0x9C, 0x0B, 0xC9, 0x48, 0x55, 0x28, 0x2C, 0xCD, 0x4C, 0xCE, 0x56,
        0x48, 0x2A, 0xCA, 0x2F, 0xCF, 0x53, 0x48, 0xCB, 0xAF, 0x50, 0xC8, 0x2A,
        0xCD, 0x2D, 0x28, 0x56, 0xC8, 0x2F, 0x4B, 0x2D, 0x52, 0x28, 0x01, 0x4A,
        0xE7, 0x24, 0x56, 0x55, 0x2A, 0xA4, 0xE4, 0xA7, 0xEB, 0x29, 0x84, 0x90,
        0xA0, 0x18, 0x00, 0xAE, 0xD1, 0x20, 0x2F,
    };
    const result = comptime blk: {
        @setEvalBranchQuota(100000);
        break :blk zlib(&compressed, original.len);
    };
    try std.testing.expectEqualStrings(original, &result);
}
