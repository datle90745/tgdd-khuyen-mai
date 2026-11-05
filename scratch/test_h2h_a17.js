const fs = require('fs');

// Load data.js
const dataJs = fs.readFileSync('data/data.js', 'utf8');
eval(dataJs);

// Load market.js
const marketJs = fs.readFileSync('data/market.js', 'utf8');
eval(marketJs);

// Load latest.js
const latestJs = fs.readFileSync('data/latest.js', 'utf8');
eval(latestJs);

// Load links.js
const linksJs = fs.readFileSync('data/links.js', 'utf8');
eval(linksJs);

// Let's copy mkKey and buildH2HData from index.html
const indexHtml = fs.readFileSync('index.html', 'utf8');

// Extract mkKey
const mkKeyMatch = indexHtml.match(/const mkKey\s*=\s*s\s*=>\s*([\s\S]*?\.replace\(\/\[\^a-z0-9\]\/g,""\);)/);
console.log("mkKeyMatch found:", !!mkKeyMatch);

const mkKey = s => String(s||"").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g,"").replace(/đ/g,"d").replace(/(\d+)\+(\d+)/g, "$1gb$2").replace(/(\d+)\/(\d+)g\b/g, "$1gb$2gb").replace(/\+/g,"plus")
  .replace(/\b(dien thoai|samsung|galaxy|xiaomi|oppo|vivo|realme|apple|chinh hang|4g|lte|nfc)\b/g," ")
  .replace(/\b(titan|xam|den|trang|xanh|vang|bac|hong|tim|gold|silver|black|white|blue|green|purple|pink|grey|gray)\b/g," ")
  .replace(/[^a-z0-9]/g,"");

console.log("mkKey('A17 8GB/128GB'):", mkKey('A17 8GB/128GB'));
console.log("mkKey('Samsung Galaxy A17 8GB 128GB'):", mkKey('Samsung Galaxy A17 8GB 128GB'));
console.log("mkKey('Samsung Galaxy A17 LTE 8GB 128GB'):", mkKey('Samsung Galaxy A17 LTE 8GB 128GB'));

const lastScan = window.MARKET.scans[window.MARKET.scans.length - 1];
console.log("Last scan date:", lastScan.date, lastScan.at);

const curRows = lastScan.rows;
const mkMap = new Map();
curRows.forEach(x => {
  const k = x.r + "|" + (x.b||"").toLowerCase() + "|" + mkKey(x.n);
  if (!mkMap.has(k) || (x.p && (!mkMap.get(k).p || x.p < mkMap.get(k).p))) {
    mkMap.set(k, x);
  }
});

const targetModel = "A17 8GB/128GB";
const k = "samsung|" + mkKey(targetModel);
console.log("Looking up target key:", k);
console.log("TGDĐ:", mkMap.get("TGDĐ|" + k));
console.log("CellphoneS:", mkMap.get("CellphoneS|" + k));
console.log("FPT Shop:", mkMap.get("FPT Shop|" + k));
console.log("Viettel Store:", mkMap.get("Viettel Store|" + k));

// Also let's check all entries in mkMap for CellphoneS with a17
console.log("\nAll CellphoneS rows matching a17 in curRows:");
curRows.filter(x => x.r === "CellphoneS" && x.n.toLowerCase().includes("a17")).forEach(x => {
  console.log("  ", x.n, "-> mkKey:", mkKey(x.n), "-> p:", x.p);
});

console.log("\nAll FPT Shop rows matching a17 in curRows:");
curRows.filter(x => x.r === "FPT Shop" && x.n.toLowerCase().includes("a17")).forEach(x => {
  console.log("  ", x.n, "-> mkKey:", mkKey(x.n), "-> p:", x.p);
});
