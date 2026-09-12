# GAP-145 collapse-site classification — sema.zig (measured, read-only)

| # | directive |
|---|---|
| 1 | Continuation of the .quoted census: classification of the 48 sema.zig sites into structural vs collapse, with the three primary collapse candidates isolated to their exact lines. |

## The Quote provenance type (already in the AST)

```
pub const Quote = enum { text, bytes, compat_text, compat_long, host };
quoted: struct { loc, val, quote: Quote = .host }
```

| # | directive |
|---|---|
| 1 | Every .quoted expression already CARRIES the source-law fact. |
| 2 | The collapse class is sites that read `.val` or map to `.str` WITHOUT consulting `.quote`. |

## The three primary collapse sites (sema.zig)

### 1. Type inference: `.quoted => .str` (line 1216)

```
.quoted => .str,   // EVERY quoted expression infers as str
```

| # | directive |
|---|---|
| 1 | Collapse: a `bytes` literal should infer as bytes (a distinct descriptor), not str. |
| 2 | The quote fact is present but unconsumed. |
| 3 | This is THE central type-level collapse — it propagates .str to every downstream consumer. |

### 2. Type check: `.quoted => repr == .str` (line 1337)

```
.quoted => repr == .str,   // EVERY quoted only checks against str
```

| # | directive |
|---|---|
| 1 | Collapse: a bytes literal compared for str compatibility would pass. |
| 2 | Same unconsumed fact. |

### 3. req()/require() text extraction (line 1090)

```
return c.args[0].quoted.val;   // raw .val regardless of quote
```

| # | directive |
|---|---|
| 1 | Collapse: extracts module text without consulting whether the literal is a text/bytes/compat face. |
| 2 | Lower-risk (module paths are text), but the fact is still unconsumed. |

## Remaining 45 sites: structural

| # | directive |
|---|---|
| 1 | The other sema.zig .quoted references are: |

- `.quoted` in switch arms (selection — correct)
- `.quoted.val` in directive/error contexts reading a name (e.g.,
  `mem_type_from_name(args[index].quoted.val)`) — these consume the
  text as a NAME, not as a string value; the quote fact is
  semantically irrelevant for names

| # | directive |
|---|---|
| 1 | These do NOT violate the GAP-145 acceptance criterion. |

## The fix shape (for the owning lane)

| # | directive |
|---|---|
| 1 | Lines 1216 and 1337 are a two-line surgical change each: |

```
.quoted => |q| switch (q.quote) {
    .text, .compat_text, .compat_long, .host => .str,
    .bytes => .bytes_descriptor,  // needs the bytes descriptor to exist
},
```

| # | directive |
|---|---|
| 1 | Blocked on: the bytes descriptor being a distinct type in the type system (currently `.str` is the only string-ish type). |
| 2 | This is a semantic decision — text vs bytes as separate descriptors — that C0 must rule on before the fix lands. |

## Verdict

| # | directive |
|---|---|
| 1 | The GAP-145 acceptance ("zero observers of the collapsed identity") requires exactly TWO semantic changes in sema.zig (lines 1216, 1337), both blocked on the bytes-vs-text descriptor ruling. |
| 2 | The other 46 sites are structural. |
| 3 | This is the complete map. |
