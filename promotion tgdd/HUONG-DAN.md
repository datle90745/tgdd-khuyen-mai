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

## Các tính năng mới nâng cấp

1. **Ma trận đối đầu 4 sàn (Head-to-Head Comparison):**
   - Nằm trong tab **Toàn thị trường** -> Bấm nút **"Ma trận đối đầu 4 sàn (86 SKU)"**.
   - So sánh trực tiếp giá bán thực tế giữa: **TGDĐ | CellphoneS | FPT Shop | Viettel Store**.
   - Tự động gắn nhãn sàn có giá tốt nhất (👑 Best price) và tính biên độ chênh lệch giá (Spread).
2. **Cảnh báo Khuyến mãi ảo & Biến động bất thường:**
   - Tự động phát hiện các SKU vừa tăng giá đen (RRP) nhưng lại treo biển giảm giá/flash sale mà giá bán thực tế không hề rẻ hơn giá niêm yết cũ.
   - Thống kê tỷ lệ sàn nắm giữ nhiều deal giá rẻ nhất trên thị trường.
3. **So sánh trực tiếp 2 máy (Tab "So sánh 2 máy"):**
   - Chọn 2 model bất kỳ để đối đầu Side-by-Side: thông số giá, mức chiết khấu, giá online thực tế.
   - Vẽ biểu đồ kép SVG so sánh lịch sử PMH qua các đợt quét.
4. **Tìm kiếm thông minh (Fuzzy Search & Viết tắt):**
   - Hỗ trợ gõ tắt trong tất cả các ô tìm kiếm: `ip 17 pm` (iPhone 17 Pro Max), `s26 u` (S26 Ultra), `a57` (Galaxy A57), `reno 16`, `note 17`, `fold 8`...
5. **Xuất báo cáo Excel Executive 3 Sheet:**
   - Nút **"Xuất Excel"** ở góc phải trên sẽ tải về file Excel chuyên nghiệp gồm:
     - Sheet 1: `KM_86_SKU_TGDD` (Khuyến mãi TGDĐ)
     - Sheet 2: `Ma_Tran_4_San` (Đối đầu 4 nhà bán lẻ)
     - Sheet 3: `Lich_Su_Tang_Gia` (Lịch sử tăng giá niêm yết)
6. **Bộ cào FPT Shop tự động chuẩn xác (Live-only Anti-bot):**
   - Tự động thử HTTP NextJS parser với browser headers & retry (nhanh 1-2s, đi qua Cloudflare proxy nếu cấu hình trên GitHub Actions).
   - Tự động thử Playwright Stealth với script gỡ bỏ cờ tự động hóa `navigator.webdriver`.
   - **Nguyên tắc dữ liệu sạch:** Tuyệt đối KHÔNG lấy số cũ từ các ngày trước để tránh gây hiểu lầm về giá thực tế; nếu cả hai cách cào live đều bị chặn, bot sẽ báo lỗi rõ ràng và để trống ô giá đợt đó.
