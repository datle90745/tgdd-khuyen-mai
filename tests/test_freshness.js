const fs = require('fs');
const vm = require('vm');
const assert = require('assert');

const html = fs.readFileSync(__dirname + '/../index.html', 'utf8');
const start = html.indexOf('const MAX_CURRENT_AGE_MS');
const end = html.indexOf('// GitHub Pages is static', start);
assert(start >= 0 && end > start);
const source = html.slice(start, end);

function check(ageHours, expectedUnavailable) {
  const stamp = ageHours === null ? null : new Date(Date.now() - ageHours * 3600000).toISOString();
  const panes = Object.fromEntries(['p-latest', 'p-market', 'p-compare'].map(id => [
    id, {dataset: {}, notice: {hidden: true, textContent: ''},
      querySelector() { return this.notice; }}
  ]));
  const elements = {xlsx: {disabled: false}, subline: {textContent: ''}};
  vm.runInNewContext(source, {
    Date, Intl, Number, Array,
    location: {protocol: 'https:'},
    document: {hidden: false, getElementById: id => panes[id], addEventListener() {}},
    LATEST: {scanned_at: stamp},
    MK: {scans: [{scanned_at: stamp}]},
    $: id => elements[id],
    setInterval() {}
  });
  for (const pane of Object.values(panes)) {
    assert.strictEqual(pane.dataset.currentUnavailable, String(expectedUnavailable));
    assert.strictEqual(pane.notice.hidden, !expectedUnavailable);
  }
  assert.strictEqual(elements.xlsx.disabled, expectedUnavailable);
}

check(1, false);
check(4, true);
check(null, true);

// A failed model in a same-day scan must not inherit its earlier PMH.
const buildStart = html.indexOf('function build(){');
const buildEnd = html.indexOf('function delta(r){', buildStart);
const base = {dates: ['09-Nov'], rows: [
  {brand: 'OPPO', model: 'Failed', rrp: 10000000, status: 'active', pmh: [500000]},
  {brand: 'OPPO', model: 'Fresh', rrp: 9000000, status: 'active', pmh: [400000]},
  {brand: 'OPPO', model: 'Missing', rrp: 8000000, status: 'active', pmh: [300000]}
]};
const buildContext = {
  BASE: base, SCANS: [], imports: [],
  LATEST: {date: '10-Nov', rows: [
    {model: 'Failed', status: 'error', rrp: null, red: null, pmh: null},
    {model: 'Fresh', status: 'active', rrp: 9000000, red: 8500000, pmh: 500000}
  ]},
  window: {BASE: base}, RRP_NOTES: {},
  canonKey: model => model, inferBrand: () => 'OPPO',
  fmt: value => String(value), rseg: () => '7-10M'
};
vm.runInNewContext('let S;\n' + html.slice(buildStart, buildEnd) +
  '\nbuild(); globalThis.testRows=S.rows;', buildContext);
const failed = buildContext.testRows.find(row => row.model === 'Failed');
assert.strictEqual(failed.status, 'error');
assert.strictEqual(failed.rrp, null);
assert.strictEqual(failed.pmh[failed.pmh.length - 1], null);
const missing = buildContext.testRows.find(row => row.model === 'Missing');
assert.strictEqual(missing.status, 'error');
assert.strictEqual(missing.pmh[missing.pmh.length - 1], null);
console.log('FRESHNESS_UI_PASS');
