# Web theo dõi khuyến mãi TGDĐ

Web tĩnh, chỉ gồm 2 file, không cần server hay cài đặt gì:

| File | Nội dung |
|---|---|
| `index.html` | Giao diện (5 tab: Tra cứu mới nhất, Lịch sử theo đợt quét, Lịch sử tăng giá, Quy tắc tính PMH, Nhập đợt quét mới) |
| `data/data.js` | Toàn bộ số liệu: `BASE` (86 SKU × các đợt quét), `RRP_NOTES`, `RISE_RAW`, `SCANS` |

## Xem trên máy
Bấm đúp `index.html` là chạy được, vì dữ liệu nạp bằng thẻ `<script>`.

## Đưa lên mạng (chọn 1 cách)

**Netlify Drop (nhanh nhất, miễn phí):** vào https://app.netlify.com/drop rồi kéo cả
thư mục `site` vào. Bạn sẽ nhận được một link dạng `https://<ten>.netlify.app`.

**GitHub Pages:** tạo repo, đưa nội dung thư mục `site` lên nhánh `main`, rồi vào
Settings → Pages → Deploy from a branch → `main` / `(root)`.
Link sẽ có dạng `https://<tai-khoan>.github.io/<ten-repo>/`.
Lưu ý: Pages công khai với mọi người có link.

## Cập nhật số liệu
- **Đợt quét mới cho mọi người cùng thấy:** mở `data/data.js`, thêm vào cuối mảng `SCANS`:
  ```js
  window.SCANS = [
    { "date": "09-Oct", "rows": [ { "model": "iPhone 17 256GB", "rrp": 28990000, "pmh": 2000000 } ] }
  ];
  ```
  `model` phải trùng tên trong `BASE`. Nếu `rrp` khác giá đen hiện tại, web tự gắn cờ "RRP".
  Sau đó đưa file lên lại (kéo thả lại Netlify, hoặc push GitHub).
- **Chỉ xem riêng trên máy mình:** dùng tab "Nhập đợt quét mới" (lưu trong trình duyệt).
- **Lịch đổi giá đen:** thêm dòng vào `RISE_RAW`: `["T10","OPPO","A6x 4GB/128GB",7090000,7490000,"2026-10-09",5.6]`.
