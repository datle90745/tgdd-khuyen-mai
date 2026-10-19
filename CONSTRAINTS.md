# CONSTRAINTS: Ràng Buộc Kỹ Thuật & Nghiệp Vụ Dự Án TGDD-KHUYEN-MAI

> Tài liệu chuẩn hóa theo phương pháp **Constraint-Driven Development** (Addy Osmani - `agent-skills`).
> Quyết định một lần, thực thi vĩnh viễn trên toàn bộ hệ thống. Mọi AI Agent hay lập trình viên không được tự ý hạ thấp tiêu chuẩn hoặc sửa đổi trái ngược quy tắc.

---

## 1. Quality Floor (Bắt buộc mọi thời điểm)

- **Không đoán mò ("No Vibe Coding")**: Mọi kết luận về bug, rule hoặc data phải có bằng chứng cụ thể (DOM thực tế, test runner, log chi tiết).
- **Tests are proof ("Seems right" is NOT done)**: Trước khi tuyên bố hoàn thành hoặc commit, bắt buộc phải chạy bộ kiểm tra tự động `powershell -ExecutionPolicy Bypass -File tests/verify-system.ps1` và đạt 100% PASS.
- **Không suy diễn bỏ sót**: Không được tự ý xóa bỏ quy tắc hoặc biến đã định nghĩa mà không có đối chiếu Adversarial (Doubt-Driven Review).

---

## 2. Domain Invariants (Quy tắc Nghiệp vụ Bất biến)

### 2.1. Quy tắc Flash Sale & Banner Cam (Lưu trữ vĩnh viễn)
1. Cụm từ **"Ưu đãi ONLINE"** và **"Kết thúc sau"** (cùng "Online Giá Rẻ Quá", "Còn x/y suất") **VẪN LÀ FLASH SALE** khi và chỉ khi:
   - **BẮT BUỘC CÓ BANNER CAM** (chứa class / style cam: `bg-fs-detail`, `bg-fs`, `box_saving`, `banner-fs`, `bg-orange`, `#ff6b00`, `#ea580c`...).
2. **Xử lý PMH khi có Banner Cam:**
   - `PMH` = Khoản "Giảm giá X" trong mục "Chọn 1 trong" (`rule = flash_chon1`).
   - Nếu không có mục "Chọn 1 trong" -> `PMH = 0` (tuyệt đối không lấy chênh lệch giá đen trừ giá đỏ của flash sale làm PMH).
3. **Xử lý PMH khi không có Banner Cam (không phải Flash Sale):**
   - `PMH` = Số lớn hơn giữa (Giá đen − Giá đỏ) và khoản "Chọn 1 trong" (`rule = den_tru_do` hoặc `chon1`).

### 2.2. Danh mục 95 SKU Master List
- Danh sách sản phẩm cào `scraper/products.csv` phải duy trì đủ 95 SKU.
- Không được lược bỏ sản phẩm dù có trạng thái `ngung_kd` hay `chua_mo_ban`.

### 2.3. Quy tắc Xuất file Excel (Đúng chuẩn 3 Sheet)
- Nút **Xuất Excel** chính (`id="xlsx"`) tạo Workbook gồm **ĐÚNG 3 SHEET**:
  - **Sheet 1 (`KM_Chi_Tiet_TGDD`)**: Khuyến mãi chi tiết TGDĐ đợt mới nhất.
  - **Sheet 2 (`Lich_Su_Theo_Dot_Quet`)**: Lịch sử giá & PMH qua các đợt quét (chuẩn 95 SKU Master List).
  - **Sheet 3 (`Ma_Tran_4_San`)**: Ma trận đối đầu so sánh giá 4 sàn lớn (TGDĐ, CellphoneS, FPT Shop, Viettel Store).
- Nút **Xuất Excel tab này (`id="mk-xlsx"`)** tại tab Toàn thị trường tạo Workbook gồm **ĐÚNG 3 SHEET**:
  - **Sheet 1 (`Ma_Tran_Doi_Dau`)**: Ma trận đối đầu 4 sàn.
  - **Sheet 2 (`Toan_Bo_Danh_Sach`)**: Danh sách phẳng toàn bộ sản phẩm 4 sàn.
  - **Sheet 3 (`Lich_Su_Theo_Dot_Quet`)**: Lịch sử đợt quét 95 SKU Master List.
- Nút **Xuất Excel tab này (`id="history-xlsx"`)** tại tab Lịch sử: Xuất riêng Sheet `Lich_Su_Theo_Dot_Quet`.

### 2.4. Đồng bộ hóa dữ liệu (Three-Way Sync)
- Khi có đợt quét mới:
  - `data/scans/scan_YYYY-MM-DD.json`: Lưu bản ghi chi tiết gốc.
  - `data/latest.js`: `window.LATEST` chứa kết quả đợt quét mới nhất.
  - `data/scans.js`: `window.SCANS` chứa toàn bộ các đợt quét lịch sử (bao gồm cả đợt quét hôm nay khi đã hoàn thành).
  - Tránh tuyệt đối việc `latest.js` có đợt mới mà `scans.js` bị bỏ sót.

### 2.5. Tính Độc Lập Biến Thể Cấu Hình (RAM/ROM) - Tuyệt Đối Không Gộp (Merge)
- **Mọi biến thể RAM/ROM trên TGDĐ là một sản phẩm/SKU hoàn toàn riêng biệt**:
  - Ví dụ: `OPPO A7 Pro 5G 6GB/256GB` và `OPPO A7 Pro 5G 8GB/128GB` là 2 sản phẩm độc lập có giá bán, khuyến mãi và đường link riêng.
- **Cấm tuyệt đối việc tự ý can thiệp hoặc thêm quy tắc đồng bộ ép mã trong `canonKey()`**:
  - Không bao giờ được map/ép phiên bản cấu hình này sang phiên bản cấu hình khác (ví dụ ép `6GB` về `8GB/256GB`).
  - `canonKey()` chỉ chuẩn hóa format chuỗi (bỏ khoảng trắng, chuẩn hóa ký hiệu RAM/ROM dạng `XgbYgb`, loại bỏ ký tự đặc biệt), không được thay đổi giá trị dung lượng thực tế.
- Nếu danh mục Master List hoặc file cấu hình bị sai tên biến thể, phải sửa đúng gốc rễ tên SKU tại `data/data.js`, `products.csv`, `latest.js`, `scans.js` thay vì dùng mã giả lập / hack trong code xử lý chuỗi.

---

## 3. Bảng Kiểm Tra & Công Cụ Đo Lường

| Chiều kiểm tra | Quy tắc / Tiêu chuẩn | Lệnh kiểm tra | Thời điểm chạy |
| :--- | :--- | :--- | :--- |
| **Scraper Logic** | Banner Cam + Flash keywords + PMH rules | `powershell -ExecutionPolicy Bypass -File tests/verify-system.ps1` | Trước mỗi commit |
| **Data Integrity** | `latest.js`, `scans.js`, `products.csv` đồng bộ | `powershell -ExecutionPolicy Bypass -File tests/verify-system.ps1` | Trước mỗi commit |
| **UI & Excel Export** | Sheet 1 & Sheet 2 hiện diện trong tất cả HTML | `powershell -ExecutionPolicy Bypass -File tests/verify-system.ps1` | Trước mỗi commit |
| **Offline Standalone** | Đồng bộ giữa `index.html` và standalone files | `bundle-standalone` / Test verification | Khi sửa giao diện |
