//! Semantic version parsing, comparison, and range matching — a port
//! of the npm `semver` package (v7.8.5) to Zig.
//!
//! The upstream test suite is ported in `tests.zig`; see README.md for
//! the API surface and intentional divergences.

const std = @import("std");

pub const version_mod = @import("version.zig");
pub const range_mod = @import("range.zig");

pub const Version = version_mod.Version;
pub const Identifier = version_mod.Identifier;
pub const IdentifierBase = version_mod.IdentifierBase;
pub const Options = version_mod.Options;
pub const Diff = version_mod.Diff;
pub const max_length = version_mod.max_length;
pub const max_safe_integer = version_mod.max_safe_integer;

pub const Comparator = range_mod.Comparator;
pub const Range = range_mod.Range;
pub const RangeError = range_mod.Error;

pub const Error = version_mod.Error;

pub const parse = Version.parse;
pub const valid = version_mod.valid;
pub const clean = version_mod.clean;
pub const major = version_mod.major;
pub const minor = version_mod.minor;
pub const patch = version_mod.patch;
pub const diff = version_mod.diff;
pub const satisfies = range_mod.satisfies;
pub const coerce = version_mod.coerce;
pub const CoerceOptions = version_mod.CoerceOptions;
pub const truncate = version_mod.truncate;

/// Comparison operators accepted by [`cmp`].
pub const Operator = enum { lt, lte, gt, gte, eq, neq };

/// `cmp(a, op, b)` with parsed versions.
pub fn cmp(a: Version, op: Operator, b: Version) bool {
    const ord = a.compare(b);
    return switch (op) {
        .lt => ord == .lt,
        .lte => ord != .gt,
        .gt => ord == .gt,
        .gte => ord != .lt,
        .eq => ord == .eq,
        .neq => ord != .eq,
    };
}

/// `gt`/`gte`/`lt`/`lte`/`eq`/`neq` on version strings.
pub fn gt(a: Version, b: Version) bool {
    return a.compare(b) == .gt;
}

pub fn gte(a: Version, b: Version) bool {
    return a.compare(b) != .lt;
}

pub fn lt(a: Version, b: Version) bool {
    return a.compare(b) == .lt;
}

pub fn lte(a: Version, b: Version) bool {
    return a.compare(b) != .gt;
}

pub fn eq(a: Version, b: Version) bool {
    return a.compare(b) == .eq;
}

pub fn neq(a: Version, b: Version) bool {
    return a.compare(b) != .eq;
}

/// `compareBuild`: full ordering including build metadata.
pub fn compareBuild(a: Version, b: Version) std.math.Order {
    return a.compareBuild(b);
}

test {
    _ = version_mod;
    _ = range_mod;
    _ = @import("tests.zig");
}
