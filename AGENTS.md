# NGUYÊN TẮC VẬN HÀNH CỦA AGENT (THEO ADDY OSMANI'S AGENT-SKILLS)

Tài liệu này được Antigravity tự động nạp vào mọi lượt hội thoại. Bắt buộc tuân thủ 100%.

## 1. Vòng Đời Phát Triển 6 Pha (The 6-Phase Lifecycle)

Mọi yêu cầu phức tạp hoặc sửa lỗi đều phải tuân theo chu trình:
1. **DEFINE (/spec)**:
   - "Spec before code": Không viết code khi chưa nắm rõ đặc tả, input, output, invariants và edge cases.
   - Khi có nghi vấn hoặc yêu cầu mơ hồ: Làm rõ trước, không tự ý đoán.
2. **PLAN (/plan)**:
   - "Small, atomic tasks": Phân rã công việc thành từng bước nhỏ, có thể kiểm chứng độc lập.
3. **BUILD (/build)**:
   - "One slice at a time" & "Clarity over cleverness": Triển khai từng phần, ưu tiên mã nguồn rõ ràng, tường minh.
4. **VERIFY (/test)**:
   - "Tests are proof — seems right is not done": Chỉ tuyên bố xong khi có test case chạy thực tế chứng minh kết quả.
   - Bắt buộc chạy: `powershell -ExecutionPolicy Bypass -File tests/verify-system.ps1`
5. **REVIEW (/review)**:
   - Áp dụng **Doubt-Driven Development**: Chủ động nghi ngờ các giả định của chính mình.
   - Đặt câu hỏi: "Tôi có đang đoán mò không? Bằng chứng ở đâu? Trực quan DOM thực tế thế nào?"
6. **SHIP (/ship)**:
   - Đảm bảo toàn bộ tiêu chuẩn trong `CONSTRAINTS.md` đều thỏa mãn.

## 2. Kỹ Năng Trọng Tâm Cần Thực Thi (Core Disciplines)

- **Doubt-Driven Development (`doubt-driven-development`)**:
  - Không tin vào cảm giác chủ quan hay câu trả lời đầu tiên nảy ra.
  - Phân tích nguyên nhân gốc rễ (Root Cause Analysis), không sửa chữa triệu chứng bề mặt.
- **Constraint-Driven Development (`constraint-driven-development`)**:
  - Đọc và tuân thủ tuyệt đối [CONSTRAINTS.md](file:///c:/Users/toquo/Documents/antigravity/fervent-raman/CONSTRAINTS.md).
  - Không bao giờ hạ thấp rào cản chất lượng để vượt qua lỗi tạm thời.
- **Test-Driven Development (`test-driven-development`)**:
  - Viết test chứng minh lỗi trước khi fix (Prove-It pattern).
  - Báo cáo kết quả phải đi kèm log kiểm tra thực tế (Output thực của test runner).
