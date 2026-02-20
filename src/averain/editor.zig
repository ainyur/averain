/// In-game tile editor. Dev-mode map painting overlay.
const std = @import("std");
const orb = @import("orb");
const map = @import("map.zig");

const Graphics = orb.Graphics;
const InputState = orb.InputState;
const Sprite = orb.ase.Sprite;

/// Palette panel width in pixels.
const PANEL_W: u32 = 80;

/// Editor UI palette indices.
const C_BG: u8 = 8; // dark grey
const C_BORDER: u8 = 12; // light grey
const C_CURSOR: u8 = 73; // gold
const C_SOLID: u8 = 41; // red
const C_TEXT: u8 = 14; // white

pub const Editor = struct {
    /// Cursor position in tile coords.
    cx: u8 = 0,
    cy: u8 = 0,
    /// Camera offset in pixels.
    cam_x: i32 = 0,
    cam_y: i32 = 0,
    /// Selected tile ID (1-based, 0 = empty).
    sel: u8 = 1,
    /// Unsaved changes indicator.
    dirty: bool = false,

    /// Process editor input. Mutates map.data directly.
    pub fn update(self: *Editor, input: InputState, sheet: Sprite) void {
        _ = sheet;

        // Cursor movement.
        if (input.pressed.down and self.cy < 255) self.cy += 1;
        if (input.pressed.left and self.cx > 0) self.cx -= 1;
        if (input.pressed.right and self.cx < 255) self.cx += 1;
        if (input.pressed.up and self.cy > 0) self.cy -= 1;

        self.track_camera();

        // Cycle tile selection.
        const tile_count: u8 = @intCast(map.TILE_COUNT);
        if (input.pressed.r and tile_count > 0) {
            self.sel = if (self.sel >= tile_count) 1 else self.sel + 1;
        }
        if (input.pressed.l) {
            self.sel = if (self.sel <= 1) tile_count else self.sel - 1;
        }

        // Paint.
        if (input.pressed.a) {
            const idx = @as(usize, self.cy) * map.WORLD_W + self.cx;
            map.data[idx] = self.sel;
            self.dirty = true;
        }

        // Eyedropper.
        if (input.pressed.b) {
            const idx = @as(usize, self.cy) * map.WORLD_W + self.cx;
            const tid = map.data[idx];
            if (tid > 0) self.sel = tid;
        }

        // Erase.
        if (input.pressed.select) {
            const idx = @as(usize, self.cy) * map.WORLD_W + self.cx;
            map.data[idx] = 0;
            self.dirty = true;
        }
    }

    /// Draw editor overlay onto the framebuffer.
    pub fn draw(self: *const Editor, gfx: *Graphics, sheet: Sprite) void {
        self.draw_map(gfx, sheet);

        // Cursor highlight.
        const ts: i32 = @intCast(map.TILE_SIZE);
        const cx: i32 = @as(i32, self.cx) * ts - self.cam_x;
        const cy: i32 = @as(i32, self.cy) * ts - self.cam_y;
        const tsz: u32 = map.TILE_SIZE;
        gfx.rect(cx, cy, tsz, 1, C_CURSOR);
        gfx.rect(cx, cy + ts - 1, tsz, 1, C_CURSOR);
        gfx.rect(cx, cy, 1, tsz, C_CURSOR);
        gfx.rect(cx + ts - 1, cy, 1, tsz, C_CURSOR);

        self.draw_panel(gfx, sheet);
    }

    /// Save world.map to disk via std.fs.
    pub fn save(self: *Editor) void {
        const tc: usize = map.TILE_COUNT;
        const grid_size = map.WORLD_W * map.WORLD_H;
        const props_size = tc + 1;
        const total = 8 + grid_size + props_size;
        var buf: [total]u8 = undefined;

        // Header.
        buf[0] = @intCast(map.WORLD_W & 0xFF);
        buf[1] = @intCast((map.WORLD_W >> 8) & 0xFF);
        buf[2] = @intCast(map.WORLD_H & 0xFF);
        buf[3] = @intCast((map.WORLD_H >> 8) & 0xFF);
        buf[4] = @intCast(tc & 0xFF);
        buf[5] = @intCast((tc >> 8) & 0xFF);
        buf[6] = 0;
        buf[7] = 0;

        // Grid.
        @memcpy(buf[8..][0..grid_size], &map.data);

        // Props.
        @memcpy(buf[8 + grid_size ..][0..props_size], map.PROPS[0..props_size]);

        const file = std.fs.cwd().createFile(
            "src/averain/assets/world.map",
            .{},
        ) catch return;
        defer file.close();
        file.writeAll(&buf) catch return;
        self.dirty = false;
    }

    fn track_camera(self: *Editor) void {
        const ts: i32 = @intCast(map.TILE_SIZE);
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

    fn draw_map(self: *const Editor, gfx: *Graphics, sheet: Sprite) void {
        const ts: i32 = @intCast(map.TILE_SIZE);
        const view_w: i32 = @as(i32, Graphics.WIDTH) - @as(i32, PANEL_W);

        const first_col: u32 = @intCast(@max(0, @divTrunc(self.cam_x, ts)));
        const first_row: u32 = @intCast(@max(0, @divTrunc(self.cam_y, ts)));
        const vis_cols: u32 = @intCast(@divTrunc(view_w, ts) + 2);
        const vis_rows: u32 = @intCast(@divTrunc(@as(i32, Graphics.HEIGHT), ts) + 2);
        const last_col = @min(first_col + vis_cols, map.WORLD_W);
        const last_row = @min(first_row + vis_rows, map.WORLD_H);

        for (first_row..last_row) |row| {
            for (first_col..last_col) |col| {
                const tid = map.data[row * map.WORLD_W + col];
                if (tid == 0) continue;
                const dx: i32 = @as(i32, @intCast(col)) * ts - self.cam_x;
                const dy: i32 = @as(i32, @intCast(row)) * ts - self.cam_y;
                if (dx + ts <= 0 or dx >= view_w) continue;
                if (dy + ts <= 0 or dy >= Graphics.HEIGHT) continue;
                gfx.blit_frame(sheet, tid, dx, dy, false);
            }
        }
    }

    fn draw_panel(self: *const Editor, gfx: *Graphics, sheet: Sprite) void {
        const px: i32 = @intCast(Graphics.WIDTH - PANEL_W);
        gfx.panel(px, 0, PANEL_W, Graphics.HEIGHT, C_BG, C_BORDER);

        // Selected tile preview.
        const ts: i32 = @intCast(map.TILE_SIZE);
        gfx.blit_frame(sheet, self.sel, px + 4, 2, false);

        // Tile palette.
        const cols_per_row: u8 = @intCast((PANEL_W - 8) / map.TILE_SIZE);
        const tile_count: u8 = @intCast(map.TILE_COUNT);

        for (1..@as(usize, tile_count) + 1) |i| {
            const ci: u8 = @intCast(i - 1);
            const col: i32 = @intCast(ci % cols_per_row);
            const row: i32 = @intCast(ci / cols_per_row);
            const tx = px + 4 + col * ts;
            const ty: i32 = 20 + row * ts;
            gfx.blit_frame(sheet, @intCast(i), tx, ty, false);

            if (i == self.sel) {
                gfx.rect(tx, ty, map.TILE_SIZE, 1, C_CURSOR);
                gfx.rect(tx, ty + ts - 1, map.TILE_SIZE, 1, C_CURSOR);
                gfx.rect(tx, ty, 1, map.TILE_SIZE, C_CURSOR);
                gfx.rect(tx + ts - 1, ty, 1, map.TILE_SIZE, C_CURSOR);
            }
        }

        // Dirty indicator.
        if (self.dirty) {
            gfx.text("*", px + @as(i32, PANEL_W) - 12, 2, C_SOLID);
        }
    }
};
