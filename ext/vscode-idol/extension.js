'use strict';

const { LanguageClient, TransportKind } = require('vscode-languageclient');
const vscode = require('vscode');

let client = null;

/**
 * @param {vscode.ExtensionContext} context
 */
async function activate(context) {
  const config = vscode.workspace.getConfiguration('idol-lsp');
  if (!config.get('enable')) {
    return;
  }

  const path = config.get('path') || 'idol-lsp';
  const trace = config.get('trace') || 'off';

  // Search PATH + common install locations
  const resolved = await resolveBinary(path);
  if (!resolved) {
    vscode.window.showWarningMessage(
      `Idol LSP binary not found at "${path}". ` +
      'Install idol-lsp or set idol-lsp.path in settings.'
    );
    return;
  }

  const traceLevels = { off: undefined, messages: 'messages', verbose: 'verbose' };

  const serverOptions = {
    run: { command: resolved, transport: TransportKind.stdio },
    debug: { command: resolved, transport: TransportKind.stdio, args: ['--debug'] },
  };

  const clientOptions = {
    documentSelector: [{ scheme: 'file', language: 'idol' }],
    traceOutputChannel: traceLevels[trace]
      ? vscode.window.createOutputChannel('Idol LSP Trace')
      : undefined,
  };

  client = new LanguageClient('idol-lsp', 'Idol Language Server', serverOptions, clientOptions);
  await client.start();
}

/**
 * @param {string} bin
 * @returns {Promise<string|null>}
 */
async function resolveBinary(bin) {
  // If it's an absolute or relative path, check directly
  if (bin.includes('/') || bin.includes('\\')) {
    try {
      await vscode.workspace.fs.stat(vscode.Uri.file(bin));
      return bin;
    } catch {
      return null;
    }
  }
  // Otherwise check PATH via which/where
  const { execFile } = require('child_process');
  const cmd = process.platform === 'win32' ? 'where' : 'which';
  return new Promise((resolve) => {
    execFile(cmd, [bin], (err, stdout) => {
      if (err) return resolve(null);
      const first = stdout.trim().split(/[\r\n]/)[0];
      resolve(first || null);
    });
  });
}

async function deactivate() {
  if (client) {
    await client.stop();
    client = null;
  }
}

module.exports = { activate, deactivate };
