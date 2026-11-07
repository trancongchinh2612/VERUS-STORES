# VERUS STORE — Bản production đã nâng cấp thanh toán

## Những gì đã thay đổi
- Checkout sau khi tạo đơn thật hiển thị ảnh QR Techcombank do chủ shop cung cấp.
- Số tiền cần chuyển được làm nổi bật màu đỏ; nội dung chuyển khoản lấy từ mã đơn do máy chủ trả về.
- Có nút tải ảnh QR, sao chép nội dung và nút **Tôi đã chuyển khoản**.
- Nút này chỉ gọi `report_deposit_transfer` để tạo thông báo chờ đối soát; KHÔNG xác nhận tiền.
- Admin có nút **Xác nhận đã nhận tiền** và **Từ chối** cho từng giao dịch đang chờ. Chỉ xác nhận sau khi kiểm tra sao kê/tài khoản ngân hàng thật.
- Sau khi báo chuyển khoản, khách được hướng dẫn chờ shop xác minh trong 12 giờ.

## Thông tin QR đã lấy từ ảnh người dùng cung cấp
- Ngân hàng: Techcombank
- Chủ tài khoản: DANG THI HUONG
- Số tài khoản hiển thị: 1907 2227 5090 17
- QR là ảnh tĩnh. Website hiển thị số tiền và nội dung chuyển khoản riêng để khách điền/đối chiếu. Khách phải kiểm tra đúng người nhận trước khi chuyển.

## Triển khai bắt buộc trước khi nhận đơn thật
1. `production/config.js` đã được điền Project URL và Publishable key mà chủ shop cung cấp. Publishable key được phép nằm ở frontend; tuyệt đối không đưa `sb_secret`, `service_role` hoặc Google Client Secret lên website. Nếu đã lộ secret, hãy thu hồi và tạo secret mới trong Supabase.
2. Chạy toàn bộ file SQL trong `supabase/migrations` theo thứ tự tên file trong Supabase SQL Editor. Đặc biệt phải chạy `202611070002_checkout_payment_hardening.sql` để tạo đúng RPC `place_order` mà checkout gọi, sau đó chạy `202611070003_payment_rpc_permissions_and_cache.sql` để cấp quyền RPC và yêu cầu PostgREST tải lại schema cache. Nếu bỏ migration, lỗi PostgreSQL `42883` có thể tiếp tục xảy ra.
3. Kiểm tra Supabase Auth Google provider, redirect URLs, RLS, quyền nhân viên/admin và cấu hình sản phẩm/tồn kho.
4. GitHub Actions trong `.github/workflows/pages.yml` đã được chỉnh để xuất bản đúng thư mục `production/`. Sau khi commit/push, đợi workflow Pages chạy thành công. Trang khách dùng `/VERUS-STORES/`; trang quản trị dùng `/VERUS-STORES/admin.html`.
5. Đặt thử một đơn kiểm thử có giá trị nhỏ, xác minh đơn xuất hiện ở Admin, bấm thử báo đã chuyển khoản, xác minh payment có trạng thái pending; sau đó Admin mới xác nhận. Xóa/hoàn tác dữ liệu thử trước khi mở bán.

## Lưu ý lỗi 42883
Lỗi 42883 là lỗi PostgreSQL không tìm thấy hàm với chữ ký được gọi. Mã frontend gọi RPC `place_order` với 11 tham số (trong đó có `p_points` và `p_idem`). Migration `202611070002_checkout_payment_hardening.sql` định nghĩa chữ ký tương ứng. ZIP không thể tự chạy migration trên Supabase của bạn; cần chạy SQL trên đúng project. Không có cách an toàn để xác nhận lỗi live đã hết trước khi migration được áp dụng và thử trên backend thực.

## Luồng thanh toán
Tạo đơn → hiện QR + số tiền cọc 20% → khách chuyển khoản → khách bấm Tôi đã chuyển khoản → payment `pending_review` → Admin kiểm tra tiền thực nhận → Admin xác nhận/từ chối. Không có tự động xác minh ngân hàng.
