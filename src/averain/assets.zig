/// Runtime asset loading with hot reload (dev) or embedded bytes (release).
const std = @import("std");
const orb = @import("orb");
const map = @import("map.zig");
const build_options = @import("build_options");

const Allocator = std.mem.Allocator;
const Sprite = orb.ase.Sprite;
const Watcher = orb.watcher.Watcher;

const dev = build_options.dev;

/// Asset directory path relative to working directory.
const ASSET_DIR = "src/averain/assets/";

/// All loaded game assets. Sprites are heap-allocated at runtime.
pub const Assets = struct {
    pal: [256]u32,
    player: Sprite,
    tiles: Sprite,
    arawn: Sprite,
    stone: Sprite,
    alloc: Allocator,
    watch: if (dev) ?Watcher else void,

    /// Load all assets. Dev: reads from disk. Release: parses @embedFile bytes.
    pub fn init(alloc: Allocator) !Assets {
        const pal = try load_gpl("palette.gpl");
        const player = try load_ase(alloc, "player.ase");
        errdefer alloc.free(@constCast(player.pixels));
        const tiles_raw = try load_ase(alloc, "tiles.ase");
        errdefer alloc.free(@constCast(tiles_raw.pixels));
        const arawn = try load_ase(alloc, "arawn.ase");
        errdefer alloc.free(@constCast(arawn.pixels));
        const stone = try load_ase(alloc, "stone.ase");
        errdefer alloc.free(@constCast(stone.pixels));

        var w: if (dev) ?Watcher else void = if (dev) null else {};
        if (dev) {
            w = Watcher.init(ASSET_DIR) catch null;
        }

        return .{
            .pal = pal,
            .player = player,
            .tiles = .{
                .width = @intCast(map.TILE_SIZE),
                .height = @intCast(map.TILE_SIZE),
                .strip_width = tiles_raw.strip_width,
                .pixels = tiles_raw.pixels,
            },
            .arawn = arawn,
            .stone = stone,
            .alloc = alloc,
            .watch = w,
        };
    }

    /// Poll for changed asset files and reload them. Dev only, no-op in release.
    pub fn poll(self: *Assets) void {
        if (!dev) return;
        if (self.watch) |*w| {
            while (w.poll()) |name| {
                self.reload(name);
            }
        }
    }

    /// Reload a single asset by filename.
    fn reload(self: *Assets, name: []const u8) void {
        if (eql(name, "palette.gpl")) {
            if (load_gpl("palette.gpl")) |pal| {
                self.pal = pal;
            } else |_| {}
        } else if (eql(name, "player.ase")) {
            self.swap(&self.player, "player.ase", null);
        } else if (eql(name, "tiles.ase")) {
            self.swap(&self.tiles, "tiles.ase", @intCast(map.TILE_SIZE));
        } else if (eql(name, "arawn.ase")) {
            self.swap(&self.arawn, "arawn.ase", null);
        } else if (eql(name, "stone.ase")) {
            self.swap(&self.stone, "stone.ase", null);
        }
    }

    /// Reload a sprite from disk, freeing the old pixel buffer.
    fn swap(self: *Assets, slot: *Sprite, comptime name: []const u8, tile_size: ?u16) void {
        const new = load_ase(self.alloc, name) catch return;
        self.alloc.free(@constCast(slot.pixels));
        if (tile_size) |ts| {
            slot.* = .{
                .width = ts,
                .height = ts,
                .strip_width = new.strip_width,
                .pixels = new.pixels,
            };
        } else {
            slot.* = new;
        }
    }

    fn eql(a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }

    /// Load a .gpl palette from disk (dev) or embedded bytes (release).
    fn load_gpl(comptime name: []const u8) ![256]u32 {
        if (dev) {
            const data = std.fs.cwd().readFileAlloc(
                std.heap.page_allocator,
                ASSET_DIR ++ name,
                64 * 1024,
            ) catch return error.ReadFailed;
            defer std.heap.page_allocator.free(data);
            return orb.gpl.load(data);
        } else {
            return orb.gpl.load(@embedFile("assets/" ++ name));
        }
    }

    /// Load an .ase sprite from disk (dev) or embedded bytes (release).
    fn load_ase(alloc: Allocator, comptime name: []const u8) !Sprite {
        if (dev) {
            const data = std.fs.cwd().readFileAlloc(
                std.heap.page_allocator,
                ASSET_DIR ++ name,
                4 * 1024 * 1024,
            ) catch return error.ReadFailed;
            defer std.heap.page_allocator.free(data);
            return orb.ase.load(alloc, data);
        } else {
            return orb.ase.load(alloc, @embedFile("assets/" ++ name));
        }
    }
};
