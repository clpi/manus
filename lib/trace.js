'use strict';

/**
 * Parse a compiler trace line from `duo compile --trace` stderr.
 * Returns { kind: 'step'|'done'|'summary', label, ms?, detail? } or null.
 */
function parseTraceLine(line) {
  if (!line || !line.trim()) return null;
  const trimmed = line.trim();

  // ✓ label (N ms — detail)  or  ✓ label (N ms)
  const done = /^✓\s+(.+?)\s+\((\d+)\s+ms(?:\s+—\s+(.+))?\)\s*$/.exec(trimmed);
  if (done) {
    return {
      kind: 'done',
      label: done[1],
      ms: Number(done[2]),
      detail: done[3] || null,
    };
  }

  // … step label
  if (trimmed.startsWith('… ')) {
    return { kind: 'step', label: trimmed.slice(2) };
  }

  // total: N ms  or  total → N ms
  const summary = /^total(?::| →)\s*(.+)$/.exec(trimmed);
  if (summary) {
    return { kind: 'summary', label: 'total', detail: summary[1] };
  }

  return null;
}

module.exports = { parseTraceLine };
