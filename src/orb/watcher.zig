/// inotify-based file watcher for hot reload (Linux, dev builds only).
/// Non-blocking poll watches a directory for CLOSE_WRITE events.
const std = @import("std");

const linux = std.os.linux;
const posix = std.posix;

/// Writable file was closed.
const IN_CLOSE_WRITE: u32 = 0x00000008;

/// File watcher backed by Linux inotify.
pub const Watcher = struct {
    fd: i32,
    wd: i32,

    /// Initialize a watcher on the given directory path.
    pub fn init(dir: [*:0]const u8) !Watcher {
        const fd = posix.inotify_init1(linux.EFD.NONBLOCK) catch return error.InotifyInit;
        const wd = posix.inotify_add_watchZ(fd, dir, IN_CLOSE_WRITE) catch {
            posix.close(fd);
            return error.InotifyWatch;
        };
        return .{ .fd = fd, .wd = wd };
    }

    /// Poll for a changed filename. Returns null if no events pending.
    pub fn poll(self: *Watcher) ?[]const u8 {
        var buf: [4096]u8 align(@alignOf(linux.inotify_event)) = undefined;
        const n = posix.read(self.fd, &buf) catch return null;
        if (n == 0) return null;

        var offset: usize = 0;
        while (offset + @sizeOf(linux.inotify_event) <= n) {
            const ev: *const linux.inotify_event = @ptrCast(@alignCast(buf[offset..].ptr));
            const name_off = offset + @sizeOf(linux.inotify_event);
            const name_end = name_off + ev.len;
            if (name_end > n) break;

            if (ev.len > 0) {
                const name_bytes = buf[name_off..name_end];
                var name_len: usize = 0;
                while (name_len < name_bytes.len and name_bytes[name_len] != 0) name_len += 1;
                if (name_len > 0) return name_bytes[0..name_len];
            }

            offset = name_end;
        }
        return null;
    }

    /// Drain all pending events without processing them.
    pub fn drain(self: *Watcher) void {
        var buf: [4096]u8 = undefined;
        while (true) {
            const n = posix.read(self.fd, &buf) catch break;
            if (n == 0) break;
        }
    }

    /// Close the inotify file descriptor.
    pub fn deinit(self: *Watcher) void {
        posix.close(self.fd);
    }
};
