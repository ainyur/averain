/// In-game tile editor. Dev-mode map painting overlay.
const std = @import("std");

const DevInput = @import("input.zig").DevInput;
const Graphics = @import("graphics.zig").Graphics;
const InputState = @import("input.zig").InputState;
const Slice = @import("ase.zig").Slice;
const Sprite = @import("ase.zig").Sprite;

/// Parameterized tile map editor.
pub fn Editor(comptime cfg: struct {
    tile_size: u32,
    world_w: u32,
    world_h: u32,
}) type {
    const PANEL_W: u32 = 80;
    const THUMB_Y: i32 = 12;
    const COLS: u8 = @intCast((PANEL_W - 8) / cfg.tile_size);
    const TS: u32 = cfg.tile_size;

    const C_BG: u8 = 8;
    const C_BORDER: u8 = 12;
    const C_CURSOR: u8 = 73;
    const C_SOLID: u8 = 41;
    const C_TEXT: u8 = 14;

    return struct {
        const Self = @This();

        /// Cursor position in tile coords.
        cx: u8 = 0,
        cy: u8 = 0,
        /// Camera offset in pixels.
        cam_x: i32 = 0,
        cam_y: i32 = 0,
        /// Current slice page.
        page: u8 = 0,
        /// Selected tile within current page (0-based).
        sel: u8 = 0,
        /// Tile panel scroll offset in rows.
        scroll: u8 = 0,
        /// Unsaved changes indicator.
        dirty: bool = false,
        /// Pointer to the mutable tile grid.
        data: *[cfg.world_w * cfg.world_h]u8,

        /// Process editor input. Mutates map data directly.
        pub fn update(self: *Self, input: InputState, sheet: Sprite, slices: []const Slice) void {
            _ = sheet;

            if (input.pressed.down and self.cy < 255) self.cy += 1;
            if (input.pressed.left and self.cx > 0) self.cx -= 1;
            if (input.pressed.right and self.cx < 255) self.cx += 1;
            if (input.pressed.up and self.cy > 0) self.cy -= 1;

            self.track_camera();

            const num_pages: u8 = @intCast(slices.len);
            if (num_pages > 0) {
                if (input.pressed.l) {
                    self.page = if (self.page == 0) num_pages - 1 else self.page - 1;
                    self.sel = 0;
                    self.scroll = 0;
                }
                if (input.pressed.r) {
                    self.page = if (self.page + 1 >= num_pages) 0 else self.page + 1;
                    self.sel = 0;
                    self.scroll = 0;
                }
                self.ensure_visible();
            }

            // Paint.
            if (input.pressed.a) {
                const tid = global_id(slices, self.page, self.sel);
                const idx = @as(usize, self.cy) * cfg.world_w + self.cx;
                self.data[idx] = tid;
                self.dirty = true;
            }

            // Eyedropper.
            if (input.pressed.b) {
                const idx = @as(usize, self.cy) * cfg.world_w + self.cx;
                const tid = self.data[idx];
                if (tid > 0) {
                    const resolved = resolve(slices, tid);
                    self.page = resolved[0];
                    self.sel = resolved[1];
                    self.scroll = 0;
                    self.ensure_visible();
                }
            }

            // Erase.
            if (input.pressed.select) {
                const idx = @as(usize, self.cy) * cfg.world_w + self.cx;
                self.data[idx] = 0;
                self.dirty = true;
            }
        }

        /// Handle dev input: mouse, wheel, keyboard tile navigation.
        pub fn mouse(self: *Self, dev: DevInput, slices: []const Slice) void {
            if (slices.len > 0) {
                const count = page_tiles(slices, self.page);
                if (count > 0) {
                    var delta: i32 = 0;
                    if (dev.mouse_wheel != 0) delta = -dev.mouse_wheel;
                    if (dev.tile_next) delta += 1;
                    if (dev.tile_prev) delta -= 1;
                    if (delta != 0) {
                        const c_i32: i32 = @intCast(count);
                        const new = @mod(@as(i32, self.sel) + delta, c_i32);
                        self.sel = @intCast(new);
                        self.ensure_visible();
                    }
                }
            }

            const mx = dev.mouse_x;
            const my = dev.mouse_y;
            const panel_x: i32 = @intCast(Graphics.WIDTH - PANEL_W);
            const ts: i32 = @intCast(TS);

            if (dev.mouse_click) {
                if (mx >= panel_x) {
                    const lx = mx - panel_x - 4;
                    const ly = my - THUMB_Y + @as(i32, self.scroll) * ts;
                    if (lx >= 0 and ly >= 0) {
                        const col: u8 = @intCast(@divTrunc(lx, ts));
                        const row: u8 = @intCast(@divTrunc(ly, ts));
                        if (col < COLS) {
                            const i = row * COLS + col;
                            const count = page_tiles(slices, self.page);
                            if (i < count) self.sel = i;
                        }
                    }
                } else {
                    const tx = @divTrunc(mx + self.cam_x, ts);
                    const ty = @divTrunc(my + self.cam_y, ts);
                    if (tx >= 0 and ty >= 0 and tx < cfg.world_w and ty < cfg.world_h) {
                        const tid = global_id(slices, self.page, self.sel);
                        const idx = @as(usize, @intCast(ty)) * cfg.world_w + @as(usize, @intCast(tx));
                        self.data[idx] = tid;
                        self.dirty = true;
                    }
                }
            }

            if (dev.mouse_right) {
                if (mx < panel_x) {
                    const tx = @divTrunc(mx + self.cam_x, ts);
                    const ty = @divTrunc(my + self.cam_y, ts);
                    if (tx >= 0 and ty >= 0 and tx < cfg.world_w and ty < cfg.world_h) {
                        const idx = @as(usize, @intCast(ty)) * cfg.world_w + @as(usize, @intCast(tx));
                        const tid = self.data[idx];
                        if (tid > 0) {
                            const resolved = resolve(slices, tid);
                            self.page = resolved[0];
                            self.sel = resolved[1];
                            self.scroll = 0;
                            self.ensure_visible();
                        }
                    }
                }
            }
        }

        /// Draw editor overlay onto the framebuffer.
        pub fn draw(self: *const Self, gfx: *Graphics, sheet: Sprite, slices: []const Slice) void {
            self.draw_map(gfx, sheet);

            const ts: i32 = @intCast(TS);
            const cx: i32 = @as(i32, self.cx) * ts - self.cam_x;
            const cy: i32 = @as(i32, self.cy) * ts - self.cam_y;
            gfx.rect(cx, cy, TS, 1, C_CURSOR);
            gfx.rect(cx, cy + ts - 1, TS, 1, C_CURSOR);
            gfx.rect(cx, cy, 1, TS, C_CURSOR);
            gfx.rect(cx + ts - 1, cy, 1, TS, C_CURSOR);

            self.draw_panel(gfx, sheet, slices);
        }

        /// Save map to disk with header.
        pub fn save(self: *Self, comptime path: []const u8) void {
            const grid_size = cfg.world_w * cfg.world_h;
            var buf: [4 + grid_size]u8 = undefined;
            buf[0] = @intCast(cfg.world_w & 0xFF);
            buf[1] = @intCast((cfg.world_w >> 8) & 0xFF);
            buf[2] = @intCast(cfg.world_h & 0xFF);
            buf[3] = @intCast((cfg.world_h >> 8) & 0xFF);
            @memcpy(buf[4..][0..grid_size], self.data);
            const file = std.fs.cwd().createFile(path, .{}) catch return;
            defer file.close();
            file.writeAll(&buf) catch return;
            self.dirty = false;
        }

        fn ensure_visible(self: *Self) void {
            const sel_row = self.sel / COLS;
            const vis_rows = (Graphics.HEIGHT - @as(u32, @intCast(THUMB_Y))) / TS;
            if (sel_row < self.scroll) {
                self.scroll = sel_row;
            } else if (sel_row >= self.scroll + @as(u8, @intCast(vis_rows))) {
                self.scroll = sel_row - @as(u8, @intCast(vis_rows)) + 1;
            }
        }

        fn track_camera(self: *Self) void {
            const ts: i32 = @intCast(TS);
            const view_w: i32 = @as(i32, Graphics.WIDTH) - @as(i32, PANEL_W);
            const view_h: i32 = Graphics.HEIGHT;
            const cur_x: i32 = @as(i32, self.cx) * ts;
            const cur_y: i32 = @as(i32, self.cy) * ts;

            if (cur_x - self.cam_x < ts) self.cam_x = cur_x - ts;
            if (cur_x - self.cam_x + ts > view_w - ts) self.cam_x = cur_x + ts * 2 - view_w;
            if (cur_y - self.cam_y < ts) self.cam_y = cur_y - ts;
            if (cur_y - self.cam_y + ts > view_h - ts) self.cam_y = cur_y + ts * 2 - view_h;

            if (self.cam_x < 0) self.cam_x = 0;
            if (self.cam_y < 0) self.cam_y = 0;
        }

        fn draw_map(self: *const Self, gfx: *Graphics, sheet: Sprite) void {
            const ts: i32 = @intCast(TS);
            const view_w: i32 = @as(i32, Graphics.WIDTH) - @as(i32, PANEL_W);

            const first_col: u32 = @intCast(@max(0, @divTrunc(self.cam_x, ts)));
            const first_row: u32 = @intCast(@max(0, @divTrunc(self.cam_y, ts)));
            const vis_cols: u32 = @intCast(@divTrunc(view_w, ts) + 2);
            const vis_rows: u32 = @intCast(@divTrunc(@as(i32, Graphics.HEIGHT), ts) + 2);
            const last_col = @min(first_col + vis_cols, cfg.world_w);
            const last_row = @min(first_row + vis_rows, cfg.world_h);

            for (first_row..last_row) |row| {
                for (first_col..last_col) |col| {
                    const tid = self.data[row * cfg.world_w + col];
                    if (tid == 0) continue;
                    const dx: i32 = @as(i32, @intCast(col)) * ts - self.cam_x;
                    const dy: i32 = @as(i32, @intCast(row)) * ts - self.cam_y;
                    if (dx + ts <= 0 or dx >= view_w) continue;
                    if (dy + ts <= 0 or dy >= @as(i32, Graphics.HEIGHT)) continue;
                    gfx.blit_frame(sheet, tid, dx, dy, false);
                }
            }
        }

        fn draw_panel(self: *const Self, gfx: *Graphics, sheet: Sprite, slices: []const Slice) void {
            const px: i32 = @intCast(Graphics.WIDTH - PANEL_W);
            gfx.panel(px, 0, PANEL_W, Graphics.HEIGHT, C_BG, C_BORDER);

            if (slices.len == 0) return;
            const s = slices[self.page];

            const name_color: u8 = if (self.dirty) C_SOLID else C_TEXT;
            gfx.text(s.name, px + 4, 2, name_color);

            const ts: i32 = @intCast(TS);
            const count = page_tiles(slices, self.page);
            const base = global_id(slices, self.page, 0);
            const scroll_off: i32 = @as(i32, self.scroll) * ts;

            for (0..count) |i| {
                const col: i32 = @intCast(i % COLS);
                const row: i32 = @intCast(i / COLS);
                const tx = px + 4 + col * ts;
                const ty: i32 = THUMB_Y + row * ts - scroll_off;
                if (ty + ts <= 0 or ty >= Graphics.HEIGHT) continue;
                gfx.blit_frame(sheet, base + @as(u32, @intCast(i)), tx, ty, false);

                if (i == self.sel) {
                    gfx.rect(tx, ty, TS, 1, C_CURSOR);
                    gfx.rect(tx, ty + ts - 1, TS, 1, C_CURSOR);
                    gfx.rect(tx, ty, 1, TS, C_CURSOR);
                    gfx.rect(tx + ts - 1, ty, 1, TS, C_CURSOR);
                }
            }

            var page_buf: [8]u8 = undefined;
            const page_str = std.fmt.bufPrint(&page_buf, "{d}/{d}", .{
                @as(u16, self.page) + 1,
                @as(u16, @intCast(slices.len)),
            }) catch "";
            const page_w: i32 = @intCast(page_str.len * 8);
            gfx.text(page_str, px + @as(i32, PANEL_W) - page_w - 4, @as(i32, Graphics.HEIGHT) - 10, name_color);
        }

        /// Number of tiles in a slice page.
        fn page_tiles(slices: []const Slice, page: u8) u8 {
            if (page >= slices.len) return 0;
            const s = slices[page];
            return @intCast((s.w / TS) * (s.h / TS));
        }

        /// Global tile ID for a page + local index. 1-based (0 = empty).
        fn global_id(slices: []const Slice, page: u8, sel: u8) u8 {
            var base: u8 = 1;
            for (slices[0..page]) |s| {
                base += @intCast((s.w / TS) * (s.h / TS));
            }
            return base + sel;
        }

        /// Reverse-map a global tile ID to (page, local index).
        fn resolve(slices: []const Slice, tid: u8) [2]u8 {
            var base: u8 = 1;
            for (slices, 0..) |s, i| {
                const count: u8 = @intCast((s.w / TS) * (s.h / TS));
                if (tid >= base and tid < base + count) {
                    return .{ @intCast(i), tid - base };
                }
                base += count;
            }
            return .{ 0, 0 };
        }
    };
}
