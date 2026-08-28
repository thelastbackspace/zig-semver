//! Version parsing, comparison, coercion, and incrementing.

const std = @import("std");

/// The maximum input length accepted by [`Version.parse`].
pub const max_length = 256;

/// JavaScript's `Number.MAX_SAFE_INTEGER`, the upper bound on the
/// numeric fields of a version.
pub const max_safe_integer: u64 = 9007199254740991;

/// Options shared by the parsing entry points.
pub const Options = struct {
    /// Accept sloppy versions: `v`/`=`/whitespace prefixes, leading
    /// zeros, and a prerelease without its leading `-`.
    loose: bool = false,
    /// Treat prerelease versions like releases inside ranges.
    include_prerelease: bool = false,
};

pub const Error = error{
    InvalidVersion,
    VersionTooLong,
    InvalidIncrement,
    InvalidIdentifier,
} || std.mem.Allocator.Error;

/// A parsed semantic version.
///
/// `Version` borrows its string fields from the input it was parsed
/// from and performs no allocation, so it lives as long as that text.
/// Versions produced by [`Version.inc`] instead borrow from the
/// allocator given there.
pub const Version = struct {
    major: u64,
    minor: u64,
    patch: u64,
    /// The prerelease, without its leading `-`; empty for a release.
    prerelease: []const u8,
    /// The build metadata, without its leading `+`; empty when absent.
    build: []const u8,
    /// The input as given (trimmed).
    raw: []const u8,

    /// Parse a version string. In strict mode (the default) this
    /// accepts exactly the semver.org grammar with an optional leading
    /// `v`; in loose mode it also accepts `=`/whitespace prefixes,
    /// leading zeros, and a prerelease written without its hyphen.
    pub fn parse(text: []const u8, options: Options) Error!Version {
        if (text.len > max_length) return error.VersionTooLong;
        const s = trimAsciiWhitespace(text);

        var p = Parser{ .s = s, .loose = options.loose };
        return p.version();
    }

    /// Render `major.minor.patch[-prerelease]` (no build metadata),
    /// matching upstream's `version`/`format()`. Caller owns the result.
    pub fn toString(self: Version, allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
        var buf = std.ArrayList(u8).empty;
        errdefer buf.deinit(allocator);
        try buf.print(allocator, "{d}.{d}.{d}", .{ self.major, self.minor, self.patch });
        if (self.prerelease.len > 0) {
            try buf.print(allocator, "-{s}", .{self.prerelease});
        }
        return buf.toOwnedSlice(allocator);
    }

    /// True when the version carries a prerelease.
    pub fn isPrerelease(self: Version) bool {
        return self.prerelease.len > 0;
    }

    /// Precedence comparison (`compare` upstream): main version, then
    /// prerelease, where a release sorts after any prerelease of the
    /// same main version. Build metadata is ignored.
    pub fn compare(self: Version, other: Version) std.math.Order {
        const main = self.compareMain(other);
        if (main != .eq) return main;
        return comparePrereleaseText(self.prerelease, other.prerelease);
    }

    /// Compare only `major.minor.patch`.
    pub fn compareMain(self: Version, other: Version) std.math.Order {
        const a = std.math.order(self.major, other.major);
        if (a != .eq) return a;
        const b = std.math.order(self.minor, other.minor);
        if (b != .eq) return b;
        return std.math.order(self.patch, other.patch);
    }

    /// Compare only the prerelease identifiers.
    pub fn comparePrerelease(self: Version, other: Version) std.math.Order {
        return comparePrereleaseText(self.prerelease, other.prerelease);
    }

    /// Compare build metadata: only relevant for ordering two versions
    /// with identical precedence.
    pub fn compareBuild(self: Version, other: Version) std.math.Order {
        return compareIdentifiedText(self.build, other.build);
    }

    /// The release type of an increment step, mirroring upstream's
    /// `RELEASE_TYPES`.
    pub const ReleaseType = enum {
        premajor,
        preminor,
        prepatch,
        prerelease,
        release,
        major,
        minor,
        patch,
        pre,
    };

    /// Increment the version. `identifier` names a prerelease (e.g.
    /// `"beta"`, or `"alpha.beta"` for dotted names). `identifier_base`
    /// mirrors upstream's `identifierBase`: `.default` is `undefined`,
    /// `.off` is the literal `false` (which suppresses the trailing
    /// `.0` and errors on some inputs), and `.value` holds a numeric
    /// string like `"0"` or `"1"`.
    ///
    /// The returned version's `raw` and `prerelease` are allocated with
    /// `allocator`; free them or keep the allocator as an arena.
    pub fn inc(
        self: Version,
        allocator: std.mem.Allocator,
        release: ReleaseType,
        identifier: ?[]const u8,
        identifier_base: IdentifierBase,
    ) Error!Version {
        var v = self;
        const id: ?[]const u8 = if (identifier != null and identifier.?.len > 0) identifier else null;
        const base = identifierBaseValue(identifier_base);

        if (isPreReleaseType(release)) {
            if (id == null and identifier_base == .off) {
                return error.InvalidIncrement;
            }
            if (id) |ident| {
                if (!validPrereleaseIdentifier(ident)) return error.InvalidIdentifier;
            }
        }

        switch (release) {
            .premajor => {
                v.prerelease = "";
                v.patch = 0;
                v.minor = 0;
                v.major += 1;
                return v.inc(allocator, .pre, id, identifier_base);
            },
            .preminor => {
                v.prerelease = "";
                v.patch = 0;
                v.minor += 1;
                return v.inc(allocator, .pre, id, identifier_base);
            },
            .prepatch => {
                v.prerelease = "";
                v = try v.inc(allocator, .patch, id, identifier_base);
                return v.inc(allocator, .pre, id, identifier_base);
            },
            .prerelease => {
                if (v.prerelease.len == 0) {
                    v = try v.inc(allocator, .patch, id, identifier_base);
                }
                return v.inc(allocator, .pre, id, identifier_base);
            },
            .release => {
                if (v.prerelease.len == 0) return error.InvalidIncrement;
                v.prerelease = "";
            },
            .major => {
                if (v.minor != 0 or v.patch != 0 or v.prerelease.len == 0) {
                    v.major += 1;
                }
                v.minor = 0;
                v.patch = 0;
                v.prerelease = "";
            },
            .minor => {
                if (v.patch != 0 or v.prerelease.len == 0) {
                    v.minor += 1;
                }
                v.patch = 0;
                v.prerelease = "";
            },
            .patch => {
                if (v.prerelease.len == 0) {
                    v.patch += 1;
                }
                v.prerelease = "";
            },
            .pre => {
                v.prerelease = try bumpPrerelease(allocator, v.prerelease, id, identifier_base, base);
            },
        }

        v.raw = try v.toString(allocator);
        if (v.build.len > 0) {
            const raw = try std.mem.concat(allocator, u8, &.{ v.raw, "+", v.build });
            v.raw = raw;
        }
        return v;
    }
};

/// The three states of upstream's `identifierBase` increment argument.
pub const IdentifierBase = union(enum) {
    /// `undefined`: numeric base defaults to 0.
    default,
    /// The literal `false`: base 0, and the `.0` suffix is suppressed.
    off,
    /// A numeric string such as `"0"` or `"1"`.
    value: []const u8,
};

fn identifierBaseValue(b: IdentifierBase) u64 {
    const v = switch (b) {
        .value => |s| std.fmt.parseInt(i64, s, 10) catch return 0,
        else => return 0,
    };
    return if (v != 0) 1 else 0;
}

fn isPreReleaseType(r: Version.ReleaseType) bool {
    return switch (r) {
        .premajor, .preminor, .prepatch, .prerelease, .pre => true,
        else => false,
    };
}

/// The `.pre` increment: bump the trailing numeric identifier, or
/// append the base; restart at `identifier` when it names a new
/// prerelease.
fn bumpPrerelease(
    allocator: std.mem.Allocator,
    raw: []const u8,
    identifier: ?[]const u8,
    identifier_base: IdentifierBase,
    base: u64,
) Error![]const u8 {
    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(allocator);

    if (raw.len == 0) {
        try buf.print(allocator, "{d}", .{base});
    } else {
        // Find the last numeric identifier.
        var spans = std.mem.splitScalar(u8, raw, '.');
        var last_numeric: ?usize = null; // byte offset of its start
        var offset: usize = 0;
        var first = true;
        while (spans.next()) |part| {
            if (!first) offset += 1;
            first = false;
            if (allDigits(part) and parseIntSafe(part) != null) {
                last_numeric = offset;
            }
            offset += part.len;
        }

        if (last_numeric) |start| {
            try buf.appendSlice(allocator, raw[0..start]);
            var end = start;
            while (end < raw.len and raw[end] != '.') end += 1;
            const n = parseIntSafe(raw[start..end]).?;
            try buf.print(allocator, "{d}", .{n + 1});
            try buf.appendSlice(allocator, raw[end..]);
        } else {
            if (identifier) |ident| {
                if (std.mem.eql(u8, raw, ident) and identifier_base == .off) {
                    return error.InvalidIncrement;
                }
            }
            try buf.appendSlice(allocator, raw);
            try buf.print(allocator, ".{d}", .{base});
        }
    }

    if (identifier) |ident| {
        var with_base = std.ArrayList(u8).empty;
        errdefer with_base.deinit(allocator);
        try with_base.appendSlice(allocator, ident);
        if (identifier_base != .off) {
            try with_base.print(allocator, ".{d}", .{base});
        }

        // When the identifier already prefixes the prerelease, keep the
        // bumped form only if the component after the prefix is
        // numeric; otherwise restart at `identifier`.
        if (isPrereleasePrefix(raw, ident)) {
            const parts = countDots(ident) + 1;
            const after = identifierPartAt(raw, parts);
            const replace = after == null or !allDigits(after.?);
            if (replace) return with_base.toOwnedSlice(allocator);
            return buf.toOwnedSlice(allocator);
        }
        return with_base.toOwnedSlice(allocator);
    }
    return buf.toOwnedSlice(allocator);
}

fn parseIntSafe(s: []const u8) ?u64 {
    if (s.len == 0 or s.len > 20) return null;
    return std.fmt.parseInt(u64, s, 10) catch null;
}

fn countDots(s: []const u8) usize {
    var n: usize = 0;
    for (s) |c| {
        if (c == '.') n += 1;
    }
    return n;
}

/// The dot-separated part of `raw` at index `i`, or null when absent.
fn identifierPartAt(raw: []const u8, i: usize) ?[]const u8 {
    var it = std.mem.splitScalar(u8, raw, '.');
    var n: usize = 0;
    while (it.next()) |part| {
        if (n == i) return part;
        n += 1;
    }
    return null;
}

/// True when every part of `identifier` matches the start of `raw`'s
/// dot-separated identifiers.
fn isPrereleasePrefix(raw: []const u8, identifier: []const u8) bool {
    if (identifier.len == 0) return false;
    var raw_it = std.mem.splitScalar(u8, raw, '.');
    var id_it = std.mem.splitScalar(u8, identifier, '.');
    while (id_it.next()) |part| {
        const raw_part = raw_it.next() orelse return false;
        // Numeric parts must match by value ("01" == "1" after the
        // constructor numberifies them).
        if (allDigits(part) and allDigits(raw_part)) {
            const a = parseIntSafe(part) orelse return false;
            const b = parseIntSafe(raw_part) orelse return false;
            if (a != b) return false;
        } else if (!std.mem.eql(u8, raw_part, part)) {
            return false;
        }
    }
    return true;
}

/// A valid standalone prerelease identifier (used to validate the
/// `identifier` argument of [`Version.inc`]).
fn validPrereleaseIdentifier(id: []const u8) bool {
    var it = std.mem.splitScalar(u8, id, '.');
    var count: usize = 0;
    while (it.next()) |part| {
        count += 1;
        if (part.len == 0) return false;
        var has_letter_or_hyphen = false;
        for (part) |c| {
            if (!(std.ascii.isAlphanumeric(c) or c == '-')) return false;
            if (std.ascii.isAlphabetic(c) or c == '-') has_letter_or_hyphen = true;
        }
        if (!has_letter_or_hyphen) {
            if (part.len > 1 and part[0] == '0') return false;
        }
    }
    return count > 0;
}

/// Walk two dot-separated identifier lists in lockstep, comparing each
/// pair: numeric identifiers compare numerically and sort before
/// alphanumeric ones.
fn compareIdentifiedText(a: []const u8, b: []const u8) std.math.Order {
    if (a.len == 0 and b.len == 0) return .eq;
    if (a.len == 0) return .gt;
    if (b.len == 0) return .lt;

    var ai = std.mem.splitScalar(u8, a, '.');
    var bi = std.mem.splitScalar(u8, b, '.');
    while (true) {
        const ap = ai.next();
        const bp = bi.next();
        if (ap == null and bp == null) return .eq;
        if (ap == null) return .lt;
        if (bp == null) return .gt;
        const ord = compareIdentifierText(ap.?, bp.?);
        if (ord != .eq) return ord;
    }
}

fn comparePrereleaseText(a: []const u8, b: []const u8) std.math.Order {
    return compareIdentifiedText(a, b);
}

fn compareIdentifierText(a: []const u8, b: []const u8) std.math.Order {
    const an = allDigits(a);
    const bn = allDigits(b);
    if (an and bn) {
        const x = parseIntSafe(a);
        const y = parseIntSafe(b);
        // Out-of-range or unsafe-large numerics stay textual upstream.
        if (x != null and y != null and x.? < max_safe_integer and y.? < max_safe_integer) {
            return std.math.order(x.?, y.?);
        }
        return std.mem.order(u8, a, b);
    }
    if (an) return .lt;
    if (bn) return .gt;
    return std.mem.order(u8, a, b);
}

const Parser = struct {
    s: []const u8,
    i: usize = 0,
    loose: bool,

    fn peek(self: *Parser) ?u8 {
        if (self.i >= self.s.len) return null;
        return self.s[self.i];
    }

    fn version(self: *Parser) Error!Version {
        if (self.loose) {
            while (self.peek()) |c| {
                if (c == 'v' or c == '=' or isAsciiWhitespace(c)) {
                    self.i += 1;
                } else break;
            }
        } else if (self.peek() == 'v') {
            self.i += 1;
        }

        const major_v = try self.numericIdentifier();
        try self.expect('.');
        const minor_v = try self.numericIdentifier();
        try self.expect('.');
        const patch_v = try self.numericIdentifier();

        var prerelease: []const u8 = "";
        if (self.loose and self.peek() != null and self.peek().? != '-' and self.peek().? != '+' and self.i < self.s.len) {
            const start = self.i;
            try self.skipPrerelease();
            prerelease = self.s[start..self.i];
        } else if (self.peek() == '-') {
            self.i += 1;
            const start = self.i;
            try self.skipPrerelease();
            prerelease = self.s[start..self.i];
        }

        var build: []const u8 = "";
        if (self.peek() == '+') {
            self.i += 1;
            const start = self.i;
            try self.skipBuild();
            build = self.s[start..self.i];
        }

        if (self.i != self.s.len) return error.InvalidVersion;
        if (major_v == null or minor_v == null or patch_v == null) return error.InvalidVersion;

        return .{
            .major = major_v.?,
            .minor = minor_v.?,
            .patch = patch_v.?,
            .prerelease = prerelease,
            .build = build,
            .raw = self.s,
        };
    }

    fn expect(self: *Parser, c: u8) Error!void {
        if (self.peek() != c) return error.InvalidVersion;
        self.i += 1;
    }

    /// `0` or a non-zero digit run in strict mode; any digit run in
    /// loose mode. Values above `max_safe_integer` are rejected.
    fn numericIdentifier(self: *Parser) Error!?u64 {
        const start = self.i;
        while (self.peek()) |c| {
            if (std.ascii.isDigit(c)) self.i += 1 else break;
        }
        if (self.i == start) return null;
        const digits = self.s[start..self.i];
        if (!self.loose and digits.len > 1 and digits[0] == '0') return error.InvalidVersion;
        const n = std.fmt.parseInt(u64, digits, 10) catch return error.InvalidVersion;
        if (n > max_safe_integer) return error.InvalidVersion;
        return n;
    }

    /// Consume dot-separated prerelease identifiers, validating each.
    fn skipPrerelease(self: *Parser) Error!void {
        while (true) {
            const start = self.i;
            while (self.peek()) |c| {
                if (std.ascii.isAlphanumeric(c) or c == '-') self.i += 1 else break;
            }
            if (self.i == start) return error.InvalidVersion;
            const id = self.s[start..self.i];
            if (allDigits(id)) {
                // A bare digit run must be a valid numeric identifier.
                if (!self.loose and id.len > 1 and id[0] == '0') return error.InvalidVersion;
                if (parseIntSafe(id) == null) return error.InvalidVersion;
            }
            if (self.peek() == '.') {
                self.i += 1;
            } else {
                break;
            }
        }
    }

    /// Consume dot-separated build identifiers.
    fn skipBuild(self: *Parser) Error!void {
        while (true) {
            const start = self.i;
            while (self.peek()) |c| {
                if (std.ascii.isAlphanumeric(c) or c == '-') self.i += 1 else break;
            }
            if (self.i == start) return error.InvalidVersion;
            if (self.peek() == '.') {
                self.i += 1;
            } else {
                break;
            }
        }
    }
};

fn allDigits(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |c| {
        if (!std.ascii.isDigit(c)) return false;
    }
    return true;
}

fn isAsciiWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == 0x0B or c == 0x0C;
}

fn trimAsciiWhitespace(s: []const u8) []const u8 {
    var start: usize = 0;
    var end: usize = s.len;
    while (start < end and isAsciiWhitespace(s[start])) start += 1;
    while (end > start and isAsciiWhitespace(s[end - 1])) end -= 1;
    return s[start..end];
}

/// `valid`: parse and return the canonical version string, or null.
pub fn valid(allocator: std.mem.Allocator, text: []const u8, options: Options) std.mem.Allocator.Error!?[]u8 {
    const v = Version.parse(text, options) catch return null;
    return try v.toString(allocator);
}

/// `clean`: strip a leading `=`/`v` run and parse, or null.
pub fn clean(allocator: std.mem.Allocator, text: []const u8, options: Options) std.mem.Allocator.Error!?[]u8 {
    const trimmed = trimAsciiWhitespace(text);
    var start: usize = 0;
    while (start < trimmed.len and (trimmed[start] == '=' or trimmed[start] == 'v')) start += 1;
    const v = Version.parse(trimmed[start..], options) catch return null;
    return try v.toString(allocator);
}

/// `major`/`minor`/`patch` accessors: parse or fail.
pub fn major(text: []const u8, options: Options) Error!u64 {
    return (try Version.parse(text, options)).major;
}

pub fn minor(text: []const u8, options: Options) Error!u64 {
    return (try Version.parse(text, options)).minor;
}

pub fn patch(text: []const u8, options: Options) Error!u64 {
    return (try Version.parse(text, options)).patch;
}

pub const Diff = enum { major, premajor, minor, preminor, patch, prepatch, prerelease };

/// `diff`: the release type between two versions, or null when equal.
pub fn diff(a_text: []const u8, b_text: []const u8) Error!?Diff {
    const v1 = try Version.parse(a_text, .{});
    const v2 = try Version.parse(b_text, .{});

    const comparison = v1.compare(v2);
    if (comparison == .eq) return null;

    const v1_higher = comparison == .gt;
    const high = if (v1_higher) v1 else v2;
    const low = if (v1_higher) v2 else v1;
    const high_has_pre = high.prerelease.len > 0;
    const low_has_pre = low.prerelease.len > 0;

    if (low_has_pre and !high_has_pre) {
        if (low.patch == 0 and low.minor == 0) return .major;
        if (low.compareMain(high) == .eq) {
            if (low.minor != 0 and low.patch == 0) return .minor;
            return .patch;
        }
    }

    if (v1.major != v2.major) return if (high_has_pre) .premajor else .major;
    if (v1.minor != v2.minor) return if (high_has_pre) .preminor else .minor;
    if (v1.patch != v2.patch) return if (high_has_pre) .prepatch else .patch;
    return .prerelease;
}

/// Options for [`coerce`].
pub const CoerceOptions = struct {
    /// Prefer the rightmost extractable version.
    rtl: bool = false,
    include_prerelease: bool = false,
};

/// `coerce`: extract a version from arbitrary text (the first
/// plausible `major[.minor[.patch]]` run that parses as a version).
/// The returned version borrows strings allocated with `allocator`.
pub fn coerce(allocator: std.mem.Allocator, text: []const u8, options: CoerceOptions) std.mem.Allocator.Error!?Version {
    var best: ?[3][]const u8 = null;
    var best_count: usize = 0;
    var best_end: usize = 0;

    var i: usize = 0;
    while (i < text.len) {
        if (!std.ascii.isDigit(text[i]) or (i > 0 and std.ascii.isDigit(text[i - 1]))) {
            i += 1;
            continue;
        }
        var comps: [3][]const u8 = undefined;
        var count: usize = 0;
        var j = i;
        while (count < 3) {
            const start = j;
            while (j < text.len and std.ascii.isDigit(text[j])) j += 1;
            const digits = text[start..j];
            if (digits.len == 0 or digits.len > 16) break;
            comps[count] = digits;
            count += 1;
            if (count < 3 and j < text.len and text[j] == '.') {
                var k = j + 1;
                while (k < text.len and std.ascii.isDigit(text[k])) k += 1;
                if (k > j + 1 and k - (j + 1) <= 16) {
                    j += 1;
                    continue;
                }
            }
            break;
        }
        if (count == 0) {
            i += 1;
            continue;
        }
        if (j < text.len and std.ascii.isDigit(text[j])) {
            i = j;
            continue;
        }
        if (!options.rtl) {
            best = comps;
            best_count = count;
            break;
        }
        if (best == null or j > best_end) {
            best = comps;
            best_count = count;
            best_end = j;
        }
        i = j;
    }

    const found = best orelse return null;
    if (best_count == 0) return null;

    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(allocator);
    for (found[0..best_count], 0..) |c, idx| {
        if (idx > 0) try buf.append(allocator, '.');
        try buf.appendSlice(allocator, c);
    }
    for (0..3 - best_count) |_| {
        try buf.appendSlice(allocator, ".0");
    }
    const owned = try allocator.dupe(u8, buf.items);
    return Version.parse(owned, .{ .loose = true }) catch return null;
}

/// `truncate`: zero out the parts below a release type, keeping any
/// prerelease. Returns null for an invalid version.
pub fn truncate(allocator: std.mem.Allocator, text: []const u8, release: Version.ReleaseType, options: Options) std.mem.Allocator.Error!?[]u8 {
    var v = Version.parse(text, options) catch return null;
    switch (release) {
        .premajor, .preminor, .prepatch, .prerelease, .pre, .release => return try v.toString(allocator),
        .major => {
            v.minor = 0;
            v.patch = 0;
            v.prerelease = "";
        },
        .minor => {
            v.patch = 0;
            v.prerelease = "";
        },
        .patch => {
            v.prerelease = "";
        },
    }
    return try v.toString(allocator);
}
