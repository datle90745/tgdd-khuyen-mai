import assert from 'node:assert/strict';
import { hasCurrentDtddProof } from './dtdd_evidence.mjs';

const scan = { scanned_at: '2026-11-12T10:20:00+07:00' };
const row = { model: 'Galaxy A18 6GB/128GB', status: 'active',
  url: 'https://www.thegioididong.com/dtdd/samsung-galaxy-a18-6gb-128gb',
  rrp: 7190000, red: 7190000,
  dtdd_verification: { source: 'dtdd_full_catalog_popup',
    slug: 'samsung-galaxy-a18-6gb-128gb', model_code: '234423',
    page_index: 8, pages_scanned: 9, catalog_total: 170,
    checked_at: '2026-11-12T10:19:00+07:00', rrp: 7190000, red: 7190000 } };
assert.equal(hasCurrentDtddProof(row, scan), true);
assert.equal(hasCurrentDtddProof({ ...row, red: 6890000 }, scan), false);
assert.equal(hasCurrentDtddProof({ ...row, dtdd_verification: { ...row.dtdd_verification,
  slug: 'samsung-galaxy-a18-4gb-128gb' } }, scan), false);
assert.equal(hasCurrentDtddProof({ ...row, dtdd_verification: { ...row.dtdd_verification,
  checked_at: '2026-11-12T06:00:00+07:00' } }, scan), false);
assert.equal(hasCurrentDtddProof({ ...row, dtdd_verification: { ...row.dtdd_verification,
  pages_scanned: 1 } }, scan), false);
console.log('DTDD_EVIDENCE_PASS');
