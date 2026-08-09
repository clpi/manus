# duon 0.1 — Text (Pass 108)

**The second of the two boring tables** (Pass 106 §2 item 4). What a `str` is,
what an index gives you, what happens when the bytes are not valid UTF-8, and
which unit an iteration walks. Normative until the graph service hosts it.
Companion: `numerics.md`.

Rows sourced from Pass 100 §12 (B-1, B-5, B-11, TEXT, LEN) are marked;
everything else is decided here.

## 1. What a `str` is — TEXT

```
str  =  bytes & utf8.valid
```

Not a sequence of characters. Not a sequence of code points. **A byte sequence
carrying a refinement fact.** The two halves matter separately:

- `bytes` is the representation, and it is exposed, not hidden. There is no
  opaque string object, no interning requirement, no hidden encoding tag.
- `utf8.valid` is a **fact**, checked once at a boundary and then relied upon
  by every operation downstream. It is the reason `chars()` can decode without
  re-validating and the reason a `str` can be handed to a foreign API with no
  adapter.

`bytes` without the fact is a perfectly good descriptor and is what you hold
while you are still parsing. The distinction is the design: *validation happens
at one named place*, and after it the fact travels.

**There is no string library.** There is a `str` descriptor and you are holding
one of its values (Pass 100 §15). `std.string`, `string.`, and `table.` do not
exist. Operations are faces on the value: `s:split(",")`, `s:trim()`,
`s:find(t)`.

## 2. Indexing — B-1

**`s[i]` IS the byte.** Not a one-character string, not a code point, not a
grapheme. A `u8`.

```
s = "héllo"        -- 6 bytes: 68 C3 A9 6C 6C 6F
s[0]  ==  0x68     -- 'h'
s[1]  ==  0xC3     -- the lead byte of 'é'
s[2]  ==  0xA9     -- the continuation byte of 'é'
#s    ==  6        -- LEN's byte unit; see §5
```

**0-based, always.** There is no second base anywhere in the language. Any face
that takes or returns a position takes or returns a 0-based byte offset — `find`
included, and `find` returning `nil` for absent rather than `0` for present-at-
the-start is *why* it can be 0-based honestly.

**Out of range is a failure, not a value.** `s[i]` for `i ≥ #s` or `i < 0` is
`u8 | error`; it is not `0`, it is not the NUL terminator, and it is not a read
of adjacent memory. **`-1` does not mean "last"** (B-1: no negative wrapping) —
it is out of range and fails like any other out-of-range index. Where a range
fact proves `i < #s`, the check is erased and the instruction is a bare load;
that erasure is the reason the safe rule is affordable in a lexer's inner loop.

The failure is a *routed* failure (B-15), not a fault: an index miss is an
ordinary thing a parser deals with, and forcing it through the bind-or-route
ladder is what stops the sentinel-zero habit before it starts.

## 3. Slices and views — B-1

**`s[i, j]` is the half-open byte range `[i, j)`, and it is a VIEW.**

```
s = "hello"
s[1, 3]  ==  "el"        -- half-open: j is excluded
s[0, 0]  ==  ""          -- empty, always legal
s[3, 3]  ==  ""
s[0, #s] ==  s           -- the whole thing
```

Half-open because it is the only convention under which `s[a,b]` and `s[b,c]`
concatenate to `s[a,c]` with no off-by-one, and under which an empty slice has
an obvious spelling. `i > j` is a failure. `j > #s` is a failure, not a clamp —
clamping is how a parser reads past its input and reports success.

**A view does not copy.** It borrows the parent's bytes with a lifetime fact,
so slicing in a loop allocates nothing. Materializing is explicit (`v:to(str)`)
and is the only place a copy happens. A view of a `str` inherits `utf8.valid`
**only if the cut lands on character boundaries** — otherwise it is `bytes`, and
the descriptor says so. This is the single most useful thing the fact system
does for text: cutting a UTF-8 string in the middle of a character does not
produce an invalid `str`, it produces a `bytes` that will not typecheck where a
`str` is demanded.

## 4. Iteration — explicit by unit, no default

**A `str` has no default iterator.** `for c in s` is a diagnostic naming the
three units, because "iterate a string" is a question with three answers and
picking one silently is how every language in this space acquired its
long-running bug.

```
s:bytes()       -> u8         every byte.        "héllo" ⇒ 6
s:chars()       -> char       every code point.  "héllo" ⇒ 5
s:graphemes()   -> str        every user-visible cluster (UAX #29 extended
                              grapheme clusters).  "héllo" ⇒ 5
```

The three are genuinely different and the difference is the reason the page
exists:

| input | bytes | chars | graphemes |
|---|---|---|---|
| `"héllo"` (é as U+00E9) | 6 | 5 | 5 |
| `"héllo"` (é as e + U+0301) | 7 | 6 | **5** |
| `"👍"` | 4 | 1 | 1 |
| `"👨‍👩‍👦"` (ZWJ family) | 18 | 5 | **1** |
| `"🇯🇵"` (regional indicators) | 8 | 2 | **1** |
| `"e\u{0301}\u{0327}"` (two combining marks) | 5 | 3 | **1** |
| `"\r\n"` | 2 | 2 | **1** |
| `"क्षि"` (Devanagari cluster) | 12 | 4 | **1** |

Read that table as the specification of `graphemes()`: **CRLF is one cluster**,
a ZWJ emoji sequence is one cluster, a regional-indicator pair is one cluster, a
base plus any run of combining marks is one cluster, and a Devanagari
consonant-virama-consonant-vowel run is one cluster. Duo implements UAX #29
*extended* grapheme clusters — including the `GB9c` Indic conjunct-linker rule
and the `GB12/GB13` even-count regional-indicator rule — and pins the Unicode
version as a **world fact**, so a corpus that counts clusters gets the same
answer on a replay five years later. A silently-upgraded segmentation table is a
silently-changed program.

`chars()` yields `char`, a distinct descriptor holding a scalar value in
`[0, 0x10FFFF]` minus the surrogate range — not an `i64`, so it will not
accidentally do arithmetic. `graphemes()` yields `str` views, not copies.

There is no `s:len(chars)` sibling for each unit; the count is
`s:chars():count()` and it is O(n), visibly.

## 5. Length — LEN

`#s` is the **byte** count, in O(1). LEN is a family whose unit is per
descriptor, and `str`'s `#` unit is bytes because bytes are the representation
and the only length available without a scan. `s:chars():count()` and
`s:graphemes():count()` are the other two, both O(n), both spelled long enough
that nobody reaches for one in a hot loop by accident.

`#s == 0` is the emptiness test and it is exact for all three units — a string
with no bytes has no characters and no clusters.

## 6. Comparison and ordering — B-11

**`<`, `<=`, `>`, `>=` on `str` are byte-lexicographic.** Unsigned byte values,
compared position by position, shorter-is-less on a prefix tie. That is the
whole definition.

```
"Z" < "a"          true    -- 0x5A < 0x61. Uppercase sorts first.
"abc" < "abcd"     true    -- prefix
"" < "a"           true
```

**Locale is injected, never ambient.** There is no "current locale", no
environment variable, no process-global collation table that can change what `<`
means. Locale-aware collation is a library that takes a locale value as an
explicit argument and returns a comparator: `xs:sort(collate(locale))`. Two
programs that sort the same bytes produce the same order on every machine, and
a program that wants human order says so in the source.

Byte-lexicographic ordering on valid UTF-8 is code-point order — a real and
useful property, and the reason B-11 costs nothing. It is *not* human alphabetic
order in any language including English, and this page does not pretend it is.

**`==` on `str` is byte equality**, and therefore `"é"` (U+00E9) `!=`
`"é"` (e + U+0301). See §7.

## 7. Normalization — the stance

**Duo does not normalize. Ever. Anywhere. Implicitly.**

`str` is `bytes & utf8.valid`, and `utf8.valid` is a statement about
well-formedness, not about normal form. Two strings that a human reads
identically may hold different bytes, and `==` will report them different,
because they *are* different — and a language that quietly makes them equal has
made `s == t` stop implying `s` and `t` are interchangeable at every other
boundary (a file path, a hash key, a wire message, a signature).

The reasoning, stated once so it is not relitigated:

- **Implicit NFC on ingest destroys data.** A program that reads a filename,
  normalizes it, and writes it back has renamed a file. macOS and Linux disagree
  about filesystem normal form; a language that picks one is wrong on the other.
- **Implicit normalization inside `==` is not free and not local.** It makes the
  cheapest operation in the language O(n) with a table lookup, and it makes
  `a == b` and `hash(a) == hash(b)` two different questions unless hashing
  normalizes too — at which point every map insert normalizes.
- **The comparison people actually want is usually caseless *and* normalized
  *and* locale-scoped**, i.e. a full collation, which cannot be hidden inside
  `==` under any stance.

So normalization is an **edge you write**:

```
s:normalize(nfc)     -- : str      total; the canonical composition
s:normalize(nfd)     -- : str
s:normalize(nfkc)    -- : str      compatibility; lossy BY DESIGN, and named so
s:normalize(nfkd)    -- : str
a:equal(nfc)(b)      -- : bool     canonical equivalence without materializing
```

`s:normalize(nfc)` attaches an `nfc` **fact** to its result, so a boundary that
demands normalized text (`: str & nfc`) is satisfied statically once and never
re-checked, and `a:equal(nfc)(b)` is erased to a byte compare when both sides
already carry the fact. That is normalization as a fact rather than a
convention, and it is the version of this feature that a type system can help
with.

The Unicode version used by `normalize` is the same world fact that pins
`graphemes()` (§4).

## 8. Invalid UTF-8 — at ingest, at index, at iterate

The whole point of putting `utf8.valid` in the descriptor is that there is one
answer per boundary rather than one answer per function.

**At ingest — validate once, at the named boundary, and route the failure.**

```
bytes -> str        FALLIBLE.  b:to(str) : str | error
                    error names the BYTE OFFSET of the first ill-formed
                    sequence and its kind (truncated / overlong / surrogate /
                    out-of-range / unexpected continuation)
```

Every source of external bytes — a file read, a socket, an argv element, an
environment variable, a foreign `char*` — arrives as `bytes`, not `str`. There
is no implicit promotion. Reading a file as text is `fs.read(path):to(str)` and
the failure is consumed by the ordinary B-12 ladder. A program that wants to
process arbitrary bytes never converts and never pays.

There is **no replacement-character mode by default.** `b:to(str)` does not
silently substitute U+FFFD, because that is data corruption wearing the costume
of robustness. It is available, named, and lossy on its face:
`b:to(str)(lossy)` replaces each maximal ill-formed subsequence with U+FFFD
following the WHATWG substitution-of-maximal-subparts rule, and it is total.

**Source files are UTF-8 and are validated by the lexer.** An ill-formed byte in
a `.duo` file — inside a string literal, inside a comment, or anywhere else — is
a **diagnostic** with the byte offset, not a pass-through. A string literal's
bytes are the file's bytes, so a literal cannot be the hole through which
invalid UTF-8 enters a `str`.

**At index — nothing happens.** `s[i]` is a byte and every byte of a valid `str`
is a byte. Indexing into the middle of a character is legal and yields the
continuation byte (§2's `s[2] == 0xA9`). This is not a hazard; it is the point
of exposing bytes. What is forbidden is *constructing* a `str` from such a cut,
and §3 handles that: a slice off a character boundary is `bytes`, not `str`.

**At iterate — nothing to decide.** `chars()` and `graphemes()` rely on
`utf8.valid` and therefore need no error path at all: they cannot encounter an
ill-formed sequence, because the fact says there isn't one. That is the payoff
for validating at the boundary — the decoder in the inner loop has no branch for
a case that cannot occur. Iterating *`bytes`* by character is a different,
fallible face (`b:chars()` yielding `char | error`), and it is spelled
differently because it is a different operation.

## 9. Building strings — B-5

**Interpolation is the way**: `"…{expr}…"`, always. The hole takes any
descriptor with a `to(str)` edge and uses it (`numerics.md` §9 for numbers).

**`..` joins strings and only strings** (B-5). `"x" .. 5` is a diagnostic, and
the diagnostic's repair is `"x{n}"`. This is not pedantry: `..` with implicit
number coercion is how `1 .. 2` becomes `"12"` and how a float ends up in a log
line at 17 digits. One concatenation operator, one operand descriptor, one
suggestion when you get it wrong.

`..` beside a literal is additionally a canon violation (CLAUDE.md §1: `" .."`
beside literals) — the canonicalizer rewrites it to interpolation rather than
diagnosing it, because the repair is total.

## 10. The `str` face inventory

Pass 100 §16, restated with the unit each face works in. **Byte unit unless
marked.** All positions 0-based, all ranges half-open.

```
split(sep) -> seq(str)      trim() trim(start) trim(end) -> str
starts(p) ends(p) -> bool   has(p) -> bool          (B-7 membership)
find(p) -> i64 | nil        replace(a, b) -> str
take(n) until(p) -> str     join(xs) -> str
chars() bytes() graphemes() -> seq                  (§4)
to(T) -> …                  #  -> i64               (§5, bytes)
s[i] -> u8 | error          s[i, j] -> view         (§2, §3)
normalize(form) -> str      equal(form)(other) -> bool   (§7)
```

**No regex, ever** (Pass 100 §16). The extraction ladder is predicates →
`scan(grammar)(s)` → cursor loops. `match`, `gmatch`, and `gsub` are Lua
pattern faces and are not part of the `str` surface.

Names are one lowercase word (CLAUDE.md §0.1), so it is `starts`, not
`starts_with`; `trim(start)`, not `trim_left` or `ltrim`. Predicates are bare
nouns: `digit`, `space`, `hex` — not `is_digit`.

**An unknown face is a diagnostic**, with a curated miss-repair naming the
nearest real one. It is never `nil`.

## 11. Status in this repository

Measured 2026-08-08 on `canonical-to-relation` at `0cea14c`, `zig build` clean,
run through **both** `--backend=c` and `--backend=direct`, read by value, every
zero positive-controlled. `duo check` was run on everything; where it answered
green on a program that then produced garbage, that is the row.

The short version: **§2 is real in one backend and produces a null pointer in
the other; §4 exists as three faces that all iterate zero times; §7 and the
grapheme half of §4 do not exist at all.**

### Implemented and agreeing with this page

| row | evidence |
|---|---|
| §2 `s[i]` IS the byte, 0-based | `"héllo"` ⇒ `s[0]=104 s[1]=195 s[2]=169`, direct backend, and in the C backend when `s` is a **parameter**. |
| §5 `#s` is bytes | `#"héllo"` ⇒ **6**, both backends. |
| §6 byte-lexicographic `<` | `"Z" < "a"` ⇒ true; `"apple" < "apricot"` ⇒ true; `"abc" < "abcd"` ⇒ true. C backend. |
| §6 `==` is byte equality | `"Z" == "Z"` ⇒ true. |
| §2 no negative wrapping | `s[-1]` does not return the last byte. (It does something worse — see below.) |
| §10 `split` | `"a,b,c":split(",")` ⇒ 3 parts. |
| §10 `to(str)` faces | `sub`, `upper`, `lower`, `find`, `rep`, `reverse` all lower and run. |

### The backends disagree

| program | `--backend=c` | `--backend=direct` |
|---|---|---|
| `s: str = "hello"` then `s[0]` (str is a **local binding**) | emits `void* b0 = NULL;` ⇒ **SIGSEGV** (exit 139) | `104` |
| same, with `b1: i64 = s[1]` | emits `lua_table_get_i64_num(s, 1)` — a **table** lookup on a string, **1-based** — and fails to build | `101` |
| `s[-1]` where `s: str` is a **parameter** | `0` | **214** (a read of memory before the string) |
| any `{f64}` hole in an interpolated string | works | **bails**: `lowerBinop() at dnir_lower.zig:2412 — concat` |

The first row is the one that matters. `s[i]` is CLAUDE.md §0.8's headline rule
and Pass 100's TEXT row, and under `--backend=c` it is a null pointer whenever
the string came from a local binding rather than a parameter. `duo check` is
green; the program segfaults. The parameter case works in both backends, which
is why the corpus (lexers, LEB128 — everything takes `s: str` as an argument)
has not surfaced it.

The last row compounds with `numerics.md` §10: every program that interpolates a
float is forced onto `--backend=c`, and `--backend=c` is compiled with
`-ffast-math`.

### Specified and NOT implemented

- **§4, all three units.** `s:bytes()`, `s:chars()`, and `s:graphemes()` all
  pass `duo check`, all compile, and all iterate **zero times**. Measured on
  `"héllo"`: `bytes=0 chars=0 graphemes=0`, against the correct `6 / 5 / 5`.
  Positive control in the same program: a numeric `for i = 1, 6` counts **6**,
  so the loop machinery is not the defect. Three silent no-ops behind a green
  check.
- **§4 graphemes, at all.** `grep -ril grapheme lib src docs` finds **2** files,
  both of them spec prose (`pass100.md`, `pass106.md`). Positive control:
  `grep -ril "grapheme\|utf8" lib src docs` finds 22. There is no segmentation
  table, no UAX #29 implementation, and no Unicode version world fact. The
  cluster table in §4 is SPECIFIED, NOT DEMONSTRATED in its entirety.
- **§7 normalization, at all.** `grep -rin "\bnfc\b\|\bnfd\b\|nfkc" lib src`
  is **empty**. Positive control: the same grep for `normaliz` finds ten files,
  all of them using the word for unrelated things (`lib/std/strings.duo`
  normalizing line endings, `lib/std/ml/norm.duo` normalizing tensors). There is
  no `normalize` face and no `nfc` fact. The stance in §7 is a decision, not a
  description.
- **§8 ingest validation.** Nothing validates. A `.duo` source file containing
  the raw bytes `FF FE` inside a string literal passes `duo check` green,
  compiles under both backends, and prints the invalid bytes verbatim
  (`n=8 s=bad\377\376utf`, identical in both). There is no `bytes -> str` edge,
  no offset-carrying error, and no lexer check. `utf8.valid` is a name in a spec
  and nothing in the compiler asserts it.
- **§2 out-of-range as a failure.** `s[#s]` and `s[99]` both answer **0** in
  both backends; `s[-1]` answers `0` (C) or a **live byte from before the
  string** (direct). No bounds check, no failure shape, no diagnostic, exit 0.
- **§3 `s[i, j]` entirely.** The spelling does not parse:
  `t3.duo:3:12: error: expected ']', got ','`. B-1's view syntax has no parser
  production. The available substitute is `s:sub(i, j)`, which is **1-based and
  inclusive** — `"hello":sub(1, 3)` ⇒ `"hel"`, where §3 requires `s[1, 3]` ⇒
  `"el"`. There is no view type and no lifetime fact; `sub` copies.
- **§2/§10 0-based positions.** Violated by the faces that exist:
  `"hello":find("ll")` ⇒ **3**, which is the 1-based answer (0-based is 2). So
  the language currently has `s[i]` 0-based in one backend and `find`/`sub`
  1-based everywhere. **The indexing base is not consistent within the
  language**, and that is the single most confusing thing on this page for a
  newcomer.
- **§9 `..` strictness.** B-5 says strict; measured, `("x": str) .. (5: i64)`
  ⇒ `"x5"`, green check, no diagnostic. Lua's coercion, intact.
- **§10 unknown face is a diagnostic.** It is a silent `nil`.
  `"hello":notarealmethod("zz")` ⇒ `duo check` **green**, compiles, prints
  `nil`. No miss-repair. This is also how the real names were discovered: `trim`,
  `starts`, and `ends` all answer `nil` because they **do not exist** — the
  implemented names are `starts_with` and `ends_with` (snake_case, CLAUDE.md §1
  deny-list rows), and there is no `trim` at all. A missing face and a face that
  legitimately returns nil are indistinguishable at every stage.

### What the `str` surface actually is today

`src/codegen.zig` dispatches `s:name(…)` over exactly this set:

```
len lower upper sub char format rep reverse byte find match gsub gmatch
split starts_with ends_with pack unpack packsize dump
```

That is **the Lua string library re-spelled as method calls**, 1-based and
pattern-based, plus `split`/`starts_with`/`ends_with`. Of the fourteen faces
§10 names, `split` and `find` exist (`find` with the wrong base), `starts`/`ends`
exist under other names, and the other ten do not. `match`/`gmatch`/`gsub` exist
and are the regex-shaped surface §10 forbids.

`lib/std/utf8.duo` is 25 lines of thin wrapper over the **Lua host's `utf8`
library** (`utf8.char`, `utf8.codes`, `utf8.codepoint`, `utf8.len`,
`utf8.offset`) — a runtime host by Pass 103's definition, with `int` and `any`
in the signatures. `lib/std/unicode.duo` is 144 lines of **ASCII-only**
classification (`is_digit(b) = b >= 48 and b <= 57`) and says so honestly in its
own header.

### What would close the largest share of this page

The cheapest high-value repair is **one decision about the base, enforced by one
fixture.** `s[i]` 0-based and `find`/`sub` 1-based is a defect that costs a
reader more than any missing feature on this page, and it is a rename plus an
offset, not an architecture. Second cheapest: make `s[i]` on a local `str`
binding lower the same way it lowers on a parameter — one path in
`src/codegen.zig` currently emits `NULL`, and a two-line fixture that binds a
string locally and reads `s[0]` would pin it forever.
