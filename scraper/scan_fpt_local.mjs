// Run on the user's Windows machine, where FPT's production API is reachable.
import { randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { writeFileSync, unlinkSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { collectVariantSnapshot } from './scan_tgdd_local.mjs';

const BRANDS = new Map([
  ['apple-iphone', 'Apple'], ['samsung', 'Samsung'], ['oppo', 'OPPO'],
  ['xiaomi', 'Xiaomi'], ['vivo', 'Vivo'], ['realme', 'Realme'],
]);
const ENDPOINT = 'https://papi.fptshop.com.vn/gw/v1/public/fulltext-search-service/category';
const REPO = 'datle90745/tgdd-khuyen-mai';
const SIZE = 50;
const GH = process.platform === 'win32' && existsSync('C:\\Program Files\\GitHub CLI\\gh.exe')
  ? 'C:\\Program Files\\GitHub CLI\\gh.exe' : 'gh';

function command(program, args, input) {
  const result = spawnSync(program, args, { encoding: 'utf8', input, maxBuffer: 16 * 1024 * 1024 });
  if (result.error || result.status !== 0) {
    throw new Error(`${program} ${args.slice(0, 2).join(' ')}: ${result.error?.message || result.stderr?.trim() || result.status}`);
  }
  return result.stdout;
}

function pricedRow(sku, brand) {
  if (!sku || typeof sku !== 'object') return null;
  const n = String(sku.displayName || sku.name || '').replace(/\s+/g, ' ').trim();
  const slug = String(sku.slug || '');
  const p = sku.currentPrice, o = sku.originalPrice;
  if (!n || !/^dien-thoai\/[a-z0-9-]+(?:\?sku=[a-zA-Z0-9]+)?$/.test(slug) ||
      !Number.isSafeInteger(p) || !Number.isSafeInteger(o) || p <= 0 || o < p || o > 200_000_000) return null;
  return { r: 'FPT Shop', b: brand, n, u: `https://fptshop.com.vn/${slug}`,
    p, o, k: 'Khuyến mãi' };
}

async function fetchCategory(slug, skip) {
  const response = await fetch(ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Origin: 'https://fptshop.com.vn',
      Referer: `https://fptshop.com.vn/dien-thoai/${slug}`, 'User-Agent': 'Mozilla/5.0' },
    body: JSON.stringify({ slug: `dien-thoai/${slug}`, skipCount: skip,
      maxResultCount: SIZE, sortMethod: 'noi-bat', categoryType: 'category' }),
    signal: AbortSignal.timeout(30000),
  });
  if (!response.ok) throw new Error(`${slug} HTTP ${response.status}`);
  const data = await response.json();
  if (!Array.isArray(data.items) || !Number.isSafeInteger(data.totalCount)) {
    throw new Error(`${slug}: invalid catalog response`);
  }
  return data;
}

async function collect() {
  const byName = new Map();
  const counts = {};
  for (const [slug, brand] of BRANDS) {
    let count = 0, total = 0;
    for (let skip = 0; ; skip += SIZE) {
      const data = await fetchCategory(slug, skip);
      total = data.totalCount;
      count += data.items.length;
      for (const product of data.items) for (const sku of product.skus || []) {
        const row = pricedRow(sku, brand);
        if (!row) continue;
        const key = `${brand}|${row.n.toLocaleLowerCase('vi')}`;
        const list = byName.get(key) || [];
        list.push(row);
        byName.set(key, list);
      }
      if (count >= total) break;
      if (!data.items.length || skip + SIZE > 500) throw new Error(`${slug}: incomplete pagination`);
    }
    counts[brand] = `${count}/${total}`;
    console.log(`${brand}: ${count}/${total} products`);
  }
  const rows = [], conflicts = [];
  for (const list of byName.values()) {
    if (new Set(list.map(x => `${x.p}/${x.o}`)).size !== 1) {
      conflicts.push(list[0].n);
      continue;
    }
    rows.push(list[0]);
  }
  const present = new Set(rows.map(x => x.b));
  if (rows.length < 80 || !['Apple', 'Samsung', 'OPPO', 'Xiaomi'].every(x => present.has(x))) {
    throw new Error(`FPT coverage too low: ${rows.length} rows, brands ${[...present].join(', ')}`);
  }
  console.log(`Verified: ${rows.length} unique models; skipped ${conflicts.length} price conflicts`);
  if (conflicts.length) console.log(`Conflicts: ${conflicts.join(' | ')}`);
  return { batch_id: randomUUID(), scanned_at: new Date().toISOString(),
    source: ENDPOINT, counts, conflicts, rows };
}

function publishFile(filename, snapshot, message) {
  const path = `repos/${REPO}/contents/data/${filename}`;
  let sha;
  try { sha = command(GH, ['api', path, '-q', '.sha']).trim(); }
  catch (error) {
    // The first run has no snapshot; other API errors must stop publication.
    if (!String(error).includes('404')) throw error;
  }
  const payload = { message,
    content: Buffer.from(JSON.stringify(snapshot)).toString('base64'), branch: 'main' };
  if (sha) payload.sha = sha;
  const temp = join(tmpdir(), `live-${snapshot.batch_id}-${filename}`);
  let snapshotCommit;
  try {
    writeFileSync(temp, JSON.stringify(payload), { mode: 0o600 });
    const uploaded = JSON.parse(command(GH, ['api', path, '-X', 'PUT', '--input', temp]));
    snapshotCommit = uploaded.commit?.sha;
    if (!/^[0-9a-f]{40}$/.test(snapshotCommit || '')) {
      throw new Error(`GitHub did not return the ${filename} commit SHA`);
    }
  } finally { try { unlinkSync(temp); } catch {} }
  return snapshotCommit;
}

function publish(snapshot, variantSnapshot) {
  publishFile('fpt_live.json', snapshot, `FPT live batch ${snapshot.batch_id}`);
  const snapshotCommit = publishFile('tgdd_variant_live.json', variantSnapshot,
    `TGDĐ live variants batch ${snapshot.batch_id}`);
  command(GH, ['workflow', 'run', 'scan-tgdd.yml', '--repo', REPO,
    '--ref', 'main', '-f', `fpt_batch_id=${snapshot.batch_id}`,
    '-f', `fpt_snapshot_sha=${snapshotCommit}`]);
  console.log(`Published batch ${snapshot.batch_id} at ${snapshotCommit} and dispatched GitHub scan`);
}

const snapshot = await collect();
const localOutAt = process.argv.indexOf('--fpt-js');
if (localOutAt >= 0) {
  const out = process.argv[localOutAt + 1];
  if (!out) throw new Error('--fpt-js requires an output path');
  const now = new Date();
  const date = new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Ho_Chi_Minh',
    day: '2-digit', month: 'short' }).format(now).replace(' ', '-');
  const at = new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Ho_Chi_Minh',
    hour: '2-digit', minute: '2-digit', hour12: false }).format(now);
  writeFileSync(out, `/* FPT production API, ${snapshot.scanned_at} */\nwindow.FPT_LOCAL = ${JSON.stringify({date, at, rows: snapshot.rows})};\n`, 'utf8');
  console.log(`Wrote ${out}`);
}
if (process.argv.includes('--publish')) {
  const variantSnapshot = await collectVariantSnapshot(snapshot.batch_id);
  publish(snapshot, variantSnapshot);
}
else console.log(`Dry run: ${snapshot.batch_id}; add --publish to update GitHub`);
