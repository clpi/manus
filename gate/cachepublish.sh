#!/bin/sh
# gate/cachepublish.sh — an artifact enters the shared cache whole, or not at all.
#
# ═══ THE DEFECT ════════════════════════════════════════════════════════════
#
# `buildCacheStore` published with ONE TRUNCATING WRITE at the final cache
# name, into a directory whose entire purpose is to be shared by every compile
# on the machine:
#
#     Io.Dir.writeFile(dir, io, .{ .sub_path = cache_name, .data = bytes })
#
# Three consequences, and the third hands back a wrong answer:
#
#   * a reader can open the entry MID-TRUNCATE and get a short buffer;
#   * a writer killed mid-write LEAVES that short buffer at a valid key,
#     permanently;
#   * `buildCacheLoad` refused `bytes.len == 0` and nothing else, so a
#     truncated-but-nonzero Mach-O was served, chmod'd executable, renamed over
#     the output, and RUN.
#
# The length check could not be written, because the key deliberately does not
# name the output path, so nothing outside the entry knew how long the artifact
# was meant to be. Both halves are repaired together: publication goes through
# a salted staging name and `rename(2)` onto the key, and the entry carries a
# prologue naming its own extent.
#
# THIS IS NOT A NEW IDIOM IN THAT FILE, which is what makes the omission a
# defect rather than a design. `buildCacheLoad` already restores cache→output
# by write-then-rename, with a comment explaining why; `materializeBootstrapC`
# already does it for the bootstrap translation unit, under the words "a
# concurrent compile must never read a half-written translation unit". The one
# write that published INTO the shared directory was the one that skipped it.
#
# ═══ WHAT THIS GATE REFUSES TO DO ══════════════════════════════════════════
#
# It does not race two compilers and call a green run proof. A timing window is
# not a subject: it passes by luck on a fast machine and fails by luck on a busy
# one, and either outcome is noise. The subject here is the ENTRY — what the
# compiler does with one that does not account for its own bytes — and that is
# deterministic.
#
# It also does not claim the cache is TRUSTED. A writer with access to the
# directory can forge a well-formed prologue over well-formed bytes; that is a
# property of a shared scratch root, not of this encoding. What is closed is the
# accident: an interrupted store, a full disk, a compiler that died between two
# writes.
#
# ═══ THE ARMS ══════════════════════════════════════════════════════════════
#
#   1  POSITIVE CONTROL   a cold run publishes, a warm run is SERVED and still
#                         answers. Without this every arm below is vacuous —
#                         a cache that never hits refuses poison for free.
#   2  TRUNCATION         a non-zero truncated entry must NOT be served, and the
#                         run must still answer correctly. This is the arm the
#                         defect fails: it served the short file.
#   3  SELF-REPAIR        after arm 2 the key is valid again and hits, so the
#                         refusal is a repair and not a permanent cache miss.
#   4  ZERO-BYTE          the length-0 case, kept measured so the older defect
#                         cannot come back through the new format.
#   5  NO RESIDUE         after all of the above the cache root holds no
#                         `*.staging-*` file: the staging path is exercised and
#                         cleaned, not merely present.
#   6  STRUCTURAL         `buildCacheStore` renames onto the key and never
#                         writes onto it, and the artifacts `idol check` and
#                         `idol test` execute carry `scratch.salt()`.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
idol="${IDOL_BIN:-$root/zig-out/bin/idol}"
[ -x "$idol" ] || { echo "cachepublish: no compiler at $idol" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "cachepublish: python3 absent" >&2; exit 2; }
main_zig="$root/src/main.zig"
[ -f "$main_zig" ] || { echo "cachepublish: no $main_zig" >&2; exit 2; }

# EVERY ARM BELOW COMPILES THROUGH THE DIRECT BACKEND, so on a host that has no
# direct-native realization the cold run cannot answer and the gate has nothing
# to poison. It said so in its own words — "the cold run answered 1, expected
# 42; the probe does not work and nothing below means anything" — which is
# honest about the measurement and silent about the host, so `gate/all.sh`
# counted it as a law signal and a reader went looking for a defect in the
# cache. `law.fact.producer.one`: one fact, one producer, and the producer for
# "can this host realize direct native code" is the file sourced here.
. "$root/gate/realization/direct.sh"
direct_native_probe "$idol"
if direct_native_absent; then
    direct_native_note 'the cache publish/poison census (every arm is a direct-backend artifact)'
    exit 1
fi

work="$(mktemp -d)" || { echo "cachepublish: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$work"' EXIT

# A PRIVATE CACHE ROOT. `scratch.root()` honours TMPDIR, so this run cannot be
# served an entry from — or leave one in — the machine's shared `/tmp`.
cache="$work/root"
mkdir -p "$cache" "$work/run" || { echo "cachepublish: mkdir failed" >&2; exit 2; }

# The probe answers a distinctive exit code, so "served the wrong bytes" and
# "answered correctly" are different observations rather than the same one.
answer=42
cat > "$work/probe.id" <<'ID'
main: i64 = ()
    41 + 1
ID

# run <label> -> writes <label>.out (compiler output) and <label>.code (exit
# status of the compiled program). The source path is held FIXED across every
# arm, so nothing here depends on a name that home mangling would embed.
run() {
  ( cd "$work/run" && TMPDIR="$cache" "$idol" run "$work/probe.id" --backend=direct \
      > "$work/$1.out" 2>&1 )
  echo "$?" > "$work/$1.code"
}

entry() { ls "$cache" | grep '^idol-cache-' | head -1; }

fail=0
say() { echo "cachepublish: FAIL — $1"; fail=$((fail + 1)); }

# ── arm 1: POSITIVE CONTROL ────────────────────────────────────────────────
run cold
[ "$(cat "$work/cold.code")" = "$answer" ] || \
  say "the cold run answered $(cat "$work/cold.code"), expected $answer; the probe does not work and nothing below means anything"
k="$(entry)"
[ -n "$k" ] || say "the cold run published NO cache entry under a private TMPDIR; with an empty cache every poison arm below passes for free (GAP-201)"

if [ -z "$k" ]; then
  echo "cachepublish: no cache entry to examine"; exit 1
fi
full="$cache/$k"
cp "$full" "$work/full.bin"
size=$(wc -c < "$work/full.bin" | tr -d ' ')

run warm
grep -q '(cached)' "$work/warm.out" || \
  say "the warm run did not report a cache hit, so this gate would prove nothing about what a hit serves"
[ "$(cat "$work/warm.code")" = "$answer" ] || \
  say "a cache HIT answered $(cat "$work/warm.code"), expected $answer"

# ── arm 2: TRUNCATION ──────────────────────────────────────────────────────
# Half an artifact, rounded to a non-zero length so the older zero-byte guard
# cannot be what catches it. This is the exact residue an interrupted store or
# a full disk leaves at a valid key.
half=$((size / 2))
[ "$half" -gt 0 ] || say "the published entry is $size byte(s); there is no non-zero truncation to plant"
dd if="$work/full.bin" of="$full" bs=1 count="$half" 2>/dev/null
planted=$(wc -c < "$full" | tr -d ' ')
[ "$planted" = "$half" ] && [ "$planted" -ne "$size" ] || \
  say "planting a truncated entry did not take (wrote $planted of a $size-byte entry); the arm below examined the wrong subject"

run trunc
if grep -q '(cached)' "$work/trunc.out"; then
  say "a TRUNCATED entry ($planted of $size bytes) was served as a cache hit — a short Mach-O renamed over the output and run"
fi
[ "$(cat "$work/trunc.code")" = "$answer" ] || \
  say "after meeting a truncated entry the run answered $(cat "$work/trunc.code"), expected $answer; refusing poison is only half the property, the compile must still succeed"

# ── arm 3: SELF-REPAIR ─────────────────────────────────────────────────────
run repaired
grep -q '(cached)' "$work/repaired.out" || \
  say "the key did not recover after the truncated entry was refused; a poisoned key must be repaired by the first run that touches it, not become a permanent miss"
[ "$(cat "$work/repaired.code")" = "$answer" ] || \
  say "the repaired entry answered $(cat "$work/repaired.code"), expected $answer"

# ── arm 4: ZERO-BYTE ───────────────────────────────────────────────────────
k2="$(entry)"
[ -n "$k2" ] || say "no cache entry survived to arm 4"
if [ -n "$k2" ]; then
  : > "$cache/$k2"
  run zero
  grep -q '(cached)' "$work/zero.out" && \
    say "a ZERO-BYTE entry was served as a cache hit — a file that runs and exits 0 having done nothing"
  [ "$(cat "$work/zero.code")" = "$answer" ] || \
    say "after meeting a zero-byte entry the run answered $(cat "$work/zero.code"), expected $answer"
fi

# ── arm 5: NO RESIDUE ──────────────────────────────────────────────────────
residue=$(ls "$cache" | grep -c 'staging' || true)
[ "$residue" = "0" ] || \
  say "$residue staging file(s) left in the cache root after $( ls "$cache" | wc -l | tr -d ' ') entries were published; a staging name that is never renamed away is a leak, not a publication"

# ── arm 6: STRUCTURAL ──────────────────────────────────────────────────────
python3 - "$main_zig" <<'PY' || fail=$((fail + 1))
import sys, re
src = open(sys.argv[1], encoding="utf-8", errors="replace").read()
bad = 0
def say(m):
    global bad
    print("cachepublish: FAIL — " + m)
    bad += 1

def body(name):
    m = re.search(r'^fn %s\(' % re.escape(name), src, re.M)
    if not m: return None
    i = src.index("{", m.start())
    d, j = 0, i
    while j < len(src):
        if src[j] == "{": d += 1
        elif src[j] == "}":
            d -= 1
            if d == 0: break
        j += 1
    # Comments carry this file's ruling verbatim, including the defective line
    # it quotes. Strip them before reading what the code does.
    return re.sub(r'//[^\n]*', '', src[i + 1:j])

store = body("buildCacheStore")
if store is None:
    say("`fn buildCacheStore` was not found in src/main.zig; the structural arm examined nothing")
else:
    renames = re.findall(r'Io\.Dir\.rename\([^;]*?,\s*cache_name\s*,', store, re.S)
    if not renames:
        say("`buildCacheStore` does not rename onto `cache_name`. Publication into a "
            "shared, multi-writer directory must be atomic: a reader observes either "
            "the previous complete entry or the new one, never a truncation. "
            "`buildCacheLoad` and `materializeBootstrapC` in this same file both "
            "already publish this way.")
    direct = re.findall(r'writeFile\([^;]*?\.sub_path\s*=\s*cache_name\b', store, re.S)
    if direct:
        say("`buildCacheStore` writes DIRECTLY onto `cache_name` (%d site(s)). That is "
            "the truncating write this gate exists for — a writer killed mid-write "
            "leaves a short file at a valid key, forever." % len(direct))
    if "scratch.salt()" not in store:
        say("`buildCacheStore`'s staging name does not carry `scratch.salt()`. A pid "
            "alone is reused, and a stale staging file from a dead compiler with the "
            "same pid is exactly the file a concurrent run must not rename onto a "
            "live key.")

# THE ARTIFACTS `check` AND `test` EXECUTE. Same defect class, different path:
# a name derived from the source BASENAME alone is shared by every compile of a
# same-named source on the machine, and the window between compiling into that
# path and executing it is wide enough to run someone else's binary.
for fmt, what in (('duo_check_', 'idol check'), ('.test.out', 'idol test')):
    for m in re.finditer(r'scratch\.path\(\s*alloc\s*,\s*"([^"]*%s[^"]*)"\s*,\s*\.\{([^}]*)\}' %
                         re.escape(fmt), src):
        args = m.group(2)
        if "scratch.salt()" not in args:
            say("the artifact %s compiles and then EXECUTES is named %r from %s — no "
                "process identity, so two runs of a same-named source share one path "
                "and one can run the other's binary. `scratch.salt()` exists for this "
                "and the test LOG in this same file already uses it."
                % (what, m.group(1), args.strip()))
        break
    else:
        say("no `scratch.path` call producing the %s artifact (%r) was found; that half "
            "of the structural arm examined nothing" % (what, fmt))

sys.exit(1 if bad else 0)
PY

if [ "$fail" -ne 0 ]; then
  echo "cachepublish: $fail finding(s)"
  exit 1
fi
echo "cachepublish: entry $size bytes — warm hit serves it; truncated to $planted it is refused, the run still answers $answer, and the key repairs; zero-byte refused; no staging residue; publication renames onto the key."