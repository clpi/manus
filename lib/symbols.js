'use strict';

const SYM_FUNCTION = 12;
const SYM_ENUM = 10;
const SYM_VARIABLE = 13;

const BLOCK_START = new Set(['fun', 'async', 'enum', 'match', 'if', 'while', 'for', 'repeat', 'do']);
const TOP_DECL = new Set(['fun', 'async', 'enum', 'alias', 'concept', 'type', 'struct', 'impl', 'global', 'const', 'use', 'req']);

function trim(s) {
  return s.trim();
}

function stripComment(line) {
  const idx = line.indexOf('--');
  return idx === -1 ? line : line.slice(0, idx);
}

function headKeyword(raw) {
  const line = trim(stripComment(raw));
  if (!line) return { kw: '', rest: '', indent: 0 };
  const m = line.match(/^(\s*)([A-Za-z_][A-Za-z0-9_]*)(?:\s+(.*))?$/);
  if (!m) return { kw: '', rest: line, indent: 0 };
  return { kw: m[2], rest: (m[3] || '').trim(), indent: m[1].length };
}

function declName(kw, rest) {
  if (kw === 'fun' || kw === 'async') {
    const m = rest.match(/^([A-Za-z_][A-Za-z0-9_.]*)/);
    return m ? m[1] : null;
  }
  if (['enum', 'alias', 'concept', 'type', 'struct', 'global', 'const'].includes(kw)) {
    const m = rest.match(/^([A-Za-z_][A-Za-z0-9_]*)/);
    return m ? m[1] : null;
  }
  return null;
}

function kindFor(kw) {
  if (kw === 'fun' || kw === 'async') return SYM_FUNCTION;
  if (kw === 'enum') return SYM_ENUM;
  return SYM_VARIABLE;
}

function bareFunctionName(stripped) {
  const m = stripped.match(/^([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)/);
  if (!m) return null;
  if (!m[2].includes(':')) return null;
  return m[1];
}

function scanSymbols(text) {
  const lines = text.split('\n');
  const syms = [];
  let blockDepth = 0;
  let braceDepth = 0;

  for (let i = 0; i < lines.length; i += 1) {
    const raw = lines[i];
    const info = headKeyword(raw);
    const { kw, rest, indent } = info;
    const stripped = trim(stripComment(raw));

    if (kw === 'end') {
      blockDepth = Math.max(0, blockDepth - 1);
    } else if (blockDepth === 0 && braceDepth === 0) {
      if (TOP_DECL.has(kw)) {
        const name = declName(kw, rest);
        if (name) syms.push({ name, kind: kindFor(kw), line: i, col: indent });
        if (BLOCK_START.has(kw)) blockDepth += 1;
      } else {
        const bf = bareFunctionName(stripped);
        if (bf) {
          syms.push({ name: bf, kind: SYM_FUNCTION, line: i, col: indent });
          blockDepth += 1;
          continue;
        }
        const nm = stripped.match(/^([A-Za-z_][A-Za-z0-9_]*)\s*[:=]/);
        if (nm) syms.push({ name: nm[1], kind: SYM_VARIABLE, line: i, col: indent });
      }
    }

    for (const ch of stripped) {
      if (ch === '{') braceDepth += 1;
      else if (ch === '}') braceDepth = Math.max(0, braceDepth - 1);
    }
  }
  return syms;
}

function symbolAt(syms, line, col) {
  let best = null;
  for (const s of syms) {
    if (s.line < line || (s.line === line && s.col <= col)) best = s;
  }
  return best;
}

module.exports = {
  SYM_FUNCTION,
  SYM_ENUM,
  SYM_VARIABLE,
  scanSymbols,
  symbolAt,
};
