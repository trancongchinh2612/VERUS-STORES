# VERUS STORE — báo cáo tiếp quản và kiểm thử

## Phạm vi đã kiểm tra

Đã giải nén source gốc và đọc trực tiếp hai trang HTML, cấu hình, package/deploy, toàn bộ 8 SQL migration có trong ZIP, cùng các phần checkout, tracking, thanh toán, đồng bộ Admin, quản lý sản phẩm, RLS và RPC. Không thay source bằng template mới.

## Nguyên nhân và sửa chữa chính

1. GitHub Actions workflow cũ nằm ở `pages.yml` tại root nhưng cấu hình upload `public/`, trong khi HTML thực tế nằm ở root. Đã chuyển workflow tới `.github/workflows/pages.yml` và deploy root.
2. `npm run serve` trỏ tới thư mục `public/` không tồn tại. Đã đổi sang root.
3. `config.js` dùng BIN Techcombank, bỏ trống tài khoản và tên người nhận. Đã cập nhật MB Bank BIN `970422`, tài khoản `0386083805`, tên `TRAN CONG CHINH`, cùng Zalo chính thức.
4. Checkout có nhánh offline tạo đơn giả trong `localStorage`. Đã chặn tạo đơn khi Supabase chưa kết nối; không báo thành công giả.
5. QR checkout dùng memo sinh từ mã đơn nhưng chưa có trường lưu tham chiếu ở database và không dễ khôi phục sau khi đóng modal. Migration mới thêm `orders.transfer_reference` được sinh ổn định từ 16 ký tự hex cuối của mã đơn; checkout dùng `pg_catalog.gen_random_uuid()` trực tiếp (64-bit suffix), trả tham chiếu do server tạo, không còn phụ thuộc workaround `gen_random_bytes` trong `public`. Migration cũng bỏ shim cũ nếu shim không thuộc extension. Tracking trả trường này; khách có thể lấy lại QR ở trang tra cứu và chi tiết đơn.
6. Quy tắc 20% COD / 100% chuyển khoản trước đây phụ thuộc `site_settings.deposit_percent`. Migration mới áp quy tắc cố định tại trigger database: COD 20%, số dư 80%; chuyển khoản 100%, số dư 0. Trigger chạy trước insert/update nên không phụ thuộc dữ liệu do trình duyệt gửi.
7. Nếu khách đã báo chuyển khoản và đơn đang `pending_review`, thao tác hủy có thể gây hiểu nhầm về khoản tiền chưa được đối soát. Đã chặn hủy ở database trong giai đoạn này; Admin cần xử lý/từ chối báo thanh toán trước khi hủy. Hủy đơn đã có payment confirmed vẫn bị chặn bởi logic cũ.
8. Admin standalone trước đây dùng số điện thoại khách tạo link `zalo.me/<phone>`. Đã đổi sang Zalo chính thức của cửa hàng. Danh sách đơn cũng tách số tiền cần chuyển, tiền đã xác nhận và số còn thu khi giao; chuyển khoản hiển thị số dư giao hàng bằng 0.
9. Khách có thể khôi phục QR từ chi tiết đơn/tracking. Khi payment đang chờ đối soát, QR được ẩn để tránh chuyển tiền lặp và hiển thị thông báo chờ shop xác minh.

## File thay đổi / thêm mới

- `config.js`, `config.example.js`
- `index.html`, `admin.html`
- `package.json`, `config.toml`, `README.md`
- `.github/workflows/pages.yml` (thay `pages.yml` cũ)
- `202611070002_checkout_payment_hardening.sql` (migration mới, không sửa lịch sử migration)
- `DEPLOYMENT.md`
- `FINAL_QA_REPORT.md`
- `tests/payment-rules.test.js`

## Migration cần chạy

- Database đã chạy đủ các migration `202611040001` đến `202611070001`: chỉ chạy `202611070002_checkout_payment_hardening.sql` sau khi backup.
- Database mới: chạy toàn bộ migration theo thứ tự tên, bao gồm migration mới nhất.
- Migration mới thêm cột generated `transfer_reference`, trigger ép điều khoản thanh toán, cập nhật `track_order`, và trigger chặn hủy trong lúc `pending_review`.

## Kiểm thử đã thực hiện

### Mức 1 — đọc và kiểm tra mã nguồn

- Truy vết checkout → `place_order` → trigger/payment row → `report_deposit_transfer` → Admin confirm/reject → tracking/cancel.
- Đọc RLS, grants, SECURITY DEFINER, search_path, schema, constraints, foreign keys và các migration có sẵn.
- Kiểm tra đường dẫn tương đối, cấu hình public key, thông tin MB Bank/Zalo và workflow.
- HTML parser đọc được cả hai trang; không phát hiện ID trùng.

### Mức 2 — chạy kiểm thử cục bộ

- `node --check` cho tất cả inline JavaScript trong `index.html` và `admin.html`: đạt.
- `npm test`: 6/6 kiểm thử đạt (công thức COD, chuyển khoản, mã tham chiếu, nội dung migration, chặn checkout offline, thông tin public).
- HTTP smoke test qua Python server: `/`, `/index.html`, `/admin.html`, `/config.js`, `.github/workflows/pages.yml` trả HTTP 200.
- `package.json` hợp lệ và workflow nằm đúng vị trí.

Các kiểm thử số tiền trong Node là kiểm thử logic/static; không thay thế chạy SQL transaction trên PostgreSQL.

### Mức 3 — Supabase / website thật

**Chưa thể xác minh trong phiên này.** Không có quyền đăng nhập vào Supabase project, không có quyền truy cập GitHub repository/actions hoặc tài khoản ngân hàng. ZIP không chứa bản sao database production. Vì vậy chưa thể khẳng định migration đã áp dụng, RPC hoạt động live, Google OAuth redirect đúng, sản phẩm/đơn thật đã đồng bộ, VietQR đã được ngân hàng xác nhận hoặc website đã deploy.

## Việc chủ quản trị cần thực hiện

1. Backup Supabase và áp dụng migration theo hướng dẫn.
2. Kiểm tra role `profiles.role` của tài khoản shop là `admin` hoặc `staff`.
3. Kiểm tra Google OAuth provider, Site URL và Redirect URLs có `https://trancongchinh2612.github.io/VERUS-STORES/`.
4. Push repository lên nhánh `main`, xác nhận GitHub Pages dùng GitHub Actions và workflow `.github/workflows/pages.yml` hoàn tất.
5. Trên staging, thử đơn COD và chuyển khoản, đối chiếu QR, `transfer_reference`, `payments`, `deposit_amount`, `balance_amount`, tracking, Admin confirm/reject và hủy đơn.
6. Đối chiếu giao dịch MB Bank thật trước khi Admin xác nhận thanh toán. Báo chuyển khoản từ khách không tự động chứng minh tiền đã vào tài khoản.

## Giới hạn còn lại

- Chưa chạy SQL trên Supabase thật; cần kiểm tra migration trên staging trước production.
- Chưa thực hiện thanh toán thật hoặc truy vấn ngân hàng. VietQR được tạo bằng endpoint VietQR với thông tin người nhận/số tiền/nội dung đã cấu hình; việc tài khoản MB Bank có nhận được khoản chuyển phải được xác minh thực tế.
- Chưa thể xác nhận GitHub Actions hoặc Google OAuth hoạt động live khi chưa có quyền repository/Supabase.
- Chưa có trình duyệt thiết bị để chạy end-to-end responsive/checkout thực tế; chỉ kiểm tra cú pháp, HTML, HTTP và logic tĩnh/cục bộ.
