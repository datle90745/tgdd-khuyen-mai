import fs from 'node:fs';
import path from 'node:path';

function fail(msg) {
  console.error(`\n[CIRCUIT BREAKER ERROR] ${msg}`);
  process.exit(1);
}

console.log("=================================================================");
console.log("   CHẠY CI/CD CIRCUIT BREAKER: KIỂM ĐỊNH TOÀN VẸN DỮ LIỆU       ");
console.log("=================================================================");

const PRODUCTS_CSV = 'scraper/products.csv';
if (!fs.existsSync(PRODUCTS_CSV)) fail(`Không tìm thấy ${PRODUCTS_CSV}`);
const lines = fs.readFileSync(PRODUCTS_CSV, 'utf8').split(/\r?\n/).filter(l => l.trim());
if (lines.length < 95) fail(`products.csv chỉ có ${lines.length} dòng (yêu cầu đủ 95 SKU)`);

const SCANS_DIR = 'data/scans';
const scanFiles = fs.readdirSync(SCANS_DIR).filter(f => f.startsWith('scan_') && f.endsWith('.json')).sort();
if (scanFiles.length === 0) fail(`Không tìm thấy file scan nào trong ${SCANS_DIR}`);

const latestScanFile = scanFiles[scanFiles.length - 1];
console.log(`Kiểm tra file scan mới nhất: ${latestScanFile}`);

const scanData = JSON.parse(fs.readFileSync(path.join(SCANS_DIR, latestScanFile), 'utf8').replace(/^\uFEFF/, ''));
const rows = scanData.rows || [];
if (rows.length < 90) fail(`Số lượng SKU quét được quá thấp: ${rows.length} < 90`);

const seenModels = new Set();
for (let idx = 0; idx < rows.length; idx++) {
  const r = rows[idx];
  const model = r.model;
  if (!model) fail(`Dòng ${idx} trong ${latestScanFile} bị thiếu tên model!`);
  if (seenModels.has(model)) fail(`Phát hiện model bị TRÙNG LẶP (Duplicate): ${model}`);
  seenModels.add(model);

  if (r.status === 'active') {
    const rrp = r.rrp;
    const red = r.red;
    const pmh = r.pmh;
    const choice = r.choice || 0;
    const rule = r.rule;

    if (rrp == null || rrp <= 0) fail(`Model ${model} có RRP không hợp lệ: ${rrp}`);
    if (red != null && (red <= 0 || red > rrp)) fail(`Model ${model} có giá đỏ không hợp lệ: red=${red}, rrp=${rrp}`);
    if (pmh != null && (pmh < 0 || pmh > rrp)) fail(`Model ${model} có PMH không hợp lệ: pmh=${pmh}, rrp=${rrp}`);

    const diff = red != null ? rrp - red : 0;
    if (rule === 'flash_chon1' && pmh !== choice) {
      fail(`Model ${model} vi phạm Domain Invariant 2.1: rule=flash_chon1 nhưng pmh=${pmh} != choice=${choice}`);
    }
    if (rule === 'den_tru_do' && red != null) {
      const expected = Math.max(diff, choice);
      if (pmh !== expected && pmh !== diff) {
        fail(`Model ${model} vi phạm Domain Invariant 2.1: rule=den_tru_do nhưng pmh=${pmh} != expected=${expected}`);
      }
    }
  }
}

console.log(`-> Kiểm tra ${rows.length} SKU trong ${latestScanFile}: 100% HỢP LỆ!`);

// Check data/latest.js
const latestContent = fs.readFileSync('data/latest.js', 'utf8').replace(/^\uFEFF/, '');
const matchLatest = latestContent.match(/window\.LATEST\s*=\s*(\{.*?\});?\s*$/s);
if (!matchLatest) fail('data/latest.js không định nghĩa window.LATEST hợp lệ!');
const latestJson = JSON.parse(matchLatest[1]);
if (latestJson.date !== scanData.date) {
  fail(`data/latest.js lệch date so với file scan (${latestJson.date} vs ${scanData.date})`);
}

// Check data/scans.js
const scansContent = fs.readFileSync('data/scans.js', 'utf8');
if (!scansContent.includes(scanData.date)) {
  fail(`data/scans.js thiếu đợt quét ngày ${scanData.date}`);
}

console.log("=================================================================");
console.log("   CIRCUIT BREAKER: 100% PASS - DỮ LIỆU ĐẠT CHUẨN ĐỂ COMMIT!   ");
console.log("=================================================================");
