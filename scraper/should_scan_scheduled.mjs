import { readFileSync, appendFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const MAX_AGE_MS = 90 * 60 * 1000;

export function isFreshLatest(latest, gate, now = Date.now()) {
  const age = now - Date.parse(latest?.scanned_at);
  const rows = latest?.rows;
  const required = Math.ceil(gate.crawlSkuCount * gate.minActivePct / 100);
  return Number.isFinite(age) && age >= 0 && age < MAX_AGE_MS &&
    Array.isArray(rows) && rows.length === gate.crawlSkuCount &&
    rows.filter(row => row.status === 'active').length >= required;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  let fresh = false;
  try {
    const source = readFileSync('data/latest.js', 'utf8');
    const match = source.match(/window\.LATEST\s*=\s*(\{.*\});/s);
    const latest = JSON.parse(match[1]);
    const gate = JSON.parse(readFileSync('tests/gate-config.json', 'utf8'));
    fresh = isFreshLatest(latest, gate);
  } catch (error) {
    console.log(`latest scan cannot be verified: ${error.message}`);
  }
  console.log(fresh ? 'skip: recent verified TGDĐ scan' : 'run: TGDĐ scan missing, stale or incomplete');
  if (process.env.GITHUB_OUTPUT) {
    appendFileSync(process.env.GITHUB_OUTPUT, `run=${fresh ? 'false' : 'true'}\n`);
  }
}
