import { Diagnostic, DiagnosticSeverity, Range } from 'vscode-languageserver/node';
import { execFile } from 'child_process';
import { URI } from 'vscode-uri';

/**
 * Error output format from `duo check`:
 *   <file>:<line>:<col>: error: <message>
 *   <file>:<line>:<col>: warning: <message>
 */
const DIAG_RE = /^(.+?):(\d+):(\d+):\s*(error|warning):\s*(.+)$/;

/**
 * Run `duo check <file>` and parse diagnostics from stderr/stdout.
 */
export async function runDiagnostics(uri: string, duoBinary: string): Promise<Diagnostic[]> {
  const filePath = URI.parse(uri).fsPath;

  const { promise, resolve } = Promise.withResolvers<Diagnostic[]>();

  execFile(duoBinary, ['check', filePath], { timeout: 10_000 }, (_err, stdout, stderr) => {
    const output = (stderr || '') + '\n' + (stdout || '');
    const diagnostics: Diagnostic[] = [];

    for (const line of output.split('\n')) {
      const m = DIAG_RE.exec(line.trim());
      if (!m) continue;

      const lineNum = Math.max(0, parseInt(m[2], 10) - 1);
      const col = Math.max(0, parseInt(m[3], 10) - 1);
      const severity = m[4] === 'warning' ? DiagnosticSeverity.Warning : DiagnosticSeverity.Error;
      const message = m[5];

      diagnostics.push({
        severity,
        range: Range.create(lineNum, col, lineNum, col + 1),
        message,
        source: 'duo',
      });
    }

    resolve(diagnostics);
  });

  return promise;
}
