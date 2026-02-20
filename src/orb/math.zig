/// Fixed-point arithmetic, 2D vectors, and easing functions.
/// Intermediate products use i64 to prevent overflow.

const std = @import("std");

pub const FixedPoint = struct {
    raw: i32,

    const FRAC_BITS = 16;
    const HALF = 1 << (FRAC_BITS - 1);

    /// Zero in fixed point.
    pub const ZERO = FixedPoint{ .raw = 0 };
    /// One in fixed point.
    pub const ONE = FixedPoint{ .raw = 1 << FRAC_BITS };

    /// Universal constructor. Accepts int, float literal, or FixedPoint.
    pub fn init(v: anytype) FixedPoint {
        const T = @TypeOf(v);
        if (T == FixedPoint) return v;
        return switch (@typeInfo(T)) {
            .comptime_int => .{ .raw = @as(i32, v) << FRAC_BITS },
            .int => .{ .raw = @as(i32, @intCast(v)) << FRAC_BITS },
            .comptime_float => .{ .raw = @as(i32, @intFromFloat(v * @as(comptime_float, 1 << FRAC_BITS))) },
            else => @compileError("FixedPoint.init: expected int, float, or FixedPoint"),
        };
    }

    /// Fraction num/den to fixed. More precise than init for rationals.
    pub fn frac(num: i32, den: i32) FixedPoint {
        return .{ .raw = @intCast(@divTrunc(@as(i64, num) << FRAC_BITS, den)) };
    }

    pub fn add(a: FixedPoint, b: FixedPoint) FixedPoint {
        return .{ .raw = a.raw + b.raw };
    }

    pub fn sub(a: FixedPoint, b: FixedPoint) FixedPoint {
        return .{ .raw = a.raw - b.raw };
    }

    pub fn mul(a: FixedPoint, b: FixedPoint) FixedPoint {
        return .{ .raw = @intCast(@as(i64, a.raw) * @as(i64, b.raw) >> FRAC_BITS) };
    }

    pub fn div(a: FixedPoint, b: FixedPoint) FixedPoint {
        return .{ .raw = @intCast(@divTrunc(@as(i64, a.raw) << FRAC_BITS, b.raw)) };
    }

    pub fn neg(self: FixedPoint) FixedPoint {
        return .{ .raw = -self.raw };
    }

    pub fn abs(self: FixedPoint) FixedPoint {
        return .{ .raw = if (self.raw < 0) -self.raw else self.raw };
    }

    /// Truncate toward zero.
    pub fn trunc(self: FixedPoint) i32 {
        if (self.raw >= 0) return self.raw >> FRAC_BITS;
        return -((-self.raw) >> FRAC_BITS);
    }

    /// Round to nearest integer (half rounds away from zero).
    pub fn round(self: FixedPoint) i32 {
        if (self.raw >= 0) return (self.raw + HALF) >> FRAC_BITS;
        return -((-self.raw + HALF) >> FRAC_BITS);
    }

    pub fn gt(a: FixedPoint, b: FixedPoint) bool {
        return a.raw > b.raw;
    }

    pub fn lt(a: FixedPoint, b: FixedPoint) bool {
        return a.raw < b.raw;
    }

    pub fn gte(a: FixedPoint, b: FixedPoint) bool {
        return a.raw >= b.raw;
    }

    /// Smoothstep: 3t^2 - 2t^3, maps 0..dur to 0..range.
    pub fn smooth(t: FixedPoint, dur: FixedPoint, range: FixedPoint) FixedPoint {
        if (t.raw <= 0) return ZERO;
        if (t.gte(dur)) return range;
        const x = t.div(dur);
        const x2 = x.mul(x);
        const x3 = x2.mul(x);
        return init(3).mul(x2).sub(init(2).mul(x3)).mul(range);
    }

    /// Quadratic ease out: fast start, decelerates to stop.
    pub fn out_quad(t: FixedPoint, dur: FixedPoint, range: FixedPoint) FixedPoint {
        if (t.raw <= 0) return ZERO;
        if (t.gte(dur)) return range;
        const x = t.div(dur);
        return init(2).mul(x).sub(x.mul(x)).mul(range);
    }

    /// Quadratic ease in: accelerates from stop.
    pub fn in_quad(t: FixedPoint, dur: FixedPoint, range: FixedPoint) FixedPoint {
        if (t.raw <= 0) return ZERO;
        if (t.gte(dur)) return range;
        const x = t.div(dur);
        return x.mul(x).mul(range);
    }
};

pub const Vec2 = struct {
    x: FixedPoint,
    y: FixedPoint,

    /// Origin (0, 0).
    pub const ZERO = Vec2{ .x = FixedPoint.ZERO, .y = FixedPoint.ZERO };

    /// Universal constructor. Accepts int, float literal, or FixedPoint per axis.
    pub fn init(x: anytype, y: anytype) Vec2 {
        return .{ .x = FixedPoint.init(x), .y = FixedPoint.init(y) };
    }

    pub fn add(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x.add(b.x), .y = a.y.add(b.y) };
    }

    pub fn sub(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x.sub(b.x), .y = a.y.sub(b.y) };
    }

    pub fn scale(self: Vec2, s: FixedPoint) Vec2 {
        return .{ .x = self.x.mul(s), .y = self.y.mul(s) };
    }

    pub fn round(self: Vec2) [2]i32 {
        return .{ self.x.round(), self.y.round() };
    }
};

/// Return type for generic easing. Matches range parameter type.
fn Eased(comptime T: type) type {
    if (T == Vec2) return Vec2;
    if (T == FixedPoint) return FixedPoint;
    return i32;
}

/// Coerce any integer type to i32 for easing functions.
fn to_i32(v: anytype) i32 {
    return switch (@typeInfo(@TypeOf(v))) {
        .comptime_int => @as(i32, v),
        .int => @as(i32, @intCast(v)),
        else => @compileError("expected integer"),
    };
}

/// Generic smoothstep. Accepts i32, FixedPoint, or Vec2 range.
pub fn smooth(t: anytype, dur: anytype, range: anytype) Eased(@TypeOf(range)) {
    const R = @TypeOf(range);
    if (R == Vec2) {
        const ft = FixedPoint.init(t);
        const fd = FixedPoint.init(dur);
        return .{ .x = FixedPoint.smooth(ft, fd, range.x), .y = FixedPoint.smooth(ft, fd, range.y) };
    }
    if (R == FixedPoint) return FixedPoint.smooth(FixedPoint.init(t), FixedPoint.init(dur), range);
    return smooth_int(to_i32(t), to_i32(dur), to_i32(range));
}

/// Generic quadratic ease out. Accepts i32, FixedPoint, or Vec2 range.
pub fn out_quad(t: anytype, dur: anytype, range: anytype) Eased(@TypeOf(range)) {
    const R = @TypeOf(range);
    if (R == Vec2) {
        const ft = FixedPoint.init(t);
        const fd = FixedPoint.init(dur);
        return .{ .x = FixedPoint.out_quad(ft, fd, range.x), .y = FixedPoint.out_quad(ft, fd, range.y) };
    }
    if (R == FixedPoint) return FixedPoint.out_quad(FixedPoint.init(t), FixedPoint.init(dur), range);
    return out_quad_int(to_i32(t), to_i32(dur), to_i32(range));
}

/// Generic quadratic ease in. Accepts i32, FixedPoint, or Vec2 range.
pub fn in_quad(t: anytype, dur: anytype, range: anytype) Eased(@TypeOf(range)) {
    const R = @TypeOf(range);
    if (R == Vec2) {
        const ft = FixedPoint.init(t);
        const fd = FixedPoint.init(dur);
        return .{ .x = FixedPoint.in_quad(ft, fd, range.x), .y = FixedPoint.in_quad(ft, fd, range.y) };
    }
    if (R == FixedPoint) return FixedPoint.in_quad(FixedPoint.init(t), FixedPoint.init(dur), range);
    return in_quad_int(to_i32(t), to_i32(dur), to_i32(range));
}

/// Smoothstep for integer values. Uses i64 intermediates to prevent overflow.
fn smooth_int(t: i32, dur: i32, range: i32) i32 {
    if (t <= 0) return 0;
    if (t >= dur) return range;
    const t64: i64 = t;
    const d64: i64 = dur;
    const r64: i64 = range;
    return @intCast(@divTrunc(t64 * t64 * (3 * d64 - 2 * t64) * r64, d64 * d64 * d64));
}

/// Quadratic ease out for integer values.
fn out_quad_int(t: i32, dur: i32, range: i32) i32 {
    if (t <= 0) return 0;
    if (t >= dur) return range;
    return @divTrunc(t * (2 * dur - t) * range, dur * dur);
}

/// Quadratic ease in for integer values.
fn in_quad_int(t: i32, dur: i32, range: i32) i32 {
    if (t <= 0) return 0;
    if (t >= dur) return range;
    return @divTrunc(t * t * range, dur * dur);
}

test "init and frac" {
    try std.testing.expectEqual(@as(i32, 65536), FixedPoint.init(1).raw);
    try std.testing.expectEqual(@as(i32, -65536), FixedPoint.init(-1).raw);
    try std.testing.expectEqual(@as(i32, 32768), FixedPoint.frac(1, 2).raw);
}

test "init float literal" {
    try std.testing.expectEqual(@as(i32, 98304), FixedPoint.init(1.5).raw);
    try std.testing.expectEqual(@as(i32, 16384), FixedPoint.init(0.25).raw);
}

test "add and sub" {
    const a = FixedPoint.init(3);
    const b = FixedPoint.frac(1, 2);
    try std.testing.expectEqual(@as(i32, 4), a.add(b).round());
    try std.testing.expectEqual(@as(i32, 3), a.sub(b).round());
}

test "mul" {
    try std.testing.expectEqual(@as(i32, 6), FixedPoint.frac(3, 2).mul(FixedPoint.init(4)).round());
    try std.testing.expectEqual(@as(i32, -6), FixedPoint.frac(-3, 2).mul(FixedPoint.init(4)).round());
}

test "div" {
    try std.testing.expectEqual(@as(i32, 3), FixedPoint.init(10).div(FixedPoint.init(3)).trunc());
}

test "trunc toward zero" {
    try std.testing.expectEqual(@as(i32, 1), FixedPoint.frac(3, 2).trunc());
    try std.testing.expectEqual(@as(i32, -1), FixedPoint.frac(-3, 2).trunc());
}

test "round to nearest" {
    try std.testing.expectEqual(@as(i32, 2), FixedPoint.frac(3, 2).round());
    try std.testing.expectEqual(@as(i32, -2), FixedPoint.frac(-3, 2).round());
    try std.testing.expectEqual(@as(i32, 1), FixedPoint.frac(3, 4).round());
    try std.testing.expectEqual(@as(i32, 0), FixedPoint.frac(1, 4).round());
}

test "fixed smooth boundaries" {
    const dur = FixedPoint.init(20);
    const range = FixedPoint.init(100);
    try std.testing.expectEqual(@as(i32, 0), FixedPoint.smooth(FixedPoint.ZERO, dur, range).round());
    try std.testing.expectEqual(@as(i32, 100), FixedPoint.smooth(dur, dur, range).round());
}

test "fixed smooth midpoint" {
    try std.testing.expectEqual(@as(i32, 50), FixedPoint.smooth(FixedPoint.init(10), FixedPoint.init(20), FixedPoint.init(100)).round());
}

test "fixed smooth is slow at edges" {
    const dur = FixedPoint.init(20);
    const range = FixedPoint.init(100);
    try std.testing.expect(FixedPoint.smooth(FixedPoint.init(5), dur, range).lt(FixedPoint.init(25)));
    try std.testing.expect(FixedPoint.smooth(FixedPoint.init(15), dur, range).gt(FixedPoint.init(75)));
}

test "vec2 init and add" {
    const a = Vec2.init(3, 4);
    const b = Vec2.init(1, 2);
    const c = a.add(b);
    try std.testing.expectEqual(@as(i32, 4), c.x.round());
    try std.testing.expectEqual(@as(i32, 6), c.y.round());
}

test "vec2 scale" {
    const v = Vec2.init(5, 10);
    const s = v.scale(FixedPoint.frac(1, 2));
    const r = s.round();
    try std.testing.expectEqual(@as(i32, 3), r[0]);
    try std.testing.expectEqual(@as(i32, 5), r[1]);
}

test "out_quad boundaries" {
    try std.testing.expectEqual(@as(i32, 0), out_quad(0, 20, 100));
    try std.testing.expectEqual(@as(i32, 100), out_quad(20, 20, 100));
}

test "out_quad midpoint past halfway" {
    try std.testing.expect(out_quad(10, 20, 100) > 50);
}

test "in_quad boundaries" {
    try std.testing.expectEqual(@as(i32, 0), in_quad(0, 20, 100));
    try std.testing.expectEqual(@as(i32, 100), in_quad(20, 20, 100));
}

test "in_quad midpoint before halfway" {
    try std.testing.expect(in_quad(10, 20, 100) < 50);
}

test "smooth boundaries" {
    try std.testing.expectEqual(@as(i32, 0), smooth(0, 20, 100));
    try std.testing.expectEqual(@as(i32, 100), smooth(20, 20, 100));
}

test "smooth midpoint at halfway" {
    try std.testing.expectEqual(@as(i32, 50), smooth(10, 20, 100));
}

test "smooth is slow at edges fast in middle" {
    try std.testing.expect(smooth(5, 20, 100) < 25);
    try std.testing.expect(smooth(15, 20, 100) > 75);
}

test "generic smooth with FixedPoint" {
    const r = smooth(@as(i32, 10), @as(i32, 20), FixedPoint.init(100));
    try std.testing.expectEqual(@as(i32, 50), r.round());
}

test "generic smooth with Vec2" {
    const range = Vec2.init(100, 200);
    const r = smooth(@as(i32, 10), @as(i32, 20), range);
    try std.testing.expectEqual(@as(i32, 50), r.x.round());
    try std.testing.expectEqual(@as(i32, 100), r.y.round());
}

test "fixed out_quad midpoint past halfway" {
    const r = FixedPoint.out_quad(FixedPoint.init(10), FixedPoint.init(20), FixedPoint.init(100));
    try std.testing.expect(r.gt(FixedPoint.init(50)));
}

test "fixed in_quad midpoint before halfway" {
    const r = FixedPoint.in_quad(FixedPoint.init(10), FixedPoint.init(20), FixedPoint.init(100));
    try std.testing.expect(r.lt(FixedPoint.init(50)));
}
