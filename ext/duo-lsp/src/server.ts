#!/usr/bin/env node
import {
  createConnection,
  TextDocuments,
  ProposedFeatures,
  InitializeParams,
  InitializeResult,
  TextDocumentSyncKind,
  CompletionItem,
  CompletionItemKind,
  DocumentSymbolParams,
  SymbolInformation,
  HoverParams,
  Hover,
  DidSaveTextDocumentParams,
  DidChangeTextDocumentParams,
  TextDocumentPositionParams,
  DefinitionParams,
  Location,
} from 'vscode-languageserver/node';

import { TextDocument } from 'vscode-languageserver-textdocument';
import { parseDocumentSymbols, DuoSymbol } from './parser';
import { getCompletionItems, resolveCompletion } from './completion';
import { runDiagnostics } from './diagnostics';

// ── Connection ──────────────────────────────────────────────────────────────

const connection = createConnection(ProposedFeatures.all);
const documents = new TextDocuments(TextDocument);

/** Per-URI symbol cache, refreshed on change/save. */
const symbolCache = new Map<string, DuoSymbol[]>();

let duoBinary = 'duo';

// ── Initialize ──────────────────────────────────────────────────────────────

connection.onInitialize((params: InitializeParams): InitializeResult => {
  const initOpts = params.initializationOptions as Record<string, unknown> | undefined;
  if (initOpts?.duoBinary && typeof initOpts.duoBinary === 'string') {
    duoBinary = initOpts.duoBinary;
  }

  return {
    capabilities: {
      textDocumentSync: TextDocumentSyncKind.Full,
      completionProvider: {
        resolveProvider: true,
        triggerCharacters: ['.', ':', '@', '<'],
      },
      documentSymbolProvider: true,
      hoverProvider: true,
      definitionProvider: true,
    },
  };
});

// ── Document sync ───────────────────────────────────────────────────────────

documents.onDidChangeContent((change) => {
  const uri = change.document.uri;
  const text = change.document.getText();
  symbolCache.set(uri, parseDocumentSymbols(text, uri));
});

documents.onDidSave(async (params: { document: TextDocument }) => {
  const uri = params.document.uri;
  const text = params.document.getText();
  symbolCache.set(uri, parseDocumentSymbols(text, uri));
  const diags = await runDiagnostics(uri, duoBinary);
  connection.sendDiagnostics({ uri, diagnostics: diags });
});

documents.onDidClose((e) => {
  symbolCache.delete(e.document.uri);
  connection.sendDiagnostics({ uri: e.document.uri, diagnostics: [] });
});

// ── Completion ──────────────────────────────────────────────────────────────

connection.onCompletion((_pos: TextDocumentPositionParams): CompletionItem[] => {
  return getCompletionItems();
});

connection.onCompletionResolve((item: CompletionItem): CompletionItem => {
  return resolveCompletion(item);
});

// ── Document symbols ────────────────────────────────────────────────────────

connection.onDocumentSymbol((params: DocumentSymbolParams): SymbolInformation[] => {
  const uri = params.textDocument.uri;
  const symbols = symbolCache.get(uri);
  if (!symbols) return [];
  return symbols.map((s) => s.toSymbolInformation());
});

// ── Hover ───────────────────────────────────────────────────────────────────

const KEYWORD_DOCS: Record<string, string> = {
  'fun': 'Typed function declaration keyword (Duo extension)',
  'function': 'Lua-compatible function declaration keyword',
  'local': 'Local variable declaration',
  'const': 'Constant binding — cannot be reassigned',
  'global': 'Global variable declaration (module scope)',
  'enum': 'Enumerated type definition',
  'concept': 'Concept (interface/trait) definition',
  'alias': 'Type alias / struct definition',
  'match': 'Pattern matching statement/expression',
  'try': 'Try block for error handling',
  'catch': 'Catch clause in try block',
  'defer': 'Defer block — runs on scope exit (LIFO)',
  'async': 'Async function modifier',
  'await': 'Await an async expression',
  'extends': 'Alias inheritance keyword',
  'private': 'Private field modifier in alias definitions',
  'i8': 'Signed 8-bit integer type',
  'i16': 'Signed 16-bit integer type',
  'i32': 'Signed 32-bit integer type',
  'i64': 'Signed 64-bit integer type (default integer)',
  'u8': 'Unsigned 8-bit integer type',
  'u16': 'Unsigned 16-bit integer type',
  'u32': 'Unsigned 32-bit integer type',
  'u64': 'Unsigned 64-bit integer type',
  'f32': 'Single-precision floating-point type',
  'f64': 'Double-precision floating-point type (default float)',
  'bool': 'Boolean type (true/false)',
  'void': 'Void return type',
  'str': 'String type',
};

connection.onHover((params: HoverParams): Hover | null => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return null;

  const text = doc.getText();
  const offset = doc.offsetAt(params.position);

  // Extract word at cursor
  let start = offset;
  let end = offset;
  while (start > 0 && /\w/.test(text[start - 1])) start--;
  while (end < text.length && /\w/.test(text[end])) end++;
  const word = text.slice(start, end);

  // Check for @ prefix (attribute)
  if (start > 0 && text[start - 1] === '@') {
    return {
      contents: { kind: 'markdown', value: `**@${word}** — Duo attribute` },
    };
  }

  const doc_text = KEYWORD_DOCS[word];
  if (doc_text) {
    return {
      contents: { kind: 'markdown', value: `**${word}** — ${doc_text}` },
    };
  }

  // Check symbol cache for user-defined symbols
  const symbols = symbolCache.get(params.textDocument.uri);
  if (symbols) {
    const sym = symbols.find((s) => s.name === word);
    if (sym) {
      return {
        contents: {
          kind: 'markdown',
          value: `**${sym.name}** — ${sym.kind} (line ${sym.line + 1})`,
        },
      };
    }
  }

  return null;
});

// ── Go-to-definition ────────────────────────────────────────────────────────

connection.onDefinition((params: DefinitionParams): Location | null => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return null;

  const text = doc.getText();
  const offset = doc.offsetAt(params.position);

  let start = offset;
  let end = offset;
  while (start > 0 && /\w/.test(text[start - 1])) start--;
  while (end < text.length && /\w/.test(text[end])) end++;
  const word = text.slice(start, end);

  // Search all cached documents
  for (const [uri, symbols] of symbolCache) {
    const sym = symbols.find((s) => s.name === word);
    if (sym) {
      return Location.create(uri, {
        start: { line: sym.line, character: sym.col },
        end: { line: sym.line, character: sym.col + sym.name.length },
      });
    }
  }

  return null;
});

// ── Start ───────────────────────────────────────────────────────────────────

documents.listen(connection);
connection.listen();
