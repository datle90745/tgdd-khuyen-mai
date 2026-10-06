/**
 * Trạm trung gian cho bộ quét PMH: GitHub Actions bị thegioididong.com chặn IP,
 * nên bộ quét gọi https://<worker>/fetch?url=... và Worker tải trang giúp từ IP Cloudflare.
 *
 * Cài đặt (làm trên trang dash.cloudflare.com, không cần cài gì trên máy):
 *   Workers & Pages → Create → Worker → dán toàn bộ file này → Deploy
 *   Settings → Variables and Secrets → thêm Secret tên PROXY_TOKEN (chuỗi ngẫu nhiên bạn tự đặt)
 * Chỉ cho phép tải trang của thegioididong.com, và bắt buộc có đúng token,
 * để người lạ không dùng ké Worker của bạn.
 */
const ALLOWED_HOSTS = new Set(["www.thegioididong.com", "thegioididong.com"]);

const BROWSER_HEADERS = {
  "User-Agent":
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
    "(KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36",
  "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
  "Accept-Language": "vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7",
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname !== "/fetch") return new Response("OK\n");

    const token = request.headers.get("X-Proxy-Token") || "";
    if (!env.PROXY_TOKEN || token !== env.PROXY_TOKEN) {
      return new Response("Unauthorized\n", { status: 401 });
    }
    let target;
    try {
      target = new URL(url.searchParams.get("url") || "");
    } catch {
      return new Response("Malformed url param\n", { status: 400 });
    }
    if (target.protocol !== "https:" || !ALLOWED_HOSTS.has(target.hostname)) {
      return new Response(`Host not allowed: ${target.hostname}\n`, { status: 403 });
    }
    const upstream = await fetch(target.toString(), { headers: BROWSER_HEADERS, redirect: "follow" });
    return new Response(await upstream.arrayBuffer(), {
      status: upstream.status,
      headers: { "Content-Type": upstream.headers.get("Content-Type") || "text/html; charset=utf-8" },
    });
  },
};
