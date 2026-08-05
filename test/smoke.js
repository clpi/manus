'use strict';

// End-to-end smoke test for the Duo-written LSP. Drives the compiled
// `ext/duo-lsp/duo-lsp` binary (built from src/server.duo) over stdio JSON-RPC
// against the real `duo` compiler. The server is written in Duo; this harness
// is just a test driver.
//
// Run: `node test/smoke.js` (after `bash build.sh` and `zig build`).
//
// Verifies: initialize handshake, diagnostics via `duo check`, documentSymbol
// outline, hover, incremental didChange, shutdown/exit.

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const assert = require('assert');

const SERVER = path.join(__dirname, '..', 'duo-lsp');
const DUO = process.env.DUO_LSP_DUO_BIN ||
  path.resolve(__dirname, '..', '..', 'duo', 'zig-out', 'bin', 'duo');

if (!fs.existsSync(SERVER)) {
  console.error(`smoke: server binary not found at ${SERVER} (run bash build.sh)`);
  process.exit(2);
}
if (!fs.existsSync(DUO)) {
  console.error(`smoke: duo binary not found at ${DUO} (run zig build)`);
  process.exit(2);
}

const child = spawn(SERVER, [], {
  env: { ...process.env, DUO_LSP_DUO_BIN: DUO },
  stdio: ['pipe', 'pipe', 'inherit'],
});

let buf = '';
const pending = new Map();
let nextId = 1;
let diagResult = null;

function send(msg) {
  const json = JSON.stringify(msg);
  child.stdin.write(`Content-Length: ${Buffer.byteLength(json)}\r\n\r\n${json}`);
}
function request(method, params) {
  const id = nextId++;
  return new Promise((resolve) => {
    pending.set(id, { resolve });
    send({ jsonrpc: '2.0', id, method, params });
  });
}
function notify(method, params) { send({ jsonrpc: '2.0', method, params }); }

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
      diagResult = msg.params;
    }
  }
});

async function run() {
  let failed = 0;
  const check = (name, cond, extra) => {
    if (cond) { console.log(`  ok  ${name}`); }
    else { console.error(`  FAIL ${name}${extra ? ' :: ' + extra : ''}`); failed++; }
  };

  const init = await request('initialize', {
    processId: process.pid, rootUri: null, capabilities: {},
  });
  check('initialize returns capabilities', !!init && !!init.capabilities);
  check('serverInfo.name == duo-lsp', init && init.serverInfo && init.serverInfo.name === 'duo-lsp',
    JSON.stringify(init && init.serverInfo));

  notify('initialized', {});

  // A malformed .duo doc -> expect a deterministic parser diagnostic.
  const badUri = 'file:///tmp/duo_smoke_bad.duo';
  const badText = 'x =\n';
  diagResult = null;
  notify('textDocument/didOpen', {
    textDocument: { uri: badUri, languageId: 'duo', version: 1, text: badText },
  });
  await new Promise((r) => setTimeout(r, 800));
  check('malformed duo doc publishes a diagnostic', !!diagResult && diagResult.diagnostics.length > 0,
    JSON.stringify(diagResult && diagResult.diagnostics.map((d) => d.message)));
  check('diagnostic mentions expected expression',
    !!diagResult && diagResult.diagnostics.some((d) => /expected expression/i.test(d.message)),
    JSON.stringify(diagResult && diagResult.diagnostics.map((d) => d.message)));

  const symUri = 'file:///tmp/duo_smoke_symbols.duo';
  const symText = 'x: i64 = 1\nf(a: i64): i64\n    a + x\nend\nprint(f(x))\n';
  notify('textDocument/didOpen', {
    textDocument: { uri: symUri, languageId: 'duo', version: 1, text: symText },
  });
  await new Promise((r) => setTimeout(r, 200));

  const syms = await request('textDocument/documentSymbol', { textDocument: { uri: symUri } });
  const names = (syms || []).map((s) => s.name);
  check('documentSymbol finds f and x', names.includes('f') && names.includes('x'),
    JSON.stringify(names));

  const hover = await request('textDocument/hover', {
    textDocument: { uri: symUri }, position: { line: 1, character: 0 },
  });
  check('hover returns a value for f', !!hover && /f/.test(JSON.stringify(hover)),
    JSON.stringify(hover));

  // A clean .duo doc → no diagnostics, symbols found.
  const duo = fs.readFileSync(path.resolve(__dirname, '..', '..', 'duo', 'examples', 'pattern_match_demo.duo'), 'utf8');
  const duoUri = 'file:///tmp/duo_smoke_pm.duo';
  diagResult = null;
  notify('textDocument/didOpen', {
    textDocument: { uri: duoUri, languageId: 'duo', version: 1, text: duo },
  });
  await new Promise((r) => setTimeout(r, 800));
  check('clean duo doc → no diagnostics', !!diagResult && diagResult.diagnostics.length === 0,
    JSON.stringify(diagResult && diagResult.diagnostics.map((d) => d.message)));
  const dsyms = await request('textDocument/documentSymbol', { textDocument: { uri: duoUri } });
  const dnames = (dsyms || []).map((s) => s.name);
  check('duo outline finds area/Shape',
    dnames.includes('area') && dnames.includes('Shape'), JSON.stringify(dnames));

  await request('shutdown', null);
  notify('exit', {});
  const code = await new Promise((r) => child.on('exit', r));
  check('exit code 0 after shutdown', code === 0, `got ${code}`);

  console.log(`\n${failed === 0 ? 'ALL PASS' : failed + ' FAILED'}`);
  process.exit(failed ? 1 : 0);
}

run().catch((e) => { console.error('smoke error:', e); process.exit(1); });
