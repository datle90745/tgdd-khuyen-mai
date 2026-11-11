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
    if (r.kind === 'pin') {
      fail(`${model}: gia ghim tu dot cu khong duoc dung trong du lieu hien tai`);
    }

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

  // scans.js CO Y chi giu dot quet thu Hai va thu Sau (alerts.KEEP_WEEKDAYS = {0, 4}) - day la
  // quy tac nguoi dung da train, write_scans_js() bo qua moi ngay khac. Nen KHONG duoc doi
  // scans.js phai co dot cua hom nay vao mot ngay khong phai T2/T6.
  //
  // Chot nay viet sai ngay 09-11-2026 (thu Hai, tinh co la ngay duoc giu, nen no PASS va toi
  // khong thay). Sang 10-11 (thu Ba) no chan ca 3 luot quet tu dong lien tiep - he thong dung
  // hoan toan. Dung lop loi "chot mau thuan voi chinh quy tac da train".
  const d0 = new Date(`${scanFileName.slice(5, 15)}T00:00:00Z`);
  const KEEP_WEEKDAYS = [1, 5];   // getUTCDay(): 1 = thu Hai, 5 = thu Sau
  const isKeepDay = KEEP_WEEKDAYS.includes(d0.getUTCDay());

  const todayEntry = byDate.get(scanData.date);
  if (!todayEntry && isKeepDay) {
    fail(
      `data/scans.js thieu dot quet "${scanData.date}" (latest.js co dot moi ma scans.js bo sot). ` +
      `Hom nay la ngay duoc giu theo KEEP_WEEKDAYS nen scans.js BAT BUOC phai co dot nay.`
    );
  } else if (!todayEntry) {
    console.log(
      `[4] scans.js khong co dot "${scanData.date}" - dung quy tac: chi giu thu Hai va thu Sau ` +
      `(alerts.KEEP_WEEKDAYS).`
    );
  } else if ((todayEntry.rows || []).length !== rows.length) {
    fail(
      `data/scans.js dot "${scanData.date}" co ${(todayEntry.rows || []).length} dong, ` +
      `file scan goc co ${rows.length} dong`
    );
  }

  // write_scans_js() co chu y giu lai `scansJsRetention` dot gan nhat (scans[-30:]),
  // nen dot cu hon bi rot ra KHONG phai loi dong bo. Thu phai kiem la: trong cua so
  // duoc giu lai, khong duoc thung mot dot nao.
  // write_scans_js() chi giu cac dot quet Thu Hai va Thu Sau theo user training (alerts.KEEP_WEEKDAYS = {0, 4}).
  // Trong JS: 1 = Thu Hai, 5 = Thu Sau.
  const onDisk = fs.readdirSync(SCANS_DIR)
    .filter((f) => /^scan_\d{4}-\d{2}-\d{2}\.json$/.test(f))
    .sort()
    .filter((f) => {
      const [y, m, d] = f.slice(5, 15).split('-').map(Number);
      const day = new Date(y, m - 1, d).getDay();
      return day === 1 || day === 5;
    })
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
// Truoc day muc nay chi so truong `date` va chi CANH BAO. Ngay 09-11-2026 lo ra la
// khong du: ban sao co CUNG `date` nhung khac NOI DUNG tung dong (ban chinh da sua
// iPhone 18 Pro thanh active, ban sao van "chua_mo_ban"), nen canh bao khong he keu.
// He thong co BON nguon chu khong phai ba: scan json, latest.js, scans.js, va ban sao
// long nhau - ma ban sao thi bi `git add "promotion tgdd"` dua vao moi dot commit.
if (CFG.nestedCopyPath) {
  const nested = path.join(ROOT, CFG.nestedCopyPath, 'data', 'latest.js');
  if (!fs.existsSync(nested)) {
    console.log(`[5] Ban sao long nhau: khong co "${CFG.nestedCopyPath}/data/latest.js", bo qua.`);
  } else {
    const res = parseWindowVar(nested, 'LATEST');
    if (res.err || !res.value) {
      fail(`Ban sao long nhau "${CFG.nestedCopyPath}/data/latest.js" khong doc duoc: ${res.err}`);
    } else if (!latestObj) {
      // latest.js ban chinh da bao loi o muc truoc roi.
    } else {
      const nestedObj = res.value;
      const diffs = [];
      if (nestedObj.date !== latestObj.date) {
        diffs.push(`date: "${nestedObj.date}" vs "${latestObj.date}"`);
      }
      const nestedByModel = new Map((nestedObj.rows || []).map((r) => [r.model, r]));
      for (const r of latestObj.rows || []) {
        const c = nestedByModel.get(r.model);
        if (!c) { diffs.push(`${r.model}: thieu han trong ban sao`); continue; }
        for (const k of ['status', 'rrp', 'red', 'pmh', 'online', 'total_online', 'choice']) {
          const a = r[k] ?? null, b = c[k] ?? null;
          if (a !== b) diffs.push(`${r.model}.${k}: ban chinh ${a} vs ban sao ${b}`);
        }
        nestedByModel.delete(r.model);
      }
      for (const m of nestedByModel.keys()) diffs.push(`${m}: chi co trong ban sao`);

      if (diffs.length) {
        fail(
          `BAN SAO LECH: "${CFG.nestedCopyPath}/data/latest.js" khong khop ban chinh ` +
          `(${diffs.length} diem lech). Ban sao nay van duoc \`git add "${CFG.nestedCopyPath}"\` ` +
          `moi dot nen no duoc commit va phuc vu web voi so lieu khac. Chay lai ` +
          `scraper/bundle.py de dong bo, hoac bo thu muc do khoi buoc git add. ` +
          `Vai diem lech dau: ${diffs.slice(0, 5).join(' | ')}`
        );
      } else {
        console.log(`[5] Ban sao long nhau: khop ban chinh (${(latestObj.rows || []).length} dong)`);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// 6. So sanh GIUA CAC DOT QUET - chan loi am tham ghi de du lieu da dung
//
// Day la lop loi ma moi check trong mot dot quet deu mu: khi PDP la landing page,
// scraper doc khong ra gia do va tra ve red = rrp -> diff = 0 -> PMH = 0. Moi truong
// con lai (rule, kind, online) van nhat quan voi nhau nen khong co gi bao dong.
// Dung loi da xay ra voi OPPO A7 Pro ngay 09-11-2026.
//
// Chot nay mo ta LOP LOI, khong dich danh model nao - vi lan truoc kien thuc bi ghi
// lai thanh ban va cho rieng A08 / A18 / A7 Pro, nen khi lop do roi vao model khac
// thi khong con gi chan.
// ---------------------------------------------------------------------------
if (scanData && scanFileName) {
  const allScans = fs.readdirSync(SCANS_DIR)
    .filter((f) => /^scan_\d{4}-\d{2}-\d{2}\.json$/.test(f))
    .sort();
  const pos = allScans.indexOf(scanFileName);
  const prevFile = pos > 0 ? allScans[pos - 1] : null;

  if (!prevFile) {
    console.log('[6] Hoi quy giua cac dot: khong co dot truoc de so sanh, bo qua.');
  } else {
    let prevScan = null;
    try {
      prevScan = JSON.parse(fs.readFileSync(path.join(SCANS_DIR, prevFile), 'utf8').replace(/^﻿/, ''));
    } catch (e) {
      fail(`Khong doc duoc dot quet truoc (${prevFile}) de so sanh hoi quy: ${e.message}`);
    }

    // Danh sach xac nhan "PMH = 0 la that". Het hieu luc khi rrp doi.
    let acks = [];
    const ackPath = path.join(ROOT, 'tests', 'known-zero-pmh.json');
    if (fs.existsSync(ackPath)) {
      try {
        acks = JSON.parse(fs.readFileSync(ackPath, 'utf8')).entries || [];
      } catch (e) {
        fail(`tests/known-zero-pmh.json khong parse duoc: ${e.message}`);
      }
    }
    const todayIso = scanFileName.slice(5, 15);
    const isAcked = (r) => acks.some((a) =>
      a.model === r.model && String(a.since) <= todayIso && Number(a.rrp) === Number(r.rrp));

    if (prevScan) {
      const prevByModel = new Map((prevScan.rows || []).map((r) => [r.model, r]));
      const flatRegressions = [];   // red == rrp  -> chu ky loi landing page
      const softZeros = [];         // red < rrp   -> co the la flash sale khong co qua (2.1.2)

      for (const r of rows) {
        if (r.status !== 'active') continue;
        const p = prevByModel.get(r.model);
        if (!p || p.status !== 'active') continue;          // model moi / truoc do khong doc duoc
        if (!((p.pmh || 0) > 0 && (r.pmh || 0) === 0)) continue;
        (r.red === r.rrp ? flatRegressions : softZeros).push({ r, p });
      }

      // (a) Systemic: nhieu model cung tut phang mot luc = loi code, khong phai thi truong.
      //     Khong the dung file xac nhan de cho qua.
      if (flatRegressions.length > CFG.maxFlatZeroDrops) {
        fail(
          `HOI QUY DIEN RONG: ${flatRegressions.length} model cung tut PMH ve 0 voi red == rrp trong ` +
          `mot dot (nguong ${CFG.maxFlatZeroDrops}). Day la dau hieu loi code/cao, khong phai thi truong. ` +
          `Khong duoc dung tests/known-zero-pmh.json de bo qua truong hop nay.`
        );
      }

      // (b) Tung model: chan tru khi da doi soat va ghi vao file xac nhan.
      for (const { r, p } of flatRegressions) {
        if (isAcked(r)) continue;
        fail(
          `HOI QUY: ${r.model} co PMH ${p.pmh.toLocaleString('vi-VN')} o dot ${prevScan.date}, ` +
          `nay PMH = 0 va red == rrp == ${r.rrp.toLocaleString('vi-VN')} (khong con chenh lech gia). ` +
          `Day la chu ky cua loi "PDP landing page khong render gia do". Doi soat card #o=3 ` +
          `(CONSTRAINTS 2.6); neu dung la het khuyen mai, them muc vao tests/known-zero-pmh.json ` +
          `kem bang chung.`
        );
      }

      // (c) PMH ve 0 nhung van con chenh lech gia: dung luat 2.1.2 voi flash sale khong co
      //     muc "Chon 1 trong". Bao de nhin, khong chan.
      for (const { r, p } of softZeros) {
        warn(
          `${r.model}: PMH ${p.pmh.toLocaleString('vi-VN')} -> 0 (${r.kind}/${r.rule}), ` +
          `nhung van con chenh lech ${(r.rrp - r.red).toLocaleString('vi-VN')} (red < rrp). ` +
          `Dung luat 2.1.2 neu la flash sale khong co muc "Chon 1 trong" - kiem lai neu thay la.`
        );
      }

      console.log(
        `[6] Hoi quy giua cac dot (${prevFile} -> ${scanFileName}): ` +
        `${flatRegressions.length} tut phang (red == rrp), ${softZeros.length} tut nhung con chenh lech`
      );
    }
  }
}

// ---------------------------------------------------------------------------
// 7. TRANG THAI DONG BANG
//
// Lop loi: mot dong KHONG active bi ghim cung mot gia tri qua nhieu dot lien tiep.
// Khi (status, rrp, red) y het nhau tung byte suot nhieu dot, do khong con la PHEP DO
// nua ma la HANG SO - nguyen nhan co the la ep cung trong scraper, URL chet, cache,
// hoac don gian la khong ai nhin lai.
//
// Dung loi da xay ra: iPhone 18 Pro Max 256GB / iPhone 18 Pro 256GB bi mot khoi
// `if product["model"] in (...)` ghim "chua_mo_ban" trong scan_tgdd.py, nen bao
// chua mo ban suot 24 dot lien tiep trong khi TGDD da mo ban that (PDP co gia, co
// nut "Mua ngay", "Da ban 101,8k"). Moi check trong mot dot deu mu voi lop loi nay
// vi tung dot nhin rieng le deu hop le.
//
// Chot nay mo ta LOP LOI, khong dich danh model nao.
// ---------------------------------------------------------------------------
if (scanData && scanFileName) {
  const allScans = fs.readdirSync(SCANS_DIR)
    .filter((f) => /^scan_\d{4}-\d{2}-\d{2}\.json$/.test(f))
    .sort();
  const pos = allScans.indexOf(scanFileName);

  let frozenAcks = [];
  const frozenAckPath = path.join(ROOT, 'tests', 'known-frozen-status.json');
  if (fs.existsSync(frozenAckPath)) {
    try {
      frozenAcks = JSON.parse(fs.readFileSync(frozenAckPath, 'utf8').replace(/^﻿/, '')).entries || [];
    } catch (e) {
      fail(`tests/known-frozen-status.json khong parse duoc: ${e.message}`);
    }
  }
  const todayIso2 = scanFileName.slice(5, 15);
  // Xac nhan het hieu luc khi rrp hoac status doi - vi luc do tinh huong da khac.
  const isFrozenAcked = (r) => frozenAcks.some((a) =>
    a.model === r.model && String(a.since) <= todayIso2 &&
    Number(a.rrp) === Number(r.rrp) && a.status === r.status);

  // Doc nguoc cac dot truoc; dung ngay khi gap dot dau tien khac gia tri.
  const prevCache = new Map();
  const readScan = (f) => {
    if (!prevCache.has(f)) {
      try {
        prevCache.set(f, JSON.parse(fs.readFileSync(path.join(SCANS_DIR, f), 'utf8').replace(/^﻿/, '')).rows || []);
      } catch { prevCache.set(f, null); }
    }
    return prevCache.get(f);
  };

  let frozenCount = 0;
  for (const r of rows) {
    if (r.status === 'active') continue;
    let streak = 1;
    for (let i = pos - 1; i >= 0; i--) {
      const prevRows = readScan(allScans[i]);
      if (!prevRows) break;
      const p = prevRows.find((x) => x.model === r.model);
      if (p && p.status === r.status && p.rrp === r.rrp && p.red === r.red) streak++;
      else break;
    }
    if (streak < CFG.maxFrozenScans) continue;
    frozenCount++;
    if (isFrozenAcked(r)) continue;
    fail(
      `TRANG THAI DONG BANG: ${r.model} giu nguyen status="${r.status}" voi ` +
      `rrp=${Number(r.rrp || 0).toLocaleString('vi-VN')} red=${Number(r.red || 0).toLocaleString('vi-VN')} ` +
      `suot ${streak} dot quet lien tiep (nguong ${CFG.maxFrozenScans}). Gia tri y het nhau qua nhieu dot ` +
      `la dau hieu cua HANG SO chu khong phai PHEP DO: kiem xem scan_tgdd.py co ep cung model nay khong ` +
      `(CONSTRAINTS 2.9 cam), URL con song khong, va doi soat PDP/card #o=3 (CONSTRAINTS 2.6/2.7). ` +
      `Neu dung la trang thai that, them muc vao tests/known-frozen-status.json kem bang chung.`
    );
  }
  console.log(`[7] Trang thai dong bang: ${frozenCount} dong non-active dat/vuot nguong ${CFG.maxFrozenScans} dot`);
}

// ---------------------------------------------------------------------------
// 8. BANG CHUNG FLASH SALE
//
// Lop loi: dong du lieu luu KET LUAN "co flash sale" ma khong luu BANG CHUNG. Sau do khong
// ai truy nguoc duoc ket luan ay den tu dau. Hai nguon rat khac nhau:
//   - "quota"  : trang chi tiet co khoi suat that -> khung gio flash DANG CHAY
//   - "hub"    : model co ten o /flashsale -> muc CHIEN DICH, suat co the da het
// Mot dong chi co ["hub"] la dong he thong bao flash ma trang chi tiet khong chung minh gi.
// Dung ca da gap: Find X9s 12GB/512GB ngay 09-11-2026 - bang bao "Flash Sale Online", bam
// vao trang thi khong co gi.
//
// Flash sale chay theo khung gio nen KHONG BAO GIO duoc mac dinh hay bе tu dot truoc sang:
// moi dot phai tu chung minh lai.
// ---------------------------------------------------------------------------
if (scanData && scanFileName) {
  const todayIso3 = scanFileName.slice(5, 15);
  if (todayIso3 < String(CFG.flashEvidenceFrom)) {
    console.log(`[8] Bang chung flash sale: dot ${todayIso3} truoc moc ${CFG.flashEvidenceFrom}, duoc mien.`);
  } else {
    const flashRows = rows.filter((r) => r.status === 'active' && (r.banner === true || r.rule === 'flash_chon1'));
    const noEvidence = flashRows.filter((r) => !Array.isArray(r.flash_src) || r.flash_src.length === 0);
    const hubOnly = flashRows.filter((r) => Array.isArray(r.flash_src) &&
      r.flash_src.length > 0 && r.flash_src.every((s) => s === 'hub'));

    for (const r of noEvidence) {
      fail(
        `FLASH KHONG BANG CHUNG: ${r.model} duoc danh flash sale (banner=${r.banner}, rule=${r.rule}) ` +
        `nhung khong co \`flash_src\`. Khong duoc ket luan co flash sale ma khong ghi lai bang chung ` +
        `cua chinh dot nay - flash sale chay theo khung gio, khong duoc mac dinh hay be tu dot truoc sang.`
      );
    }
    if (hubOnly.length > CFG.maxFlashHubOnly) {
      fail(
        `FLASH CHI DUA VAO HUB: ${hubOnly.length} dong chi co bang chung ["hub"] (nguong ${CFG.maxFlashHubOnly}). ` +
        `Anh chup hub /flashsale dang quyet dinh thay cho trang chi tiet tren dien rong - ` +
        `hub van liet ke ca khi suat khung gio hien tai da het.`
      );
    }
    for (const r of hubOnly) {
      warn(
        `${r.model}: bao flash sale nhung bang chung duy nhat la ten trong hub /flashsale, ` +
        `trang chi tiet khong co khoi suat nao. Bam vao trang co the khong thay flash sale.`
      );
    }
    console.log(
      `[8] Bang chung flash sale: ${flashRows.length} dong flash, ` +
      `${noEvidence.length} thieu bang chung, ${hubOnly.length} chi dua vao hub`
    );
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
