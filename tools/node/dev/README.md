# Idol node dev bootstrap

This directory carries the reproducible machine bootstrap for Idol. It is
tooling projection only; semantic authority remains `AGENTS.md` and C0.

Required on a fresh supported macOS machine:

- repository clone
- credentials for Codex and Cursor
- `./tools/node/dev/setup`

The setup command builds the compiler from source, generates project-local
Codex, Cursor, and OpenCode MCP projections from `mcp.manifest.json`, updates
the Codex and OpenCode user MCP configs from those projections, syncs the
agent skills, verifies Cursor Agent headless auth and launches
`cursor agent login` when the supported login flow is required, approves the
enabled project MCP servers for Cursor Agent, probes every enabled MCP server
through real JSON-RPC initialize requests, and runs the admission doctor.

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
| `zls` | Zig editor navigation (the zls MCP server stays disabled in the manifest) | pinned in `.tool-versions`; `doctor` |
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
declares the enabled project servers:

- `idol` — required; repository status/head/orient (`tools/mcp/native.id`,
  native backend, `idol run`).
- `idol-native` — semantic-graph server from the sibling `idol-native`
  checkout: `check`, `symbols`, `graph`, `run`, `gates`, `orient`, `sim`,
  `explain`, `fmt`, `asm` (`tools/mcp/server.id` on that tree's `bin/idol`).

The retired pre-rename transports (`idol-bench`, `idol-lsp`, `zls`) were
removed: their legacy-syntax sources predated the C-backend retirement and
never compiled under a live backend. Exact file claims use
`tools/node/dev/claim`; gap numbers use `tools/node/dev/gap`; locked work uses
`tools/node/dev/idol-lock`; language
intelligence comes from `idol-native` (MCP + language server); Zig navigation
uses the editor's own zls directly. These commands preserve the useful
coordination contracts without making a text dispatcher semantic authority.

`tools/node/dev/generate-configs` projects the manifest into:

- `.codex/mcp.generated.toml` for local inspection;
- a marked block in `~/.codex/config.toml` for Codex;
- `.cursor/mcp.json` for Cursor;
- `.opencode/opencode.json` for OpenCode (project config);
- the managed `mcp` entries of `~/.config/opencode/opencode.jsonc` (all other
  user keys are preserved);
- `.opencode/skills/{idol,idol-dev}` symlinks into `.pi/skills`, plus the
  same skills synced to `~/.config/opencode/skills` for global discovery.

Claude Code is wired at user scope in `~/.claude.json` `mcpServers` (same
servers, `sh -c` cd-wrappers because Claude has no cwd field). pi loads the
same manifest through `.pi/extensions/idol-mcp.ts`. Editors that want `.id`
language intelligence use the idol-native LSP:
`sh /path/to/idol-native/tools/lsp/launch.sh` with `IDOL_BIN` pointing at
that tree's `bin/idol`.

`tools/node/dev/install-skills` installs the **`idol-dev`** and **`idol`**
skills into `~/.codex/skills` and `~/.config/devin/skills` and retires any
existing `idol-development` stub. OpenCode skill installation is owned by
`generate-configs` (paths above). Run after clone or when agent onboarding
drifts.

The generated files contain absolute machine paths and are ignored. Regenerate
them on each machine; never copy them from another host. When the clone lives
under the `~/x` symlink, the generator emits the stable symlink spelling.

Cursor Agent must also approve each enabled project server. `setup` performs
that approval with `cursor agent mcp enable` for every manifest-enabled
server. That is still not enough for admission: `doctor` also starts a fresh
headless Cursor Agent session from the repository root and requires it to
orient through `AGENTS.md` to `docs/spec/constitution.md`.
