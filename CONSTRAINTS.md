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

**Mỗi kết luận Flash Sale phải mang theo BẰNG CHỨNG của chính đợt đó (`flash_src`):**
Trước đây dòng dữ liệu chỉ lưu *kết luận* `banner: true`, không lưu bằng chứng — sau đó không ai
truy ngược được nó đến từ đâu. Hai nguồn rất khác nhau:

| `flash_src` | Nghĩa là gì | Mạnh yếu |
| :--- | :--- | :--- |
| `quota` | Trang chi tiết **có khối suất thật** (`.bg-stock-quantity` / "Còn x/y suất" / `.box_saving`) | Khung giờ flash **đang chạy** |
| `fs-class` / `orange` / `keyword` | Lớp CSS / từ khoá của khối flash trên trang chi tiết | Trung bình |
| `hub` | Model có tên ở `/flashsale` | Mức **chiến dịch**, không phải khung giờ — hub vẫn liệt kê cả khi suất đã hết |

- Một dòng mà bằng chứng **duy nhất** là `["hub"]` là dòng **cần nhìn lại**: hệ thống báo Flash Sale
  nhưng trang chi tiết không có gì chứng minh. Bấm vào có thể không thấy gì. Đã xảy ra với
  `Find X9s 12GB/512GB` ngày 09-11-2026.

> ### QUYẾT ĐỊNH CỦA NGƯỜI DÙNG — 10-11-2026: GIỮ NGUYÊN LUẬT
>
> Câu hỏi đã đặt ra: **tên trong hub `/flashsale` có đủ để tính là Flash Sale không?**
> Người dùng đã quyết: **CÓ — giữ nguyên luật.** `in_hub` vẫn đủ để `banner = true`, và
> PMH vẫn `= khoản "Chọn 1 trong"` theo mục 2.1.
>
> **Hệ quả đã được nêu rõ trước khi quyết, và người dùng chấp nhận:** đợt 10-11-2026 có 13 dòng
> flash thì 10 dòng không có khối suất trên trang chi tiết. Ví dụ `A6 Pro 5G 8GB/256GB`:
> `choice = 0` → `PMH = 0`, trong khi giá đen − giá đỏ = **1.220.000**. Nếu dòng đó bị tính là
> *không* flash sale thì PMH sẽ là 1.220.000. Chênh lệch này là **có chủ ý**, không phải lỗi.
>
> **Tuyệt đối không được tự ý đảo lại quyết định này.** Đây là định nghĩa nghiệp vụ, không phải
> lỗi kỹ thuật — không một commit nào được tự quyết. Muốn đổi thì **phải hỏi người dùng** (mục
> 2.11). Cụ thể, `is_true_flash = bool(has_quota or in_hub)` phải giữ nguyên phép **`or`**;
> đổi thành `and`, hoặc bỏ `in_hub`, là đảo ngược quyết định này.
>
> Cảnh báo "bằng chứng duy nhất là hub" vẫn giữ — nó để **nhìn**, không để tự động sửa số.
- **Tuyệt đối không mặc định có Flash Sale, và không bê từ đợt trước sang.** Không có banner thì
  `flash_src` phải **rỗng**. Mỗi đợt phải tự chứng minh lại từ đầu.
- Ảnh chụp hub `/flashsale` lấy **một lần** đầu đợt sẽ cũ sau ~9–20 phút quét, nên trước khi lưu
  phải **quét lại** riêng các model ứng viên Flash Sale với hub nạp lại (`verify_flash_rows`).
  Một ảnh chụp cũ không được phép quyết định trạng thái flash của cả đợt.
- Cả hai nhánh nhận diện trong `parse_page` / `parse_next_layout` đều phải đòi bằng chứng suất
  thật (`has_quota or in_hub`). Trang chi tiết có chữ **"Đèn Flash camera sau"** trong phần thông
  số, nên một nhánh chỉ dò chữ "flash" sẽ tự nhận định ra flash sale từ không có gì.
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

### 2.4. Đồng bộ hóa dữ liệu (BỐN nguồn, không phải ba)
- Khi có đợt quét mới:
  - `data/scans/scan_YYYY-MM-DD.json`: Lưu bản ghi chi tiết gốc.
  - `data/latest.js`: `window.LATEST` chứa kết quả đợt quét mới nhất.
  - `data/scans.js`: `window.SCANS` chứa toàn bộ các đợt quét lịch sử (bao gồm cả đợt quét hôm nay khi đã hoàn thành).
  - **`promotion tgdd/data/*.js`**: bản sao do `scraper/bundle.py` sinh ra. Workflow
    `git add "promotion tgdd"` mỗi đợt, nên bản sao này **được commit và phục vụ web**.
  - Tránh tuyệt đối việc `latest.js` có đợt mới mà `scans.js` bị bỏ sót.
- **Bản sao phải khớp bản chính TỪNG DÒNG, không chỉ cùng `date`.** Ngày 09-11-2026 bản sao
  có **cùng** `date` nhưng `status`/`pmh` của 2 dòng iPhone 18 Pro vẫn là giá trị cũ — cổng chỉ
  so `date` nên không hề kêu. Bước đóng gói có `continue-on-error: true`, nên khi nó hỏng thì
  bản sao cũ vẫn được commit. Nay cổng so từng dòng và **chặn**.

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

### 2.7. Chốt Chặn Cuối Cùng (Ultimate Ground Truth Fallback) Qua Danh Mục Thương Hiệu TGDĐ
- **Đường dẫn chuẩn tham chiếu:** [https://www.thegioididong.com/dtdd](https://www.thegioididong.com/dtdd) và các tab thương hiệu tương ứng (`/dtdd-samsung`, `/dtdd-apple-iphone`, `/dtdd-oppo`, `/dtdd-xiaomi`, `/dtdd-vivo`, `/dtdd-realme`, `/dtdd-honor`).
- **BẮT BUỘC tra cứu lần cuối (last check) khi không tự dò được kết quả:** mọi nhánh kết thúc
  mà không có giá — kể cả nhánh **lỗi mạng / lỗi kết nối** (`status = "error"`) — đều phải tra
  cứu lần cuối qua danh mục TGDĐ **trước khi bỏ cuộc**. Phải thử **cả hai** đường: tab thương
  hiệu `/dtdd-<brand>` rồi đến danh mục tổng `/dtdd`.
  - Ngày 09-11-2026 phát hiện: nhánh lỗi trả thẳng về `{"status": "error"}` mà **không hề gọi**
    chốt chặn — đúng lúc nó cần nhất thì nó không chạy. Mọi dòng `status = error` trong lịch sử
    đều chưa bao giờ được tra cứu lại. Và vì `hub_url` chỉ dùng `/dtdd` khi **không** đoán được
    brand, nên với mọi hãng đã biết thì link `/dtdd` gần như không bao giờ được dùng.
  - Việc đánh dấu "đã tra cứu" chỉ được làm khi **thật sự đọc được trang**. Đánh dấu trước khi
    gọi HTTP thì một lỗi mạng thoáng qua sẽ khoá luôn model đó suốt cả đợt quét.
- **Nguyên tắc vận hành khi có nghi vấn hoặc trang chi tiết (PDP) gặp sự cố:**
  - Trên `https://www.thegioididong.com/dtdd`, có khung lọc riêng cho từng thương hiệu (brand filter).
  - Khi bấm vào từng brand, trang sẽ hiển thị danh sách các card sản phẩm của brand đó kèm các nút pill biến thể (SKU: RAM/ROM).
  - Bấm vào từng nút pill SKU sẽ dẫn đến đúng trang của SKU đó, đem lại câu trả lời chuẩn xác nhất theo thời gian thực (live ground truth).
  - Áp dụng độc lập cho từng model khi cần xác minh, tuyệt đối không bịa đặt, không hardcode giá tĩnh trong mã nguồn, và không mượn lại dữ liệu cũ từ các đợt quét trước.
- **Tính chất động của Flash Sale:**
  - Flash Sale trên TGDĐ thay đổi liên tục theo khung giờ (suất có hạn, đồng hồ đếm ngược). Mỗi đợt quét phải kiểm tra DOM độc lập tại thời điểm quét.
  - Không bao giờ mặc định một model có Flash Sale hoặc mang Flash Sale từ đợt này sang đợt khác. Không ép buộc số lượng máy Flash Sale phải lớn hơn 0 trong các test gate nếu thời điểm đó TGDĐ thực tế không chạy Flash Sale.

### 2.8. Chống ghi đè âm thầm lên dữ liệu đã đúng (so sánh giữa các đợt quét)

**Lớp lỗi:** PDP của sản phẩm chiến dịch là Landing Page, không render giá đỏ tĩnh (mục 2.6).
Scraper đọc không ra giá → trả về `red = rrp` → `diff = 0` → `PMH = 0`. Mọi trường còn lại
(`rule`, `kind`, `online`) vẫn nhất quán với nhau, nên **không một check nào trong phạm vi một
đợt quét phát hiện được**. Đã xảy ra với OPPO A7 Pro ngày 09-11-2026.

- `tests/verify_scan.js` bắt buộc so đợt quét mới với đợt liền trước:
  - **CHẶN COMMIT** khi một model đang có `PMH > 0` bỗng về `PMH = 0` **và** `red == rrp`.
  - **CHẶN và không thể bỏ qua** khi số model như vậy vượt `maxFlatZeroDrops` — nhiều model
    cùng tụt phẳng một lúc là lỗi code, không phải thị trường.
  - **Cảnh báo** (không chặn) khi `PMH` về 0 nhưng `red < rrp` — đúng luật 2.1.2 với flash sale
    không có mục "Chọn 1 trong".
- Muốn cho qua một trường hợp: đối soát card `#o=3` hoặc bảng tracking của người dùng, rồi thêm
  mục vào `tests/known-zero-pmh.json` **kèm bằng chứng** trong `reason`. Mục đó tự hết hiệu lực
  khi `rrp` của model đổi.
- **Cấm viết chốt đích danh một model.** Kiến thức phải mô tả **lớp lỗi**. 31% khẳng định hiện có
  đang nêu đích danh model/giá cụ thể — đó là lý do cùng một lỗi cứ tái diễn ở model khác.

### 2.9. Cấm ép cứng kết quả cào theo tên model

**Lớp lỗi:** một khối `if product["model"] in (...)` / `== "..."` trong `scraper/scan_tgdd.py`
ghi đè lên **kết quả cào thật**, không kèm bất kỳ điều kiện nào. Dòng đó thôi đo, và bắt đầu
trả về **hằng số** — nhưng vẫn đi qua mọi check vì từng đợt nhìn riêng lẻ đều hợp lệ.

Đã xảy ra (commit `ff9693a`): `iPhone 18 Pro Max 256GB` và `iPhone 18 Pro 256GB` bị ghim
`status = "chua_mo_ban"` vĩnh viễn. TGDĐ đã mở bán thật — PDP có giá 41.990.000 / 38.990.000,
có nút "Mua ngay", ghi "Đã bán 101,8k" — nhưng hệ thống vẫn báo "Chưa mở bán" suốt **24 đợt
quét liên tiếp** với `rrp`/`red`/`pmh` y hệt nhau từng byte.

- **Cấm** khối `if product["model"] in (...)` ép trạng thái. `verify-system.ps1` chặn trực tiếp.
- Việc phát hiện trạng thái phải đọc **tín hiệu từ trang**, không đọc tên model: `chua_mo_ban`
  chỉ được đặt khi trang **không có giá** và có chữ "đăng ký nhận tin" / "sắp ra mắt".
- `tests/verify_scan.js` chặn commit khi một dòng **không active** giữ nguyên y hệt
  `(status, rrp, red)` quá `maxFrozenScans` đợt liên tiếp. Giá trị không đổi qua nhiều đợt là
  dấu hiệu của **hằng số** chứ không phải **phép đo**.
- Muốn cho qua: mở PDP hoặc card `#o=3` (mục 2.7), xác nhận, rồi thêm mục vào
  `tests/known-frozen-status.json` **kèm bằng chứng**. Mục tự hết hiệu lực khi `rrp` hoặc
  `status` đổi.

**Giá dự phòng (pinned) — cách duy nhất được phép ghim số:**
Một số PDP là Marketing Landing Page, không render bất kỳ khối giá tĩnh nào (không
`box-price`, không `data-priceorg`, không cả thẻ `<main>`), và card brand hub chỉ mang giá của
**đúng một** biến thể (biến thể chính của card) — các nút pill SKU còn lại không kèm giá. Khi
thật sự không còn nguồn sống nào:

- Số liệu để trong **`scraper/pinned_prices.json`**, tuyệt đối không viết thẳng trong `.py`.
- Nó là **dự phòng, không phải ghi đè**: chỉ áp dụng khi cào ra `status != active` hoặc không
  có `rrp`. Cào được giá thật thì giá thật **luôn thắng**, và scraper in cảnh báo nhắc gỡ mục đó.
- Dòng được áp giá dự phòng mang `kind = "pin"` để nhìn là biết.
- Mỗi mục phải có `source` + `reason` (≥ 40 ký tự) và thỏa `rrp − red = pmh`.
- Quá `maxAgeDays` mà chưa đối soát lại thì **cổng chặn**. Đối soát lại = mở trang, xác nhận,
  rồi cập nhật `since`. Một hằng số không ai nhìn lại thì không được phép đi qua lặng lẽ.

### 2.10. Cổng kiểm tra phải đứng SAU bước cuối cùng còn sửa được dữ liệu

**Lớp lỗi:** cổng chạy đúng, báo PASS đúng, rồi một bước **phía sau nó** sửa lại dữ liệu.
Kết quả cuối cùng không bao giờ được kiểm.

Đã xảy ra hai lần:
1. Bước báo lỗi nằm **sau** bước commit → đợt quét hỏng vẫn commit dữ liệu cũ rồi mới báo đỏ.
2. (09-11-2026) Circuit breaker chạy **trước** `git rebase -X theirs origin/main`. File
   `scan_*.json` in mỗi trường một dòng, nên rebase trộn **theo dòng** giữa hai phiên bản của
   cùng một dòng dữ liệu — lấy `status` của bản này và `pmh` của bản kia. Dòng tự mâu thuẫn
   (`status = "chua_mo_ban"` nhưng `pmh = 0`) được đẩy thẳng lên `main`.

- `node tests/verify_scan.js` phải chạy **lại** sau mỗi lần rebase, trước `git push`. Hỏng thì
  `exit 1` — không đẩy lên.
- Quy tắc chung: **mọi bước còn ghi được vào `data/` đều phải nằm TRƯỚC cổng kiểm tra cuối cùng.**
  Thêm một bước sau cổng thì phải thêm một lần chạy cổng sau bước đó.

### 2.11. Rào chất lượng chỉ được hạ một cách công khai

Lịch sử dự án: **24 khẳng định đã bị xoá âm thầm**, và **1 khẳng định bị đảo ngược hoàn toàn**
(`-notmatch` ↔ `-match` trên cùng regex `alerts.KEEP_WEEKDAYS`). Cả hai trạng thái đều báo
`100% PASS`, nên không ai biết quy tắc người dùng train đã bị thay bằng phủ định của nó.

- `gate-config.json → minAssertions` là sàn số lượng khẳng định. Xoá khẳng định thì **bắt buộc**
  hạ con số này trong cùng commit — để việc hạ rào hiện ra trong diff.
- Trước khi đảo chiều một khẳng định đã có (`-match` ⇄ `-notmatch`), **phải hỏi người dùng**.
  Không có commit nào được tự quyết điều này.
- `tests/verify_scan.js` phải luôn còn chốt so sánh giữa các đợt quét (2.8), chốt trạng thái
  đóng băng (2.9) và hai file xác nhận của chúng; `scan-tgdd.yml` phải luôn còn lần chạy cổng
  sau rebase (2.10); `.github/workflows/verify-python.yml` phải luôn còn — máy dev không có
  Python nên đó là chỗ duy nhất `scraper/*.py` thực sự được biên dịch.
- Khẳng định kiểm tra sự tồn tại của một chốt phải dùng `-cmatch` (phân biệt hoa thường) và bắt
  đúng **câu báo lỗi** trong `fail()`, không bắt dòng `console.log` mô tả. PowerShell `-match`
  không phân biệt hoa thường, nên một chốt viết bằng `-match 'HOI QUY'` vẫn PASS sau khi chốt
  thật đã bị gỡ, chỉ cần còn dòng log `[6] Hoi quy giua cac dot...` là đủ lừa.

**Khẳng định phải kiểm HÀNH VI, không kiểm sự tồn tại.** Đây là lớp lỗi đã lặp lại nhiều lần
trong dự án: luật được ghi đúng, cơ chế có thật, khẳng định mang đúng tên luật — nhưng thân nó
chỉ kiểm một cái tên hoặc một chuỗi có xuất hiện ở đâu đó. Mọi thứ báo `100% PASS` trong khi
luật không chạy. Các ca đã gặp:

| Khẳng định | Nó thực sự kiểm gì | Hệ quả |
| :--- | :--- | :--- |
| "không được chứa giá hardcode trong `_CATALOG_ITEMS`" | `_CATALOG_ITEMS = {}` có tồn tại | 6 con số giá ép cứng ngay 3 dòng dưới vẫn PASS |
| "phải có hàm `fetch_model_from_brand_hub` làm chốt chặn cuối cùng" | `def fetch_model_from_brand_hub(` có tồn tại | Hàm không hề được gọi ở nhánh lỗi vẫn PASS |
| "phải định nghĩa hàm `fast_check_o3`" | `def fast_check_o3(` có tồn tại | Không ai gọi thì vẫn PASS |
| "`'Kết thúc sau'` phải nằm trong `FLASH_KEYWORDS_RE`" | chuỗi `sau` có ở đâu đó trong file | Chữ "sau" có trong hàng chục từ tiếng Việt khác |
| "phải chứa đủ các tháng T1→T10" | 4 chuỗi `T1`/`T4`/`T7`/`T10` | **T2 rỗng suốt mà không ai biết** |
| "phải render đầy đủ các tháng T1–T10" | 2 tên model | Mất 8 tháng vẫn PASS |
| "`load_base_rrp_map` phải nạp cả `scans.js`" | chuỗi `scans.js` — **khớp vào docstring** | Xoá câu lệnh đọc thật vẫn PASS |

Quy tắc bắt buộc từ nay:
- Luật nói **"phải chạy / phải được gọi"** thì khẳng định phải bắt **lời gọi**, và bắt **đúng thứ
  tự** so với bước liên quan — không chỉ bắt `def`.
- Kiểm một chuỗi thì phải kiểm **trong đúng phạm vi** của nó (thân hàm, thân `re.compile`), không
  kiểm trên cả file; và phải bắt **câu lệnh thật**, không bắt lời văn trong docstring/comment/log.
- Luật nói **"đầy đủ"** thì phải **đếm** hoặc **duyệt hết tập**, không lấy vài mẫu đại diện.
- Mỗi chốt mới phải có **phép thử ngược**: cố tình phá đúng thứ nó canh, và xác nhận nó CHẶN.
- Một chốt có hành vi **phụ thuộc ngày trong tuần / thời điểm** mà chỉ được thử đúng một ngày
  thì **chưa được coi là đã thử**. Ngày 09-11-2026 (thứ Hai) chốt "scans.js phải có đợt hôm nay"
  PASS vì thứ Hai tình cờ là ngày được giữ theo `KEEP_WEEKDAYS`; sang thứ Ba nó chặn **cả 3 lượt
  quét tự động liên tiếp** và hệ thống dừng hẳn một ngày.
- Một chốt **không bao giờ được mâu thuẫn với một quy tắc người dùng đã train**. Trước khi thêm
  chốt, đối chiếu với `KEEP_WEEKDAYS`, Master List, và các quy tắc ở mục 2 — chốt sai thì nó
  không bảo vệ gì, nó chỉ khoá hệ thống.

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
