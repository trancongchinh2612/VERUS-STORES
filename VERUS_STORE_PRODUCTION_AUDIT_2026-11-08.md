# VERUS STORE — Rà soát gói production

Ngày rà soát: 08/11/2026

## Kết quả kiểm tra

### Đã phát hiện và chỉnh trong gói này
1. Workflow GitHub Pages cũ xuất bản `path: .`, trong khi `index.html` ở thư mục gốc là offline demo. Bản website thật nằm trong `production/`. Đã đổi workflow thành `path: production`.
2. `production/config.js` còn URL và publishable key mẫu, dẫn đến URL `your_project_ref.supabase.co` và lỗi DNS. Đã thay bằng Project URL và Publishable key do chủ shop cung cấp trong cuộc trò chuyện.
3. Không đưa khóa `sb_secret` vào mã nguồn. Khóa secret đã được gửi trong chat nên phải thu hồi/rotate trước khi mở website thật.

### Kiểm thử tự động
- `npm test`: 9/9 test pass.
- `node --test tests/production-payment.test.js`: 5/5 test pass.
- Các test này là kiểm tra tĩnh trên mã nguồn, KHÔNG chứng minh Supabase production đã chạy, OAuth Google đã được bật, migration đã áp dụng hoặc thanh toán thật đã được đối soát.

## Việc bắt buộc chủ shop cần làm trên Supabase
1. Thu hồi khóa `sb_secret` đã lộ; không gửi secret mới vào chat hoặc frontend.
2. Mở đúng project `pjtjtllhrcmpvvgbzhcb` → SQL Editor. Chạy toàn bộ migration trong `production/supabase/migrations/` theo thứ tự tên file tăng dần. Đảm bảo chạy đủ đến `202611070003_payment_rpc_permissions_and_cache.sql`.
3. Authentication → Providers → bật Google và điền OAuth Client ID/Secret từ Google Cloud.
4. Authentication → URL Configuration: thêm URL trang Pages `https://trancongchinh2612.github.io/VERUS-STORES/` vào Site URL/Redirect URLs (và callback URL do Supabase hiển thị vào Google Cloud OAuth client).
5. Đăng nhập Google bằng tài khoản chủ shop; sau đó cấp role admin cho đúng email trong SQL Editor, ví dụ:

```sql
update public.profiles
set role = 'admin'
where id = (
  select id from auth.users
  where lower(email) = lower('EMAIL_CHU_SHOP_CUA_BAN')
);
```

6. Commit/push ZIP đã sửa lên repository. Chờ GitHub Actions → Deploy VERUS STORE to GitHub Pages hoàn tất xanh.
7. Thử đăng nhập, tạo đơn thử, báo chuyển khoản, kiểm tra trạng thái pending_review, rồi chỉ admin mới xác nhận sau khi thấy tiền thật vào tài khoản.

## Các giới hạn chưa thể xác nhận từ file ZIP
- Chưa thể xác nhận migration đã chạy trên Supabase thật hay chưa.
- Chưa thể xác nhận Google OAuth Client ID/Secret, danh sách redirect, domain callback của Google Cloud.
- Chưa thể xác nhận tài khoản admin đã được cấp role admin.
- Chưa thể xác nhận dữ liệu sản phẩm thật, tồn kho, chính sách hoàn/hủy và email hỗ trợ đã được cấu hình đúng.
- Chưa có kiểm thử end-to-end với Supabase thật hoặc giao dịch ngân hàng thật.

## Lưu ý chức năng tài khoản
Bản production hiện chỉ hỗ trợ đăng nhập bằng Google; đăng ký email/mật khẩu và đặt lại mật khẩu đang bị khóa có chủ ý trong `production/index.html`. Trigger `handle_new_user` tạo profile khi tài khoản Google mới được tạo. Nếu chủ shop muốn cả đăng ký email/mật khẩu, cần thay đổi yêu cầu và bổ sung luồng xác thực + xác minh email an toàn, không chỉ mở lại nút giao diện.

## Luồng thanh toán đã rà soát trong mã
COD: cọc 20%, còn 80% khi nhận hàng. Chuyển khoản: 100%. Nút khách báo đã chuyển khoản chỉ tạo yêu cầu đối soát; admin xác nhận thủ công. QR là ảnh tĩnh, khách cần đối chiếu đúng người nhận trước khi chuyển.

## Hai điểm cần chốt trước khi mở bán
- Danh mục mẫu có được seed, nhưng không thấy dữ liệu sản phẩm/biến thể/tồn kho mẫu trong các migration. Sau khi triển khai, cửa hàng có thể hiện rỗng cho đến khi admin thêm sản phẩm thật và nhập đủ biến thể/size/tồn kho/ảnh.
- Chủ shop từng yêu cầu có cả đăng ký và đăng nhập tài khoản; mã production hiện chỉ có Google OAuth, các hàm email/mật khẩu bị khóa. Đây là phần chưa đạt nếu yêu cầu vẫn là đăng ký email + mật khẩu. Cần triển khai lại giao diện và luồng `signUp`, `signInWithPassword`, xác minh email, quên mật khẩu bằng Supabase Auth trước khi coi là hoàn chỉnh.
