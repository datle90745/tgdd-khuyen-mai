# CONSTRAINTS: Ràng Buộc Kỹ Thuật & Nghiệp Vụ Dự Án TGDD-KHUYEN-MAI

> Tài liệu chuẩn hóa theo phương pháp **Constraint-Driven Development** (Addy Osmani - `agent-skills`).
> Quyết định một lần, thực thi vĩnh viễn trên toàn bộ hệ thống. Mọi AI Agent hay lập trình viên không được tự ý hạ thấp tiêu chuẩn hoặc sửa đổi trái ngược quy tắc.

---

## 1. Quality Floor (Bắt buộc mọi thời điểm)

- **Không đoán mò ("No Vibe Coding")**: Mọi kết luận về bug, rule hoặc data phải có bằng chứng cụ thể (DOM thực tế, test runner, log chi tiết).
- **Tests are proof ("Seems right" is NOT done)**: Trước khi tuyên bố hoàn thành hoặc commit, bắt buộc phải chạy bộ kiểm tra tự động `powershell -ExecutionPolicy Bypass -File tests/verify-system.ps1` và đạt 100% PASS.
- **Không suy diễn bỏ sót**: Không được tự ý xóa bỏ quy tắc hoặc biến đã định nghĩa mà không có đối chiếu Adversarial (Doubt-Driven Review).
- **Ràng buộc chỉ đến từ tài liệu này, không suy ra từ code**: Thấy một hàm luôn xuất ra giá trị X
  thì đó là *cài đặt hiện tại*, **không phải** đặc tả. Tự nâng nó thành ràng buộc rồi phán dữ liệu
  đúng là sai chính là "vibe coding" ở dạng nguy hiểm nhất, vì nó mang hình hài của sự nghiêm ngặt.
  Chưa có trong `CONSTRAINTS.md` thì hỏi người dùng, không tự quyết.
- **Cổng kiểm tra phải soi dữ liệu HÔM NAY**: Test neo vào ngày và giá cố định chỉ chứng minh
  "lỗi cũ chưa tái phát", **không** chứng minh dữ liệu mới đúng. Mọi đợt quét mới bắt buộc phải có
  ít nhất một test động chạm vào nó. Suite từng báo 81/81 PASS suốt nhiều tuần trong khi không một
  test nào nhìn vào đợt quét trong ngày.
- **Không bịa số để dữ liệu trông hợp lệ**: Thiếu giá thì hạ trạng thái xuống `no_price` cho lộ ra,
  tuyệt đối không suy ra / thay thế / làm tròn trong im lặng. Mọi lần hiệu chỉnh giá trị phải in log.

---

## 2. Domain Invariants (Quy tắc Nghiệp vụ Bất biến)

### 2.1. Quy tắc Flash Sale & Banner Cam (Lưu trữ vĩnh viễn)

**Định nghĩa Flash Sale — phải thỏa mãn CẢ HAI, thiếu một là không phải:**
1. **Có BANNER CAM**: class / style cam (`bg-fs-detail`, `bg-fs`, `box_saving`, `banner-fs`, `bg-orange`, `#ff6b00`, `#ea580c`...), **và**
2. **Có TỪ KHOÁ FLASH**: "Ưu đãi ONLINE", "Kết thúc sau", "Online Giá Rẻ Quá", "Còn x/y suất".

> Cài đặt tương ứng trong `scraper/scan_tgdd.py`: `banner = bool(has_banner_cam and has_flash_kw)`.
> Chỉ có banner cam mà không có từ khoá flash thì **không** phải flash sale, và ngược lại.

**Xử lý PMH — ba nhánh, không chồng lấn:**

| Điều kiện | `rule` | `PMH` |
| :--- | :--- | :--- |
| Là Flash Sale (banner cam **và** từ khoá flash) | `flash_chon1` | = khoản "Giảm giá X" trong "Chọn 1 trong"; không có mục đó thì `PMH = 0` |
| Không Flash Sale, và (Giá đen − Giá đỏ) ≥ "Chọn 1 trong" | `den_tru_do` | = Giá đen − Giá đỏ |
| Không Flash Sale, và (Giá đen − Giá đỏ) < "Chọn 1 trong" | `chon1` | = khoản "Chọn 1 trong" |

- Với Flash Sale, **tuyệt đối không** lấy chênh lệch giá đen trừ giá đỏ làm PMH.
- Dòng `status != "active"` thì `PMH = null`, không phải `0`.

**Trường `kind` KHÔNG phải ràng buộc.** Nó là **nguồn dữ liệu**, không phải quy tắc PMH:

| Giá trị | Ý nghĩa |
| :--- | :--- |
| `banner` / `thuong` | bóc từ trang chi tiết (PDP) |
| `brand_tab` | bóc từ card danh mục `#o=3` — chính là Ground Truth mà mục 2.6 công nhận |
| `moi` / `moi-banner` | do `enforce_domain_invariants()` ghi đè lên |

> Không được suy ra ràng buộc cho `kind` rồi coi dữ liệu đúng là sai. Thứ phải kiểm là quan hệ
> banner cam ⇄ choice ⇄ PMH, và nó nằm ở `rule` + `pmh`.

### 2.2. HAI danh mục tách biệt — tuyệt đối không ép bằng nhau

Hệ thống **cố ý** có hai danh sách khác nhau. Nhầm lẫn giữa chúng là nguồn lỗi đã xảy ra nhiều lần.

| | File | Số lượng | Dùng cho |
| :--- | :--- | :---: | :--- |
| **Danh sách CÀO** | `scraper/products.csv` | `crawlSkuCount` | Scraper quét; quyết định số dòng của `data/scans/*.json`, `data/latest.js`, `data/scans.js`. Web hiển thị "Theo dõi khuyến mãi (N SKU)". |
| **Master List BÁO CÁO** | `data/data.js` (`window.BASE.rows` + `window.MASTER_ORDER`) | `masterListCount` | Bảng tracking đã **khoá**: thứ tự dòng, sheet Excel `Lich_Su_Theo_Dot_Quet`, ma trận đối đầu 4 sàn. Web hiển thị "Khoá N SKU Master List". |

- **Con số thực tế nằm ở `tests/gate-config.json`**, không viết cứng ở bất kỳ đâu khác.
  Trước đây cùng một con số bị viết rải rác 5 nơi (85 / 86 / 94 / 95 / 106) nên mọi check đều
  dùng `>=` và mất SKU vẫn PASS.
- Quan hệ giữa hai danh sách là **phủ hết MỘT CHIỀU**: mọi model trong `data.js` phải có trong
  `products.csv`. Chiều ngược lại — cào nhiều hơn báo cáo — là **bình thường**.
- Master List báo cáo đã khoá: **chỉ thêm / bớt khi người dùng yêu cầu**, và phải sửa
  `masterListCount` cùng lúc.
- Không được lược bỏ sản phẩm dù có trạng thái `ngung_kd` hay `chua_mo_ban`.

### 2.3. Quy tắc Xuất file Excel (Đúng chuẩn 3 Sheet)
- Nút **Xuất Excel** chính (`id="xlsx"`) tạo Workbook gồm **ĐÚNG 3 SHEET**:
  - **Sheet 1 (`KM_Chi_Tiet_TGDD`)**: Khuyến mãi chi tiết TGDĐ đợt mới nhất.
  - **Sheet 2 (`Lich_Su_Theo_Dot_Quet`)**: Lịch sử giá & PMH qua các đợt quét (khoá theo **Master List BÁO CÁO** ở mục 2.2, không phải danh sách cào).
  - **Sheet 3 (`Ma_Tran_4_San`)**: Ma trận đối đầu so sánh giá 4 sàn lớn (TGDĐ, CellphoneS, FPT Shop, Viettel Store).
- Nút **Xuất Excel tab này (`id="mk-xlsx"`)** tại tab Toàn thị trường tạo Workbook gồm **ĐÚNG 3 SHEET**:
  - **Sheet 1 (`Ma_Tran_Doi_Dau`)**: Ma trận đối đầu 4 sàn.
  - **Sheet 2 (`Toan_Bo_Danh_Sach`)**: Danh sách phẳng toàn bộ sản phẩm 4 sàn.
  - **Sheet 3 (`Lich_Su_Theo_Dot_Quet`)**: Lịch sử đợt quét, khoá theo **Master List BÁO CÁO** (mục 2.2).
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

### 2.6. Quy Trình Fast-Check Hằng Ngày Qua Trang "Mới Ra Mắt" MWG (`#o=3`)
- **Đường dẫn chuẩn tham chiếu (Ground Truth Reference):** [https://www.thegioididong.com/dtdd#o=3&pi=0](https://www.thegioididong.com/dtdd#o=3&pi=0) (hoặc API `Category/FilterProductBox?c=42&o=3`).
- **Bản chất nghiệp vụ:**
  - Trang chi tiết (PDP) của các sản phẩm chiến dịch (như OPPO A7 Pro, vivo V80 Lite, Galaxy A18, Redmi A7 Pro,...) thường là Landing Page Marketing, không render giá đỏ trực tiếp trong HTML tĩnh.
  - Trang danh mục `#o=3` chuẩn hóa toàn bộ về card danh mục, hiển thị trực tiếp giá đỏ, RRP và variant pills (RAM/ROM) của mọi model mới nhất.
- **Thực thi vận hành:**
  - Hằng ngày sau khi hoàn thành đợt quét, scraper và bot tự động phải thực hiện bước kiểm tra nhanh `fast_check_o3()` đối chiếu qua trang `#o=3` để log đối soát Ground Truth.
  - Tuyệt đối không phán đoán hay dùng số liệu cũ khi có nghi vấn về giá và khuyến mãi của các model mới.

---

## 3. Bảng Kiểm Tra & Công Cụ Đo Lường

Mọi ngưỡng số đọc từ **`tests/gate-config.json`** — không viết cứng ở nơi khác.

| Chiều kiểm tra | Quy tắc / Tiêu chuẩn | Lệnh kiểm tra | Thời điểm chạy |
| :--- | :--- | :--- | :--- |
| **Dữ liệu đợt quét hôm nay** | Đợt quét phải là của hôm nay; đủ `crawlSkuCount` dòng; ≥ `minActivePct` active; đủ 3 nhánh rule ở 2.1; `latest.js` khớp file scan từng số; Three-Way Sync | `node tests/verify_scan.js` | Trong CI, trước mỗi commit |
| **Toàn hệ thống** | Nhóm 0 (động theo ngày) + Nhóm 1–4 (regression guard lỗi cũ) | `powershell -ExecutionPolicy Bypass -File tests/verify-system.ps1` | Trước mỗi commit |
| **UI & Excel Export** | Đúng 3 sheet; sheet lịch sử = `masterListCount` + 1 header, đo thật bằng Chrome headless | `powershell -ExecutionPolicy Bypass -File tests/verify-system.ps1` | Trước mỗi commit |
| **Offline Standalone** | `promotion tgdd*.html` phải nhúng đúng `data/*.js` hiện hành | `python scraper/bundle.py` rồi chạy lại suite | Khi sửa giao diện hoặc dữ liệu |

**CI Circuit Breaker** (`.github/workflows/scan-tgdd.yml`): bước quét hỏng thì **chặn trước khi
commit**, không để bước báo lỗi nằm sau bước commit. Vì `verify_scan.js` bắt buộc đợt quét phải là
của hôm nay, scan hỏng sẽ tự động không commit được dữ liệu cũ.
