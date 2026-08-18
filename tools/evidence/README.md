# evidence — subjects and perturbation proofs (Pickle Missions C/D)

Tooling only; no language or compiler semantics.

## subject — make one gate output impossible to fake retroactively

```sh
tools/evidence/subject [-o out.json] [-s stdout-to-file] \
  [--label k=v ...] -- <command...>
```

Runs the command, captures its REAL inner exit status, and emits an
`evidence-subject-v1` JSON object: repository commit, dirty-file count,
the command, inner exit, stdout/stderr SHA-256s and sizes, the hashes of
touched artifacts, and caller labels. The helper's own exit status is the
inner command's, so wrappers keep working. `-s` passes the inner stdout
through to a file (gates that must inspect output, like probe-mcp's
initialize responses).

## perturb — prove a damage control actually damages its target

```sh
tools/evidence/perturb <file> <regex> <before-count> <after-count> \
  <sed-expr> <check-command...>
```

Passes only when ALL hold: the pattern matched `before-count` times on the
original; the check command passes undamaged; the sed mutation actually
changed the file hash (a no-op mutation FAILS); the pattern then matched
`after-count` times; the check command FAILED on the damaged file; and the
restored file hash is byte-identical to the original.

## Selftest

`tools/evidence/selftest` — subject exit passthrough (0 and 7), subject
JSON schema, perturb pass, no-op rejection, wrong-count rejection.

## Integrated gate (exactly one, per the brief)

`tools/node/dev/probe-mcp` wraps every enabled-server launch in
`evidence/subject` and emits each subject to stderr on pass (preserved in
gate logs; the whole probe workdir is retained on failure). Every
"ok <name> initialize" line now carries its commit + compiler-hash +
output-hash subject beside it.

## Migration rule

One gate per patch. The next gate to migrate should be `mcp-gate` (it
already carries inline damage controls that `perturb` can adopt).

## rotate — verifier rotation (V-B)

`tools/evidence/rotate [name ...]` falsifies live gates through
`evidence/perturb`. Each named rotation damages one real guard file,
proves the gate failed on the damaged file, and proves byte-exact
restoration:

- `mcp-gate-id-extraction` — damages `tools/mcp/native.id`'s id-at-end
  extraction (`taillen - 1` -> `taillen`); the MCP gate's member-order
  tolerance control must fire.
- `config-freshness` — corrupts the OpenCode projection's sibling-server
  paths; `generate-configs --check` must report the artifact stale.

First full rotation (2026-08-17): PASS on both.
