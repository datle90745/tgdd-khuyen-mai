/**
 * CI/CD CIRCUIT BREAKER - Kiem dinh toan ven du lieu truoc khi cho phep commit.
 *
 * Day la BAN TRIEN KHAI DUY NHAT cua circuit breaker. tests/verify_scan.py chi la
 * vo boc goi sang file nay, de khong bao gio ton tai hai ban logic lech nhau.
 *
 * Khac biet so voi ban cu (va ly do):
 *  - Kiem dung dot quet HOM NAY, khong phai "file moi nhat tren dia". Ban cu khi scan
 *    that bai se lang le kiem lai file hom qua roi bao PASS.
 *  - Dem SKU theo tests/gate-config.json (so chinh xac), khong phai >= mot so ma thuat.
 *  - Kiem ca 3 rule (flash_chon1 / den_tru_do / chon1) va ca truong `kind`,
 *    khong con menh de thoat `|| pmh === diff` lam check vo hieu.
 *  - Three-way sync kiem bang parse JSON that, khong phai so khop chuoi con.
 *  - Gom TAT CA loi roi moi thoat, thay vi dung o loi dau tien.
 *
 * Chay: node tests/verify_scan.js
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const CFG = JSON.parse(fs.readFileSync(path.join(ROOT, 'tests', 'gate-config.json'), 'utf8'));

const SCANS_DIR = path.join(ROOT, 'data', 'scans');
const LATEST_JS = path.join(ROOT, 'data', 'latest.js');
const SCANS_JS = path.join(ROOT, 'data', 'scans.js');
const PRODUCTS_CSV = path.join(ROOT, 'scraper', 'products.csv');

const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const errors = [];
const warnings = [];
const fail = (msg) => errors.push(msg);
const warn = (msg) => warnings.push(msg);

/** Doc `window.X = <json>;` o cuoi file (bo qua dong comment dau file). */
function parseWindowVar(file, varName) {
  const text = fs.readFileSync(file, 'utf8').replace(/^﻿/, '');
  const marker = `window.${varName}`;
  const i = text.indexOf(marker);
  if (i < 0) return { err: `khong tim thay \`${marker}\`` };
  const eq = text.indexOf('=', i + marker.length);
  if (eq < 0) return { err: `\`${marker}\` khong co dau =` };
  // Dung o khai bao window.* ke tiep - data.js co nhieu bien trong cung mot file.
  const rest = text.slice(eq + 1);
  const next = rest.indexOf('\nwindow.');
  const body = (next < 0 ? rest : rest.slice(0, next)).trim().replace(/;\s*$/, '');
  try {
    return { value: JSON.parse(body) };
  } catch (e) {
    return { err: `JSON khong hop le: ${e.message}` };
  }
}

/** '2026-11-07' -> '07-Nov' (dung de doi chieu field `date` voi ten file). */
function isoToDdMmm(iso) {
  const [, m, d] = iso.split('-');
  return `${d}-${MON[Number(m) - 1]}`;
}

function todayInTz(tz) {
  // 'en-CA' tra ve dung dinh dang YYYY-MM-DD.
  return new Date().toLocaleDateString('en-CA', { timeZone: tz });
}

console.log('=================================================================');
console.log('   CI/CD CIRCUIT BREAKER - KIEM DINH TOAN VEN DU LIEU');
console.log('=================================================================');

// ---------------------------------------------------------------------------
// 1. Master list: scraper/products.csv
// ---------------------------------------------------------------------------
let masterModels = [];
if (!fs.existsSync(PRODUCTS_CSV)) {
  fail(`Khong tim thay danh muc ${path.relative(ROOT, PRODUCTS_CSV)}`);
} else {
  const lines = fs.readFileSync(PRODUCTS_CSV, 'utf8')
    .replace(/^﻿/, '')
    .split(/\r?\n/)
    .filter((l) => l.trim());
  const header = lines.shift() || '';
  if (!/^model\s*,\s*url/i.test(header)) {
    fail(`products.csv co header la "${header}", mong doi "model,url"`);
  }
  masterModels = lines.map((l) => l.split(',')[0].trim());

  if (masterModels.length !== CFG.crawlSkuCount) {
    fail(
      `products.csv co ${masterModels.length} SKU, danh sach cao quy dinh DUNG ${CFG.crawlSkuCount} ` +
      `(sua tests/gate-config.json neu day la thay doi co chu y)`
    );
  }
  const dupMaster = masterModels.filter((m, i) => masterModels.indexOf(m) !== i);
  if (dupMaster.length) {
    fail(`products.csv co model trung lap: ${[...new Set(dupMaster)].join(', ')}`);
  }
  console.log(`[1] Danh sach cao: ${masterModels.length} SKU trong products.csv`);
}

// data/data.js = Master List BAO CAO da khoa (bang tracking). No KHAC danh sach cao va
// khong duoc ep bang nhau - xem _twoLists trong gate-config.json. Rang buoc that la:
// kich thuoc dung nhu da khoa, MASTER_ORDER khop BASE.rows, va products.csv phu het no.
const DATA_JS = path.join(ROOT, 'data', 'data.js');
if (fs.existsSync(DATA_JS)) {
  // Parse that window.BASE / window.MASTER_ORDER - dem `"model":` tren ca file se lech
  // vi cac bien khac (RRP_NOTES, RISE_RAW...) cung chua khoa do.
  const baseRes = parseWindowVar(DATA_JS, 'BASE');
  if (baseRes.err) {
    fail(`data/data.js: window.BASE ${baseRes.err}`);
  } else {
    const catalog = baseRes.value.rows || [];
    if (catalog.length !== CFG.masterListCount) {
      fail(
        `data/data.js co ${catalog.length} model nhung Master List bao cao da khoa o ` +
        `${CFG.masterListCount} SKU. Day la bang tracking - chi doi khi nguoi dung yeu cau, ` +
        `va phai sua masterListCount trong tests/gate-config.json cung luc.`
      );
    }
    // Chieu dung: moi model DUOC BAO CAO deu phai nam trong danh sach cao.
    // Chieu nguoc lai (products.csv nhieu hon data.js) la BINH THUONG.
    const crawled = new Set(masterModels);
    const reportedNotCrawled = catalog.map((r) => r.model).filter((m) => !crawled.has(m));
    if (reportedNotCrawled.length) {
      fail(
        `${reportedNotCrawled.length} model co trong Master List bao cao nhung KHONG duoc cao ` +
        `(thieu trong products.csv): ` + reportedNotCrawled.slice(0, 10).join(', ') +
        (reportedNotCrawled.length > 10 ? ', ...' : '')
      );
    }
    // index.html dung MASTER_ORDER de dung bang va sheet Excel; lech voi BASE la mat dong.
    const moRes = parseWindowVar(DATA_JS, 'MASTER_ORDER');
    if (moRes.err) {
      fail(`data/data.js: window.MASTER_ORDER ${moRes.err}`);
    } else if (moRes.value.length !== catalog.length) {
      fail(
        `data/data.js: MASTER_ORDER co ${moRes.value.length} muc nhung BASE.rows co ${catalog.length}`
      );
    }
  }
}

// ---------------------------------------------------------------------------
// 2. Dot quet phai la cua HOM NAY (gio Viet Nam)
// ---------------------------------------------------------------------------
const today = todayInTz(CFG.timezone);
let scanData = null;
let scanFileName = null;

if (!fs.existsSync(SCANS_DIR)) {
  fail(`Khong tim thay thu muc ${path.relative(ROOT, SCANS_DIR)}`);
} else {
  const scanFiles = fs.readdirSync(SCANS_DIR)
    .filter((f) => /^scan_\d{4}-\d{2}-\d{2}\.json$/.test(f))
    .sort();

  if (!scanFiles.length) {
    fail(`Khong co file scan nao trong ${path.relative(ROOT, SCANS_DIR)}`);
  } else {
    const newest = scanFiles[scanFiles.length - 1];
    const newestIso = newest.slice(5, 15);

    if (CFG.requireScanToday && newestIso !== today) {
      fail(
        `Dot quet moi nhat la ${newestIso} nhung hom nay (${CFG.timezone}) la ${today}. ` +
        `Buoc quet da that bai hoac chua chay - TUYET DOI khong commit du lieu cu.`
      );
    }

    scanFileName = newest;
    try {
      scanData = JSON.parse(fs.readFileSync(path.join(SCANS_DIR, newest), 'utf8').replace(/^﻿/, ''));
    } catch (e) {
      fail(`Loi cu phap JSON trong ${newest}: ${e.message}`);
    }

    if (scanData) {
      const expectedDate = isoToDdMmm(newestIso);
      if (scanData.date !== expectedDate) {
        fail(
          `${newest} co field date="${scanData.date}" nhung ten file ung voi "${expectedDate}". ` +
          `(strftime("%d-%b") phu thuoc locale - day la dau hieu chay sai moi truong.)`
        );
      }
    }
    console.log(`[2] Dot quet kiem tra: ${newest} (hom nay: ${today})`);
  }
}

// ---------------------------------------------------------------------------
// 3. Domain Invariants tren tung dong cua dot quet
// ---------------------------------------------------------------------------
const rows = (scanData && scanData.rows) || [];

if (scanData) {
  if (rows.length !== CFG.crawlSkuCount) {
    fail(`${scanFileName} co ${rows.length} dong, danh sach cao quy dinh DUNG ${CFG.crawlSkuCount}`);
  }

  const seen = new Set();
  let activeCount = 0;

  rows.forEach((r, idx) => {
    const model = r.model;
    if (!model) {
      fail(`${scanFileName} dong ${idx} thieu ten model`);
      return;
    }
    if (seen.has(model)) fail(`Model TRUNG LAP trong ${scanFileName}: ${model}`);
    seen.add(model);

    if (r.status !== 'active') {
      if (r.pmh !== null && r.pmh !== undefined) {
        fail(`${model}: status=${r.status} nhung pmh=${r.pmh} (phai la null)`);
      }
      return;
    }

    activeCount++;
    const { rrp, red, pmh, kind, rule } = r;
    const choice = r.choice || 0;

    // --- Gia tri co ban (CONSTRAINTS 1 + docstring cua enforce_domain_invariants) ---
    if (typeof rrp !== 'number' || rrp <= 0) {
      fail(`${model}: RRP khong hop le (${rrp}) - active bat buoc RRP > 0`);
      return;
    }
    if (typeof red !== 'number' || red <= 0) {
      fail(`${model}: gia do khong hop le (${red}) - active bat buoc red > 0`);
      return;
    }
    if (red > rrp) {
      fail(`${model}: red=${red} > rrp=${rrp}`);
      return;
    }
    if (typeof pmh !== 'number' || pmh < 0 || pmh > rrp) {
      fail(`${model}: PMH khong hop le (pmh=${pmh}, rrp=${rrp})`);
      return;
    }

    // `kind` CO Y khong bi gate - xem _kindNote trong gate-config.json.
    // Chi kiem no ton tai de bat loi dong bi cat xen.
    if (typeof kind !== 'string' || !kind) {
      fail(`${model}: thieu truong kind`);
    }
    if (!CFG.allowedRules.includes(rule)) {
      fail(`${model}: rule="${rule}" khong thuoc {${CFG.allowedRules.join(', ')}}`);
      return;
    }

    const diff = rrp - red;

    // --- CONSTRAINTS 2.1: ba nhanh, kiem day du, khong co menh de thoat ---
    if (rule === 'flash_chon1') {
      if (pmh !== choice) {
        fail(`${model}: vi pham 2.1.2 - rule=flash_chon1 nhung pmh=${pmh} != choice=${choice}`);
      }
    } else if (rule === 'den_tru_do') {
      if (diff < choice) {
        fail(
          `${model}: vi pham 2.1.3 - diff=${diff} < choice=${choice} nen rule phai la "chon1", ` +
          `khong phai "den_tru_do"`
        );
      }
      if (pmh !== diff) {
        fail(`${model}: vi pham 2.1.3 - rule=den_tru_do nhung pmh=${pmh} != diff=${diff}`);
      }
    } else if (rule === 'chon1') {
      if (choice <= diff) {
        fail(
          `${model}: vi pham 2.1.3 - choice=${choice} <= diff=${diff} nen rule phai la "den_tru_do", ` +
          `khong phai "chon1"`
        );
      }
      if (pmh !== choice) {
        fail(`${model}: vi pham 2.1.3 - rule=chon1 nhung pmh=${pmh} != choice=${choice}`);
      }
    }

    // --- online luon la chenh lech den-do (enforce_domain_invariants dong 308) ---
    if (typeof r.online === 'number' && r.online !== diff) {
      fail(`${model}: online=${r.online} != diff=${diff}`);
    }

    // --- CONSTRAINTS 2.1: Banner cam phai di cung flash_chon1 ---
    if (r.banner === true && rule !== 'flash_chon1') {
      fail(`${model}: vi pham 2.1 - row co banner=true nhung rule="${rule}" khong phai "flash_chon1"`);
    }
    if (rule === 'flash_chon1' && choice === 0 && pmh !== 0) {
      fail(`${model}: vi pham 2.1.2 - rule=flash_chon1 voi choice=0 bat buoc pmh=0, nhung pmh=${pmh}`);
    }

    // --- So lieu phai la so hop le, khong duoc chua NaN hoac null ---
    for (const f of ['rrp', 'red', 'pmh', 'online', 'total_online', 'choice']) {
      if (typeof r[f] !== 'number' || isNaN(r[f])) {
        fail(`${model}: truong ${f} khong phai so hop le (${r[f]})`);
      }
    }
  });

  // Ban cu chi dem len(rows) >= 90, ma rows gom ca dong loi. Day moi la nguong that.
  const minActive = Math.ceil((CFG.crawlSkuCount * CFG.minActivePct) / 100);
  if (activeCount < minActive) {
    fail(
      `Chi co ${activeCount}/${rows.length} SKU doc duoc gia (status=active), ` +
      `toi thieu ${minActive} (${CFG.minActivePct}% Master List)`
    );
  }

  // Moi SKU trong Master List phai co mat trong dot quet.
  const missing = masterModels.filter((m) => !seen.has(m));
  if (missing.length) {
    fail(`${missing.length} SKU trong products.csv bi thieu khoi dot quet: ${missing.slice(0, 10).join(', ')}${missing.length > 10 ? ', ...' : ''}`);
  }

  console.log(`[3] Domain Invariants: ${rows.length} dong, ${activeCount} active`);
}

// ---------------------------------------------------------------------------
// 4. Three-Way Sync (CONSTRAINTS 2.4) - parse that, khong so khop chuoi con
// ---------------------------------------------------------------------------
let latestObj = null;
if (!fs.existsSync(LATEST_JS)) {
  fail('Khong tim thay data/latest.js');
} else {
  const res = parseWindowVar(LATEST_JS, 'LATEST');
  if (res.err) fail(`data/latest.js: ${res.err}`);
  else latestObj = res.value;
}

if (latestObj && scanData) {
  if (latestObj.date !== scanData.date) {
    fail(`data/latest.js date="${latestObj.date}" lech voi dot quet "${scanData.date}"`);
  }
  const lRows = latestObj.rows || [];
  if (lRows.length !== rows.length) {
    fail(`data/latest.js co ${lRows.length} dong, dot quet co ${rows.length} dong`);
  }
  // Doi chieu tung so, khong chi dem.
  const scanByModel = new Map(rows.map((r) => [r.model, r]));
  let drift = 0;
  for (const lr of lRows) {
    const sr = scanByModel.get(lr.model);
    if (!sr) {
      fail(`data/latest.js co model "${lr.model}" khong ton tai trong ${scanFileName}`);
      continue;
    }
    for (const k of ['rrp', 'red', 'pmh', 'rule', 'kind', 'status']) {
      if (sr[k] !== lr[k]) {
        if (drift < 10) fail(`Lech latest.js vs ${scanFileName} - ${lr.model}.${k}: ${lr[k]} vs ${sr[k]}`);
        drift++;
      }
    }
  }
  if (drift >= 10) fail(`... va ${drift - 10} sai lech khac giua latest.js va ${scanFileName}`);
}

let scansArr = null;
if (!fs.existsSync(SCANS_JS)) {
  fail('Khong tim thay data/scans.js');
} else {
  const res = parseWindowVar(SCANS_JS, 'SCANS');
  if (res.err) fail(`data/scans.js: ${res.err}`);
  else if (!Array.isArray(res.value)) fail('data/scans.js: window.SCANS khong phai mang');
  else scansArr = res.value;
}

if (scansArr && scanData) {
  const byDate = new Map(scansArr.map((s) => [s.date, s]));

  const todayEntry = byDate.get(scanData.date);
  if (!todayEntry) {
    fail(`data/scans.js thieu dot quet "${scanData.date}" (latest.js co dot moi ma scans.js bo sot)`);
  } else if ((todayEntry.rows || []).length !== rows.length) {
    fail(
      `data/scans.js dot "${scanData.date}" co ${(todayEntry.rows || []).length} dong, ` +
      `file scan goc co ${rows.length} dong`
    );
  }

  // write_scans_js() co chu y giu lai `scansJsRetention` dot gan nhat (scans[-30:]),
  // nen dot cu hon bi rot ra KHONG phai loi dong bo. Thu phai kiem la: trong cua so
  // duoc giu lai, khong duoc thung mot dot nao.
  const onDisk = fs.readdirSync(SCANS_DIR)
    .filter((f) => /^scan_\d{4}-\d{2}-\d{2}\.json$/.test(f))
    .sort()
    .map((f) => ({ file: f, date: isoToDdMmm(f.slice(5, 15)) }));
  const retained = onDisk.slice(-CFG.scansJsRetention);
  const gaps = retained.filter((o) => !byDate.has(o.date));
  if (gaps.length) {
    fail(
      `CONSTRAINTS 2.4 - ${gaps.length} dot quet nam trong cua so ${CFG.scansJsRetention} dot gan nhat ` +
      `nhung bi bo sot khoi window.SCANS: ${gaps.map((o) => o.file).join(', ')}`
    );
  }
  if (scansArr.length !== retained.length) {
    fail(
      `data/scans.js co ${scansArr.length} dot, mong doi ${retained.length} ` +
      `(${onDisk.length} file scan, giu lai ${CFG.scansJsRetention} dot gan nhat)`
    );
  }
  console.log(
    `[4] Three-Way Sync: ${onDisk.length} file scan, giu ${retained.length}, ` +
    `scans.js co ${scansArr.length} dot`
  );
}

// ---------------------------------------------------------------------------
// 5. Ban sao long nhau (nguon du lieu ma / divergent copy)
// ---------------------------------------------------------------------------
if (CFG.nestedCopyPath) {
  const nested = path.join(ROOT, CFG.nestedCopyPath, 'data', 'latest.js');
  if (fs.existsSync(nested)) {
    const res = parseWindowVar(nested, 'LATEST');
    const nestedDate = res.value ? res.value.date : '(khong doc duoc)';
    // Canh bao chu khong chan commit: ban sao cu khong lam sai du lieu dang phuc vu web,
    // nhung no van bi `git add "promotion tgdd"` dua vao moi dot commit.
    if (!latestObj || nestedDate !== latestObj.date) {
      warn(
        `Ban sao long nhau "${CFG.nestedCopyPath}/data/latest.js" dang o dot "${nestedDate}" ` +
        `trong khi ban chinh o "${latestObj ? latestObj.date : '?'}". ` +
        `Workflow van \`git add "${CFG.nestedCopyPath}"\` nen ban cu nay duoc commit moi dot - ` +
        `nen xoa thu muc do hoac bo khoi buoc git add.`
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Tong ket
// ---------------------------------------------------------------------------
console.log('');
for (const w of warnings) console.log(`[CANH BAO] ${w}`);

if (errors.length) {
  console.error('=================================================================');
  console.error(`   CIRCUIT BREAKER: ${errors.length} VI PHAM - CHAN COMMIT`);
  console.error('=================================================================');
  errors.forEach((e, i) => console.error(`  ${String(i + 1).padStart(2, ' ')}. ${e}`));
  console.error('');
  process.exit(1);
}

console.log('=================================================================');
console.log('   CIRCUIT BREAKER: 100% PASS - DU LIEU DAT CHUAN DE COMMIT');
console.log('=================================================================');
