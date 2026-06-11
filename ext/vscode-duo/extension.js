'use strict';

const { LanguageClient, TransportKind } = require('vscode-languageclient');
const vscode = require('vscode');

let client = null;

/**
 * @param {vscode.ExtensionContext} context
 */
async function activate(context) {
  const config = vscode.workspace.getConfiguration('duo-lsp');
  if (!config.get('enable')) {
    return;
  }

  const path = config.get('path') || 'duo-lsp';
  const trace = config.get('trace') || 'off';

  // Search PATH + common install locations
  const resolved = await resolveBinary(path);
  if (!resolved) {
    vscode.window.showWarningMessage(
      `Duo LSP binary not found at "${path}". ` +
      'Install duo-lsp or set duo-lsp.path in settings.'
    );
    return;
  }

  const traceLevels = { off: undefined, messages: 'messages', verbose: 'verbose' };

  const serverOptions = {
    run: { command: resolved, transport: TransportKind.stdio },
    debug: { command: resolved, transport: TransportKind.stdio, args: ['--debug'] },
  };

  const clientOptions = {
    documentSelector: [{ scheme: 'file', language: 'duo' }],
    traceOutputChannel: traceLevels[trace]
      ? vscode.window.createOutputChannel('Duo LSP Trace')
      : undefined,
  };

  client = new LanguageClient('duo-lsp', 'Duo Language Server', serverOptions, clientOptions);
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
