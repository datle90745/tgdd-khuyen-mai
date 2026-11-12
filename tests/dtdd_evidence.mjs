export function hasCurrentDtddProof(row, scan) {
  const proof = row?.dtdd_verification;
  if (!proof || !['dtdd_full_catalog_popup', 'dtdd_full_catalog_card'].includes(proof.source)) return false;
  if (typeof row.url !== 'string' || !/^https:\/\/www\.thegioididong\.com\/dtdd\/[a-z0-9-]+(?:\?.*)?$/.test(row.url)) return false;
  const slug = new URL(row.url).pathname.split('/').at(-1);
  if (proof.slug !== slug || !/^\d+$/.test(String(proof.model_code))) return false;
  if (!Number.isSafeInteger(proof.page_index) || !Number.isSafeInteger(proof.pages_scanned) ||
      !Number.isSafeInteger(proof.catalog_total) || proof.page_index < 0 ||
      proof.page_index >= proof.pages_scanned || proof.pages_scanned < 1 ||
      proof.pages_scanned > 25 || proof.catalog_total < 1 ||
      proof.catalog_total > 500 || proof.pages_scanned * 20 < proof.catalog_total) return false;
  if (!Number.isSafeInteger(row.rrp) || !Number.isSafeInteger(row.red) ||
      row.red <= 0 || row.red > row.rrp ||
      proof.rrp !== row.rrp || proof.red !== row.red) return false;
  const scanAt = Date.parse(scan?.scanned_at), checkedAt = Date.parse(proof.checked_at);
  const age = scanAt - checkedAt;
  return Number.isFinite(age) && age >= -60_000 && age <= 30 * 60_000;
}
