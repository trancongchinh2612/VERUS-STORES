# VERUS STORE — OFFLINE CUSTOMER DEMO

## Chạy trên máy tính
1. Giải nén ZIP.
2. Mở thư mục `VERUS-STORES-main`.
3. Cách đơn giản: mở `index.html` bằng Chrome/Edge/Firefox. Nếu trình duyệt hạn chế lưu dữ liệu khi mở file trực tiếp, dùng máy chủ cục bộ: cài Python, mở Terminal tại thư mục và chạy `python3 -m http.server 8080`, sau đó mở `http://localhost:8080`.
4. Website tự vào tài khoản khách hàng demo Nguyễn An; không đăng ký, không Google, không Supabase.

## Trải nghiệm
- Chọn danh mục hoặc tìm sản phẩm.
- Mở sản phẩm, chọn màu, size, số lượng và thêm vào giỏ.
- Giỏ hàng hỗ trợ tăng/giảm/xóa, mã `VERUS10`, tính tổng.
- Checkout yêu cầu họ tên, số điện thoại 10 số, tỉnh/thành, phường/xã, địa chỉ và xác nhận chính sách.
- Khi xác nhận, đơn được lưu cục bộ, sinh mã `VS-DEMO-...`, hiện trang thành công và xuất hiện trong Tài khoản → Đơn hàng.
- COD: cọc 20%, còn 80%; chuyển khoản 100% chỉ là mô phỏng.
- Có yêu thích, sửa hồ sơ, VIP, địa chỉ, Outfit Builder và reset demo.
- Zalo là nút icon riêng, liên kết QR Zalo đã có trong cấu hình gốc. Cần Internet để mở Zalo.

## Lưu ý dữ liệu
Ưu tiên IndexedDB; nếu trình duyệt không hỗ trợ thì fallback LocalStorage. Dữ liệu chỉ nằm trên trình duyệt/thiết bị hiện tại, không tự đồng bộ giữa thiết bị. Không dùng đơn demo làm đơn thật.

## Offline thực tế
Các chức năng cửa hàng cốt lõi hoạt động không cần Internet sau khi tải/mở file. Zalo và các dịch vụ bên ngoài cần Internet. Hình ảnh sản phẩm trong bản demo là placeholder CSS, không tải ảnh ngoài.

## Reset
Nhấn `Khôi phục dữ liệu demo` ở chân trang hoặc trong Tài khoản. Thao tác xóa đơn, giỏ và yêu thích demo trên thiết bị hiện tại.


## Bản production có QR và Admin đối soát
Trong thư mục `production/` có bản website kết nối Supabase để nhận đơn thật, ảnh QR Techcombank và trang Admin xác nhận thủ công. Đây KHÔNG phải bản offline demo. Trước khi triển khai, đọc `production/README_TRIEN_KHAI_SAN_XUAT_VI.md`, điền cấu hình Supabase và chạy migrations. Không đưa website production lên nhận đơn thật khi chưa hoàn tất các bước này.
