# VERUS STORE — bản đã hoàn thiện

Bản này gồm cửa hàng khách hàng, trang quản trị, cấu hình Supabase, tài sản QR ngân hàng, các migration SQL và workflow GitHub Pages.

## Các thay đổi

- Thêm khu vực **Đơn hủy / đổi trả** và hội thoại khách hàng trong tài khoản.
- Yêu cầu đổi trả của khách được lưu trên đơn Supabase và hiện tại mục đổi trả của admin; admin mở đơn website để xử lý tiếp. Ghi nhận hoàn tiền đòi hỏi nhập khoản thực sự chuyển cho khách; không chuyển tiền tự động.
- Thêm xác nhận đã nhận hàng. Máy chủ tự tính và cộng điểm đúng một lần khi khách xác nhận đã nhận hàng: đơn 100.000đ được 10 điểm; mỗi điểm dùng giảm 500đ. Sau khi xác nhận, yêu cầu đổi size thông thường của đơn đó bị khóa.
- Đồng bộ voucher admin sang cửa hàng; voucher đang hoạt động có thể xem công khai và được máy chủ kiểm tra lại khi thanh toán.
- Cập nhật dữ liệu sản phẩm, biến thể, tồn kho, cài đặt, đơn và điểm qua Supabase Realtime; giao diện khách không cần tải lại trang.
- Gỡ bộ lọc “phong cách”, thêm bộ lọc size XS–XXXL, quần 26–38, giày/dép EU 35–46 và Free Size; mở rộng bảng size và cách đo.
- Viết lại chính sách mua hàng, thông tin chat và nội dung giới thiệu sản phẩm; phiên đăng nhập hiện có không tự bật cửa sổ tài khoản.
- Thêm workflow triển khai GitHub Pages tại `.github/workflows/pages.yml`.

## Trước khi đưa lên bán thật

1. Sao lưu cơ sở dữ liệu Supabase hiện tại.
2. Kiểm tra trạng thái migrations cũ. Nếu các migration hiện có trong gói đã chạy, chỉ chạy tiếp `202611080003_customer_delivery_returns.sql`, rồi `202611080004_live_storefront_realtime_vouchers.sql`. Nếu chưa chạy migration cũ, áp dụng toàn bộ SQL theo thứ tự tên trước đó.
3. Kiểm tra Supabase Auth Google, RLS, tài khoản `staff/admin`, Realtime và URL chuyển hướng GitHub Pages.
4. Điểm đã cấu hình theo yêu cầu: 10.000đ = 1 điểm, mỗi điểm giảm 500đ. Rà soát các điều khoản đổi trả, điều kiện hàng hóa và hoàn tiền theo quy định áp dụng trước khi bán thật.
5. Cấu hình sản phẩm, tồn kho, voucher và ngân hàng trong admin; thử một đơn giá trị nhỏ, hoàn tất đối soát trong Supabase, kiểm tra chat hai chiều và cập nhật trạng thái đơn trước khi nhận đơn thật.
6. Đưa nội dung thư mục này lên nhánh `main` của repository GitHub. GitHub Pages cần đặt nguồn là **GitHub Actions**; workflow xuất bản thư mục gốc của gói này.

## Ghi chú vận hành

- `config.js` chứa URL dự án và khóa publishable/anon của Supabase để frontend kết nối. Không thêm `service_role`, secret key hay thông tin đăng nhập ngân hàng vào đây.
- Báo đã chuyển khoản chỉ tạo bản ghi chờ đối soát; admin phải kiểm tra giao dịch thực tế trước khi xác nhận.
- Xác nhận đã nhận hàng chỉ cộng điểm một lần. Khách đã xác nhận sẽ không gửi được yêu cầu đổi size thông thường qua luồng này; hàng lỗi/giao sai vẫn có thể được nhắn shop để hỗ trợ.
- Chat từ trang cửa hàng nằm trong tab **Tin nhắn website** của admin. Các hội thoại nội bộ của shop vẫn ở mục riêng.
- Trên điện thoại, **Hộp thư khách hàng** nằm ngay trên thanh điều hướng admin. Đây là hộp thư chung cho chat trong Tài khoản và biểu mẫu “Gửi cho VERUS”; hội thoại nội bộ được tách sang mục riêng.
- Nếu nút “Đã nhận hàng tốt” hiện thông báo cần cập nhật cơ sở dữ liệu, phải chạy migration `202611080003_customer_delivery_returns.sql` trên đúng dự án Supabase đang dùng. Chỉ tải file lên GitHub Pages không cập nhật database. Migration `202611080004_live_storefront_realtime_vouchers.sql` cũng cần chạy để bật đồng bộ realtime và voucher.
- Sau khi migration chạy thành công, tải lại trang một lần để làm mới cache API của Supabase. Việc khách báo đã chuyển khoản chỉ lưu yêu cầu đối soát; shop vẫn cần xác minh giao dịch ngân hàng trong admin trước khi đánh dấu đã nhận tiền.
- Số đo size là tham khảo phổ biến. Size và tồn kho khách đặt luôn lấy từ từng sản phẩm đã cấu hình trong admin.

