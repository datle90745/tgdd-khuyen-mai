// Windows-side live variant prices for the same batch as the FPT scan.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const ROOT = new URL('../', import.meta.url);
const SITE = 'https://www.thegioididong.com';
const API = 'https://api.thegioididong.com/gw/bus-tgdd-tmdt/api/Product/GetPopup';
const BRANDS = ['apple-iphone', 'samsung', 'oppo', 'xiaomi', 'vivo', 'realme',
  'honor', 'motorola', 'nothing-phone'];
const HEADERS = { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/138.0.0.0 Safari/537.36',
  Origin: SITE, Referer: `${SITE}/dtdd`, Accept: 'application/json,text/html,*/*' };

async function get(url) {
  const response = await fetch(url, { headers: HEADERS, signal: AbortSignal.timeout(25000) });
  if (!response.ok) throw new Error(`${url}: HTTP ${response.status}`);
  return response;
}

export function parseExactPopup(data, slug) {
  const prices = new Set();
  for (const box of data?.data?.boxBuys || []) {
    if (String(box.url || '').replace(/^\//, '').split('?')[0] !== `dtdd/${slug}`) continue;
    for (const entry of box.productPrices || []) {
      const red = entry.price, rrp = entry.sysPrice;
      if (entry.isCanBuy === true && Number.isSafeInteger(red) && Number.isSafeInteger(rrp) &&
          0 < red && red <= rrp && rrp <= 200_000_000) prices.add(`${rrp}/${red}`);
    }
  }
  if (prices.size !== 1) return null;
  const [rrp, red] = [...prices][0].split('/').map(Number);
  return { slug, rrp, red };
}

function trackedSlugs() {
  const csv = readFileSync(new URL('scraper/products.csv', ROOT), 'utf8');
  return new Set([...csv.matchAll(/https:\/\/www\.thegioididong\.com\/dtdd\/([a-z0-9-]+)/g)]
    .map(match => match[1]));
}

export async function collectVariantSnapshot(batchId) {
  if (!/^[0-9a-f-]{36}$/.test(batchId)) throw new Error('Invalid batch ID');
  const tracked = trackedSlugs();
  const variants = new Map();
  const failures = [];
  for (const brand of BRANDS) {
    try {
      const html = await (await get(`${SITE}/dtdd-${brand}`)).text();
      for (const card of html.split('<div data-product-code="').slice(1)) {
        const modelCode = card.match(/data-model-code="(\d+)"/)?.[1];
        const links = [...card.matchAll(/href="\/dtdd\/([a-z0-9-]+)(?:\?[^" ]*)?"/g)].map(m => m[1]);
        if (!modelCode || !links.length) continue;
        const main = links[0];
        for (const slug of new Set(links)) {
          if (slug !== main && tracked.has(slug)) variants.set(slug, modelCode);
        }
      }
      console.log(`TGDĐ ${brand}: ${[...variants.values()].length} tracked variant links collected`);
    } catch (error) {
      failures.push(`${brand}: ${error.message}`);
    }
  }
  const popupCache = new Map();
  const rows = [];
  for (const [slug, modelCode] of variants) {
    try {
      if (!popupCache.has(modelCode)) {
        const url = `${API}?modelCode=${modelCode}&provinceId=1000&sellerId=10`;
        popupCache.set(modelCode, await (await get(url)).json());
      }
      const row = parseExactPopup(popupCache.get(modelCode), slug);
      if (row) rows.push({ ...row, model_code: modelCode });
      else failures.push(`${slug}: no unique live price`);
    } catch (error) {
      failures.push(`${slug}: ${error.message}`);
    }
  }
  if (!rows.length) throw new Error(`TGDĐ: no verified variant prices; ${failures.join(' | ')}`);
  console.log(`TGDĐ live: ${rows.length}/${variants.size} exact variants; ${failures.length} failures`);
  for (const row of rows) console.log(`  ${row.slug}: red=${row.red} rrp=${row.rrp}`);
  return { batch_id: batchId, scanned_at: new Date().toISOString(), source: API,
    tracked_variants: variants.size, failures, rows };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const snapshot = await collectVariantSnapshot('00000000-0000-4000-8000-000000000000');
  console.log(JSON.stringify({ count: snapshot.rows.length, failures: snapshot.failures }));
}
