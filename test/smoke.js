'use strict';

// End-to-end smoke test: drives the real duo-lsp binary over stdio JSON-RPC,
// using the real `duo` compiler for diagnostics. Verifies:
//   - initialize handshake returns the expected capabilities
//   - opening a .lua doc with an undeclared global publishes a diagnostic
//   - textDocument/documentSymbol returns the top-level declarations
//   - shutdown/exit terminates cleanly
//
// Run with `npm run smoke` / `node test/smoke.js`. Point at a duo binary via
// DUO_LSP_DUO_BIN (defaults to ../../zig-out/bin/duo).

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const assert = require('assert');

const LSP_BIN = path.join(__dirname, '..', 'bin', 'duo-lsp');
const DUO_BIN = process.env.DUO_LSP_DUO_BIN ||
  path.resolve(__dirname, '..', '..', '..', 'zig-out', 'bin', 'duo');

if (!fs.existsSync(DUO_BIN)) {
  console.error(`smoke: duo binary not found at ${DUO_BIN} (build it with \`zig build\`)`);
  process.exit(2);
}

const DOC_URI = 'file:///tmp/duo_smoke.lua';
const DOC_TEXT = [
  'local x = 1',
  'function f(): i64',
  '    return x + y',
  'end',
  'print(f())',
].join('\n') + '\n';

const child = spawn('node', [LSP_BIN], {
  env: { ...process.env, DUO_LSP_DUO_BIN: DUO_BIN },
  stdio: ['pipe', 'pipe', 'inherit'],
});

let buf = '';
const pending = new Map(); // id -> {resolve, type}
let diagNotifSeen = false;
let exitCode = 0;
let nextId = 1;

function send(msg) {
  const json = JSON.stringify(msg);
  child.stdin.write(`Content-Length: ${Buffer.byteLength(json)}\r\n\r\n${json}`);
}

function request(method, params) {
  const id = nextId++;
  return new Promise((resolve) => {
    pending.set(id, { resolve, method });
    send({ jsonrpc: '2.0', id, method, params });
  });
}

function notify(method, params) {
  send({ jsonrpc: '2.0', method, params });
}

child.stdout.on('data', (chunk) => {
  buf += chunk.toString('utf8');
  for (;;) {
    const h = buf.indexOf('\r\n\r\n');
    if (h < 0) return;
    const headers = buf.slice(0, h).split('\r\n');
    let len = -1;
    for (const hd of headers) {
      const idx = hd.indexOf(':');
      if (idx >= 0 && hd.slice(0, idx).trim().toLowerCase() === 'content-length')
        len = parseInt(hd.slice(idx + 1).trim(), 10);
    }
    if (len < 0 || buf.length < h + 4 + len) return;
    const body = buf.slice(h + 4, h + 4 + len);
    buf = buf.slice(h + 4 + len);
    let msg;
    try { msg = JSON.parse(body); } catch (e) { console.error('bad json', e); continue; }
    if (msg.id !== undefined && msg.result !== undefined) {
      const p = pending.get(msg.id);
      if (p) { pending.delete(msg.id); p.resolve(msg.result); }
    } else if (msg.method === 'textDocument/publishDiagnostics') {
      diagNotifSeen = true;
      handleDiag(msg.params);
    }
  }
});

let diagAssert = false;
function handleDiag(params) {
  if (params.uri !== DOC_URI) return;
  const msgs = params.diagnostics.map((d) => d.message);
  console.log('  diagnostics:', JSON.stringify(msgs));
  // Duo's lua mode flags undeclared globals; expect something about 'y'.
  diagAssert = params.diagnostics.length > 0 &&
    params.diagnostics.some((d) => /y|global/i.test(d.message));
}

async function run() {
  const init = await request('initialize', {
    processId: process.pid,
    rootUri: null,
    capabilities: {},
  });
  assert.ok(init.capabilities, 'initialize returned capabilities');
  assert.ok(init.capabilities.textDocumentSync !== undefined, 'textDocumentSync present');
  assert.strictEqual(init.serverInfo.name, 'duo-lsp');
  console.log('  ok  initialize ->', init.serverInfo.name, init.serverInfo.version);

  notify('initialized', {});
  notify('textDocument/didOpen', {
    textDocument: { uri: DOC_URI, languageId: 'lua', version: 1, text: DOC_TEXT },
  });

  // Give the server time to run the debounced check + publish diagnostics.
  await new Promise((r) => setTimeout(r, 1500));

  const syms = await request('textDocument/documentSymbol', {
    textDocument: { uri: DOC_URI },
  });
  const symNames = (syms || []).map((s) => s.name);
  console.log('  symbols:', JSON.stringify(symNames));
  assert.ok(symNames.includes('f'), `documentSymbol missing 'f': ${symNames}`);

  const hover = await request('textDocument/hover', {
    textDocument: { uri: DOC_URI },
    position: { line: 1, character: 10 }, // on `f` in `function f(): i64`
  });
  assert.ok(hover, 'hover returned a result');
  console.log('  ok  hover ->', JSON.stringify(hover.contents.value).slice(0, 80));

  await request('shutdown', null);
  notify('exit', {});

  // Allow process to exit.
  const code = await new Promise((r) => child.on('exit', r));
  console.log('  exit code:', code);
  console.log('  diagnostics assert:', diagAssert ? 'PASS' : 'FAIL');
  exitCode = (code === 0 && diagAssert) ? 0 : 1;
  if (!diagAssert) console.error('  FAIL: expected an undeclared-global diagnostic for `y`');
  process.exit(exitCode);
}

run().catch((e) => { console.error('smoke error:', e); process.exit(1); });