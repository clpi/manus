# Idol node dev bootstrap

This directory carries the reproducible machine bootstrap for Idol. It is
tooling projection only; semantic authority remains `AGENTS.md` and C0.

Required on a fresh supported macOS machine:

- repository clone
- credentials for Codex and Cursor
- `./tools/node/dev/setup`

The setup command builds the compiler from source, generates project-local
Codex and Cursor MCP projections from `mcp.manifest.json`, updates Codex user
MCP config from that projection, verifies Cursor Agent headless auth and
launches `cursor agent login` when the supported login flow is required,
approves the required project MCP servers for Cursor Agent, probes all three
required MCP servers through real JSON-RPC initialize requests, and runs the
admission doctor.

`./tools/node/dev/doctor` is the pre-agent admission check. It rejects stale
compiler artifacts, wrong tool versions, missing generated projections, missing
credentials, dead MCP servers, stale Codex app-server sockets, and broken
repository gates before substantive work starts. Run it before any substantive
agent work on an existing checkout.

Generated binaries, Codex/Cursor histories, caches, transcripts, and generated
absolute-path MCP files are machine-local state. They are never project
authority and must not be copied between machines.

Devin uses `tools/node/dev/devin-environment.yaml` as the repository-owned
projection. It routes Devin into `AGENTS.md`, `tools/node/dev/orient`, and the
same doctor/gate evidence path instead of carrying a Devin-specific language
summary.

## Production-reachable host dependencies

The setup path installs or validates only tools that are reached by the current
compiler build, required admission gates, editor/agent startup, or explicitly
admitted benchmark/foreign-lawset surfaces.

| Dependency | Required for | Admission evidence |
| --- | --- | --- |
| Xcode command line tools: `clang`, `cc` | C backend compilation and native link probes | `doctor`, compiler build, unit gate |
| `zig` | Fresh compiler build and Zig unit tests | pinned in `.tool-versions`; `doctor`; `zig build --summary all`; `zig build unit-test` |
| `git` | checkout state, submodules, freshness and hygiene checks | `doctor`; setup submodule update |
| `jq` | canonical MCP manifest projection and checks | `generate-configs`; `probe-mcp`; `doctor` |
| `zls` | required Zig navigation MCP server | pinned in `.tool-versions`; `probe-mcp`; `mcp-gate`; `doctor` |
| `codex` | Codex fresh-session and MCP admission | pinned by `doctor`; generated `~/.codex/config.toml`; `codex doctor`; `codex mcp get` |
| `cursor`, `cursor-agent` | Cursor Agent admission and project MCP/rules projection | pinned by `doctor`; `.cursor/rules/00-authority.mdc`; scoped rule set; `.cursor/mcp.json`; `cursor agent --help`; `cursor agent mcp list` |
| `tree-sitter` | editor grammar projection gates | `doctor`; reachable through `tree-sitter-coverage` and projection gates |
| `node`, `npm` | tree-sitter/editor package toolchain | pinned `node` in `.tool-versions`; `doctor` |
| `lua`, `luajit` | cross-language benchmark baselines | pinned in `.tool-versions`; `doctor`; reachable through benchmark gates |
| `wasmtime` | Wasm oracle and runtime benchmark/conformance | `doctor`; reachable through `wasm-test` and Wasm benchmarks |
| Homebrew, `mise` | macOS provisioning mechanism | `setup`; `.tool-versions` |

Correctness-sensitive versions currently pinned or checked:

- `zig 0.17.0-dev.1567+f0354179a`
- `zls 0.16.0`
- `codex-cli 0.147.0`
- `cursor 3.5.33`
- `cursor-agent 2026.08.04-aaa8809`
- `node 26.7.0`
- `lua 5.5.1`
- `luajit 2.1.1744318430`

## Optional or historical dependencies

Benchmark competitors and foreign engines not present in `doctor` are optional
unless a named benchmark/conformance gate is being run. Historical `.id`
source, generated editor artifacts, generated binaries, caches, Codex rollout
history, Cursor memories, and previous machine MCP files are not dependencies
and are not authority. A future need becomes required only when it is reachable
from a production gate or an admitted setup/admission check.

## MCP projection contract

`tools/node/dev/mcp.manifest.json` is the single canonical MCP manifest. It
declares the three required project servers: `idol-bench`, `idol-lsp`, and `zls`.
`tools/node/dev/generate-configs` projects it into:

- `.codex/mcp.generated.toml` for local inspection;
- a marked block in `~/.codex/config.toml` for Codex;
- `.cursor/mcp.json` for Cursor.

`tools/node/dev/install-skills` installs the **`idol-dev`** skill into
`~/.codex/skills/idol-dev` and retires any existing `idol-development` stub.
Run it after clone or when agent onboarding drifts.

The generated files contain absolute machine paths and are ignored. Regenerate
them on each machine; never copy them from another host.

Cursor Agent must also approve each generated project server. `setup` performs
that approval with `cursor agent mcp enable` for `idol-bench`, `idol-lsp`, and
`zls`; `doctor` requires `cursor agent mcp list` to report all three as ready.
That is still not enough for admission: `doctor` also starts a fresh headless
Cursor Agent session from the repository root and requires it to orient through
`AGENTS.md` to `docs/spec/constitution.md`.
