// Tram trung gian cho bo quet (GitHub Actions bi cac trang ban le chan IP).
// Chi cho phep cac trang ban le duoi day va bat buoc co dung X-Proxy-Token (Secret PROXY_TOKEN).
const ALLOWED = new Set(["www.thegioididong.com", "thegioididong.com", "api.cellphones.com.vn", "cellphones.com.vn", "papi.fptshop.com.vn", "fptshop.com.vn", "viettelstore.vn", "www.viettelstore.vn"]);
const PASS = ["content-type", "x-requested-with", "order-channel", "referer"];
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36";
export default {
async fetch(request, env) {
const url = new URL(request.url);
if (url.pathname !== "/fetch") return new Response("OK\n");
const token = request.headers.get("X-Proxy-Token") || "";
if (!env.PROXY_TOKEN || token !== env.PROXY_TOKEN) return new Response("Unauthorized\n", {status: 401});
let target;
try { target = new URL(url.searchParams.get("url") || ""); } catch { return new Response("Malformed url\n", {status: 400}); }
if (target.protocol !== "https:" || !ALLOWED.has(target.hostname)) return new Response("Host not allowed\n", {status: 403});
const headers = {"User-Agent": UA, "Accept": "text/html,application/json,*/*;q=0.8", "Accept-Language": "vi-VN,vi;q=0.9,en-US;q=0.8"};
for (const h of PASS) { const v = request.headers.get(h); if (v) headers[h] = v; }
const init = {method: request.method === "POST" ? "POST" : "GET", headers, redirect: "follow"};
if (init.method === "POST") init.body = await request.arrayBuffer();
const up = await fetch(target.toString(), init);
return new Response(await up.arrayBuffer(), {status: up.status, headers: {"Content-Type": up.headers.get("Content-Type") || "text/html; charset=utf-8"}});
}
};
