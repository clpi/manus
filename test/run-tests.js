'use strict';

// Unit tests for the duo-lsp internals. No external dependencies — plain
// Node `assert`. Run with `npm test` / `node test/run-tests.js`.

const assert = require('assert');
const { parseLine, wordEnd, SEV_ERROR, SEV_WARNING } = require('../lib/diagnostic');
const { scanSymbols, symbolAt, SYM_FUNCTION, SYM_ENUM, SYM_VARIABLE } = require('../lib/symbols');
const { applyChanges, offsetAt } = require('../lib/server');

let passed = 0;
let failed = 0;
function test(name, fn) {
  try { fn(); passed++; console.log(`  ok  ${name}`); }
  catch (e) { failed++; console.error(`  FAIL ${name}\n      ${e.message}\n      ${e.stack.split('\n')[1] || ''}`); }
}

// ── diagnostic parsing ────────────────────────────────────────────────────────
test('parseLine: debug-dump error', () => {
  const line = `.{ .file = { 47, 116 }, .line = 2, .col = 1 }: error: attempt to assign to const variable 'x'`;
  const r = parseLine(line);
  assert.strictEqual(r.line, 1, 'line is 0-based');
  assert.strictEqual(r.col, 0, 'col is 0-based');
  assert.strictEqual(r.severity, SEV_ERROR);
  assert.strictEqual(r.message, "attempt to assign to const variable 'x'");
});

test('parseLine: debug-dump warning', () => {
  const line = `.{ .file = { 47 }, .line = 9, .col = 4 }: warning: unused variable 'y'`;
  const r = parseLine(line);
  assert.strictEqual(r.line, 8);
  assert.strictEqual(r.col, 3);
  assert.strictEqual(r.severity, SEV_WARNING);
  assert.strictEqual(r.message, "unused variable 'y'");
});

test('parseLine: parse-error location (no error:/warning: prefix)', () => {
  const line = `.{ .file = { 47 }, .line = 1, .col = 7 }: expected 'name', got ':'`;
  const r = parseLine(line);
  assert.strictEqual(r.line, 0);
  assert.strictEqual(r.col, 6);
  assert.strictEqual(r.severity, SEV_ERROR);
  assert.strictEqual(r.message, "expected 'name', got ':'");
});

test('parseLine: clean format error', () => {
  const line = `examples/x.duo:5:3: error: type mismatch`;
  const r = parseLine(line);
  assert.strictEqual(r.line, 4);
  assert.strictEqual(r.col, 2);
  assert.strictEqual(r.severity, SEV_ERROR);
  assert.strictEqual(r.message, 'type mismatch');
});

test('parseLine: non-diagnostic line returns null', () => {
  assert.strictEqual(parseLine('1 error(s)'), null);
  assert.strictEqual(parseLine('parse error: error.ExpectedToken'), null);
  assert.strictEqual(parseLine('>>> EXPECT FAILED at ...'), null);
  assert.strictEqual(parseLine(''), null);
});

test('parseLine: debug-dump ignores .col inside file byte array', () => {
  // The file byte array could itself contain digits; the regex must anchor on
  // the trailing `.line = ..., .col = ... }:` tail, not the array.
  const line = `.{ .file = { 99, 50 }, .line = 3, .col = 2 }: error: boom`;
  const r = parseLine(line);
  assert.strictEqual(r.line, 2);
  assert.strictEqual(r.col, 1);
  assert.strictEqual(r.message, 'boom');
});

// ── wordEnd ─────────────────────────────────────────────────────────────────
test('wordEnd: extends over identifier', () => {
  assert.strictEqual(wordEnd('abc def', 0, 0), 3);
});
test('wordEnd: handles dot in qualified names', () => {
  assert.strictEqual(wordEnd('Shape.Circle', 0, 0), 12);
});
test('wordEnd: punctuation covers one char', () => {
  assert.strictEqual(wordEnd('++', 0, 0), 1);
});
test('wordEnd: missing text falls back to col+1', () => {
  assert.strictEqual(wordEnd(null, 0, 4), 5);
});

// ── symbol scan ─────────────────────────────────────────────────────────────
const SAMPLE = [
  'alias Point2D = { x: f64, y: f64 }',
  '',
  'enum Shape',
  '    Circle',
  '    Rect',
  'end',
  '',
  'fun area(s: Shape): f64',
  '    a: f64 = 0.0',
  '    match s',
  '        case Shape.Circle(r) then a = 3.14 * r * r',
  '    end',
  '    a',
  'end',
  '',
  'circ: Shape = Shape.Circle(2.0)',
  'print(area(circ))',
].join('\n');

test('scanSymbols: finds top-level fun/enum/alias/var', () => {
  const syms = scanSymbols(SAMPLE);
  const names = syms.map((s) => s.name);
  assert.ok(names.includes('Point2D'), `got ${names}`);
  assert.ok(names.includes('Shape'));
  assert.ok(names.includes('area'));
  assert.ok(names.includes('circ'));
});

test('scanSymbols: does NOT collect nested decls inside fun/enum/match', () => {
  const syms = scanSymbols(SAMPLE);
  const names = syms.map((s) => s.name);
  // `a` is declared inside `fun area`; `Circle` is inside `enum Shape`.
  assert.ok(!names.includes('Circle'), `nested enum member leaked: ${names}`);
  assert.ok(!names.includes('a'), `nested local leaked: ${names}`);
});

test('scanSymbols: kind mapping', () => {
  const syms = scanSymbols(SAMPLE);
  const byName = Object.fromEntries(syms.map((s) => [s.name, s.kind]));
  assert.strictEqual(byName.area, SYM_FUNCTION);
  assert.strictEqual(byName.Shape, SYM_ENUM);
  assert.strictEqual(byName.circ, SYM_VARIABLE);
});

test('scanSymbols: brace-nested fun inside table is not top-level', () => {
  const src = [
    'point = {',
    '    distance = fun(self): f64 self.x end,',
    '}',
  ].join('\n');
  const syms = scanSymbols(src);
  // `point` is the top-level global; `distance`/`fun` is inside the table.
  assert.ok(syms.some((s) => s.name === 'point'));
  assert.ok(!syms.some((s) => s.name === 'distance'), `nested table fn leaked`);
});

test('scanSymbols: comment does not start a block', () => {
  const src = '-- fun fake()\nfun real(): i64 1 end\n';
  const syms = scanSymbols(src);
  assert.ok(syms.some((s) => s.name === 'real'));
  assert.ok(!syms.some((s) => s.name === 'fake'));
});

test('symbolAt: matches declaration line', () => {
  const syms = scanSymbols(SAMPLE);
  const s = symbolAt(syms, 7, 0); // line of `fun area`
  assert.ok(s);
  assert.strictEqual(s.name, 'area');
});

// ── text sync ───────────────────────────────────────────────────────────────
test('applyChanges: full replace', () => {
  assert.strictEqual(applyChanges('abc', [{ text: 'xyz' }]), 'xyz');
});
test('applyChanges: incremental range replace', () => {
  const out = applyChanges('hello world', [{
    range: { start: { line: 0, character: 0 }, end: { line: 0, character: 5 } },
    text: 'HELLO',
  }]);
  assert.strictEqual(out, 'HELLO world');
});
test('applyChanges: incremental insert (empty range)', () => {
  const out = applyChanges('ab', [{
    range: { start: { line: 0, character: 1 }, end: { line: 0, character: 1 } },
    text: 'X',
  }]);
  assert.strictEqual(out, 'aXb');
});
test('offsetAt: multi-line', () => {
  assert.strictEqual(offsetAt('ab\ncd', { line: 1, character: 1 }), 4);
});

// ── summary ─────────────────────────────────────────────────────────────────
console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);