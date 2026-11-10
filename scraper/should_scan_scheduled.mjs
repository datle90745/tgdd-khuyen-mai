import { readFileSync } from 'node:fs';

// A local Windows dispatch that already completed this slot takes precedence.
let fresh = false;
try {
  const text = readFileSync('data/market.js', 'utf8');
  const json = JSON.parse(text.match(/window\.MARKET\s*=\s*(\{.*\});/s)[1]);
  const latest = json.scans.at(-1);
  const age = Date.now() - Date.parse(latest.scanned_at);
  fresh = Number.isInteger(latest.report?.['FPT Shop']) &&
    latest.report['FPT Shop'] >= 80 && age >= 0 && age < 60 * 60 * 1000;
} catch {}
console.log(fresh ? 'skip: recent verified Windows FPT scan' : 'run: no recent verified FPT scan');
if (process.env.GITHUB_OUTPUT) {
  const { appendFileSync } = await import('node:fs');
  appendFileSync(process.env.GITHUB_OUTPUT, `run=${fresh ? 'false' : 'true'}\n`);
}
