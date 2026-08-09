# duo-mcp — MCP servers for Duo

MCP servers implemented in **pure Duo** (not Zig). Depends on the `duo` compiler binary from `~/x/duo`.

## Dependency

Build duo first if the binary doesn't exist:
```bash
cd ~/x/duo && zig build -Doptimize=ReleaseFast
# Binary lands at ~/x/duo/zig-out/bin/duo
```

`duo` must be on PATH or set `DUO_ROOT=~/x/duo`.

## Running the MCP servers

Run them **from the repo root, by path** — never `cd tools/mcp` first:

```bash
duo run tools/mcp/duo_bench.duo   # bench/perf/build-gate/coordination server (35 tools)
duo run tools/mcp/duo_lsp.duo     # LSP intelligence + @comp.* catalog server (32 tools)
duo run tools/mcp/zls.duo         # Zig source navigation (wraps zls subprocess)
```

## The three rules these files are one bug away from at all times

Both servers were DEAD — not slow, dead — for an unknown period, and nothing
noticed. All three rules below are that failure, written down.

1. **Every `req` at FILE SCOPE, and project modules spelled from the project
   root.** A `req` inside a tool handler binds a local the handler's nested
   closures try to capture; Duo has no closure capture, so lowering emits
   `duo_make_closure_29(sx)` — an undeclared C identifier — and the server
   fails to build. It still passes `duo check`. And write
   `req "tools.mcp.duo_shared"`, never `req "duo_shared"`: `req` resolves at
   COMPILE time against the tree above the source file, so the bare spelling
   only worked when the process was started with cwd = `tools/mcp`, which an
   MCP client will not do.

2. **No file-scope FUNCTION calls from inside a handler.** A named file-scope
   function called from a handler lowers to `cl->up0()` and dies with "called
   object type 'lua_Value' is not a function". Values and `req`'d module tables
   are fine; the call is not. Resolve things like `DUO_ROOT` into a file-scope
   VALUE once.

3. **No `std.script`, and no `req "std.x"` either.** `std.script` is the denied
   activity junk drawer (Pass 100 §15). And under Pass 118 §0h **std is the
   PRELUDE GRAPH — no module tree, no import**: reference std descriptors
   directly (`std.fs.exists`, `std.proc.capture`, `std.json.encode`,
   `std.mcp.register_tool`, `std.os.getenv`), which works from inside a handler
   and was verified before these files stopped importing them. Every `req` left
   in this directory names a PROJECT module, which is not std. Note
   `std.os.getenv` answers `""` — never nil — for an unset name, and the old
   two-argument `os.getenv(name, default)` SILENTLY DROPPED its default.

## The gate

`zig build mcp-gate`, wired into `agent-smoke` (tier 0). It speaks real
JSON-RPC over stdio and asserts response BYTES — exact tool counts, named
coordination tools, and a value round trip through the file-claim lock that
requires the lock to REFUSE a second owner. Adding or removing a tool means
updating the expected count in `mcp_gate.duo` on purpose.

## Coordination is allocated, not requested

- `duo_agent_gaps_update(action="open")` **allocates** the `GAP-0NN`. Callers
  do not pass a number and cannot. Allocation is a `mkdir(2)` on a reservation
  directory, which POSIX makes atomic, so two sessions can never be handed the
  same number. Measured: 12 concurrent processes, 12 distinct numbers.
- `duo_dev_claim_acquire` claims **file paths**, not features, and refuses when
  a live claim overlaps at a path-segment boundary. Measured: 12 concurrent
  processes racing one path, exactly 1 grant.

## The invisible-death rule: NEVER end a handler with a bare `if … else … end`

A tool handler whose tail expression is a bare `if … else … end`, rather than
explicit `return`s, sends **no response at all** and ends the session. There is
no error, no diagnostic, no non-zero exit — the server simply stops. The tool
is still registered and still appears in `tools/list`, so it looks alive from
every angle except calling it.

Seven handlers were dead this way and nobody knew: `duo_semantic_snapshot`
(duo_bench) plus `duo_table_shapes`, `duo_meta_catalog`, `duo_grammar_spec_read`,
`duo_grammar_spec_update`, `duo_directive_hierarchy_read`, `duo_complexity` and
`duo_multiplier_opportunities` (duo_lsp). The shape predicted death with 7/7
accuracy. All are fixed, and `mcp-gate` calls six of them by name so the class
cannot come back silently.

## G-TOTAL for the MCP front-end (Pass 117 §0g) — measured, then moved

Pass 117 §0g requires MCP responses to be `(span, role, why, dnir)` tuples;
plain-string output is an H-8 OUTPUT TOTALITY finding.

| | before | after |
|---|---|---|
| total tools across duo_bench + duo_lsp + zls | 71 | 71 |
| emit a JSON body | 50 | **66** |
| emit **plain text** (H-8 finding) | **21** | **5** |
| emit `(span, role, why, dnir)` tuples | **0** | **0** |

40 of the 71 were classified by CALLING the tool and parsing the response body;
the rest are static reads, because calling them runs builds, benchmarks or
writes to tracked files.

**What moved.** The ten document readers now return an envelope carrying the
document's PROVENANCE as checkable facts — `path`, `exists`, `bytes`, `lines`,
`truncated`. That is a real repair, not a reshuffle: `duo_perf_ledger` had been
silently cutting a 604947-byte ledger to 10000 bytes, and no caller could tell
that from a short document. `duo_coordination_update` and `duo_session_log`
answered `"ok: …"`, which told the caller nothing it could act on; they now name
the buffer they wrote and the status the entry landed with.

**What did NOT move, and why it should not be faked.** The compliant count is
still **0**, and the remaining 5 stay plain text on purpose:

- `duo_semantic_snapshot` (×2) and `zig_format` are PASSTHROUGHS — they return
  whatever `duo sim` / `zig fmt` printed. The honest repair is upstream: the
  compiler CLI is itself a rendered artifact under G-TOTAL. Wrapping its prose
  in a tuple-shaped envelope here would be worse than leaving it, because it
  would read as compliant while carrying exactly the same bytes.
- No tool emits a `role`, deliberately. The 18-role taxonomy H-2 calls CLOSED is
  not enumerated anywhere in the tree: `docs/spec/roles.md` §4 counts 17 named,
  states role 18 "is unnamed anywhere", lists two candidates and **refuses to
  guess between them**, and shows §0g's fine splits oblige ≥29. `gaps/GAP-071`
  records that G-TOTAL cannot yet be measured. §0g also requires
  **zero unresolved-ambiguity spans** — two candidates is a mixed-space
  diagnostic, never a fallback. A guessed role would satisfy a scan and make
  every number downstream of it unfalsifiable.

**The interface this front-end will consume**, so the taxonomy owner can aim at
it: a per-token `(line, col, len, role)` quadruple — the shape already used by
`fixtures/highlight/*.roles.duo` — plus a `why` carrying the rule id that
decided the role. `duo_diagnostics`, `duo_compile_check` and `duo_table_shapes`
already return real spans (`file`, `line`, `col`) and are the three tools that
become tuple-compliant the day the role list closes. **Owed: the enumeration of
role 18 and a decision on the ≥12 unhued-but-required splits.**

## MCP config snippet (for Claude Desktop / claude_desktop_config.json)

```json
{
  "mcpServers": {
    "duo-bench": {
      "command": "duo",
      "args": ["run", "<DUO_ROOT>/tools/mcp/duo_bench.duo"],
      "env": { "DUO_ROOT": "<DUO_ROOT>" }
    },
    "duo-lsp": {
      "command": "duo",
      "args": ["run", "<DUO_ROOT>/tools/mcp/duo_lsp.duo"],
      "env": { "DUO_ROOT": "<DUO_ROOT>" }
    }
  }
}
```

## Files

```
duo_bench.duo   Benchmark, build gate, perf audit, agent coordination server
duo_lsp.duo     Language intelligence, @comp.* catalog, diagnostics server
duo_shared.duo  Shared implementations: gates, coordination, gap allocation, claims
duo_eval.duo    Exponential evaluator used by duo_bench's duo_exponential_eval
zls.duo         Zig source navigation server (bridges zls subprocess)
mcp_gate.duo    zig build mcp-gate — the proof any of this works
vendor → ~/x/duo/lib   Symlink to duo stdlib
```
