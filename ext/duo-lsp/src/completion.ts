import { CompletionItem, CompletionItemKind, InsertTextFormat } from 'vscode-languageserver/node';

// ── Keyword lists (matching src/lexer.zig TokenKind) ────────────────────────

const LUA_KEYWORDS = [
  'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for',
  'function', 'fun', 'global', 'goto', 'if', 'in', 'local', 'nil',
  'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while',
];

const TYPE_KEYWORDS = [
  'const', 'enum', 'i8', 'i16', 'i32', 'i64', 'u8', 'u16', 'u32',
  'u64', 'f32', 'f64', 'bool', 'void', 'str',
];

const CONTEXTUAL_KEYWORDS = [
  'match', 'try', 'catch', 'defer', 'async', 'await', 'concept',
  'alias', 'private', 'extends',
];

const BUILTINS = [
  'print', 'tostring', 'tonumber', 'type', 'error', 'pcall', 'xpcall',
  'require', 'assert', 'ipairs', 'pairs', 'next', 'select',
  'setmetatable', 'getmetatable', 'rawget', 'rawset', 'rawlen', 'rawequal',
  'unpack', 'collectgarbage', 'load', 'dofile',
];

const ATTRIBUTES = [
  'export', 'inline', 'deprecated', 'implements', 'arc', 'packed',
  'align', 'nopanic', 'concurrent', 'ffi',
];

// ── Snippet templates ───────────────────────────────────────────────────────

const SNIPPETS: Array<{ label: string; insert: string; detail: string }> = [
  {
    label: 'fun',
    insert: 'fun ${1:name}(${2:params}): ${3:void}\n\t${0}\nend',
    detail: 'Typed function definition',
  },
  {
    label: 'if',
    insert: 'if ${1:cond} then\n\t${0}\nend',
    detail: 'If statement',
  },
  {
    label: 'for',
    insert: 'for ${1:k}, ${2:v} in ${3:pairs(t)} do\n\t${0}\nend',
    detail: 'Generic for loop',
  },
  {
    label: 'fori',
    insert: 'for ${1:i} = ${2:1}, ${3:n} do\n\t${0}\nend',
    detail: 'Numeric for loop',
  },
  {
    label: 'while',
    insert: 'while ${1:cond} do\n\t${0}\nend',
    detail: 'While loop',
  },
  {
    label: 'match',
    insert: 'match ${1:expr}\n\t${2:_} => ${0}\nend',
    detail: 'Match expression',
  },
  {
    label: 'enum',
    insert: 'enum ${1:Name}\n\t${0}\nend',
    detail: 'Enum definition',
  },
  {
    label: 'concept',
    insert: 'concept ${1:Name}\n\t${0}\nend',
    detail: 'Concept (interface) definition',
  },
  {
    label: 'alias',
    insert: 'alias ${1:Name}\n\t${0}\nend',
    detail: 'Alias (struct) definition',
  },
  {
    label: 'try',
    insert: 'try\n\t${0}\ncatch ${1:e}\n\t-- handle error\nend',
    detail: 'Try/catch block',
  },
  {
    label: 'defer',
    insert: 'defer\n\t${0}\nend',
    detail: 'Defer block',
  },
];

// ── Public API ──────────────────────────────────────────────────────────────

let _items: CompletionItem[] | null = null;

export function getCompletionItems(): CompletionItem[] {
  if (_items) return _items;

  const items: CompletionItem[] = [];

  for (const kw of LUA_KEYWORDS) {
    items.push({
      label: kw,
      kind: CompletionItemKind.Keyword,
      data: { type: 'keyword' },
    });
  }

  for (const kw of TYPE_KEYWORDS) {
    items.push({
      label: kw,
      kind: CompletionItemKind.TypeParameter,
      data: { type: 'type' },
    });
  }

  for (const kw of CONTEXTUAL_KEYWORDS) {
    items.push({
      label: kw,
      kind: CompletionItemKind.Keyword,
      data: { type: 'contextual' },
    });
  }

  for (const fn of BUILTINS) {
    items.push({
      label: fn,
      kind: CompletionItemKind.Function,
      data: { type: 'builtin' },
    });
  }

  for (const attr of ATTRIBUTES) {
    items.push({
      label: `@${attr}`,
      kind: CompletionItemKind.Property,
      data: { type: 'attribute' },
    });
  }

  for (const snip of SNIPPETS) {
    items.push({
      label: snip.label,
      kind: CompletionItemKind.Snippet,
      insertText: snip.insert,
      insertTextFormat: InsertTextFormat.Snippet,
      detail: snip.detail,
      data: { type: 'snippet' },
    });
  }

  _items = items;
  return items;
}

export function resolveCompletion(item: CompletionItem): CompletionItem {
  const data = item.data as { type: string } | undefined;
  if (!data) return item;

  switch (data.type) {
    case 'keyword':
      item.detail = 'Duo keyword';
      break;
    case 'type':
      item.detail = 'Duo type';
      break;
    case 'contextual':
      item.detail = 'Duo contextual keyword';
      break;
    case 'builtin':
      item.detail = 'Lua/Duo built-in function';
      break;
    case 'attribute':
      item.detail = 'Duo attribute';
      break;
  }

  return item;
}
