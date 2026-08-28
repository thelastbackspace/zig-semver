//! Range parsing and version matching: `^1.2.3`, `~1.2`, `1.2.x`,
//! `1.0.0 - 2.0.0`, `>=1 <2 || >=3`, with prerelease gating.

const std = @import("std");
const version_mod = @import("version.zig");

pub const Version = version_mod.Version;
pub const Options = version_mod.Options;

pub const Error = error{
    InvalidRange,
    InvalidComparator,
    InvalidVersion,
    VersionTooLong,
    InvalidIncrement,
    InvalidIdentifier,
} || std.mem.Allocator.Error;

const null_set_value = "<0.0.0-0";

/// A single comparison: an operator plus a version, or "any".
///
/// Slices borrow the allocator given to [`Range.parse`].
pub const Comparator = struct {
    operator: Operator,
    /// `null` means "any version" (upstream's `Comparator.ANY`).
    semver: ?Version,
    /// Canonical form: `""` for any, otherwise operator + version.
    value: []const u8,

    pub const Operator = enum {
        none,
        lt,
        lte,
        gt,
        gte,
    };

    /// Test a version against this comparator.
    pub fn matches(self: Comparator, v: Version) bool {
        const s = self.semver orelse return true;
        const ord = v.compare(s);
        return switch (self.operator) {
            .none => ord == .eq,
            .lt => ord == .lt,
            .lte => ord != .gt,
            .gt => ord == .gt,
            .gte => ord != .lt,
        };
    }

    /// Whether two comparators can both be satisfied by some version.
    pub fn intersects(self: Comparator, comp: Comparator, options: Options) bool {
        if (self.operator == .none) {
            if (self.value.len == 0) return true;
            var r = Range.parse(std.heap.page_allocator, comp.value, options) catch return false;
            defer r.deinit();
            _ = &r;
            return r.testVersion(self.semver.?);
        }
        if (comp.operator == .none) {
            if (comp.value.len == 0) return true;
            var r = Range.parse(std.heap.page_allocator, self.value, options) catch return false;
            defer r.deinit();
            _ = &r;
            return r.testVersion(comp.semver.?);
        }

        if (options.include_prerelease and
            (std.mem.eql(u8, self.value, null_set_value) or
                std.mem.eql(u8, comp.value, null_set_value))) return false;
        if (!options.include_prerelease and
            (std.mem.startsWith(u8, self.value, "<0.0.0") or
                std.mem.startsWith(u8, comp.value, "<0.0.0"))) return false;

        // Same direction.
        if (isIncreasing(self.operator) and isIncreasing(comp.operator)) return true;
        if (isDecreasing(self.operator) and isDecreasing(comp.operator)) return true;

        // Same version, both inclusive.
        if (self.semver.?.compare(comp.semver.?) == .eq and
            isInclusive(self.operator) and isInclusive(comp.operator)) return true;

        // Opposite directions with room between the bounds.
        const ord = self.semver.?.compare(comp.semver.?);
        if (ord == .lt and isIncreasing(self.operator) and isDecreasing(comp.operator)) return true;
        if (ord == .gt and isDecreasing(self.operator) and isIncreasing(comp.operator)) return true;

        return false;
    }
};

fn isIncreasing(op: Comparator.Operator) bool {
    return op == .gt or op == .gte;
}

fn isDecreasing(op: Comparator.Operator) bool {
    return op == .lt or op == .lte;
}

fn isInclusive(op: Comparator.Operator) bool {
    return op == .gte or op == .lte;
}

/// A range: OR (`||`) of comparator sets, each an AND.
///
/// All memory (comparators, version slices, the canonical form) is
/// owned by the instance and freed by [`deinit`].
pub const Range = struct {
    arena: std.heap.ArenaAllocator,
    raw: []const u8,
    set: []const []const Comparator,
    formatted: []const u8,

    /// Parse a range string. An empty range is "any version".
    pub fn parse(allocator: std.mem.Allocator, range: []const u8, options: Options) Error!Range {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const a = arena.allocator();

        const collapsed = try collapseWhitespace(a, std.mem.trim(u8, range, &js_space));

        var branches = std.ArrayList([]const Comparator).empty;
        var it = std.mem.splitSequence(u8, collapsed, "||");
        while (it.next()) |branch| {
            const trimmed = std.mem.trim(u8, branch, " ");
            const set = parseRangeBranch(a, trimmed, options) catch |e| switch (e) {
                error.OutOfMemory => return e,
                // In loose mode invalid branches are dropped; a fully
                // invalid range still fails below.
                else => if (options.loose) &.{} else return e,
            };
            if (set.len > 0) try branches.append(a, set);
        }

        if (branches.items.len == 0) return error.InvalidRange;

        // Drop null-set branches when anything else matches; collapse
        // to "any" when an "any" branch is present.
        if (branches.items.len > 1) {
            const first = branches.items[0];
            var kept = std.ArrayList([]const Comparator).empty;
            for (branches.items) |set| {
                if (!std.mem.eql(u8, set[0].value, null_set_value)) {
                    try kept.append(a, set);
                }
            }
            if (kept.items.len == 0) {
                try kept.append(a, first);
            } else if (kept.items.len > 1) {
                var any_index: ?usize = null;
                for (kept.items, 0..) |set, i| {
                    if (set.len == 1 and set[0].value.len == 0) {
                        any_index = i;
                        break;
                    }
                }
                if (any_index) |i| {
                    const any_set = kept.items[i];
                    try kept.resize(a, 1);
                    kept.items[0] = any_set;
                }
            }
            branches = kept;
        }

        const set = try branches.toOwnedSlice(a);

        var formatted = std.ArrayList(u8).empty;
        for (set, 0..) |comps, i| {
            if (i > 0) try formatted.appendSlice(a, "||");
            for (comps, 0..) |comp, k| {
                if (k > 0) try formatted.appendSlice(a, " ");
                try formatted.appendSlice(a, std.mem.trim(u8, comp.value, " "));
            }
        }

        return .{
            .arena = arena,
            .raw = collapsed,
            .set = set,
            .formatted = try formatted.toOwnedSlice(a),
        };
    }

    pub fn deinit(self: *Range) void {
        self.arena.deinit();
    }

    /// The canonical comparator form (upstream `range`/`format()`).
    pub fn format(self: *const Range) []const u8 {
        return self.formatted;
    }

    /// `satisfies`: true when any comparator set fully matches.
    pub fn testVersion(self: *const Range, v: Version) bool {
        for (self.set) |comps| {
            if (testSet(comps, v)) return true;
        }
        return false;
    }

    /// `satisfies` for an unparsed version string; unparseable versions
    /// never satisfy.
    pub fn testString(self: *const Range, text: []const u8, options: Options) bool {
        const v = Version.parse(text, options) catch return false;
        return self.testVersion(v);
    }

    /// Whether two ranges share at least one satisfiable version.
    pub fn intersects(self: *const Range, other: *const Range, options: Options) bool {
        for (self.set) |this_comps| {
            if (!isSatisfiable(this_comps, options)) continue;
            for (other.set) |other_comps| {
                if (!isSatisfiable(other_comps, options)) continue;
                var all = true;
                for (this_comps) |tc| {
                    for (other_comps) |oc| {
                        if (!tc.intersects(oc, options)) {
                            all = false;
                            break;
                        }
                    }
                    if (!all) break;
                }
                if (all) return true;
            }
        }
        return false;
    }

    /// `toComparators`: the desugared comparator sets.
    pub fn toComparators(self: *const Range) []const []const Comparator {
        return self.set;
    }
};

const js_space = [_]u8{ ' ', '\t', '\n', '\r', 0x0B, 0x0C };

fn collapseWhitespace(a: std.mem.Allocator, s: []const u8) Error![]const u8 {
    var out = std.ArrayList(u8).empty;
    var in_space = false;
    for (s) |c| {
        const is_space = std.mem.indexOfScalar(u8, &js_space, c) != null or c == 0xA0;
        if (is_space) {
            if (!in_space) try out.append(a, ' ');
            in_space = true;
        } else {
            try out.append(a, c);
            in_space = false;
        }
    }
    return out.toOwnedSlice(a);
}

fn testSet(comps: []const Comparator, v: Version) bool {
    for (comps) |comp| {
        if (!comp.matches(v)) return false;
    }
    return true;
}

/// Approximate satisfiability the way upstream does: every comparator
/// must intersect every other.
fn isSatisfiable(comps: []const Comparator, options: Options) bool {
    if (comps.len <= 1) return true;
    for (comps, 0..) |a, i| {
        for (comps[i + 1 ..]) |b| {
            if (!a.intersects(b, options)) return false;
        }
    }
    return true;
}

const XPart = union(enum) {
    any,
    number: u64,
};

const XRange = struct {
    gtlt: ?[]const u8,
    major: XPart,
    minor: XPart,
    patch: XPart,
    prerelease: ?[]const u8,
};

/// Parse the XRANGEPLAIN grammar used by hyphen ranges and the
/// caret/tilde/x-range replacements.
fn parseXRangePlain(s: []const u8, loose: bool) ?XRange {
    var i: usize = 0;
    while (i < s.len and (s[i] == 'v' or s[i] == '=' or isSpaceByte(s[i]))) i += 1;

    var parts: [3]XPart = .{ .any, .any, .any };
    var part_count: usize = 0;
    var j = i;
    while (part_count < 3) {
        const start = j;
        while (j < s.len and (std.ascii.isDigit(s[j]))) j += 1;
        const tok = s[start..j];
        if (tok.len > 0 and allDigits(tok)) {
            if (!loose and tok.len > 1 and tok[0] == '0') return null;
            parts[part_count] = .{ .number = std.fmt.parseInt(u64, tok, 10) catch return null };
        } else if (tok.len == 0 and j < s.len and (s[j] == 'x' or s[j] == 'X' or s[j] == '*')) {
            j += 1;
            parts[part_count] = .any;
        } else if (tok.len == 0 and j == s.len and part_count > 0) {
            break;
        } else {
            return null;
        }
        part_count += 1;
        if (part_count < 3) {
            if (j < s.len and s[j] == '.') {
                j += 1;
            } else {
                break;
            }
        }
    }

    var prerelease: ?[]const u8 = null;
    if (j < s.len and s[j] == '-') {
        const start = j + 1;
        var k = start;
        while (k < s.len and s[k] != '+') k += 1;
        prerelease = s[start..k];
        j = k;
    } else if (loose and j < s.len and (std.ascii.isAlphanumeric(s[j]) or s[j] == '-')) {
        // Loose mode allows a prerelease without its hyphen.
        const start = j;
        var k = j;
        while (k < s.len and s[k] != '+') k += 1;
        prerelease = s[start..k];
        j = k;
    }
    if (j < s.len and s[j] == '+') {
        // Build metadata is stripped everywhere in ranges.
        while (j < s.len and !isSpaceByte(s[j])) j += 1;
    }
    if (j != s.len) return null;

    return .{
        .gtlt = null,
        .major = parts[0],
        .minor = parts[1],
        .patch = parts[2],
        .prerelease = prerelease,
    };
}

fn isSpaceByte(c: u8) bool {
    return std.mem.indexOfScalar(u8, &js_space, c) != null;
}

fn allDigits(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |c| {
        if (!std.ascii.isDigit(c)) return false;
    }
    return true;
}

fn isX(p: XPart) bool {
    return p == .any;
}

fn partNumber(p: XPart) u64 {
    return switch (p) {
        .number => |n| n,
        .any => 0,
    };
}

/// Parse one `||`-free branch into comparators.
fn parseRangeBranch(a: std.mem.Allocator, branch: []const u8, options: Options) Error![]const Comparator {
    // Strip build metadata everywhere.
    const stripped = try stripBuild(a, branch);

    // Hyphen ranges: `1.2.3 - 2.3.4`.
    const hyphenated = try tryHyphenReplace(a, stripped, options);

    // Operator/tilde/caret spacing: `> 1.2.3` -> `>1.2.3`.
    var tokens = std.ArrayList([]const u8).empty;
    {
        var it = std.mem.tokenizeScalar(u8, hyphenated, ' ');
        while (it.next()) |tok| try tokens.append(a, tok);
        try mergeOperatorSpacing(a, &tokens);
    }

    // Desugar each token through caret, tilde, x-range, star.
    var desugared = std.ArrayList([]const u8).empty;
    for (tokens.items) |tok| {
        const after_caret = try replaceCaret(a, tok, options);
        var it2 = std.mem.tokenizeScalar(u8, after_caret, ' ');
        while (it2.next()) |t| try desugared.append(a, t);
    }
    var expanded = std.ArrayList([]const u8).empty;
    for (desugared.items) |tok| {
        const after_tilde = try replaceTilde(a, tok, options);
        var it2 = std.mem.tokenizeScalar(u8, after_tilde, ' ');
        while (it2.next()) |t| try expanded.append(a, t);
    }
    var xran = std.ArrayList([]const u8).empty;
    for (expanded.items) |tok| {
        const after_x = try replaceXRange(a, tok, options);
        var it2 = std.mem.tokenizeScalar(u8, after_x, ' ');
        while (it2.next()) |t| try xran.append(a, t);
    }

    // Build comparators, applying the `>=0.0.0` == any rule.
    var comparators = std.ArrayList(Comparator).empty;
    var seen_null_set = false;
    for (xran.items) |tok| {
        if (isGteZero(tok)) continue;
        const star_stripped = try stripStar(a, tok);
        if (star_stripped.len == 0) {
            try comparators.append(a, .{ .operator = .none, .semver = null, .value = "" });
            continue;
        }
        const comp = try parseComparator(a, star_stripped, options);
        if (std.mem.eql(u8, comp.value, null_set_value)) {
            seen_null_set = true;
            try comparators.append(a, comp);
            break;
        }
        try comparators.append(a, comp);
    }

    if (seen_null_set) {
        const set = try a.alloc(Comparator, 1);
        set[0] = comparators.items[comparators.items.len - 1];
        return set;
    }

    // Dedupe by value; drop "any" when anything else is present.
    var unique = std.ArrayList(Comparator).empty;
    var has_any = false;
    for (comparators.items) |comp| {
        if (comp.value.len == 0) has_any = true;
        var dup = false;
        for (unique.items) |u| {
            if (std.mem.eql(u8, u.value, comp.value)) {
                dup = true;
                break;
            }
        }
        if (!dup) try unique.append(a, comp);
    }
    if (unique.items.len > 1 and has_any) {
        var kept = std.ArrayList(Comparator).empty;
        for (unique.items) |comp| {
            if (comp.value.len > 0) try kept.append(a, comp);
        }
        unique = kept;
    }
    if (unique.items.len == 0) {
        try unique.append(a, .{ .operator = .none, .semver = null, .value = "" });
    }
    return unique.toOwnedSlice(a);
}

fn stripBuild(a: std.mem.Allocator, s: []const u8) Error![]const u8 {
    var out = std.ArrayList(u8).empty;
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '+') {
            // Consume the longest valid build sequence: identifiers of
            // [a-zA-Z0-9-]+ separated by single dots.
            var j = i + 1;
            var last_id_end: ?usize = null;
            while (j < s.len) {
                const start = j;
                while (j < s.len and (std.ascii.isAlphanumeric(s[j]) or s[j] == '-')) j += 1;
                if (j == start) break;
                last_id_end = j;
                if (j < s.len and s[j] == '.' and j + 1 < s.len and
                    (std.ascii.isAlphanumeric(s[j + 1]) or s[j + 1] == '-'))
                {
                    j += 1;
                } else break;
            }
            if (last_id_end) |end| {
                i = end;
                continue;
            }
        }
        try out.append(a, s[i]);
        i += 1;
    }
    return out.toOwnedSlice(a);
}

/// `A - B` -> `>=A0 <=B`, matching upstream's hyphen desugaring.
fn tryHyphenReplace(a: std.mem.Allocator, s: []const u8, options: Options) Error![]const u8 {
    const idx = std.mem.indexOf(u8, s, " - ") orelse return s;
    const left = std.mem.trim(u8, s[0..idx], " ");
    const right = std.mem.trim(u8, s[idx + 3 ..], " ");

    const from_x = parseXRangePlain(left, options.loose) orelse return s;
    const to_x = parseXRangePlain(right, options.loose) orelse return s;
    if (left.len == 0 or right.len == 0) return s;

    const inc_pr = options.include_prerelease;

    var from_buf = std.ArrayList(u8).empty;
    if (isX(from_x.major)) {
        from_buf.clearRetainingCapacity();
    } else if (isX(from_x.minor)) {
        try from_buf.print(a, ">={d}.0.0{s}", .{ partNumber(from_x.major), if (inc_pr) "-0" else "" });
    } else if (isX(from_x.patch)) {
        try from_buf.print(a, ">={d}.{d}.0{s}", .{ partNumber(from_x.major), partNumber(from_x.minor), if (inc_pr) "-0" else "" });
    } else if (from_x.prerelease != null) {
        try from_buf.print(a, ">={s}", .{left});
    } else {
        try from_buf.print(a, ">={s}{s}", .{ left, if (inc_pr) "-0" else "" });
    }

    var to_buf = std.ArrayList(u8).empty;
    if (isX(to_x.major)) {
        to_buf.clearRetainingCapacity();
    } else if (isX(to_x.minor)) {
        try to_buf.print(a, "<{d}.0.0-0", .{partNumber(to_x.major) + 1});
    } else if (isX(to_x.patch)) {
        try to_buf.print(a, "<{d}.{d}.0-0", .{ partNumber(to_x.major), partNumber(to_x.minor) + 1 });
    } else if (to_x.prerelease != null) {
        try to_buf.print(a, "<={d}.{d}.{d}-{s}", .{ partNumber(to_x.major), partNumber(to_x.minor), partNumber(to_x.patch), to_x.prerelease.? });
    } else if (inc_pr) {
        try to_buf.print(a, "<{d}.{d}.{d}-0", .{ partNumber(to_x.major), partNumber(to_x.minor), partNumber(to_x.patch) + 1 });
    } else {
        try to_buf.print(a, "<={s}", .{right});
    }

    if (from_buf.items.len == 0 and to_buf.items.len == 0) return try a.dupe(u8, "");
    if (from_buf.items.len == 0) return to_buf.toOwnedSlice(a);
    if (to_buf.items.len == 0) return from_buf.toOwnedSlice(a);
    return std.mem.concat(a, u8, &.{ from_buf.items, " ", to_buf.items });
}

/// Merge an operator token with the version that follows it.
fn mergeOperatorSpacing(a: std.mem.Allocator, tokens: *std.ArrayList([]const u8)) Error!void {
    var merged = std.ArrayList([]const u8).empty;
    var i: usize = 0;
    while (i < tokens.items.len) : (i += 1) {
        const tok = tokens.items[i];
        const is_op = std.mem.eql(u8, tok, "<") or std.mem.eql(u8, tok, ">") or
            std.mem.eql(u8, tok, "<=") or std.mem.eql(u8, tok, ">=") or
            std.mem.eql(u8, tok, "~") or std.mem.eql(u8, tok, "~>") or
            std.mem.eql(u8, tok, "^");
        if (is_op and i + 1 < tokens.items.len) {
            try merged.append(a, try std.mem.concat(a, u8, &.{ tok, tokens.items[i + 1] }));
            i += 1;
        } else {
            try merged.append(a, tok);
        }
    }
    tokens.* = merged;
}

fn replaceCaret(a: std.mem.Allocator, tok: []const u8, options: Options) Error![]const u8 {
    var body = tok;
    if (body.len > 0 and body[0] == '^') {
        body = body[1..];
    } else return tok;

    const x = parseXRangePlain(body, options.loose) orelse return tok;
    if (invalidXOrder(&x)) return tok;

    const inc_pr = options.include_prerelease;
    const z: []const u8 = if (inc_pr) "-0" else "";

    const M = partNumber(x.major);
    const m = partNumber(x.minor);
    const p = partNumber(x.patch);
    const m_is_zero = x.minor == .number and m == 0;
    const M_is_zero = x.major == .number and M == 0;

    if (isX(x.major)) {
        return try a.dupe(u8, "");
    } else if (isX(x.minor)) {
        return std.fmt.allocPrint(a, ">={d}.0.0{s} <{d}.0.0-0", .{ M, z, M + 1 });
    } else if (isX(x.patch)) {
        if (M_is_zero) {
            return std.fmt.allocPrint(a, ">={d}.{d}.0{s} <{d}.{d}.0-0", .{ M, m, z, M, m + 1 });
        }
        return std.fmt.allocPrint(a, ">={d}.{d}.0{s} <{d}.0.0-0", .{ M, m, z, M + 1 });
    } else if (x.prerelease) |pr| {
        if (M_is_zero and m_is_zero) {
            return std.fmt.allocPrint(a, ">={d}.{d}.{d}-{s} <{d}.{d}.{d}-0", .{ M, m, p, pr, M, m, p + 1 });
        } else if (M_is_zero) {
            return std.fmt.allocPrint(a, ">={d}.{d}.{d}-{s} <{d}.{d}.0-0", .{ M, m, p, pr, M, m + 1 });
        }
        return std.fmt.allocPrint(a, ">={d}.{d}.{d}-{s} <{d}.0.0-0", .{ M, m, p, pr, M + 1 });
    } else {
        if (M_is_zero and m_is_zero) {
            return std.fmt.allocPrint(a, ">={d}.{d}.{d} <{d}.{d}.{d}-0", .{ M, m, p, M, m, p + 1 });
        } else if (M_is_zero) {
            return std.fmt.allocPrint(a, ">={d}.{d}.{d} <{d}.{d}.0-0", .{ M, m, p, M, m + 1 });
        }
        return std.fmt.allocPrint(a, ">={d}.{d}.{d} <{d}.0.0-0", .{ M, m, p, M + 1 });
    }
}

fn replaceTilde(a: std.mem.Allocator, tok: []const u8, options: Options) Error![]const u8 {
    var body = tok;
    if (body.len > 0 and body[0] == '~') {
        body = body[1..];
        if (body.len > 0 and body[0] == '>') body = body[1..];
    } else return tok;

    const x = parseXRangePlain(body, options.loose) orelse return tok;
    if (invalidXOrder(&x)) return tok;

    const inc_pr = options.include_prerelease;
    const z: []const u8 = if (inc_pr) "-0" else "";

    const M = partNumber(x.major);
    const m = partNumber(x.minor);
    const p = partNumber(x.patch);

    if (isX(x.major)) {
        return try a.dupe(u8, "");
    } else if (isX(x.minor)) {
        return std.fmt.allocPrint(a, ">={d}.0.0{s} <{d}.0.0-0", .{ M, z, M + 1 });
    } else if (isX(x.patch)) {
        return std.fmt.allocPrint(a, ">={d}.{d}.0{s} <{d}.{d}.0-0", .{ M, m, z, M, m + 1 });
    } else if (x.prerelease) |pr| {
        return std.fmt.allocPrint(a, ">={d}.{d}.{d}-{s} <{d}.{d}.0-0", .{ M, m, p, pr, M, m + 1 });
    } else {
        return std.fmt.allocPrint(a, ">={d}.{d}.{d} <{d}.{d}.0-0", .{ M, m, p, M, m + 1 });
    }
}

fn replaceXRange(a: std.mem.Allocator, tok: []const u8, options: Options) Error![]const u8 {
    var gtlt: ?[]const u8 = null;
    var body = tok;
    if (body.len > 0 and (body[0] == '<' or body[0] == '>')) {
        var op_len: usize = 1;
        if (body.len > 1 and body[1] == '=') op_len = 2;
        gtlt = body[0..op_len];
        body = body[op_len..];
    }

    const x = parseXRangePlain(body, options.loose) orelse return tok;
    if (invalidXOrder(&x)) return tok;

    const inc_pr = options.include_prerelease;

    const xM = isX(x.major);
    const xm = xM or isX(x.minor);
    const xp = xm or isX(x.patch);
    const any_x = xp;

    var op = gtlt;
    if (op != null and std.mem.eql(u8, op.?, "=")) op = null;

    const M = partNumber(x.major);
    const m = partNumber(x.minor);

    var pr: []const u8 = if (inc_pr) "-0" else "";

    if (xM) {
        if (op) |o| {
            if (std.mem.eql(u8, o, ">") or std.mem.eql(u8, o, "<")) {
                return a.dupe(u8, null_set_value);
            }
        }
        return a.dupe(u8, "*");
    } else if (op != null and any_x) {
        var M2 = M;
        var m2: u64 = if (isX(x.minor)) 0 else m;
        const p2: u64 = 0;
        var op2 = op.?;
        if (std.mem.eql(u8, op2, ">")) {
            op2 = ">=";
            if (isX(x.minor)) {
                M2 = M + 1;
                m2 = 0;
            } else {
                m2 = m2 + 1;
            }
        } else if (std.mem.eql(u8, op2, "<=")) {
            op2 = "<";
            if (isX(x.minor)) {
                M2 = M + 1;
            } else {
                m2 = m2 + 1;
            }
        }
        if (std.mem.eql(u8, op2, "<")) pr = "-0";
        return std.fmt.allocPrint(a, "{s}{d}.{d}.{d}{s}", .{ op2, M2, m2, p2, pr });
    } else if (xm) {
        return std.fmt.allocPrint(a, ">={d}.0.0{s} <{d}.0.0-0", .{ M, pr, M + 1 });
    } else if (xp) {
        return std.fmt.allocPrint(a, ">={d}.{d}.0{s} <{d}.{d}.0-0", .{ M, m, pr, M, m + 1 });
    }
    return tok;
}

fn invalidXOrder(x: *const XRange) bool {
    const M_x = isX(x.major);
    const m_x = isX(x.minor);
    const p_x = isX(x.patch);
    return (M_x and !m_x) or (m_x and !p_x and x.patch != .any and !isX(x.patch));
}

fn isGteZero(tok: []const u8) bool {
    return std.mem.eql(u8, tok, ">=0.0.0") or std.mem.eql(u8, tok, ">=0.0.0-0");
}

fn stripStar(a: std.mem.Allocator, tok: []const u8) Error![]const u8 {
    var i: usize = 0;
    while (i < tok.len and (tok[i] == '<' or tok[i] == '>' or tok[i] == '=')) i += 1;
    while (i < tok.len and tok[i] == ' ') i += 1;
    if (i < tok.len and tok[i] == '*') {
        var k = i + 1;
        while (k < tok.len and tok[k] == ' ') k += 1;
        if (k == tok.len) return a.dupe(u8, "");
    }
    return tok;
}

fn parseComparator(a: std.mem.Allocator, tok: []const u8, options: Options) Error!Comparator {
    var op: Comparator.Operator = .none;
    var body = tok;
    if (body.len > 0 and body[0] == '=') {
        body = body[1..];
    } else if (body.len > 0 and (body[0] == '<' or body[0] == '>')) {
        if (body.len > 1 and body[1] == '=') {
            op = if (body[0] == '<') .lte else .gte;
            body = body[2..];
        } else {
            op = if (body[0] == '<') .lt else .gt;
            body = body[1..];
        }
    }

    const v = Version.parse(body, options) catch return error.InvalidComparator;

    const op_str = switch (op) {
        .none => "",
        .lt => "<",
        .lte => "<=",
        .gt => ">",
        .gte => ">=",
    };
    const version_str = try v.toString(a);
    const value = try std.mem.concat(a, u8, &.{ op_str, version_str });

    return .{ .operator = op, .semver = v, .value = value };
}

/// `satisfies(version, range)`: unparseable ranges match nothing.
pub fn satisfies(allocator: std.mem.Allocator, version: []const u8, range: []const u8, options: Options) bool {
    const v = Version.parse(version, options) catch return false;
    var r = Range.parse(allocator, range, options) catch return false;
    defer r.deinit();
    return applyPrereleaseGate(r.set, v, options) and r.testVersion(v);
}

/// The prerelease rule shared by `testSet` upstream: a version with a
/// prerelease only matches when some comparator pins that same
/// major.minor.patch with a prerelease of its own.
fn applyPrereleaseGate(set: []const []const Comparator, v: Version, options: Options) bool {
    if (v.prerelease.len == 0 or options.include_prerelease) return true;

    for (set) |comps| {
        var all_match = true;
        for (comps) |comp| {
            if (!comp.matches(v)) {
                all_match = false;
                break;
            }
        }
        if (!all_match) continue;

        for (comps) |comp| {
            const s = comp.semver orelse continue;
            if (s.prerelease.len > 0 and
                s.major == v.major and s.minor == v.minor and s.patch == v.patch)
            {
                return true;
            }
        }
    }
    return false;
}
