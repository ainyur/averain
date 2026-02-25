/// Runtime asset loading with hot reload (dev) or embedded bytes (release).
const std = @import("std");
const orb = @import("orb");
const map = @import("map.zig");

const build_options = @import("build_options");

const Allocator = std.mem.Allocator;
const Slice = orb.ase.Slice;
const Sprite = orb.ase.Sprite;
const Watcher = orb.watcher.Watcher;

const DEV = build_options.dev;

/// Asset directory path relative to working directory.
const ASSET_DIR = "src/averain/assets/";

/// All loaded game assets. Sprites are heap-allocated at runtime.
pub const Assets = struct {
    alloc: Allocator,
    arawn: Sprite,
    pal: [256]u32,
    player: Sprite,
    slices: []Slice,
    stone: Sprite,
    tiles: Sprite,
    watch: if (DEV) ?Watcher else void,

    /// Load all assets. Dev: reads from disk. Release: parses @embedFile bytes.
    pub fn init(alloc: Allocator) !Assets {
        const pal = try load_gpl("palette.gpl");
        const player = try load_ase(alloc, "player.ase");
        errdefer alloc.free(@constCast(player.pixels));
        const tiles_raw = try load_ase(alloc, "tiles.ase");
        defer alloc.free(@constCast(tiles_raw.pixels));
        const slices = try load_slices(alloc, "tiles.ase");
        errdefer alloc.free(slices);
        const tiles = try orb.ase.rearrange(alloc, tiles_raw, slices, map.TILE_SIZE);
        errdefer alloc.free(@constCast(tiles.pixels));
        const arawn = try load_ase(alloc, "arawn.ase");
        errdefer alloc.free(@constCast(arawn.pixels));
        const stone = try load_ase(alloc, "stone.ase");
        errdefer alloc.free(@constCast(stone.pixels));

        var w: if (DEV) ?Watcher else void = if (DEV) null else {};
        if (DEV) {
            w = Watcher.init(ASSET_DIR) catch null;
        }

        map.props = orb.ase.build_props(slices, map.TILE_SIZE, &.{
            .{ .tag = "solid", .flag = map.Prop.SOLID },
        });

        return .{
            .alloc = alloc,
            .arawn = arawn,
            .pal = pal,
            .player = player,
            .slices = slices,
            .stone = stone,
            .tiles = tiles,
            .watch = w,
        };
    }

    /// Poll for changed asset files and reload them. Dev only, no-op in release.
    pub fn poll(self: *Assets) void {
        if (!DEV) return;
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
            self.swap(&self.player, "player.ase");
        } else if (eql(name, "tiles.ase")) {
            const raw = load_ase(self.alloc, "tiles.ase") catch return;
            defer self.alloc.free(@constCast(raw.pixels));
            const new_slices = load_slices(self.alloc, "tiles.ase") catch return;
            const new_tiles = orb.ase.rearrange(self.alloc, raw, new_slices, map.TILE_SIZE) catch return;
            self.alloc.free(@constCast(self.tiles.pixels));
            self.tiles = new_tiles;
            self.alloc.free(self.slices);
            self.slices = new_slices;
            map.props = orb.ase.build_props(self.slices, map.TILE_SIZE, &.{
                .{ .tag = "solid", .flag = map.Prop.SOLID },
            });
        } else if (eql(name, "arawn.ase")) {
            self.swap(&self.arawn, "arawn.ase");
        } else if (eql(name, "stone.ase")) {
            self.swap(&self.stone, "stone.ase");
        }
    }

    /// Reload a sprite from disk, freeing the old pixel buffer.
    fn swap(self: *Assets, slot: *Sprite, comptime name: []const u8) void {
        const new = load_ase(self.alloc, name) catch return;
        self.alloc.free(@constCast(slot.pixels));
        slot.* = new;
    }

    fn eql(a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }

    /// Load a .gpl palette from disk (dev) or embedded bytes (release).
    fn load_gpl(comptime name: []const u8) ![256]u32 {
        if (DEV) {
            const data = try orb.assets.read(std.heap.page_allocator, ASSET_DIR ++ name, 64 * 1024);
            defer std.heap.page_allocator.free(data);
            return orb.gpl.load(data);
        } else {
            return orb.gpl.load(@embedFile("assets/" ++ name));
        }
    }

    /// Load an .ase sprite from disk (dev) or embedded bytes (release).
    fn load_ase(alloc: Allocator, comptime name: []const u8) !Sprite {
        if (DEV) {
            const data = try orb.assets.read(std.heap.page_allocator, ASSET_DIR ++ name, 4 * 1024 * 1024);
            defer std.heap.page_allocator.free(data);
            return orb.ase.load(alloc, data);
        } else {
            return orb.ase.load(alloc, @embedFile("assets/" ++ name));
        }
    }

    /// Load slice metadata from an .ase file. Keeps the file buffer alive
    /// because Slice.name borrows into it.
    fn load_slices(alloc: Allocator, comptime name: []const u8) ![]Slice {
        if (DEV) {
            const data = try orb.assets.read(alloc, ASSET_DIR ++ name, 4 * 1024 * 1024);
            return orb.ase.load_slices(alloc, data);
        } else {
            return orb.ase.load_slices(alloc, @embedFile("assets/" ++ name));
        }
    }
};
