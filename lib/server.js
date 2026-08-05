'use strict';

function offsetAt(text, pos) {
  const line = pos.line;
  const chcol = pos.character;
  const lines = text.split('\n');
  let off = 0;
  for (let i = 0; i < line && i < lines.length; i += 1) {
    off += lines[i].length + 1;
  }
  off += chcol;
  return off < 0 ? 0 : off;
}

function applyChanges(text, changes) {
  let out = text;
  for (const ch of changes) {
    const txt = ch.text == null ? '' : ch.text;
    if (ch.range != null) {
      const s = offsetAt(out, ch.range.start);
      const e = offsetAt(out, ch.range.end);
      const start = s < 0 ? 0 : s;
      const end = e < start ? start : e;
      out = out.slice(0, start) + txt + out.slice(end);
    } else {
      out = txt;
    }
  }
  return out;
}

module.exports = {
  offsetAt,
  applyChanges,
};
