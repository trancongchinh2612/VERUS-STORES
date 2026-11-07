# VERUS STORE — Báo cáo rà soát thanh toán production

## Đã sửa trong gói mã nguồn
- Thay QR VietQR động từ bên thứ ba bằng đúng ảnh QR người dùng cung cấp (được đóng gói cục bộ).
- Thêm tải ảnh QR, hiển thị số tiền cần chuyển nổi bật màu đỏ, số tài khoản/ngân hàng/chủ tài khoản và nội dung chuyển khoản theo mã đơn.
- Thêm nút khách tự báo đã chuyển khoản; chỉ tạo bản ghi chờ đối soát.
- Bổ sung nút Admin xác nhận hoặc từ chối từng payment pending qua RPC `admin_confirm_payment` / `admin_reject_payment`.
- Thông báo rõ thời hạn đối soát 12 giờ và không tự xác nhận tiền.

## Chưa thể xác nhận trong môi trường đóng gói
- Không có quyền truy cập Supabase project thực tế nên chưa thể chạy migrations, kiểm tra RPC trên backend đang chạy hoặc xác nhận lỗi 42883 đã được khắc phục trên GitHub Pages live.
- Không có thông tin Supabase URL/anon key trong bản ZIP demo; `production/config.js` chứa placeholder cần chủ shop điền.
- Chưa thể chạy thử giao dịch ngân hàng thật.

## Rủi ro cần kiểm thử trước mở bán
- Ảnh QR là ảnh tĩnh: khách cần đối chiếu người nhận và nhập đúng số tiền/nội dung nếu app ngân hàng không tự điền.
- `report_deposit_transfer` phải được deploy cùng các migrations thanh toán.
- Tài khoản Admin phải có role staff hợp lệ; RLS và quyền EXECUTE RPC cần đúng.
