import assert from 'node:assert/strict';
import { isFreshLatest } from '../scraper/should_scan_scheduled.mjs';

const now = Date.parse('2026-11-12T03:00:00Z');
const gate = { crawlSkuCount: 135, minActivePct: 90 };
const rows = Array.from({ length: 135 }, () => ({ status: 'active' }));
const fresh = { scanned_at: new Date(now - 60 * 60 * 1000).toISOString(), rows };
assert.equal(isFreshLatest(fresh, gate, now), true);
assert.equal(isFreshLatest({ ...fresh, scanned_at: new Date(now - 91 * 60 * 1000).toISOString() }, gate, now), false);
assert.equal(isFreshLatest({ ...fresh, rows: rows.slice(0, 134) }, gate, now), false);
assert.equal(isFreshLatest({ ...fresh, rows: rows.map((r, i) => i < 121 ? r : { status: 'error' }) }, gate, now), false);
assert.equal(isFreshLatest(null, gate, now), false);
console.log('SCHEDULE_GUARD_PASS');
