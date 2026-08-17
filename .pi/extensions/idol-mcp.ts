/**
 * idol-mcp — bridge the project MCP servers into pi tools.
 *
 * WHY THIS EXISTS
 * pi has no native MCP. The Idol coordination workflow is MCP-based:
 * `idol` owns status/head/orient; `idol-native` (sibling idol-native
 * checkout) owns the semantic-graph surface: check, symbols, graph, run,
 * gates, orient, sim, explain, fmt, asm. This extension speaks
 * newline-delimited JSON-RPC 2.0 to those servers by spawning each server's
 * own `idol` binary on the entrypoints declared by
 * tools/node/dev/mcp.manifest.json.
 *
 * SCOPE — tooling projection only
 * This is the pi analogue of .cursor/mcp.json, .codex/mcp.generated.toml,
 * and .opencode/opencode.json. It adds NO compiler subsystem, NO new
 * grammar/parser authority, and NO std.* surface. It only forwards calls to
 * the project's own MCP servers. It must never bypass a gate or invent
 * vocabulary. Authority lives in C0.
 *
 * USAGE
 * - `idol_mcp_status`        — report server health + discovered tools.
 * - `idol__<server>__<tool>` — one pi tool per MCP tool discovered via
 *   tools/list (e.g. idol__idol-native__graph). Arguments are forwarded as
 *   the MCP `arguments` object.
 *
 * Servers start lazily on first use and are torn down on session_shutdown.
 * Manifest entries with "enabled": false are listed but never started. If an
 * entrypoint fails to compile/start, the tool returns a clear structured
 * error rather than hanging.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";

interface ManifestServer {
  name: string;
  entry: string;
  backend: string;
  /** Sibling checkout name; resolves the root and launcher against it. */
  sibling?: string;
  /** Launcher binary inside the server root (sibling servers only). */
  bin?: string;
  enabled?: boolean;
  required?: boolean;
  startup_timeout_sec?: number;
  purpose?: string;
}
interface Manifest {
  servers: ManifestServer[];
}

interface JsonRpcResponse {
  jsonrpc: "2.0";
  id?: number;
  result?: unknown;
  error?: { code: number; message: string; data?: unknown };
}
interface McpTool {
  name: string;
  description?: string;
  inputSchema?: { type?: string; properties?: Record<string, unknown> };
}
type Pending = {
  resolve: (v: unknown) => void;
  reject: (e: Error) => void;
};

class McpClient {
  private proc: ChildProcessWithoutNullStreams | null = null;
  private nextId = 1;
  private pending = new Map<number, Pending>();
  private buffer = "";
  private initPromise: Promise<void> | null = null;
  private startError: string | null = null;
  readonly tools: McpTool[] = [];

  constructor(
    private readonly idolBin: string,
    private readonly root: string,
    private readonly server: ManifestServer,
  ) {}

  /** Start the server and complete the MCP initialize handshake. */
  async start(startupTimeoutMs: number): Promise<void> {
    if (this.initPromise) return this.initPromise;
    this.initPromise = this.doStart(startupTimeoutMs);
    return this.initPromise;
  }

  private doStart(startupTimeoutMs: number): Promise<void> {
    const { promise, resolve, reject } = Promise.withResolvers<void>();
    let proc: ChildProcessWithoutNullStreams;
    try {
      proc = spawn(
        this.idolBin,
        ["run", `--backend=${this.server.backend}`, join(this.root, this.server.entry)],
        {
          cwd: this.root,
          stdio: ["pipe", "pipe", "pipe"],
          env: { ...process.env, IDOL_ROOT: this.root, IDOL_BIN: this.idolBin },
        },
      );
    } catch (e) {
      this.startError = `spawn failed: ${(e as Error).message}`;
      reject(new Error(this.startError));
      return promise;
    }
    this.proc = proc;

    let stderrTail = "";
    const timer = setTimeout(() => {
      const msg = `${this.server.name} did not initialize within ${startupTimeoutMs}ms`;
      this.startError = msg;
      this.kill();
      reject(new Error(`${msg}\nstderr:\n${stderrTail.slice(-2000)}`));
    }, startupTimeoutMs);

    proc.on("error", (e) => {
      clearTimeout(timer);
      this.startError = `process error: ${e.message}`;
      reject(e);
    });
    proc.on("exit", (code, signal) => {
      if (!this.tools.length && !this.startError) {
        this.startError = `process exited before initialize (code=${code} signal=${signal})`;
      }
      for (const p of this.pending.values()) {
        p.reject(new Error(`${this.server.name} server exited`));
      }
      this.pending.clear();
    });
    proc.stderr.on("data", (d: Buffer) => {
      stderrTail += d.toString();
      if (stderrTail.length > 4000) stderrTail = stderrTail.slice(-4000);
    });
    proc.stdout.on("data", (d: Buffer) => this.onData(d));

    // Initialize handshake. protocolVersion 2024-11-05 is what probe-mcp asserts.
    this.call("initialize", { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "pi-idol-mcp", version: "0" } })
      .then(() => this.notify("notifications/initialized"))
      .then(() => this.call("tools/list", {}))
      .then((res) => {
        const list = (res as { tools?: McpTool[] } | null)?.tools ?? [];
        this.tools.push(...list);
        clearTimeout(timer);
        resolve();
      })
      .catch((e: Error) => {
        clearTimeout(timer);
        this.startError = e.message;
        this.kill();
        reject(new Error(`${this.server.name} initialize failed: ${e.message}\nstderr:\n${stderrTail.slice(-2000)}`));
      });
    return promise;
  }

  private onData(d: Buffer): void {
    this.buffer += d.toString();
    let nl: number;
    while ((nl = this.buffer.indexOf("\n")) >= 0) {
      const line = this.buffer.slice(0, nl).trim();
      this.buffer = this.buffer.slice(nl + 1);
      if (!line) continue;
      let msg: JsonRpcResponse;
      try {
        msg = JSON.parse(line);
      } catch {
        continue; // not JSON; ignore (server banner etc.)
      }
      if (msg.id !== undefined && this.pending.has(msg.id)) {
        const p = this.pending.get(msg.id)!;
        this.pending.delete(msg.id);
        if (msg.error) p.reject(new Error(`${msg.error.message} (code ${msg.error.code})`));
        else p.resolve(msg.result);
      }
    }
  }

  call(method: string, params: unknown): Promise<unknown> {
    if (!this.proc) return Promise.reject(new Error(`${this.server.name} not started`));
    const id = this.nextId++;
    const { promise, resolve, reject } = Promise.withResolvers<unknown>();
    const req = JSON.stringify({ jsonrpc: "2.0", id, method, params });
    this.pending.set(id, { resolve, reject });
    this.proc!.stdin.write(req + "\n");
    return promise;
  }

  private notify(method: string): Promise<void> {
    if (!this.proc) return Promise.reject(new Error(`${this.server.name} not started`));
    this.proc.stdin.write(JSON.stringify({ jsonrpc: "2.0", method }) + "\n");
    return Promise.resolve();
  }

  kill(): void {
    if (this.proc) {
      try {
        this.proc.stdin.end();
      } catch {
        /* ignore */
      }
      try {
        this.proc.kill("SIGTERM");
      } catch {
        /* ignore */
      }
      this.proc = null;
    }
  }
}

export default function (pi: ExtensionAPI) {
  let repo = process.cwd();
  const manifestPath = join(repo, "tools", "node", "dev", "mcp.manifest.json");

  // The Idol dev workflow sends session metadata; PI env may resolve repo.
  const fromEnv = process.env.IDOL_REPO ?? process.env.IDOL_ROOT;
  if (fromEnv) repo = fromEnv;
  const idolBin = process.env.IDOL_BOOTSTRAP_BIN ?? process.env.IDOL_BIN ?? join(repo, "zig-out", "bin", "idol");

  const clients = new Map<string, McpClient>();
  const statusToolName = "idol_mcp_status";

  const loadManifest = (): ManifestServer[] => {
    try {
      const raw = JSON.parse(readFileSync(manifestPath, "utf8")) as Manifest;
      return raw.servers ?? [];
    } catch (e) {
      pi.logger?.error?.(`idol-mcp: cannot read manifest ${manifestPath}: ${(e as Error).message}`);
      return [];
    }
  };

  // A server with a "sibling" field resolves its root and launcher against
  // the sibling checkout of this clone (for example the idol-native
  // repository); every other server resolves against this repository.
  const serverRoot = (s: ManifestServer): string =>
    s.sibling ? join(dirname(repo), s.sibling) : repo;
  const serverBin = (s: ManifestServer): string =>
    s.sibling ? join(serverRoot(s), s.bin ?? "bin/idol") : idolBin;

  const ensureClient = async (s: ManifestServer): Promise<McpClient> => {
    let c = clients.get(s.name);
    if (!c) {
      c = new McpClient(serverBin(s), serverRoot(s), s);
      clients.set(s.name, c);
    }
    await c.start((s.startup_timeout_sec ?? 60) * 1000);
    return c;
  };

  // One pi tool per MCP tool, registered after tools/list. Forwarded by name.
  const registerServerTools = (s: ManifestServer, client: McpClient) => {
    for (const t of client.tools) {
      const toolName = `idol__${s.name}__${t.name}`;
      const desc = `[${s.name}] ${t.description ?? t.name}`.slice(0, 1024);
      try {
        pi.registerTool({
          name: toolName,
          label: `Idol ${s.name}/${t.name}`,
          description: desc,
          parameters: Type.Object({
            arguments: Type.Record(Type.String(), Type.Unknown(), {
              description: "MCP arguments object (server-defined schema).",
            }),
          }),
          async execute(_id, params, signal) {
            if (signal?.aborted) throw new Error("aborted");
            const res = (await client.call("tools/call", {
              name: t.name,
              arguments: (params.arguments ?? {}) as Record<string, unknown>,
            })) as { content?: { type: string; text?: string }[]; isError?: boolean } | null;
            const parts = (res?.content ?? []).map((c) => c.text ?? "").join("\n");
            return {
              content: [{ type: "text", text: parts || "(empty)" }],
              isError: res?.isError === true,
              details: { server: s.name, mcpTool: t.name },
            };
          },
        });
      } catch {
        // already registered (reload) — ignore
      }
    }
  };

  pi.on("session_start", () => {
    // Manifest read is cheap; no server is started here (lazy on first call).
    loadManifest();
  });

  pi.on("session_shutdown", () => {
    for (const c of clients.values()) c.kill();
    clients.clear();
  });

  // Meta tool: health + discovered tools. Also triggers lazy discovery.
  pi.registerTool({
    name: statusToolName,
    label: "Idol MCP status",
    description:
      "Bridge health for the Idol MCP servers (idol, idol-native) and the tools each exposes. Start here to see whether the repository status and semantic-graph servers are reachable from pi.",
    parameters: Type.Object({}),
    async execute() {
      const servers = loadManifest();
      const report: string[] = [`repo: ${repo}`, `idol: ${idolBin}`, `manifest: ${manifestPath}`, ""];
      for (const s of servers) {
        if (s.enabled === false) {
          report.push(`off   ${s.name} — disabled in manifest`);
          continue;
        }
        try {
          const client = await ensureClient(s);
          report.push(`ok    ${s.name} — ${client.tools.length} tools${s.required === false ? "" : " (required)"}`);
          for (const t of client.tools.slice(0, 40)) {
            report.push(`        ${t.name}`);
          }
          registerServerTools(s, client);
        } catch (e) {
          report.push(`fail  ${s.name} — ${(e as Error).message.split("\n")[0]}`);
          report.push(`        entry: ${s.entry}  backend: ${s.backend}`);
          report.push(`        purpose: ${s.purpose ?? ""}`);
        }
      }
      return { content: [{ type: "text", text: report.join("\n") }], details: { servers: servers.length } };
    },
  });
}
