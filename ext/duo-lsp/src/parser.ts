import { SymbolInformation, SymbolKind, Location, Range } from 'vscode-languageserver/node';

export interface DuoSymbol {
  name: string;
  kind: string;
  line: number;
  col: number;
  uri: string;
  toSymbolInformation(): SymbolInformation;
}

function mkSymbol(name: string, kind: string, line: number, col: number, uri: string): DuoSymbol {
  return {
    name,
    kind,
    line,
    col,
    uri,
    toSymbolInformation(): SymbolInformation {
      const symKind =
        kind === 'function' ? SymbolKind.Function :
        kind === 'enum'     ? SymbolKind.Enum :
        kind === 'concept'  ? SymbolKind.Interface :
        kind === 'alias'    ? SymbolKind.Struct :
        kind === 'const'    ? SymbolKind.Constant :
                              SymbolKind.Variable;

      return {
        name,
        kind: symKind,
        location: Location.create(uri, Range.create(line, col, line, col + name.length)),
      };
    },
  };
}

// ── Patterns ────────────────────────────────────────────────────────────────

const FUNC_RE     = /^[ \t]*(?:(?:@\w+(?:\([^)]*\))?\s+)*)?(local\s+)?(?:function|fun)\s+([a-zA-Z_]\w*(?:\.[a-zA-Z_]\w*)*(?::[a-zA-Z_]\w*)?)/gm;
const ENUM_RE     = /^[ \t]*(?:(?:@\w+(?:\([^)]*\))?\s+)*)?enum\s+([a-zA-Z_]\w*)/gm;
const CONCEPT_RE  = /^[ \t]*(?:(?:@\w+(?:\([^)]*\))?\s+)*)?concept\s+([a-zA-Z_]\w*)/gm;
const ALIAS_RE    = /^[ \t]*(?:(?:@\w+(?:\([^)]*\))?\s+)*)?alias\s+([a-zA-Z_]\w*)/gm;
const LOCAL_RE    = /^[ \t]*local\s+([a-zA-Z_]\w*)/gm;
const CONST_RE    = /^[ \t]*const\s+([a-zA-Z_]\w*)/gm;

interface PatternEntry {
  re: RegExp;
  kind: string;
  group: number;
}

const PATTERNS: PatternEntry[] = [
  { re: FUNC_RE,    kind: 'function', group: 2 },
  { re: ENUM_RE,    kind: 'enum',     group: 1 },
  { re: CONCEPT_RE, kind: 'concept',  group: 1 },
  { re: ALIAS_RE,   kind: 'alias',    group: 1 },
  { re: LOCAL_RE,   kind: 'variable', group: 1 },
  { re: CONST_RE,   kind: 'const',    group: 1 },
];

// ── Public API ──────────────────────────────────────────────────────────────

/**
 * Parse a Duo source text for top-level declarations.
 * Returns an array of symbols with line/col positions.
 */
export function parseDocumentSymbols(text: string, uri: string): DuoSymbol[] {
  const symbols: DuoSymbol[] = [];
  const lines = text.split('\n');

  // Build line-offset table for fast line/col lookup
  const offsets: number[] = [];
  let off = 0;
  for (const line of lines) {
    offsets.push(off);
    off += line.length + 1; // +1 for \n
  }

  for (const { re, kind, group } of PATTERNS) {
    re.lastIndex = 0;
    let m: RegExpExecArray | null;
    while ((m = re.exec(text)) !== null) {
      const name = m[group];
      if (!name) continue;
      // Find line number from offset
      const matchOffset = m.index;
      let line = 0;
      for (let i = offsets.length - 1; i >= 0; i--) {
        if (offsets[i] <= matchOffset) {
          line = i;
          break;
        }
      }
      const col = matchOffset - offsets[line];
      symbols.push(mkSymbol(name, kind, line, col, uri));
    }
  }

  return symbols;
}
