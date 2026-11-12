// Collect current FPT production catalog through the Cloudflare Worker.
// The output is consumed only by this GitHub run's matching batch ID.
import { randomUUID } from 'node:crypto';
import { appendFileSync, writeFileSync } from 'node:fs';

const BRANDS = new Map([
  ['apple-iphone', 'Apple'], ['samsung', 'Samsung'], ['oppo', 'OPPO'],
  ['xiaomi', 'Xiaomi'], ['vivo', 'Vivo'], ['realme', 'Realme'],
]);
const ENDPOINT = 'https://papi.fptshop.com.vn/gw/v1/public/fulltext-search-service/category';
const SIZE = 50;
const proxyUrl = process.env.CF_PROXY_URL?.replace(/\/$/, '');
const token = process.env.CF_PROXY_TOKEN;
if (!proxyUrl || !token) throw Error('Cloudflare proxy credentials are missing');

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
  const response = await fetch(`${proxyUrl}/fetch?url=${encodeURIComponent(ENDPOINT)}`, {
    method: 'POST',
    headers: { 'X-Proxy-Token': token, 'Content-Type': 'application/json',
      Origin: 'https://fptshop.com.vn', Referer: `https://fptshop.com.vn/dien-thoai/${slug}` },
    body: JSON.stringify({ slug: `dien-thoai/${slug}`, skipCount: skip,
      maxResultCount: SIZE, sortMethod: 'noi-bat', categoryType: 'category' }),
    signal: AbortSignal.timeout(30000),
  });
  if (!response.ok) throw Error(`${slug} HTTP ${response.status}`);
  const data = await response.json();
  if (!Array.isArray(data.items) || !Number.isSafeInteger(data.totalCount)) {
    throw Error(`${slug}: invalid catalog response`);
  }
  return data;
}

const byName = new Map(), counts = {};
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
    if (!data.items.length || skip + SIZE > 500) throw Error(`${slug}: incomplete pagination`);
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
  throw Error(`FPT coverage too low: ${rows.length} rows; brands ${[...present].join(', ')}`);
}
const batch = randomUUID();
const snapshot = { batch_id: batch, scanned_at: new Date().toISOString(),
  source: ENDPOINT, counts, conflicts, rows };
writeFileSync(process.env.FPT_OUTPUT || new URL('../data/fpt_live.json', import.meta.url),
  JSON.stringify(snapshot));
if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `batch_id=${batch}\n`);
console.log(`Verified ${rows.length} current FPT SKUs; ${conflicts.length} conflicting models excluded`);
