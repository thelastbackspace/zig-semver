# semver

Semantic version parsing, comparison, and range matching.

```zig
const semver = @import("semver");

const v = try semver.Version.parse("1.2.3-alpha.7", .{});
const v2 = try semver.Version.parse("1.2.3", .{});

const ord = v.compare(v2); // .lt: a prerelease sorts below its release

// Ranges: caret, tilde, x-ranges, hyphen ranges, and `||` unions.
const ok = semver.satisfies(allocator, "1.9.2", "^1.2.3", .{}); // true
const no = semver.satisfies(allocator, "2.0.0", "^1.2.3", .{}); // false
// Prerelease gating matches npm: "1.2.3-pre" does not satisfy "^1.2.3".
```

## Installation

Requires Zig 0.16.0.

```sh
zig fetch --save git+https://github.com/thelastbackspace/zig-semver#v1.0.0
```

Then in `build.zig`:

```zig
const semver = b.dependency("semver", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("semver", semver.module("semver"));
```

## API

### `Version`

`Version.parse(text, options)` parses without allocating; the
returned struct borrows its string fields from `text`:

- `major`, `minor`, `patch` — numeric components.
- `prerelease`, `build` — raw slices without the `-`/`+`.
- `compare`, `compareMain`, `comparePrerelease`, `compareBuild` —
  precedence ordering (`std.math.Order`); a release sorts above any
  prerelease of the same main version, and build metadata is ignored
  for precedence but ordered by `compareBuild`.
- `toString(allocator)` — canonical `M.m.p[-pre]` string; caller owns.
- `inc(allocator, release, identifier, identifier_base)` — bump to the
  next `major`/`minor`/`patch`/`premajor`/…/`prerelease`/`release`,
  with an optional prerelease identifier (`"beta"`, `"alpha.beta"`) and
  numeric base (`"0"`/`"1"`, or `.off` to suppress the suffix). The
  result borrows from `allocator`.

### `Options`

- `loose: bool = false` — accept `v`/`=`/whitespace prefixes, leading
  zeros, and a hyphen-less prerelease (`1.2.3alpha`).
- `include_prerelease: bool = false` — let prerelease versions satisfy
  ranges like releases.

### Ranges

`Range.parse(allocator, range, options)` desugars `^1.2.3`, `~1.2`,
`1.2.x`, `1.0.0 - 2.0.0`, comparators (`>`, `>=`, `<`, `<=`, `=`), and
`||` unions into comparator sets; `deinit` frees everything.

- `range.testVersion(v)` / `satisfies(allocator, version, range,
  options)` — match, with npm's prerelease rule: a prerelease version
  only matches when a comparator pins its exact `major.minor.patch`
  with a prerelease.
- `range.format()` — the canonical comparator form.
- `range.intersects(other, options)` — whether the ranges overlap.
- `range.toComparators()` — the desugared sets.

### Free functions

`valid`, `clean`, `coerce` (leftmost or `.rtl` rightmost plausible
version in arbitrary text), `truncate`, `diff`, `cmp`/`gt`/`gte`/`lt`/
`lte`/`eq`/`neq`, `major`/`minor`/`patch`.

## Notes

- Numeric fields are bounded by JavaScript's `Number.MAX_SAFE_INTEGER`,
  matching upstream exactly.
- Not ported from upstream: `ltr`/`gtr`/`outside`, `subset`,
  `minVersion`/`maxSatisfying`, the CLI, and the `loose` mode's
  branch-dropping tolerance is implemented only where upstream
  documents it.
- `Version.parse` does not allocate; comparisons walk the raw
  prerelease strings, so no setup or teardown is needed for matching
  parsed versions.

## Testing

```sh
zig build test
```

The suite ports upstream's table fixtures (valid/invalid versions,
equality, comparisons, increments, truncations, range canonical
forms, satisfies tables, and intersections) — about 670 assertions.

## Contributing

PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). The CI gate
(`zig fmt --check`, tests, build) must pass.

## Credits

Behavior and the test suite follow the npm package
[`semver`](https://github.com/npm/node-semver) v7.8.5 (ISC, © Isaac Z.
Schlueter and Contributors); the implementation is original. Zig
implementation © 2026 thelastbackspace, ISC — see [LICENSE](LICENSE).
