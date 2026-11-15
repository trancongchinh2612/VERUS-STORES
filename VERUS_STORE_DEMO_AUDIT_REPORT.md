# VERUS STORE — DEMO AUDIT REPORT

## Phạm vi
Đã giải nén ZIP người dùng gửi, kiểm tra `index.html`, `admin.html`, `config.js`, `package.json`, các migration SQL, báo cáo QA gốc và luồng checkout trong mã nguồn. Giữ nguyên bản customer production ban đầu tại `source-original/index-production-original.html`; `admin.html` và SQL production được giữ lại, không dùng trong demo.

## Lỗi quan sát được
- Trang khách hàng gốc boot theo nhánh Supabase nếu cấu hình URL/key tồn tại; checkout gọi RPC `place_order`. Ảnh người dùng cho thấy thông báo lỗi mã 42883 khi gửi đơn. Đây là mã lỗi PostgreSQL thuộc nhóm undefined function; không thể xác định chính xác hàm thiếu/chữ ký không khớp chỉ từ ảnh.
- Khi backend chưa sẵn sàng, bản gốc chặn checkout thay vì tạo đơn demo.
- Các lớp đăng nhập Google / Supabase và production guard vẫn chi phối trải nghiệm khách hàng.
- Bộ dữ liệu khởi tạo trong source production đã đặt mảng sản phẩm rỗng ở đoạn boot legacy; không thể dùng nó làm catalog demo ngay.

## Thay đổi
- Thay `index.html` trong gói demo bằng storefront customer demo độc lập, tự động vào phiên khách hàng Nguyễn An.
- Không tải SDK Supabase, không gọi Supabase/Auth/RPC/Database/Storage, không có Google OAuth.
- Checkout cục bộ xác thực các trường bắt buộc, sinh mã đơn, ghi đơn vào IndexedDB (fallback LocalStorage), hiển thị trang thành công chỉ sau khi ghi dữ liệu xong.
- COD tính cọc `ceil(total × 20%)`, phần còn lại bằng tổng trừ tiền cọc; chuyển khoản là 100% mô phỏng. Không tạo giao dịch hoặc gọi API thanh toán.
- Thêm 8 sản phẩm mẫu, danh mục, tìm kiếm, lọc, chi tiết, màu/size, giỏ, voucher, yêu thích, hồ sơ, địa chỉ, đơn hàng, VIP và Outfit Builder.
- Zalo chuyển thành nút icon riêng và nút nổi. Link Zalo lấy đúng từ cấu hình ZIP ban đầu.
- Thêm reset demo, README tiếng Việt, test và báo cáo.

## Ranh giới demo / production
- Hoạt động thật trong trình duyệt: thao tác catalog mẫu, giỏ, tính toán, lưu dữ liệu cục bộ, tạo đơn demo, xem lịch sử, yêu thích, hồ sơ, outfit và reset.
- Giả lập: sản phẩm/tồn kho/giá, voucher, hạng/điểm, trạng thái đơn, thanh toán, vận chuyển, thời gian giao.
- Cần backend khi production: xác thực khách hàng, catalog/tồn kho trung tâm, tạo đơn đồng bộ, đối soát cọc, thanh toán, vận chuyển, hoàn tiền, CRM, VIP/điểm, chat và admin.
- Tuyệt đối không dùng bản demo để nhận đơn thật hoặc xác nhận đã nhận tiền. Dữ liệu chỉ nằm trên thiết bị hiện tại.

## Phụ thuộc Internet
Storefront không tải ảnh/CDN/thư viện ngoài và các luồng cốt lõi không gọi mạng. Mở Zalo cần Internet. Mở file trên trình duyệt có thể bị hạn chế IndexedDB theo chính sách file://; chạy `python3 -m http.server 8080` là cách ổn định hơn.

## Kiểm thử đã thực hiện
- Kiểm tra cú pháp JavaScript bằng `node --check`: xem kết quả thực chạy ở QA log khi có Node.
- Kiểm thử tự động Node: `npm test` đạt 4/4.
- `node --check` cho JavaScript inline: đạt.
- HTTP smoke test: `/`, `/index.html`, `/config.js`, `/README_DEMO_VI.md` đều trả HTTP 200.
- Đã thử chạy Chromium headless để kiểm thử thao tác checkout, nhưng môi trường hiện tại chặn điều hướng trình duyệt với `ERR_BLOCKED_BY_ADMINISTRATOR`; vì vậy checkout end-to-end, lưu sau reload và responsive thật trên Android/iPhone được ghi NOT TESTED, không tự nhận PASS.
- Chưa kiểm thử backend production hoặc migration SQL trên Supabase. Mã 42883 không thể xác nhận đã sửa trên production vì demo không còn gọi backend.

## Kết luận
Trong chế độ OFFLINE CUSTOMER DEMO, đặt hàng demo không còn phụ thuộc RPC nên lỗi 42883 từ backend không nằm trên luồng checkout. Đơn chỉ được báo thành công sau khi dữ liệu đã ghi được vào bộ nhớ cục bộ. Điều này không khẳng định checkout production/Supabase đã được sửa; production cần chẩn đoán RPC và schema riêng.


## Nâng cấp thanh toán production (bản bổ sung)
- Đã tạo thư mục `production/` chứa customer production, admin production, cấu hình mẫu và ảnh QR Techcombank được cung cấp.
- Checkout production hiển thị tiền cần chuyển màu đỏ, mã đơn/nội dung chuyển khoản, tải ảnh QR và nút khách tự báo đã chuyển khoản.
- Báo chuyển khoản chỉ ghi nhận `pending_review`; Admin có thao tác xác nhận/từ chối thủ công qua RPC bảo vệ quyền staff.
- Chưa thể xác nhận lỗi 42883 đã hết trên website đang chạy: cần chạy migration trên đúng Supabase project và kiểm thử live.
- Bản offline demo tại thư mục gốc vẫn không thu tiền thật và không dùng QR ngân hàng thật.
