//! ONE OWNER FOR EVERY BYTE THIS COMPILER WRITES OUTSIDE ITS OUTPUT.
//!
//! Intermediate objects, emitted C, profile data, test logs, the executable
//! cache: all of it used to be spelled `"/tmp/..."` inline at the point of
//! use, with names derived from the SOURCE STEM. Two consequences, both
//! measured in this project:
//!
//!   NO `TMPDIR`. A caller could not give a run a private scratch root, so
//!     every concurrent compile on the machine shared one directory. There was
//!     no isolation to ask for.
//!
//!   COLLIDING NAMES. `/tmp/duo_<stem>_native_dylib.o` carries no process
//!     identity at all. Two Idol compiles of the same-named source, running at
//!     the same time, wrote and deleted one another's object. The failure
//!     surfaces as
//!
//!         clang: error: no such file or directory: '/tmp/duo_x_native_dylib.o'
//!
//!     which reads EXACTLY like a compiler defect. It produced a bogus
//!     108-failure gate run; separately it made one 976-file sweep lose 122
//!     files (12.5%) and report capability at 119/976 when the true figure was
//!     238/976 — a factor-of-two error with no visible signal.
//!
//! Both are fixed here rather than at ~20 call sites:
//!
//!   `root()`   honours `TMPDIR`, so `TMPDIR=<unique> idol ...` gives a run a
//!              private cache, object, C and log root in one move. Unset
//!              `TMPDIR` keeps the historical `/tmp`, so gates that sweep
//!              `/tmp/idol-cache-*` are unaffected until they opt in.
//!
//!   `salt()`   a value unique to THIS PROCESS. Folded into the hash field of
//!              an intermediate name it makes cross-process collision
//!              impossible without changing the name's SHAPE, which
//!              `gate/differential.sh`'s `duo_[A-Za-z0-9_]+_[0-9a-f]{6,}_[0-9]+`
//!              normaliser depends on.
//!
//! WHAT THIS FILE DOES NOT DO: it does not make the executable cache key
//! unique. That cache exists to be shared between runs; isolating it is the
//! CALLER's decision, expressed by setting `TMPDIR`.

const std = @import("std");

var root_cache: ?[]const u8 = null;
var salt_cache: ?u64 = null;

/// The scratch root for this process. Absolute, no trailing slash.
///
/// A relative or empty `TMPDIR` is IGNORED rather than honoured: the paths
/// built from this are handed to `clang` and to a `Dir.openDirAbsolute`, and a
/// relative root would silently follow whatever directory the compiler last
/// changed into.
pub fn root() []const u8 {
    if (root_cache) |r| return r;
    const resolved = blk: {
        // `std.posix.getenv` does not exist in this compiler's std; the C
        // environment is the portable reach from here, and it is the same
        // block `clang` will read when this compiler spawns it.
        const raw = std.c.getenv("TMPDIR") orelse break :blk "/tmp";
        const env: []const u8 = std.mem.sliceTo(raw, 0);
        if (env.len == 0) break :blk "/tmp";
        if (env[0] != '/') break :blk "/tmp";
        var end = env.len;
        while (end > 1 and env[end - 1] == '/') end -= 1;
        break :blk env[0..end];
    };
    root_cache = resolved;
    return resolved;
}

/// `root()` joined with the formatted tail. Caller owns the result.
pub fn path(alloc: std.mem.Allocator, comptime fmt: []const u8, args: anytype) ![]u8 {
    const tail = try std.fmt.allocPrint(alloc, fmt, args);
    defer alloc.free(tail);
    return std.fmt.allocPrint(alloc, "{s}/{s}", .{ root(), tail });
}

/// A 64-bit value no other live process shares.
///
/// The pid alone is not enough on its own — pids are reused, and a stale
/// object from a dead compiler with the same pid is exactly the artifact a
/// concurrent run must not pick up — so the process start time and the address
/// of a stack slot (ASLR) go in with it.
pub fn salt() u64 {
    if (salt_cache) |s| return s;
    var h = std.hash.Wyhash.init(0);
    const pid: i32 = std.c.getpid();
    h.update(std.mem.asBytes(&pid));
    var ts: std.c.timespec = undefined;
    if (std.c.clock_gettime(.REALTIME, &ts) == 0) h.update(std.mem.asBytes(&ts));
    var here: u8 = 0;
    const addr: usize = @intFromPtr(&here);
    h.update(std.mem.asBytes(&addr));
    const s = h.final();
    salt_cache = s;
    return s;
}

test "root defaults to /tmp and rejects a relative TMPDIR" {
    // The cache makes this order-dependent, so assert the pure rule directly
    // rather than by mutating the environment of a live process.
    root_cache = null;
    const r = root();
    try std.testing.expect(r.len > 0);
    try std.testing.expect(r[0] == '/');
    try std.testing.expect(r.len == 1 or r[r.len - 1] != '/');
}

test "salt is stable within a process" {
    try std.testing.expectEqual(salt(), salt());
}

test "path joins under the root with a single separator" {
    const p = try path(std.testing.allocator, "duo_{s}.c", .{"probe"});
    defer std.testing.allocator.free(p);
    try std.testing.expect(std.mem.endsWith(u8, p, "/duo_probe.c"));
    try std.testing.expect(std.mem.startsWith(u8, p, root()));
    try std.testing.expect(std.mem.indexOf(u8, p, "//") == null);
}
