import assert from 'node:assert/strict';
import {checkScanner, latestAgeMs} from '../cloudflare-watchdog.mjs';

const now = Date.parse('2026-11-12T12:00:00Z');
const env = {GH_DISPATCH_TOKEN: 'test-secret'};
const latest = mins => `window.LATEST = ${JSON.stringify({
  scanned_at: new Date(now - mins * 60_000).toISOString(),
  rows: [{status: 'active'}]
})};`;
assert.equal(latestAgeMs(latest(60), now), 60 * 60_000);
assert.equal(latestAgeMs('broken', now), Infinity);

function mock(source, runs = [], dispatchStatus = 204) {
  const calls = [];
  const request = async (url, options = {}) => {
    calls.push({url: String(url), method: options.method || 'GET'});
    if (String(url).includes('raw.githubusercontent.com')) return new Response(source);
    if (String(url).endsWith('/dispatches')) return new Response(null, {status: dispatchStatus});
    return Response.json({workflow_runs: runs});
  };
  return {request, calls};
}

let t = mock(latest(60));
assert.deepEqual(await checkScanner(env, t.request, now), {state: 'fresh', ageMinutes: 60});
assert.equal(t.calls.length, 1);
t = mock(latest(190), [{status: 'in_progress'}]);
assert.equal((await checkScanner(env, t.request, now)).state, 'running');
assert.equal(t.calls.length, 2);
t = mock(latest(190));
assert.equal((await checkScanner(env, t.request, now, true)).state, 'would_dispatch');
assert.equal(t.calls.length, 2);
t = mock(latest(190));
assert.equal((await checkScanner(env, t.request, now)).state, 'dispatched');
assert.equal(t.calls.length, 3);
t = mock(latest(190), [], 401);
await assert.rejects(checkScanner(env, t.request, now), /GitHub dispatch HTTP 401/);
console.log('CLOUD_WATCHDOG_PASS');
