# VERUS STORE — Nâng cấp trang khách hàng (VERUS LUXE)

Phiên bản: LUXE v1 · Ngày: 09/11/2026 · Phạm vi: chỉ giao diện trang khách hàng `index.html`.

## 1. Đã làm gì

Trang chủ khách hàng được chuyển sang phong cách **dark-luxury** (nền đen sâu, chữ ngà, điểm nhấn vàng champagne) với hiệu ứng 3D/parallax:

- **Banner chính mới**: tiêu đề chữ serif lớn (Cormorant Garamond, hỗ trợ tiếng Việt), dòng thứ hai nghiêng ánh vàng, chữ xuất hiện dần khi mở trang.
- **Sân khấu 3D**: khối "V" vàng dạng 3D xoay chậm, 2 vòng quỹ đạo, bụi vàng lơ lửng, 3 thẻ danh mục Áo / Quần / Giày bay quanh. Trên máy tính, rê chuột làm cả sân khấu nghiêng theo; trên điện thoại, sân khấu tự xoay nhẹ.
- **Parallax khi cuộn**: chữ banner, sân khấu 3D, quầng sáng và lưới nền di chuyển ở tốc độ khác nhau; thanh tiến trình vàng ở mép trên.
- **Hiện dần khi cuộn**: thẻ dịch vụ, danh mục, câu chuyện, hỏi đáp, 4 bước mua, form liên hệ, chân trang.
- **Nghiêng 3D khi rê chuột**: thẻ dịch vụ, thẻ danh mục, thẻ câu chuyện, thẻ 4 bước (thẻ sản phẩm giữ hiệu ứng nghiêng có sẵn, đổi ánh sáng sang vàng).
- **Thẻ sản phẩm** nền tối, giá chữ serif vàng, nút "MUA NGAY" và "Chọn mẫu & size" tông vàng.
- Dải chữ chạy dạng chữ viền serif, khối tuyên bố thương hiệu dạng trích dẫn, câu hỏi thường gặp kiểu danh sách thanh lịch, chân trang và thanh điều hướng điện thoại tông tối.
- Thêm tiêu đề "Khám phá theo danh mục" phía trên các ô danh mục.
- Cửa sổ sản phẩm, giỏ hàng, thanh toán, tài khoản **giữ nguyên giao diện sáng đã kiểm chứng**, chỉ làm mờ nền phía sau.
- Tôn trọng cài đặt "giảm chuyển động" của thiết bị: khi bật, mọi hiệu ứng tắt và nội dung hiện ngay.
- Sửa khả năng tiếp cận: 3 nút danh mục 3D trước đây nằm trong vùng bị ẩn với trình đọc màn hình, nay đọc được và có nhãn rõ ràng.

## 2. Không thay đổi (giữ nguyên nghiệp vụ)

- Toàn bộ 19 khối JavaScript gốc của `index.html` (Supabase, đăng nhập Google, giỏ hàng, đặt hàng `place_order`, thanh toán COD 20% / chuyển khoản 100%, báo đã chuyển khoản, theo dõi đơn, đổi trả, realtime, voucher) **giữ nguyên từng ký tự** — có test tự động kiểm tra.
- `admin.html`, `config.js`, `config.example.js`, mọi file SQL migration, RLS: **không sửa**.
- Không tạo sản phẩm, đánh giá, số liệu bán hàng hay lời khen giả. Không chạy migration. Không deploy.

## 3. Sửa thêm một lỗi có sẵn

Trang tham chiếu ảnh QR thanh toán tại `assets/verus-payment-qr.jpg`, nhưng gói ZIP chỉ có `verus-payment-qr.png` ở thư mục gốc → ảnh QR bị lỗi 404. Đã tạo `assets/verus-payment-qr.jpg` chuyển trực tiếp từ đúng file PNG có sẵn (cùng mã QR Techcombank – DANG THI HUONG, không đổi nội dung). File PNG gốc vẫn giữ nguyên.

## 4. Danh sách file

| File | Trạng thái |
|---|---|
| `index.html` | Sửa: thẻ `<html class="lux">`, màu theme, font, khối banner, tiêu đề danh mục, thêm lớp `VERUS LUXE` cuối trang |
| `backup/index-truoc-nang-cap-luxe.html` | Mới: bản sao lưu nguyên vẹn `index.html` trước nâng cấp |
| `assets/verus-payment-qr.jpg` | Mới: ảnh QR mà trang đang tham chiếu |
| `tests/storefront-luxe.test.js` | Mới: 10 test bảo vệ nghiệp vụ và giao diện |
| `tools/luxe/` | Mới: mã nguồn lớp giao diện (`luxe.css`, `luxe.js`) và script áp dụng |
| `tools/luxe-visual-check.py` | Mới: script Playwright chụp/kiểm tra giao diện |
| `NANG_CAP_GIAO_DIEN_LUXE.md` | Mới: tài liệu này |

## 5. Kết quả kiểm thử

**Test tự động (`npm test`) — 10/10 đạt:**
script nghiệp vụ gốc giữ nguyên; lớp giao diện không gọi mạng / không đọc ghi dữ liệu / không đụng thanh toán; nút banner gọi đúng hàm cũ; nút 3D đọc được bằng trình đọc màn hình; tôn trọng giảm chuyển động; nội dung không bị ẩn nếu JavaScript lỗi; không có đánh giá/số liệu giả; ảnh QR tồn tại đúng JPEG; `config.js` không chứa khóa bí mật.

**Test cũ của dự án** (các file `*.test.js` ở thư mục gốc, viết cho cấu trúc thư mục `production/` cũ, nên phải dựng lại cấu trúc tạm để chạy):
- Trước nâng cấp: 14 đạt / 7 lỗi. Sau nâng cấp: **15 đạt / 6 lỗi** (thêm 1 đạt nhờ ảnh QR).
- 6 lỗi còn lại **có sẵn từ trước, không liên quan giao diện**: 4 test của bản demo offline cũ (bản hiện tại là bản thật dùng Supabase); 1 test đòi tài khoản MB Bank – TRAN CONG CHINH trong khi test khác và `config.js` dùng Techcombank – DANG THI HUONG (hai test mâu thuẫn nhau); 1 test tìm cú pháp hàm báo chuyển khoản phiên bản cũ. Cần chủ shop xác nhận tài khoản ngân hàng đúng trước khi sửa các test này.

**Kiểm tra trên trình duyệt (Chromium, dữ liệu thật đọc từ Supabase):**
- Máy tính 1280px và điện thoại 390px: không lỗi JavaScript, không lỗi tải file, không tràn ngang trên điện thoại.
- Rê chuột làm sân khấu 3D nghiêng; bấm thẻ "QUẦN" trên banner lọc đúng danh mục Quần.
- Cuộn hết trang: mọi khối đều hiện ra. Chế độ giảm chuyển động: không còn khối nào bị ẩn.
- Mở cửa sổ sản phẩm và giỏ hàng: chữ rõ, bố cục như cũ.

## 6. Giới hạn kiểm thử (chưa kiểm)

- **Chưa đặt đơn thật, chưa đăng nhập Google, chưa thanh toán/báo chuyển khoản** — để tránh tạo dữ liệu trên database thật. Các luồng này không bị sửa code (đã kiểm bằng test), nhưng nên thử một đơn nhỏ trên bản xem trước trước khi đưa lên.
- Chưa kiểm trên Safari iPhone thật và máy Android cấu hình yếu (chỉ giả lập Chromium).
- Banner sự kiện, "Bạn vừa xem", outfit, đánh giá chỉ hiện khi có dữ liệu; đã có giao diện tối cho chúng nhưng database hiện chưa có dữ liệu để xem thực tế.
- Database hiện có 2 sản phẩm thử tên "Ok" và "Tr" (một sản phẩm dùng ảnh QR làm ảnh bìa). Nên ẩn/sửa trong trang quản trị trước khi bán.
- Font chữ tải từ Google Fonts; nếu mạng chặn, trang dùng font dự phòng (Georgia/hệ thống).

## 7. Chạy thử trên máy

```sh
npm run serve        # mở http://localhost:8080/
npm test             # chạy 10 test giao diện/nghiệp vụ
# tuỳ chọn, cần Python + Playwright:
python3 tools/luxe-visual-check.py http://localhost:8080/index.html
```

## 8. Đưa lên (khi chủ shop đồng ý)

1. Không cần chạy migration nào cho bản này.
2. Đẩy thư mục lên nhánh `main` → GitHub Actions tự xuất bản GitHub Pages như trước.
3. Mở trang, tải lại cứng (Ctrl+F5) và thử một đơn giá trị nhỏ.

**Quay lại bản cũ**: chép `backup/index-truoc-nang-cap-luxe.html` đè lên `index.html`. Hoặc xoá đoạn giữa `<!-- VERUS LUXE START` và `<!-- VERUS LUXE END -->` (banner mới vẫn hoạt động nhưng mất tông tối).

Lưu ý: GitHub Pages xuất bản cả thư mục gốc, nên `backup/` và `tools/` cũng truy cập công khai được (chỉ chứa nội dung vốn đã công khai). Có thể xoá chúng khỏi repo nếu không muốn.

## Bản v2 — Đồng bộ Dark Luxury cho toàn bộ cửa sổ chức năng
- Giỏ hàng, Yêu thích, Đăng nhập Google, Theo dõi đơn, Mã giảm giá, Chính sách, Trung tâm hỗ trợ, Chi tiết sản phẩm, Bảng size, Đặt hàng (checkout), Thanh toán QR, Tài khoản khách hàng, Hội thoại và thông báo nhỏ (toast) đều chuyển sang nền đen kính mờ, viền vàng mảnh.
- Nút Google dùng đúng logo 4 màu chính thức, tông tối theo hướng dẫn của Google.
- Chỉ thêm khối `<style id="verus-luxe-modals">` (nguồn: `tools/luxe/luxe-modals.css`). Không sửa script nghiệp vụ, Supabase, đơn hàng hay thanh toán (bài kiểm tra 10/10 đạt).
- Ảnh QR vẫn giữ nền trắng để ngân hàng quét được.
- Kiểm tra trực quan: `python3 -m http.server 8099` rồi chạy `python3 tools/audit_modals.py <thư-mục-ảnh>` và `python3 tools/audit_flows.py <thư-mục-ảnh> m`. Màn đặt hàng, thanh toán và tài khoản chỉ được dựng trên trình duyệt thử, không gửi đơn.
