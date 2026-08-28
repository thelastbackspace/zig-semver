//! Port of the upstream test suite (tap tests plus the table fixtures
//! in test/fixtures/) for node-semver v7.8.5. `ltr`/`gtr`/`outside`,
//! `subset`, `minVersion`, and the CLI are not part of this port and
//! their fixtures are not carried over.

const std = @import("std");
const sv = @import("root.zig");

const t = std.testing;

fn checkParse(input: []const u8, options: sv.Options, want: ?[]const u8) !void {
    const v = sv.Version.parse(input, options) catch {
        try t.expect(want == null);
        return;
    };
    try t.expect(want != null);
    const s = try v.toString(t.allocator);
    defer t.allocator.free(s);
    try t.expectEqualStrings(want.?, s);
}

fn checkSatisfies(version: []const u8, range: []const u8, options: sv.Options, want: bool) !void {
    const got = sv.satisfies(t.allocator, version, range, options);
    if (got != want) {
        std.debug.print("satisfies(\"{s}\", \"{s}\") = {}\n", .{ version, range, got });
        return error.TestUnexpectedResult;
    }
}

fn checkCanonical(range: []const u8, options: sv.Options, want: ?[]const u8) !void {
    var r = sv.Range.parse(t.allocator, range, options) catch {
        try t.expect(want == null);
        return;
    };
    defer r.deinit();
    try t.expect(want != null);
    const expected = if (std.mem.eql(u8, want.?, "*")) "" else want.?;
    try t.expectEqualStrings(expected, r.format());
}

fn checkCmp(a: []const u8, b: []const u8, options: sv.Options, op: sv.Operator) !void {
    const va = try sv.Version.parse(a, options);
    const vb = try sv.Version.parse(b, options);
    if (!sv.cmp(va, op, vb)) {
        std.debug.print("{s} {s} {s} failed\n", .{ a, @tagName(op), b });
        return error.TestUnexpectedResult;
    }
}

fn releaseFromName(name: []const u8) sv.Version.ReleaseType {
    inline for (@typeInfo(sv.Version.ReleaseType).@"enum".fields) |f| {
        if (std.mem.eql(u8, name, f.name)) return @field(sv.Version.ReleaseType, f.name);
    }
    unreachable;
}

fn idb(x: ?[]const u8) sv.IdentifierBase {
    if (x == null) return .default;
    if (x.?.len == 0) return .default;
    return .{ .value = x.? };
}

test "parse: valid versions" {
    {
        const ver = try sv.Version.parse("1.0.0", .{});
        try t.expectEqual(@as(u64, 1), ver.major);
        try t.expectEqual(@as(u64, 0), ver.minor);
        try t.expectEqual(@as(u64, 0), ver.patch);
    }
    {
        const ver = try sv.Version.parse("2.1.0", .{});
        try t.expectEqual(@as(u64, 2), ver.major);
        try t.expectEqual(@as(u64, 1), ver.minor);
        try t.expectEqual(@as(u64, 0), ver.patch);
    }
    {
        const ver = try sv.Version.parse("3.2.1", .{});
        try t.expectEqual(@as(u64, 3), ver.major);
        try t.expectEqual(@as(u64, 2), ver.minor);
        try t.expectEqual(@as(u64, 1), ver.patch);
    }
    {
        const ver = try sv.Version.parse("v1.2.3", .{});
        try t.expectEqual(@as(u64, 1), ver.major);
        try t.expectEqual(@as(u64, 2), ver.minor);
        try t.expectEqual(@as(u64, 3), ver.patch);
    }
    {
        const ver = try sv.Version.parse("1.2.3-0", .{});
        try t.expectEqual(@as(u64, 1), ver.major);
        try t.expectEqual(@as(u64, 2), ver.minor);
        try t.expectEqual(@as(u64, 3), ver.patch);
    }
    {
        const ver = try sv.Version.parse("1.2.3-123", .{});
        try t.expectEqual(@as(u64, 1), ver.major);
        try t.expectEqual(@as(u64, 2), ver.minor);
        try t.expectEqual(@as(u64, 3), ver.patch);
    }
    {
        const ver = try sv.Version.parse("1.2.3-1.2.3", .{});
        try t.expectEqual(@as(u64, 1), ver.major);
        try t.expectEqual(@as(u64, 2), ver.minor);
        try t.expectEqual(@as(u64, 3), ver.patch);
    }
    {
        const ver = try sv.Version.parse("1.2.3-1a", .{});
        try t.expectEqual(@as(u64, 1), ver.major);
        try t.expectEqual(@as(u64, 2), ver.minor);
        try t.expectEqual(@as(u64, 3), ver.patch);
    }
    {
        const ver = try sv.Version.parse("1.2.3-a1", .{});
        try t.expectEqual(@as(u64, 1), ver.major);
        try t.expectEqual(@as(u64, 2), ver.minor);
        try t.expectEqual(@as(u64, 3), ver.patch);
    }
    {
        const ver = try sv.Version.parse("1.2.3-alpha", .{});
        try t.expectEqual(@as(u64, 1), ver.major);
        try t.expectEqual(@as(u64, 2), ver.minor);
        try t.expectEqual(@as(u64, 3), ver.patch);
    }
    {
        const ver = try sv.Version.parse("1.2.3-alpha.1", .{});
        try t.expectEqual(@as(u64, 1), ver.major);
        try t.expectEqual(@as(u64, 2), ver.minor);
        try t.expectEqual(@as(u64, 3), ver.patch);
    }
    {
        const ver = try sv.Version.parse("1.2.3-alpha-1", .{});
        try t.expectEqual(@as(u64, 1), ver.major);
        try t.expectEqual(@as(u64, 2), ver.minor);
        try t.expectEqual(@as(u64, 3), ver.patch);
    }
    {
        const ver = try sv.Version.parse("1.2.3-alpha-.-beta", .{});
        try t.expectEqual(@as(u64, 1), ver.major);
        try t.expectEqual(@as(u64, 2), ver.minor);
        try t.expectEqual(@as(u64, 3), ver.patch);
    }
    {
        const ver = try sv.Version.parse("1.2.3+456", .{});
        try t.expectEqual(@as(u64, 1), ver.major);
        try t.expectEqual(@as(u64, 2), ver.minor);
        try t.expectEqual(@as(u64, 3), ver.patch);
    }
    {
        const ver = try sv.Version.parse("1.2.3+build", .{});
        try t.expectEqual(@as(u64, 1), ver.major);
        try t.expectEqual(@as(u64, 2), ver.minor);
        try t.expectEqual(@as(u64, 3), ver.patch);
    }
    {
        const ver = try sv.Version.parse("1.2.3+new-build", .{});
        try t.expectEqual(@as(u64, 1), ver.major);
        try t.expectEqual(@as(u64, 2), ver.minor);
        try t.expectEqual(@as(u64, 3), ver.patch);
    }
    {
        const ver = try sv.Version.parse("1.2.3+build.1", .{});
        try t.expectEqual(@as(u64, 1), ver.major);
        try t.expectEqual(@as(u64, 2), ver.minor);
        try t.expectEqual(@as(u64, 3), ver.patch);
    }
    {
        const ver = try sv.Version.parse("1.2.3+build.1a", .{});
        try t.expectEqual(@as(u64, 1), ver.major);
        try t.expectEqual(@as(u64, 2), ver.minor);
        try t.expectEqual(@as(u64, 3), ver.patch);
    }
    {
        const ver = try sv.Version.parse("1.2.3+build.a1", .{});
        try t.expectEqual(@as(u64, 1), ver.major);
        try t.expectEqual(@as(u64, 2), ver.minor);
        try t.expectEqual(@as(u64, 3), ver.patch);
    }
    {
        const ver = try sv.Version.parse("1.2.3+build.alpha", .{});
        try t.expectEqual(@as(u64, 1), ver.major);
        try t.expectEqual(@as(u64, 2), ver.minor);
        try t.expectEqual(@as(u64, 3), ver.patch);
    }
    {
        const ver = try sv.Version.parse("1.2.3+build.alpha.beta", .{});
        try t.expectEqual(@as(u64, 1), ver.major);
        try t.expectEqual(@as(u64, 2), ver.minor);
        try t.expectEqual(@as(u64, 3), ver.patch);
    }
    {
        const ver = try sv.Version.parse("1.2.3-alpha+build", .{});
        try t.expectEqual(@as(u64, 1), ver.major);
        try t.expectEqual(@as(u64, 2), ver.minor);
        try t.expectEqual(@as(u64, 3), ver.patch);
    }
}
test "parse: invalid versions" {
    try checkParse("hello, world", .{}, null);
    var long = std.ArrayList(u8).empty;
    defer long.deinit(t.allocator);
    for (0..256) |_| try long.append(t.allocator, '1');
    try checkParse(long.items, .{}, null);
    try checkParse("90071992547409910.0.0", .{}, null);
    try checkParse("0.90071992547409910.0", .{}, null);
    try checkParse("0.0.90071992547409910", .{}, null);
}
test "equality (loose)" {
    try checkCmp("1.2.3", "v1.2.3", .{ .loose = true }, .eq);
    try checkCmp("1.2.3", "=1.2.3", .{ .loose = true }, .eq);
    try checkCmp("1.2.3", "v 1.2.3", .{ .loose = true }, .eq);
    try checkCmp("1.2.3", "= 1.2.3", .{ .loose = true }, .eq);
    try checkCmp("1.2.3", " v1.2.3", .{ .loose = true }, .eq);
    try checkCmp("1.2.3", " =1.2.3", .{ .loose = true }, .eq);
    try checkCmp("1.2.3", " v 1.2.3", .{ .loose = true }, .eq);
    try checkCmp("1.2.3", " = 1.2.3", .{ .loose = true }, .eq);
    try checkCmp("1.2.3-0", "v1.2.3-0", .{ .loose = true }, .eq);
    try checkCmp("1.2.3-0", "=1.2.3-0", .{ .loose = true }, .eq);
    try checkCmp("1.2.3-0", "v 1.2.3-0", .{ .loose = true }, .eq);
    try checkCmp("1.2.3-0", "= 1.2.3-0", .{ .loose = true }, .eq);
    try checkCmp("1.2.3-0", " v1.2.3-0", .{ .loose = true }, .eq);
    try checkCmp("1.2.3-0", " =1.2.3-0", .{ .loose = true }, .eq);
    try checkCmp("1.2.3-0", " v 1.2.3-0", .{ .loose = true }, .eq);
    try checkCmp("1.2.3-0", " = 1.2.3-0", .{ .loose = true }, .eq);
    try checkCmp("1.2.3-1", "v1.2.3-1", .{ .loose = true }, .eq);
    try checkCmp("1.2.3-1", "=1.2.3-1", .{ .loose = true }, .eq);
    try checkCmp("1.2.3-1", "v 1.2.3-1", .{ .loose = true }, .eq);
    try checkCmp("1.2.3-1", "= 1.2.3-1", .{ .loose = true }, .eq);
    try checkCmp("1.2.3-1", " v1.2.3-1", .{ .loose = true }, .eq);
    try checkCmp("1.2.3-1", " =1.2.3-1", .{ .loose = true }, .eq);
    try checkCmp("1.2.3-1", " v 1.2.3-1", .{ .loose = true }, .eq);
    try checkCmp("1.2.3-1", " = 1.2.3-1", .{ .loose = true }, .eq);
    try checkCmp("1.2.3-beta", "v1.2.3-beta", .{ .loose = true }, .eq);
    try checkCmp("1.2.3-beta", "=1.2.3-beta", .{ .loose = true }, .eq);
    try checkCmp("1.2.3-beta", "v 1.2.3-beta", .{ .loose = true }, .eq);
    try checkCmp("1.2.3-beta", "= 1.2.3-beta", .{ .loose = true }, .eq);
    try checkCmp("1.2.3-beta", " v1.2.3-beta", .{ .loose = true }, .eq);
    try checkCmp("1.2.3-beta", " =1.2.3-beta", .{ .loose = true }, .eq);
    try checkCmp("1.2.3-beta", " v 1.2.3-beta", .{ .loose = true }, .eq);
    try checkCmp("1.2.3-beta", " = 1.2.3-beta", .{ .loose = true }, .eq);
    try checkCmp("1.2.3-beta+build", " = 1.2.3-beta+otherbuild", .{ .loose = true }, .eq);
    try checkCmp("1.2.3+build", " = 1.2.3+otherbuild", .{ .loose = true }, .eq);
    try checkCmp("1.2.3-beta+build", "1.2.3-beta+otherbuild", .{}, .eq);
    try checkCmp("1.2.3+build", "1.2.3+otherbuild", .{}, .eq);
    try checkCmp("  v1.2.3+build", "1.2.3+otherbuild", .{}, .eq);
}
test "comparisons: v1 > v2 and v2 < v1" {
    try checkCmp("0.0.0", "0.0.0-foo", .{}, .gt);
    try checkCmp("0.0.0-foo", "0.0.0", .{}, .lt);
    try checkCmp("0.0.1", "0.0.0", .{}, .gt);
    try checkCmp("0.0.0", "0.0.1", .{}, .lt);
    try checkCmp("1.0.0", "0.9.9", .{}, .gt);
    try checkCmp("0.9.9", "1.0.0", .{}, .lt);
    try checkCmp("0.10.0", "0.9.0", .{}, .gt);
    try checkCmp("0.9.0", "0.10.0", .{}, .lt);
    try checkCmp("0.99.0", "0.10.0", .{}, .gt);
    try checkCmp("0.10.0", "0.99.0", .{}, .lt);
    try checkCmp("2.0.0", "1.2.3", .{}, .gt);
    try checkCmp("1.2.3", "2.0.0", .{}, .lt);
    try checkCmp("v0.0.0", "0.0.0-foo", .{ .loose = true }, .gt);
    try checkCmp("0.0.0-foo", "v0.0.0", .{ .loose = true }, .lt);
    try checkCmp("v0.0.1", "0.0.0", .{ .loose = true }, .gt);
    try checkCmp("0.0.0", "v0.0.1", .{ .loose = true }, .lt);
    try checkCmp("v1.0.0", "0.9.9", .{ .loose = true }, .gt);
    try checkCmp("0.9.9", "v1.0.0", .{ .loose = true }, .lt);
    try checkCmp("v0.10.0", "0.9.0", .{ .loose = true }, .gt);
    try checkCmp("0.9.0", "v0.10.0", .{ .loose = true }, .lt);
    try checkCmp("v0.99.0", "0.10.0", .{ .loose = true }, .gt);
    try checkCmp("0.10.0", "v0.99.0", .{ .loose = true }, .lt);
    try checkCmp("v2.0.0", "1.2.3", .{ .loose = true }, .gt);
    try checkCmp("1.2.3", "v2.0.0", .{ .loose = true }, .lt);
    try checkCmp("0.0.0", "v0.0.0-foo", .{ .loose = true }, .gt);
    try checkCmp("v0.0.0-foo", "0.0.0", .{ .loose = true }, .lt);
    try checkCmp("0.0.1", "v0.0.0", .{ .loose = true }, .gt);
    try checkCmp("v0.0.0", "0.0.1", .{ .loose = true }, .lt);
    try checkCmp("1.0.0", "v0.9.9", .{ .loose = true }, .gt);
    try checkCmp("v0.9.9", "1.0.0", .{ .loose = true }, .lt);
    try checkCmp("0.10.0", "v0.9.0", .{ .loose = true }, .gt);
    try checkCmp("v0.9.0", "0.10.0", .{ .loose = true }, .lt);
    try checkCmp("0.99.0", "v0.10.0", .{ .loose = true }, .gt);
    try checkCmp("v0.10.0", "0.99.0", .{ .loose = true }, .lt);
    try checkCmp("2.0.0", "v1.2.3", .{ .loose = true }, .gt);
    try checkCmp("v1.2.3", "2.0.0", .{ .loose = true }, .lt);
    try checkCmp("1.2.3", "1.2.3-asdf", .{}, .gt);
    try checkCmp("1.2.3-asdf", "1.2.3", .{}, .lt);
    try checkCmp("1.2.3", "1.2.3-4", .{}, .gt);
    try checkCmp("1.2.3-4", "1.2.3", .{}, .lt);
    try checkCmp("1.2.3", "1.2.3-4-foo", .{}, .gt);
    try checkCmp("1.2.3-4-foo", "1.2.3", .{}, .lt);
    try checkCmp("1.2.3-5-foo", "1.2.3-5", .{}, .gt);
    try checkCmp("1.2.3-5", "1.2.3-5-foo", .{}, .lt);
    try checkCmp("1.2.3-5", "1.2.3-4", .{}, .gt);
    try checkCmp("1.2.3-4", "1.2.3-5", .{}, .lt);
    try checkCmp("1.2.3-5-foo", "1.2.3-5-Foo", .{}, .gt);
    try checkCmp("1.2.3-5-Foo", "1.2.3-5-foo", .{}, .lt);
    try checkCmp("3.0.0", "2.7.2+asdf", .{}, .gt);
    try checkCmp("2.7.2+asdf", "3.0.0", .{}, .lt);
    try checkCmp("1.2.3-a.10", "1.2.3-a.5", .{}, .gt);
    try checkCmp("1.2.3-a.5", "1.2.3-a.10", .{}, .lt);
    try checkCmp("1.2.3-a.b", "1.2.3-a.5", .{}, .gt);
    try checkCmp("1.2.3-a.5", "1.2.3-a.b", .{}, .lt);
    try checkCmp("1.2.3-a.b", "1.2.3-a", .{}, .gt);
    try checkCmp("1.2.3-a", "1.2.3-a.b", .{}, .lt);
    try checkCmp("1.2.3-a.b.c.10.d.5", "1.2.3-a.b.c.5.d.100", .{}, .gt);
    try checkCmp("1.2.3-a.b.c.5.d.100", "1.2.3-a.b.c.10.d.5", .{}, .lt);
    try checkCmp("1.2.3-r2", "1.2.3-r100", .{}, .gt);
    try checkCmp("1.2.3-r100", "1.2.3-r2", .{}, .lt);
    try checkCmp("1.2.3-r100", "1.2.3-R2", .{}, .gt);
    try checkCmp("1.2.3-R2", "1.2.3-r100", .{}, .lt);
}
test "increments" {
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("major"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("2.0.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("minor"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.3.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("patch"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.4", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3tag", .{ .loose = true });
        const r = try v.inc(arena.allocator(), releaseFromName("major"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("2.0.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-tag", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("major"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("2.0.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.0-0", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("patch"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.0", s);
    }
    {
        if (sv.Version.parse("fake", .{}) catch null) |v| {
            if (v.inc(t.allocator, releaseFromName("major"), null, idb(null)) catch null) |_| {
                return error.TestUnexpectedResult;
            }
        }
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-4", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("major"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("2.0.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-4", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("minor"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.3.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-4", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("patch"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.0.beta", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("major"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("2.0.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.0.beta", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("minor"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.3.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.0.beta", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("patch"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.4", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.5-0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-0", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-1", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.0", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha.1", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha.2", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.2", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha.3", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.0.beta", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha.1.beta", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.1.beta", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha.2.beta", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.2.beta", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha.3.beta", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.10.0.beta", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha.10.1.beta", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.10.1.beta", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha.10.2.beta", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.10.2.beta", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha.10.3.beta", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.10.beta.0", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha.10.beta.1", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.10.beta.1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha.10.beta.2", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.10.beta.2", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha.10.beta.3", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("3.0.0-alpha.beta.5.4", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "alpha.beta", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("3.0.0-alpha.beta.5.5", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("3.0.0-alpha.beta.5.4", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "alpha.beta.5", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("3.0.0-alpha.beta.5.5", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("3.0.0-alpha.beta.gamma", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "alpha.beta", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("3.0.0-alpha.beta.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.9.beta", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha.10.beta", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.10.beta", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha.11.beta", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.11.beta", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha.12.beta", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.0.0", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prepatch"), "alpha.1.1a", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.0.1-alpha.1.1a.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.0", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prepatch"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.1-0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.0-1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prepatch"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.1-0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.0", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("preminor"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.3.0-0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("preminor"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.3.0-0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.0", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("premajor"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("2.0.0-0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("premajor"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("2.0.0-0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.0-1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("minor"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.0.0-1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("major"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.0.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.0.0-1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("release"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.0.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.0-1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("release"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("release"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3", s);
    }
    {
        if (sv.Version.parse("1.2.3", .{}) catch null) |v| {
            if (v.inc(t.allocator, releaseFromName("release"), null, idb(null)) catch null) |_| {
                return error.TestUnexpectedResult;
            }
        }
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("major"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("2.0.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("minor"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.3.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("patch"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.4", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3tag", .{ .loose = true });
        const r = try v.inc(arena.allocator(), releaseFromName("major"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("2.0.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-tag", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("major"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("2.0.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.0-0", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("patch"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.0", s);
    }
    {
        if (sv.Version.parse("fake", .{}) catch null) |v| {
            if (v.inc(t.allocator, releaseFromName("major"), "dev", idb(null)) catch null) |_| {
                return error.TestUnexpectedResult;
            }
        }
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-4", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("major"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("2.0.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-4", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("minor"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.3.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-4", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("patch"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.0.beta", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("major"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("2.0.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.0.beta", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("minor"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.3.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.0.beta", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("patch"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.4", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.5-dev.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-0", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-dev.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.0", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-dev.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.0", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "alpha", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha.1", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.0.beta", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-dev.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.0.beta", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "alpha", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha.1.beta", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.10.0.beta", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-dev.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.10.0.beta", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "alpha", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha.10.1.beta", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.10.1.beta", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "alpha", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha.10.2.beta", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.10.2.beta", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "alpha", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha.10.3.beta", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.10.beta.0", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-dev.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.10.beta.0", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "alpha", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha.10.beta.1", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.10.beta.1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "alpha", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha.10.beta.2", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.10.beta.2", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "alpha", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha.10.beta.3", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("3.0.0-alpha.beta.5.4", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "alpha.beta", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("3.0.0-alpha.beta.5.5", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("3.0.0-alpha.beta.5.4", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "alpha.beta.5", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("3.0.0-alpha.beta.5.5", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("3.0.0-alpha.beta.gamma", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "alpha.beta", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("3.0.0-alpha.beta.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.9.beta", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-dev.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.9.beta", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "alpha", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha.10.beta", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.10.beta", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "alpha", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha.11.beta", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-alpha.11.beta", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "alpha", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha.12.beta", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.0", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prepatch"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.1-dev.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.0-1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prepatch"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.1-dev.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.0", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("preminor"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.3.0-dev.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("preminor"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.3.0-dev.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.0", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("premajor"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("2.0.0-dev.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("premajor"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("2.0.0-dev.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("premajor"), "dev", idb("1"));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("2.0.0-dev.1", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.0-1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("minor"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.0.0-1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("major"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.0.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-dev.bar", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-dev.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-0", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "1", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-1.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-1.0", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "1", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-1.1", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-1.1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "1", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-1.2", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-1.1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "2", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-2.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.0-1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "alpha", idb("0"));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.0-alpha.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "alpha", idb("0"));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.2-alpha.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("0.2.0", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "alpha", idb("0"));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("0.2.1-alpha.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.2", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "alpha", idb("1"));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha.1", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "alpha", idb("1"));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.4-alpha.1", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.4", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "alpha", idb("1"));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.5-alpha.1", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.0", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prepatch"), "dev", idb("1"));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.1-dev.1", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.0-1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prepatch"), "dev", idb("1"));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.1-dev.1", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.0", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("premajor"), "dev", idb("0"));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("2.0.0-dev.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("premajor"), "dev", idb("0"));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("2.0.0-dev.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-dev.bar", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "dev", idb("0"));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-dev.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-dev.bar", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "dev", idb("1"));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-dev.1", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-dev.bar", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "", idb("0"));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-dev.bar.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-dev.bar", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "", idb("1"));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-dev.bar.1", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.0", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("preminor"), "dev", idb("1"));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.3.0-dev.1", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("preminor"), "dev", idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.3.0-dev.0", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.0", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "", idb("1"));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.1-1", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.0-1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "alpha", sv.IdentifierBase.off);
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.0-alpha", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "alpha", sv.IdentifierBase.off);
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.2-alpha", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.2", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "alpha", sv.IdentifierBase.off);
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-alpha", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.0", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prepatch"), "dev", sv.IdentifierBase.off);
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.1-dev", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.0-1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prepatch"), "dev", sv.IdentifierBase.off);
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.1-dev", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.0", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("premajor"), "dev", sv.IdentifierBase.off);
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("2.0.0-dev", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("premajor"), "dev", sv.IdentifierBase.off);
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("2.0.0-dev", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-dev.bar", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "dev", sv.IdentifierBase.off);
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-dev", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-dev.bar", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), "dev.baz", sv.IdentifierBase.off);
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.3-dev.baz", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.0", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("preminor"), "dev", sv.IdentifierBase.off);
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.3.0-dev", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.3-1", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("preminor"), "dev", sv.IdentifierBase.off);
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.3.0-dev", s);
    }
    {
        if (sv.Version.parse("1.2.3-dev", .{}) catch null) |v| {
            if (v.inc(t.allocator, releaseFromName("prerelease"), "dev", sv.IdentifierBase.off) catch null) |_| {
                return error.TestUnexpectedResult;
            }
        }
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.0-dev", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("premajor"), "dev", sv.IdentifierBase.off);
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("2.0.0-dev", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.0-dev", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("preminor"), "beta", sv.IdentifierBase.off);
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.3.0-beta", s);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.2.0-dev", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prepatch"), "dev", sv.IdentifierBase.off);
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.2.1-dev", s);
    }
    {
        if (sv.Version.parse("1.2.0", .{}) catch null) |v| {
            if (v.inc(t.allocator, releaseFromName("prerelease"), "", sv.IdentifierBase.off) catch null) |_| {
                return error.TestUnexpectedResult;
            }
        }
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const v = try sv.Version.parse("1.0.0-rc.1+build.4", .{});
        const r = try v.inc(arena.allocator(), releaseFromName("prerelease"), null, idb(null));
        const s = try r.toString(arena.allocator());
        try t.expectEqualStrings("1.0.0-rc.2", s);
    }
    {
        if (sv.Version.parse("1.2.0", .{}) catch null) |v| {
            if (v.inc(t.allocator, releaseFromName("prerelease"), "invalid/preid", idb(null)) catch null) |_| {
                return error.TestUnexpectedResult;
            }
        }
    }
    {
        if (sv.Version.parse("1.2.0", .{}) catch null) |v| {
            if (v.inc(t.allocator, releaseFromName("prerelease"), "invalid+build", idb(null)) catch null) |_| {
                return error.TestUnexpectedResult;
            }
        }
    }
    {
        if (sv.Version.parse("1.2.0beta", .{ .loose = true }) catch null) |v| {
            if (v.inc(t.allocator, releaseFromName("prerelease"), "invalid/preid", idb(null)) catch null) |_| {
                return error.TestUnexpectedResult;
            }
        }
    }
}
test "truncate" {
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const got = try sv.truncate(arena.allocator(), "1.2.3-foo", releaseFromName("patch"), .{});
        try t.expectEqualStrings("1.2.3", got.?);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const got = try sv.truncate(arena.allocator(), "1.2.3", releaseFromName("patch"), .{});
        try t.expectEqualStrings("1.2.3", got.?);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const got = try sv.truncate(arena.allocator(), "1.2.3", releaseFromName("minor"), .{});
        try t.expectEqualStrings("1.2.0", got.?);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const got = try sv.truncate(arena.allocator(), "1.2.3", releaseFromName("major"), .{});
        try t.expectEqualStrings("1.0.0", got.?);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const got = try sv.truncate(arena.allocator(), "4.5.6-rc2", releaseFromName("prerelease"), .{});
        try t.expectEqualStrings("4.5.6-rc2", got.?);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const got = try sv.truncate(arena.allocator(), "4.5.6-rc2", releaseFromName("prepatch"), .{});
        try t.expectEqualStrings("4.5.6-rc2", got.?);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const got = try sv.truncate(arena.allocator(), "4.5.6-rc2", releaseFromName("preminor"), .{});
        try t.expectEqualStrings("4.5.6-rc2", got.?);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const got = try sv.truncate(arena.allocator(), "4.5.6-rc2", releaseFromName("premajor"), .{});
        try t.expectEqualStrings("4.5.6-rc2", got.?);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const got = try sv.truncate(arena.allocator(), "4.5.6-rc2", releaseFromName("patch"), .{});
        try t.expectEqualStrings("4.5.6", got.?);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const got = try sv.truncate(arena.allocator(), "4.5.6-rc2", releaseFromName("minor"), .{});
        try t.expectEqualStrings("4.5.0", got.?);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const got = try sv.truncate(arena.allocator(), "4.5.6-rc2", releaseFromName("major"), .{});
        try t.expectEqualStrings("4.0.0", got.?);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const got = try sv.truncate(arena.allocator(), "4.5.6+dadb0d", releaseFromName("prerelease"), .{});
        try t.expectEqualStrings("4.5.6", got.?);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const got = try sv.truncate(arena.allocator(), "4.5.6+dadb0d", releaseFromName("prepatch"), .{});
        try t.expectEqualStrings("4.5.6", got.?);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const got = try sv.truncate(arena.allocator(), "4.5.6+dadb0d", releaseFromName("preminor"), .{});
        try t.expectEqualStrings("4.5.6", got.?);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const got = try sv.truncate(arena.allocator(), "4.5.6+dadb0d", releaseFromName("premajor"), .{});
        try t.expectEqualStrings("4.5.6", got.?);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const got = try sv.truncate(arena.allocator(), "4.5.6+dadb0d", releaseFromName("patch"), .{});
        try t.expectEqualStrings("4.5.6", got.?);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const got = try sv.truncate(arena.allocator(), "4.5.6+dadb0d", releaseFromName("minor"), .{});
        try t.expectEqualStrings("4.5.0", got.?);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const got = try sv.truncate(arena.allocator(), "4.5.6+dadb0d", releaseFromName("major"), .{});
        try t.expectEqualStrings("4.0.0", got.?);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const got = try sv.truncate(arena.allocator(), "4.5.6-rc2+dadb0d", releaseFromName("prerelease"), .{});
        try t.expectEqualStrings("4.5.6-rc2", got.?);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const got = try sv.truncate(arena.allocator(), "4.5.6-rc2+dadb0d", releaseFromName("prepatch"), .{});
        try t.expectEqualStrings("4.5.6-rc2", got.?);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const got = try sv.truncate(arena.allocator(), "4.5.6-rc2+dadb0d", releaseFromName("preminor"), .{});
        try t.expectEqualStrings("4.5.6-rc2", got.?);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const got = try sv.truncate(arena.allocator(), "4.5.6-rc2+dadb0d", releaseFromName("premajor"), .{});
        try t.expectEqualStrings("4.5.6-rc2", got.?);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const got = try sv.truncate(arena.allocator(), "4.5.6-rc2+dadb0d", releaseFromName("patch"), .{});
        try t.expectEqualStrings("4.5.6", got.?);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const got = try sv.truncate(arena.allocator(), "4.5.6-rc2+dadb0d", releaseFromName("minor"), .{});
        try t.expectEqualStrings("4.5.0", got.?);
    }
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        const got = try sv.truncate(arena.allocator(), "4.5.6-rc2+dadb0d", releaseFromName("major"), .{});
        try t.expectEqualStrings("4.0.0", got.?);
    }
}
test "range parsing: canonical forms" {
    try checkCanonical("1.0.0 - 2.0.0", .{}, ">=1.0.0 <=2.0.0");
    try checkCanonical("1.0.0 - 2.0.0", .{ .include_prerelease = true }, ">=1.0.0-0 <2.0.1-0");
    try checkCanonical("1 - 2", .{}, ">=1.0.0 <3.0.0-0");
    try checkCanonical("1 - 2", .{ .include_prerelease = true }, ">=1.0.0-0 <3.0.0-0");
    try checkCanonical("1.0 - 2.0", .{}, ">=1.0.0 <2.1.0-0");
    try checkCanonical("1.0 - 2.0", .{ .include_prerelease = true }, ">=1.0.0-0 <2.1.0-0");
    try checkCanonical("1.0.0", .{}, "1.0.0");
    try checkCanonical(">=*", .{}, "*");
    try checkCanonical("", .{}, "*");
    try checkCanonical("*", .{}, "*");
    try checkCanonical(">=1.0.0", .{}, ">=1.0.0");
    try checkCanonical(">1.0.0", .{}, ">1.0.0");
    try checkCanonical("<=2.0.0", .{}, "<=2.0.0");
    try checkCanonical("1", .{}, ">=1.0.0 <2.0.0-0");
    try checkCanonical("<2.0.0", .{}, "<2.0.0");
    try checkCanonical(">= 1.0.0", .{}, ">=1.0.0");
    try checkCanonical(">=  1.0.0", .{}, ">=1.0.0");
    try checkCanonical(">=   1.0.0", .{}, ">=1.0.0");
    try checkCanonical("> 1.0.0", .{}, ">1.0.0");
    try checkCanonical(">  1.0.0", .{}, ">1.0.0");
    try checkCanonical("<=   2.0.0", .{}, "<=2.0.0");
    try checkCanonical("<= 2.0.0", .{}, "<=2.0.0");
    try checkCanonical("<=  2.0.0", .{}, "<=2.0.0");
    try checkCanonical("<    2.0.0", .{}, "<2.0.0");
    try checkCanonical("<\t2.0.0", .{}, "<2.0.0");
    try checkCanonical(">=0.1.97", .{}, ">=0.1.97");
    try checkCanonical("0.1.20 || 1.2.4", .{}, "0.1.20||1.2.4");
    try checkCanonical(">=0.2.3 || <0.0.1", .{}, ">=0.2.3||<0.0.1");
    try checkCanonical("||", .{}, "*");
    try checkCanonical("2.x.x", .{}, ">=2.0.0 <3.0.0-0");
    try checkCanonical("1.2.x", .{}, ">=1.2.0 <1.3.0-0");
    try checkCanonical("1.2.x || 2.x", .{}, ">=1.2.0 <1.3.0-0||>=2.0.0 <3.0.0-0");
    try checkCanonical("1.x.5", .{}, null);
    try checkCanonical("1.*.5", .{}, null);
    try checkCanonical("1.x.5 || 2.x", .{}, null);
    try checkCanonical("x.1", .{}, null);
    try checkCanonical("x.1.2", .{}, null);
    try checkCanonical("x.x.1", .{}, null);
    try checkCanonical("x", .{}, "*");
    try checkCanonical("2.*.*", .{}, ">=2.0.0 <3.0.0-0");
    try checkCanonical("1.2.*", .{}, ">=1.2.0 <1.3.0-0");
    try checkCanonical("1.2.* || 2.*", .{}, ">=1.2.0 <1.3.0-0||>=2.0.0 <3.0.0-0");
    try checkCanonical("2", .{}, ">=2.0.0 <3.0.0-0");
    try checkCanonical("2.3", .{}, ">=2.3.0 <2.4.0-0");
    try checkCanonical("~2.4", .{}, ">=2.4.0 <2.5.0-0");
    try checkCanonical("~>3.2.1", .{}, ">=3.2.1 <3.3.0-0");
    try checkCanonical("~1", .{}, ">=1.0.0 <2.0.0-0");
    try checkCanonical("~>1", .{}, ">=1.0.0 <2.0.0-0");
    try checkCanonical("~> 1", .{}, ">=1.0.0 <2.0.0-0");
    try checkCanonical("~1.0", .{}, ">=1.0.0 <1.1.0-0");
    try checkCanonical("~ 1.0", .{}, ">=1.0.0 <1.1.0-0");
    try checkCanonical("~1", .{ .include_prerelease = true }, ">=1.0.0-0 <2.0.0-0");
    try checkCanonical("~1.x", .{ .include_prerelease = true }, ">=1.0.0-0 <2.0.0-0");
    try checkCanonical("~1.2", .{ .include_prerelease = true }, ">=1.2.0-0 <1.3.0-0");
    try checkCanonical("~1.2.x", .{ .include_prerelease = true }, ">=1.2.0-0 <1.3.0-0");
    try checkCanonical("~0.0", .{ .include_prerelease = true }, "<0.1.0-0");
    try checkCanonical("~1.2.3", .{ .include_prerelease = true }, ">=1.2.3 <1.3.0-0");
    try checkCanonical("~1.2.3-beta.4", .{ .include_prerelease = true }, ">=1.2.3-beta.4 <1.3.0-0");
    try checkCanonical("^0", .{}, "<1.0.0-0");
    try checkCanonical("^ 1", .{}, ">=1.0.0 <2.0.0-0");
    try checkCanonical("^0.1", .{}, ">=0.1.0 <0.2.0-0");
    try checkCanonical("^1.0", .{}, ">=1.0.0 <2.0.0-0");
    try checkCanonical("^1.2", .{}, ">=1.2.0 <2.0.0-0");
    try checkCanonical("^0.0.1", .{}, ">=0.0.1 <0.0.2-0");
    try checkCanonical("^0.0.1-beta", .{}, ">=0.0.1-beta <0.0.2-0");
    try checkCanonical("^0.1.2", .{}, ">=0.1.2 <0.2.0-0");
    try checkCanonical("^1.2.3", .{}, ">=1.2.3 <2.0.0-0");
    try checkCanonical("^1.2.3-beta.4", .{}, ">=1.2.3-beta.4 <2.0.0-0");
    try checkCanonical("<1", .{}, "<1.0.0-0");
    try checkCanonical("< 1", .{}, "<1.0.0-0");
    try checkCanonical(">=1", .{}, ">=1.0.0");
    try checkCanonical(">= 1", .{}, ">=1.0.0");
    try checkCanonical("<1.2", .{}, "<1.2.0-0");
    try checkCanonical("< 1.2", .{}, "<1.2.0-0");
    try checkCanonical(">01.02.03", .{ .loose = true }, ">1.2.3");
    try checkCanonical(">01.02.03", .{}, null);
    try checkCanonical("~1.2.3beta", .{ .loose = true }, ">=1.2.3-beta <1.3.0-0");
    try checkCanonical("~1.2.3beta", .{}, null);
    try checkCanonical("^ 1.2 ^ 1", .{}, ">=1.2.0 <2.0.0-0 >=1.0.0");
    try checkCanonical("1.2 - 3.4.5", .{}, ">=1.2.0 <=3.4.5");
    try checkCanonical("1.2.3 - 3.4", .{}, ">=1.2.3 <3.5.0-0");
    try checkCanonical("1.2 - 3.4", .{}, ">=1.2.0 <3.5.0-0");
    try checkCanonical(">1", .{}, ">=2.0.0");
    try checkCanonical(">1.2", .{}, ">=1.3.0");
    try checkCanonical(">X", .{}, "<0.0.0-0");
    try checkCanonical("<X", .{}, "<0.0.0-0");
    try checkCanonical("<x <* || >* 2.x", .{}, "<0.0.0-0");
    try checkCanonical(">x 2.x || * || <x", .{}, "*");
    try checkCanonical(">=09090", .{}, null);
    try checkCanonical(">=09090", .{ .loose = true }, ">=9090.0.0");
    try checkCanonical(">=09090-0", .{}, null);
    try checkCanonical(">=09090-0", .{}, null);
    try checkCanonical("1.x.x+build >2.x+build", .{}, ">=1.0.0 <2.0.0-0 >=3.0.0");
    try checkCanonical(">=1.x+build <2.x.x+build", .{}, ">=1.0.0 <2.0.0-0");
    try checkCanonical("1.x.x+build || 2.x.x+build", .{}, ">=1.0.0 <2.0.0-0||>=2.0.0 <3.0.0-0");
    try checkCanonical("1.x+build.123", .{}, ">=1.0.0 <2.0.0-0");
    try checkCanonical("1.x.x+meta-data", .{}, ">=1.0.0 <2.0.0-0");
    try checkCanonical("1.x.x+build.123 >2.x.x+meta-data", .{}, ">=1.0.0 <2.0.0-0 >=3.0.0");
    try checkCanonical("1.x.x+build <2.x.x+meta", .{}, ">=1.0.0 <2.0.0-0");
    try checkCanonical(">1.x+build <=2.x.x+meta", .{}, ">=2.0.0 <3.0.0-0");
    try checkCanonical(" 1.x.x+build   >2.x.x+build  ", .{}, ">=1.0.0 <2.0.0-0 >=3.0.0");
    try checkCanonical("^1.x+build", .{}, ">=1.0.0 <2.0.0-0");
    try checkCanonical("^1.x.x+build", .{}, ">=1.0.0 <2.0.0-0");
    try checkCanonical("^1.2.x+build", .{}, ">=1.2.0 <2.0.0-0");
    try checkCanonical("^1.x+meta-data", .{}, ">=1.0.0 <2.0.0-0");
    try checkCanonical("^1.x.x+build.123", .{}, ">=1.0.0 <2.0.0-0");
    try checkCanonical("~1.x+build", .{}, ">=1.0.0 <2.0.0-0");
    try checkCanonical("~1.x.x+build", .{}, ">=1.0.0 <2.0.0-0");
    try checkCanonical("~1.2.x+build", .{}, ">=1.2.0 <1.3.0-0");
    try checkCanonical("~1.x+meta-data", .{}, ">=1.0.0 <2.0.0-0");
    try checkCanonical("~1.x.x+build.123", .{}, ">=1.0.0 <2.0.0-0");
    try checkCanonical("^1.x.x+build || ~2.x.x+meta", .{}, ">=1.0.0 <2.0.0-0||>=2.0.0 <3.0.0-0");
    try checkCanonical("~1.x.x+build >2.x+meta", .{}, ">=1.0.0 <2.0.0-0 >=3.0.0");
    try checkCanonical("^1.x+build.123 <2.x.x+meta-data", .{}, ">=1.0.0 <2.0.0-0");
    try checkCanonical("1.x.x-alpha+build", .{}, ">=1.0.0 <2.0.0-0");
    try checkCanonical(">1.x.x-alpha+build", .{}, ">=2.0.0");
    try checkCanonical(">=1.x.x-alpha+build <2.x.x+build", .{}, ">=1.0.0 <2.0.0-0");
    try checkCanonical("1.x.x-alpha+build || 2.x.x+build", .{}, ">=1.0.0 <2.0.0-0||>=2.0.0 <3.0.0-0");
    // template-literal and concatenation cases from the fixture
    try checkCanonical("^9007199254740991.0.0", .{}, null);
    var long_build = std.ArrayList(u8).empty;
    defer long_build.deinit(t.allocator);
    try long_build.appendSlice(t.allocator, "v1.0+");
    for (0..249) |_| try long_build.append(t.allocator, 'a');
    try long_build.appendSlice(t.allocator, "x6");
    try checkCanonical(long_build.items, .{}, ">=1.0.0 <1.1.0-0");
    var long_build2 = std.ArrayList(u8).empty;
    defer long_build2.deinit(t.allocator);
    try long_build2.appendSlice(t.allocator, "1.2.3+");
    for (0..251) |_| try long_build2.append(t.allocator, 'a');
    {
        const with_range = try std.mem.concat(t.allocator, u8, &.{ long_build2.items, " - 2.0.0" });
        defer t.allocator.free(with_range);
        try checkCanonical(with_range, .{}, ">=1.2.3 <=2.0.0");
    }
    {
        const gt = try std.mem.concat(t.allocator, u8, &.{ "> 1.2.3+", long_build2.items[6..] });
        defer t.allocator.free(gt);
        try checkCanonical(gt, .{}, ">1.2.3");
    }
    {
        const tl = try std.mem.concat(t.allocator, u8, &.{ "~1.2.3+", long_build2.items[6..] });
        defer t.allocator.free(tl);
        try checkCanonical(tl, .{}, ">=1.2.3 <1.3.0-0");
    }
    {
        const ca = try std.mem.concat(t.allocator, u8, &.{ "^1.2.3+", long_build2.items[6..] });
        defer t.allocator.free(ca);
        try checkCanonical(ca, .{}, ">=1.2.3 <2.0.0-0");
    }
}
test "ranges: range-include" {
    try checkSatisfies("1.2.3", "1.0.0 - 2.0.0", .{}, true);
    try checkSatisfies("1.2.3", "^1.2.3+build", .{}, true);
    try checkSatisfies("1.3.0", "^1.2.3+build", .{}, true);
    try checkSatisfies("1.2.3", "1.2.3-pre+asdf - 2.4.3-pre+asdf", .{}, true);
    try checkSatisfies("1.2.3", "1.2.3pre+asdf - 2.4.3-pre+asdf", .{ .loose = true }, true);
    try checkSatisfies("1.2.3", "1.2.3-pre+asdf - 2.4.3pre+asdf", .{ .loose = true }, true);
    try checkSatisfies("1.2.3", "1.2.3pre+asdf - 2.4.3pre+asdf", .{ .loose = true }, true);
    try checkSatisfies("1.2.3-pre.2", "1.2.3-pre+asdf - 2.4.3-pre+asdf", .{}, true);
    try checkSatisfies("2.4.3-alpha", "1.2.3-pre+asdf - 2.4.3-pre+asdf", .{}, true);
    try checkSatisfies("1.2.3", "1.2.3+asdf - 2.4.3+asdf", .{}, true);
    try checkSatisfies("1.0.0", "1.0.0", .{}, true);
    try checkSatisfies("0.2.4", ">=*", .{}, true);
    try checkSatisfies("1.0.0", "", .{}, true);
    try checkSatisfies("1.2.3", "*", .{}, true);
    try checkSatisfies("v1.2.3", "*", .{ .loose = true }, true);
    try checkSatisfies("1.0.0", ">=1.0.0", .{}, true);
    try checkSatisfies("1.0.1", ">=1.0.0", .{}, true);
    try checkSatisfies("1.1.0", ">=1.0.0", .{}, true);
    try checkSatisfies("1.0.1", ">1.0.0", .{}, true);
    try checkSatisfies("1.1.0", ">1.0.0", .{}, true);
    try checkSatisfies("2.0.0", "<=2.0.0", .{}, true);
    try checkSatisfies("1.9999.9999", "<=2.0.0", .{}, true);
    try checkSatisfies("0.2.9", "<=2.0.0", .{}, true);
    try checkSatisfies("1.9999.9999", "<2.0.0", .{}, true);
    try checkSatisfies("0.2.9", "<2.0.0", .{}, true);
    try checkSatisfies("1.0.0", ">= 1.0.0", .{}, true);
    try checkSatisfies("1.0.1", ">=  1.0.0", .{}, true);
    try checkSatisfies("1.1.0", ">=   1.0.0", .{}, true);
    try checkSatisfies("1.0.1", "> 1.0.0", .{}, true);
    try checkSatisfies("1.1.0", ">  1.0.0", .{}, true);
    try checkSatisfies("2.0.0", "<=   2.0.0", .{}, true);
    try checkSatisfies("1.9999.9999", "<= 2.0.0", .{}, true);
    try checkSatisfies("0.2.9", "<=  2.0.0", .{}, true);
    try checkSatisfies("1.9999.9999", "<    2.0.0", .{}, true);
    try checkSatisfies("0.2.9", "<\t2.0.0", .{}, true);
    try checkSatisfies("v0.1.97", ">=0.1.97", .{ .loose = true }, true);
    try checkSatisfies("0.1.97", ">=0.1.97", .{}, true);
    try checkSatisfies("1.2.4", "0.1.20 || 1.2.4", .{}, true);
    try checkSatisfies("0.0.0", ">=0.2.3 || <0.0.1", .{}, true);
    try checkSatisfies("0.2.3", ">=0.2.3 || <0.0.1", .{}, true);
    try checkSatisfies("0.2.4", ">=0.2.3 || <0.0.1", .{}, true);
    try checkSatisfies("1.3.4", "||", .{}, true);
    try checkSatisfies("2.1.3", "2.x.x", .{}, true);
    try checkSatisfies("1.2.3", "1.2.x", .{}, true);
    try checkSatisfies("2.1.3", "1.2.x || 2.x", .{}, true);
    try checkSatisfies("1.2.3", "1.2.x || 2.x", .{}, true);
    try checkSatisfies("1.2.3", "x", .{}, true);
    try checkSatisfies("2.1.3", "2.*.*", .{}, true);
    try checkSatisfies("1.2.3", "1.2.*", .{}, true);
    try checkSatisfies("2.1.3", "1.2.* || 2.*", .{}, true);
    try checkSatisfies("1.2.3", "1.2.* || 2.*", .{}, true);
    try checkSatisfies("1.2.3", "*", .{}, true);
    try checkSatisfies("2.1.2", "2", .{}, true);
    try checkSatisfies("2.3.1", "2.3", .{}, true);
    try checkSatisfies("0.0.1", "~0.0.1", .{}, true);
    try checkSatisfies("0.0.2", "~0.0.1", .{}, true);
    try checkSatisfies("0.0.9", "~x", .{}, true);
    try checkSatisfies("2.0.9", "~2", .{}, true);
    try checkSatisfies("2.4.0", "~2.4", .{}, true);
    try checkSatisfies("2.4.5", "~2.4", .{}, true);
    try checkSatisfies("3.2.2", "~>3.2.1", .{}, true);
    try checkSatisfies("1.2.3", "~1", .{}, true);
    try checkSatisfies("1.2.3", "~>1", .{}, true);
    try checkSatisfies("1.2.3", "~> 1", .{}, true);
    try checkSatisfies("1.0.2", "~1.0", .{}, true);
    try checkSatisfies("1.0.2", "~ 1.0", .{}, true);
    try checkSatisfies("1.0.12", "~ 1.0.3", .{}, true);
    try checkSatisfies("1.0.12", "~ 1.0.3alpha", .{ .loose = true }, true);
    try checkSatisfies("1.0.0", ">=1", .{}, true);
    try checkSatisfies("1.0.0", ">= 1", .{}, true);
    try checkSatisfies("1.1.1", "<1.2", .{}, true);
    try checkSatisfies("1.1.1", "< 1.2", .{}, true);
    try checkSatisfies("0.5.5", "~v0.5.4-pre", .{}, true);
    try checkSatisfies("0.5.4", "~v0.5.4-pre", .{}, true);
    try checkSatisfies("0.7.2", "=0.7.x", .{}, true);
    try checkSatisfies("0.7.2", "<=0.7.x", .{}, true);
    try checkSatisfies("0.7.2", ">=0.7.x", .{}, true);
    try checkSatisfies("0.6.2", "<=0.7.x", .{}, true);
    try checkSatisfies("1.2.3", "~1.2.1 >=1.2.3", .{}, true);
    try checkSatisfies("1.2.3", "~1.2.1 =1.2.3", .{}, true);
    try checkSatisfies("1.2.3", "~1.2.1 1.2.3", .{}, true);
    try checkSatisfies("1.2.3", "~1.2.1 >=1.2.3 1.2.3", .{}, true);
    try checkSatisfies("1.2.3", "~1.2.1 1.2.3 >=1.2.3", .{}, true);
    try checkSatisfies("1.2.3", ">=1.2.1 1.2.3", .{}, true);
    try checkSatisfies("1.2.3", "1.2.3 >=1.2.1", .{}, true);
    try checkSatisfies("1.2.3", ">=1.2.3 >=1.2.1", .{}, true);
    try checkSatisfies("1.2.3", ">=1.2.1 >=1.2.3", .{}, true);
    try checkSatisfies("1.2.8", ">=1.2", .{}, true);
    try checkSatisfies("1.8.1", "^1.2.3", .{}, true);
    try checkSatisfies("0.1.2", "^0.1.2", .{}, true);
    try checkSatisfies("0.1.2", "^0.1", .{}, true);
    try checkSatisfies("0.0.1", "^0.0.1", .{}, true);
    try checkSatisfies("1.4.2", "^1.2", .{}, true);
    try checkSatisfies("1.4.2", "^1.2 ^1", .{}, true);
    try checkSatisfies("1.2.3-pre", "^1.2.3-alpha", .{}, true);
    try checkSatisfies("1.2.0-pre", "^1.2.0-alpha", .{}, true);
    try checkSatisfies("0.0.1-beta", "^0.0.1-alpha", .{}, true);
    try checkSatisfies("0.0.1", "^0.0.1-alpha", .{}, true);
    try checkSatisfies("0.1.1-beta", "^0.1.1-alpha", .{}, true);
    try checkSatisfies("1.2.3", "^x", .{}, true);
    try checkSatisfies("0.9.7", "x - 1.0.0", .{}, true);
    try checkSatisfies("0.9.7", "x - 1.x", .{}, true);
    try checkSatisfies("1.9.7", "1.0.0 - x", .{}, true);
    try checkSatisfies("1.9.7", "1.x - x", .{}, true);
    try checkSatisfies("7.9.9", "<=7.x", .{}, true);
    try checkSatisfies("2.0.0-pre.0", "2.x", .{ .include_prerelease = true }, true);
    try checkSatisfies("2.1.0-pre.0", "2.x", .{ .include_prerelease = true }, true);
    try checkSatisfies("1.1.0-a", "1.1.x", .{ .include_prerelease = true }, true);
    try checkSatisfies("1.1.1-a", "1.1.x", .{ .include_prerelease = true }, true);
    try checkSatisfies("1.1.0-a", "~1.1", .{ .include_prerelease = true }, true);
    try checkSatisfies("1.1.0-a", "~1.1.x", .{ .include_prerelease = true }, true);
    try checkSatisfies("1.1.1-a", "~1.1", .{ .include_prerelease = true }, true);
    try checkSatisfies("2.0.0-pre.0", "~2", .{ .include_prerelease = true }, true);
    try checkSatisfies("2.0.0-pre.0", "~2.x", .{ .include_prerelease = true }, true);
    try checkSatisfies("1.0.0-rc1", "*", .{ .include_prerelease = true }, true);
    try checkSatisfies("1.0.1-rc1", "^1.0.0-0", .{ .include_prerelease = true }, true);
    try checkSatisfies("1.0.1-rc1", "^1.0.0-rc2", .{ .include_prerelease = true }, true);
    try checkSatisfies("1.0.1-rc1", "^1.0.0", .{ .include_prerelease = true }, true);
    try checkSatisfies("1.1.0-rc1", "^1.0.0", .{ .include_prerelease = true }, true);
    try checkSatisfies("2.0.0-pre", "1 - 2", .{ .include_prerelease = true }, true);
    try checkSatisfies("1.0.0-pre", "1 - 2", .{ .include_prerelease = true }, true);
    try checkSatisfies("1.0.0-pre", "1.0 - 2", .{ .include_prerelease = true }, true);
    try checkSatisfies("0.7.0-asdf", "=0.7.x", .{ .include_prerelease = true }, true);
    try checkSatisfies("0.7.0-asdf", ">=0.7.x", .{ .include_prerelease = true }, true);
    try checkSatisfies("0.7.0-asdf", "<=0.7.x", .{ .include_prerelease = true }, true);
    try checkSatisfies("1.1.0-pre", ">=1.0.0 <=1.1.0", .{ .include_prerelease = true }, true);
}
test "ranges: range-exclude" {
    try checkSatisfies("2.2.3", "1.0.0 - 2.0.0", .{}, false);
    try checkSatisfies("1.2.3-pre.2", "1.2.3+asdf - 2.4.3+asdf", .{}, false);
    try checkSatisfies("2.4.3-alpha", "1.2.3+asdf - 2.4.3+asdf", .{}, false);
    try checkSatisfies("2.0.0", "^1.2.3+build", .{}, false);
    try checkSatisfies("1.2.0", "^1.2.3+build", .{}, false);
    try checkSatisfies("1.2.3-pre", "^1.2.3", .{}, false);
    try checkSatisfies("1.2.0-pre", "^1.2", .{}, false);
    try checkSatisfies("1.3.0-beta", ">1.2", .{}, false);
    try checkSatisfies("1.2.3-beta", "<=1.2.3", .{}, false);
    try checkSatisfies("1.2.3-beta", "^1.2.3", .{}, false);
    try checkSatisfies("0.7.0-asdf", "=0.7.x", .{}, false);
    try checkSatisfies("0.7.0-asdf", ">=0.7.x", .{}, false);
    try checkSatisfies("0.7.0-asdf", "<=0.7.x", .{}, false);
    try checkSatisfies("1.0.0beta", "1", .{ .loose = true }, false);
    try checkSatisfies("1.0.0beta", "<1", .{ .loose = true }, false);
    try checkSatisfies("1.0.0beta", "< 1", .{ .loose = true }, false);
    try checkSatisfies("1.0.1", "1.0.0", .{}, false);
    try checkSatisfies("0.0.0", ">=1.0.0", .{}, false);
    try checkSatisfies("0.0.1", ">=1.0.0", .{}, false);
    try checkSatisfies("0.1.0", ">=1.0.0", .{}, false);
    try checkSatisfies("0.0.1", ">1.0.0", .{}, false);
    try checkSatisfies("0.1.0", ">1.0.0", .{}, false);
    try checkSatisfies("3.0.0", "<=2.0.0", .{}, false);
    try checkSatisfies("2.9999.9999", "<=2.0.0", .{}, false);
    try checkSatisfies("2.2.9", "<=2.0.0", .{}, false);
    try checkSatisfies("2.9999.9999", "<2.0.0", .{}, false);
    try checkSatisfies("2.2.9", "<2.0.0", .{}, false);
    try checkSatisfies("v0.1.93", ">=0.1.97", .{ .loose = true }, false);
    try checkSatisfies("0.1.93", ">=0.1.97", .{}, false);
    try checkSatisfies("1.2.3", "0.1.20 || 1.2.4", .{}, false);
    try checkSatisfies("0.0.3", ">=0.2.3 || <0.0.1", .{}, false);
    try checkSatisfies("0.2.2", ">=0.2.3 || <0.0.1", .{}, false);
    try checkSatisfies("1.1.3", "2.x.x", .{}, false);
    try checkSatisfies("3.1.3", "2.x.x", .{}, false);
    try checkSatisfies("1.3.3", "1.2.x", .{}, false);
    try checkSatisfies("3.1.3", "1.2.x || 2.x", .{}, false);
    try checkSatisfies("1.1.3", "1.2.x || 2.x", .{}, false);
    try checkSatisfies("1.1.3", "2.*.*", .{}, false);
    try checkSatisfies("3.1.3", "2.*.*", .{}, false);
    try checkSatisfies("1.3.3", "1.2.*", .{}, false);
    try checkSatisfies("3.1.3", "1.2.* || 2.*", .{}, false);
    try checkSatisfies("1.1.3", "1.2.* || 2.*", .{}, false);
    try checkSatisfies("1.1.2", "2", .{}, false);
    try checkSatisfies("2.4.1", "2.3", .{}, false);
    try checkSatisfies("0.1.0-alpha", "~0.0.1", .{}, false);
    try checkSatisfies("0.1.0", "~0.0.1", .{}, false);
    try checkSatisfies("2.5.0", "~2.4", .{}, false);
    try checkSatisfies("2.3.9", "~2.4", .{}, false);
    try checkSatisfies("3.3.2", "~>3.2.1", .{}, false);
    try checkSatisfies("3.2.0", "~>3.2.1", .{}, false);
    try checkSatisfies("0.2.3", "~1", .{}, false);
    try checkSatisfies("2.2.3", "~>1", .{}, false);
    try checkSatisfies("1.1.0", "~1.0", .{}, false);
    try checkSatisfies("1.0.0", "<1", .{}, false);
    try checkSatisfies("1.1.1", ">=1.2", .{}, false);
    try checkSatisfies("2.0.0beta", "1", .{ .loose = true }, false);
    try checkSatisfies("0.5.4-alpha", "~v0.5.4-beta", .{}, false);
    try checkSatisfies("0.8.2", "=0.7.x", .{}, false);
    try checkSatisfies("0.6.2", ">=0.7.x", .{}, false);
    try checkSatisfies("0.7.2", "<0.7.x", .{}, false);
    try checkSatisfies("1.2.3-beta", "<1.2.3", .{}, false);
    try checkSatisfies("1.2.3-beta", "=1.2.3", .{}, false);
    try checkSatisfies("1.2.8", ">1.2", .{}, false);
    try checkSatisfies("0.0.2-alpha", "^0.0.1", .{}, false);
    try checkSatisfies("0.0.2", "^0.0.1", .{}, false);
    try checkSatisfies("2.0.0-alpha", "^1.2.3", .{}, false);
    try checkSatisfies("1.2.2", "^1.2.3", .{}, false);
    try checkSatisfies("1.1.9", "^1.2", .{}, false);
    try checkSatisfies("v1.2.3-foo", "*", .{ .loose = true }, false);
}
test "range intersections" {
    {
        var a = try sv.Range.parse(t.allocator, "1.3.0 || <1.0.0 >2.0.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "1.3.0 || <1.0.0 >2.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "<1.0.0 >2.0.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, ">0.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, ">0.0.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<1.0.0 >2.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "<1.0.0 >2.0.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, ">1.4.0 <1.6.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "<1.0.0 >2.0.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, ">1.4.0 <1.6.0 || 2.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, ">1.0.0 <=2.0.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "2.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "<1.0.0 >=2.0.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "2.1.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "<1.0.0 >=2.0.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, ">1.4.0 <1.6.0 || 2.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "1.5.x", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<1.5.0 || >=1.6.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "<1.5.0 || >=1.6.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "1.5.x", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "<1.6.16 || >=1.7.0 <1.7.11 || >=1.8.0 <1.8.2", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, ">=1.6.16 <1.7.0 || >=1.7.11 <1.8.0 || >=1.8.2", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "<=1.6.16 || >=1.7.0 <1.7.11 || >=1.8.0 <1.8.2", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, ">=1.6.16 <1.7.0 || >=1.7.11 <1.8.0 || >=1.8.2", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, ">=1.0.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<=1.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, ">1.0.0 <1.0.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<=0.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "*", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "0.0.1", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "*", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, ">=1.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "*", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, ">1.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "*", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "~1.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "*", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<1.6.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "*", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<=1.6.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "1.*", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "0.0.1", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "1.*", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "2.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "1.*", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "1.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "1.*", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<2.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "1.*", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, ">1.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "1.*", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<=1.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "1.*", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "^1.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "1.0.*", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "0.0.1", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "1.0.*", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<0.0.1", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "1.0.*", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, ">0.0.1", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "*", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "1.3.0 || <1.0.0 >2.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "1.3.0 || <1.0.0 >2.0.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "*", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "1.*", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "1.3.0 || <1.0.0 >2.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "x", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "0.0.1", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "x", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, ">=1.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "x", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, ">1.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "x", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "~1.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "x", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<1.6.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "x", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<=1.6.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "1.x", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "0.0.1", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "1.x", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "2.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "1.x", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "1.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "1.x", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<2.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "1.x", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, ">1.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "1.x", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<=1.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "1.x", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "^1.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "1.0.x", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "0.0.1", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "1.0.x", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<0.0.1", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "1.0.x", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, ">0.0.1", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "x", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "1.3.0 || <1.0.0 >2.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "1.3.0 || <1.0.0 >2.0.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "x", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "1.x", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "1.3.0 || <1.0.0 >2.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "*", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "*", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "x", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.intersects(&b, .{}));
    }
}
test "comparator intersections" {
    {
        var a = try sv.Range.parse(t.allocator, "1.3.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, ">=1.3.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "1.3.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, ">1.3.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, ">=1.3.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "1.3.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, ">1.3.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "1.3.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, ">1.3.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, ">1.2.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, ">1.2.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, ">1.3.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, ">=1.2.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, ">1.3.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, ">1.2.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, ">=1.3.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "<1.3.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<1.2.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "<1.2.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<1.3.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "<=1.2.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<1.3.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "<1.2.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<=1.3.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, ">=1.3.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<=1.3.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, ">=v1.3.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<=1.3.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, ">=1.3.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, ">=1.3.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "<=1.3.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<=1.3.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "<=1.3.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<=v1.3.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, ">1.3.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<=1.3.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, ">=1.3.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<1.3.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, ">1.0.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<2.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, ">=1.0.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<2.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, ">=1.0.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<=2.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, ">1.0.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<=2.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "<=2.0.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, ">1.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "<=1.0.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, ">=2.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, ">1.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "<=2.0.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(true == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "<0.0.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<0.1.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "<0.1.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<0.0.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "<0.0.0-0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<0.1.0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "<0.1.0", .{});
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<0.0.0-0", .{});
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.set[0][0].intersects(b.set[0][0], .{}));
    }
    {
        var a = try sv.Range.parse(t.allocator, "<0.0.0-0", .{ .loose = true });
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<0.1.0", .{ .loose = true });
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.set[0][0].intersects(b.set[0][0], .{ .loose = true }));
    }
    {
        var a = try sv.Range.parse(t.allocator, "<0.1.0", .{ .loose = true });
        defer a.deinit();
        _ = &a;
        var b = try sv.Range.parse(t.allocator, "<0.0.0-0", .{ .loose = true });
        defer b.deinit();
        _ = &b;
        try t.expect(false == a.set[0][0].intersects(b.set[0][0], .{ .loose = true }));
    }
}
