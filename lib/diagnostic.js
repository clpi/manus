'use strict';

/** LSP DiagnosticSeverity.Error */
const SEV_ERROR = 1;
/** LSP DiagnosticSeverity.Warning */
const SEV_WARNING = 2;
/** LSP DiagnosticSeverity.Information */
const SEV_INFO = 3;
/** LSP DiagnosticSeverity.Hint */
const SEV_HINT = 4;

function parseDigits(s, i) {
  const n = s.length;
  let v = 0;
  let any = false;
  while (i <= n) {
    const b = s.charCodeAt(i - 1);
    if (b >= 48 && b <= 57) {
      v = v * 10 + (b - 48);
      any = true;
      i += 1;
    } else break;
  }
  if (!any) return null;
  return { val: v, next: i };
}

function findFrom(s, needle, start) {
  const idx = s.indexOf(needle, start - 1);
  return idx === -1 ? 0 : idx + 1;
}

function startsWith(s, prefix) {
  return s.startsWith(prefix);
}

/**
 * Parse one diagnostic line from `duo check` stderr.
 * Supports debug-dump, plain `path:line:col: severity: msg`, and styled prefixes.
 */
function parseLine(line) {
  if (!line || !line.trim()) return null;

  // Debug-dump: .{ .file = ..., .line = N, .col = M }: ...
  const p = findFrom(line, '.line = ', 1);
  if (p !== 0) {
    const ld = parseDigits(line, p + 8);
    if (!ld) return null;
    const p2 = findFrom(line, ', .col = ', p + 8);
    if (p2 === 0) return null;
    const cd = parseDigits(line, p2 + 9);
    if (!cd) return null;
    const p3 = findFrom(line, '}: ', cd.next);
    if (p3 === 0) return null;
    const rest = line.slice(p3 + 2);
    return parseSeverityMessage(ld.val - 1, cd.val - 1, rest);
  }

  // Plain / path:line:col: severity: message
  const markers = [
    { needle: ': error: ', sev: SEV_ERROR, len: 9 },
    { needle: ': warning: ', sev: SEV_WARNING, len: 11 },
    { needle: ': hint: ', sev: SEV_HINT, len: 8 },
    { needle: ': info: ', sev: SEV_INFO, len: 8 },
  ];
  for (const m of markers) {
    const pos = findFrom(line, m.needle, 1);
    if (pos === 0) continue;
    const msg = line.slice(pos + m.len - 1);
    const prefix = line.slice(0, pos - 1);
    const loc = parsePathLineCol(prefix);
    if (!loc) return null;
    return { line: loc.line, col: loc.col, severity: m.sev, message: msg };
  }

  return null;
}

function parseSeverityMessage(line0, col0, rest) {
  const rules = [
    { prefix: 'error: ', sev: SEV_ERROR },
    { prefix: 'warning: ', sev: SEV_WARNING },
    { prefix: 'hint: ', sev: SEV_HINT },
    { prefix: 'info: ', sev: SEV_INFO },
  ];
  for (const r of rules) {
    if (startsWith(rest, r.prefix)) {
      return { line: line0, col: col0, severity: r.sev, message: rest.slice(r.prefix.length) };
    }
  }
  return { line: line0, col: col0, severity: SEV_ERROR, message: rest };
}

function parsePathLineCol(prefix) {
  const c1 = prefix.lastIndexOf(':');
  if (c1 <= 0) return null;
  const cnum = Number(prefix.slice(c1 + 1));
  const prefix2 = prefix.slice(0, c1);
  const c2 = prefix2.lastIndexOf(':');
  if (c2 <= 0) return null;
  const lnum = Number(prefix2.slice(c2 + 1));
  if (!Number.isFinite(lnum) || !Number.isFinite(cnum)) return null;
  return { line: lnum - 1, col: cnum - 1 };
}

/** Extend highlight range to end of token at (line, col). */
function wordEnd(text, line, col) {
  if (text == null) return col + 1;
  const lines = text.split('\n');
  if (line < 0 || line >= lines.length) return col + 1;
  const row = lines[line];
  if (col < 0 || col >= row.length) return col + 1;
  const isIdent = (c) => /[A-Za-z0-9_.$@]/.test(c);
  const isOp = (c) => '+-*/%^#&|<>=~:.?!'.includes(c);
  let i = col;
  const ch = row[i];
  if (isIdent(ch)) {
    while (i < row.length && isIdent(row[i])) i += 1;
    return i;
  }
  if (isOp(ch)) return col + 1;
  return col + 1;
}

module.exports = {
  SEV_ERROR,
  SEV_WARNING,
  SEV_INFO,
  SEV_HINT,
  parseLine,
  wordEnd,
};
