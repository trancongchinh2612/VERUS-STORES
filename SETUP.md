# Hướng dẫn triển khai VERUS STORE

## A. Tạo Supabase project

1. Tạo project mới trong Supabase.
2. Lưu Project URL, anon/publishable key và database password ở nơi an toàn.
3. Không chia sẻ database password hoặc `service_role` key.

## B. Tạo database

Mở Supabase → SQL Editor → New query. Chạy lần lượt:

1. `supabase/migrations/202611040001_core_schema.sql`
2. `supabase/migrations/202611040002_functions.sql`
3. `supabase/migrations/202611040003_rls_storage.sql`
4. `supabase/migrations/202611060001_order_payment_init.sql`
5. `supabase/migrations/202611060002_free_shipping_all_orders.sql`
6. `supabase/migrations/202611060003_order_payment_safety.sql`
7. `supabase/migrations/202611060004_customer_tracking_payment_polish.sql`
8. `supabase/migrations/202611070001_v13_hardening.sql` (sửa lỗi đặt hàng do pgcrypto, khóa cột profiles, chống spam, v.v.)

Nếu SQL báo lỗi do policy/bucket đã tồn tại hoặc do project có schema cũ, dừng lại và kiểm tra trước khi chạy lại. Không xóa dữ liệu production để xử lý lỗi migration.

## C. Bật Google Login cho khách

1. Google Cloud Console → tạo OAuth Client ID loại Web.
2. Trong Supabase → Authentication → URL Configuration, đặt Site URL thành URL GitHub Pages của bạn.
3. Thêm Redirect URL:
   - `http://localhost:8080/**` khi chạy local.
   - `https://YOUR_GITHUB_USERNAME.github.io/**` khi chạy GitHub Pages.
   - Nếu dùng custom domain, thêm đúng domain đó.
4. Supabase → Authentication → Providers → Google → bật provider và nhập Google Client ID + Client Secret.
5. Trong Google Cloud Console, thêm Supabase callback URL được hiển thị trong phần Google provider của Supabase vào Authorized redirect URIs.
6. Không đặt Google Client Secret trong `config.js` hoặc GitHub.

## D. Cấu hình website

Mở `public/config.js`, điền:

```js
window.VERUS_CONFIG = {
  SUPABASE_URL: "https://YOUR_PROJECT_REF.supabase.co",
  SUPABASE_ANON_KEY: "YOUR_ANON_OR_PUBLISHABLE_KEY"
};
```

Chỉ dùng anon/publishable key. Không dùng `service_role`.

## E. Tạo tài khoản Admin

1. Mở website khách trên domain đã deploy và đăng nhập Google ít nhất một lần, để trigger tạo profile.
2. Supabase → Authentication → Users, sao chép UUID của tài khoản chủ shop.
3. Chạy SQL sau, thay UUID bằng UUID thật:

```sql
update public.profiles
set role = 'admin'
where id = 'PUT_AUTH_USER_UUID_HERE';
```

4. Trang `admin.html` hiện dùng đăng nhập email/password Supabase. Tài khoản admin phải có email/password hợp lệ trong Supabase Auth. Có thể tạo user quản trị riêng trong Authentication → Users → Add user, sau đó gán role `admin` bằng UUID của user đó.
5. Không cấp role admin cho tài khoản khách thông thường.

## F. Deploy GitHub Pages

1. Tạo repository GitHub.
2. Upload toàn bộ nội dung thư mục này, giữ nguyên cấu trúc.
3. Vào Settings → Pages.
4. Source: **GitHub Actions** (GitHub Pages không cho chọn thư mục `/public` khi deploy từ branch — chỉ có `/` hoặc `/docs`).
5. Workflow `.github/workflows/pages.yml` tự đóng gói thư mục `public` mỗi lần push vào `main`.
6. Đợi workflow chạy xong để có URL.
7. Thêm URL này vào Supabase Auth → URL Configuration → Redirect URLs.
8. Mở `index.html` và `admin.html` qua URL GitHub Pages.

Nếu muốn deploy qua GitHub Actions, workflow mẫu nằm trong `.github/workflows/pages.yml`.

## G. Storage

Migration tạo bucket `product-media` dạng public để ảnh sản phẩm hiển thị công khai. Chỉ staff/admin đã xác thực mới được upload, sửa hoặc xóa object qua policy.

## H. Kiểm thử bắt buộc trước khi bán thật

- Khách đăng nhập Google, đăng xuất, đăng nhập lại.
- Khách thường không đọc được đơn của người khác.
- Tài khoản customer không thể vào Admin hoặc sửa sản phẩm.
- Tài khoản staff không thể sửa role, giá vốn hoặc cấu hình nhạy cảm.
- Admin tạo sản phẩm có nhiều màu/size; khách nhìn thấy đúng ảnh và tồn kho.
- Giỏ hàng rỗng không có phí ship, tổng 0đ và không thể checkout.
- Đơn có hàng: miễn phí vận chuyển; database phải lưu shipping_fee = 0.
- Đặt đơn COD: cọc 20% (hoặc tỷ lệ cấu hình), phần còn lại thu khi giao.
- Đặt đơn chuyển khoản: thanh toán 100%, không phát sinh COD.
- Thử báo chuyển khoản nhiều lần: chỉ cập nhật một payment pending, không tạo payment trùng.
- Thử xác nhận cùng payment hai lần: lần hai phải bị từ chối, không tăng ledger lần nữa.
- Hủy đơn trước trạng thái shipping: tồn kho/điểm/coupon được hoàn đúng một lần.
- Thử hủy khi status = shipping: backend phải từ chối, kể cả gọi RPC trực tiếp.
- Thử hủy đơn đã có tiền xác nhận: backend phải từ chối và hướng dẫn shop xử lý hoàn tiền.
- Hai lần bấm đặt hàng không tạo hai đơn (idempotency key).
- Tồn kho không âm khi hai khách đặt gần nhau.
- Shop đối soát thanh toán; không có tự động xác nhận tiền.
- Test đổi trạng thái, vận đơn, hoàn tiền, review và chat.
- Kiểm tra RLS bằng hai tài khoản khác nhau.

## I. Các phần cần kiểm thử/hoàn thiện riêng

- Các module CRM, ví/sổ cái và rút tiền là nghiệp vụ nhạy cảm; cần review quy trình kế toán trước khi sử dụng.
- SQL nền này không tích hợp ngân hàng, cổng thanh toán, email/Zalo hay tự động vận chuyển.
- Chưa có kiểm thử trực tiếp trên project Supabase thật; phải chạy migrations ở staging và kiểm thử trước khi nhận tiền thật.

## VERUS STORE order-confirmation hours

The customer checkout and Admin order list display the shop confirmation windows in Vietnam time (UTC+7): **05:00–07:00, 11:00–13:00, and 16:00–24:00**. Orders submitted outside these windows remain recorded and are handled in the next confirmation window. These are shop order-review hours, not a promise of automatic payment reconciliation. The QR is shown after the order is successfully saved; payment is only marked received after a verified transaction or trusted admin confirmation.

## Techcombank QR checkout

The customer checkout uses VietQR Quick Link to render an amount-specific QR after the order is successfully saved. The Quick Link format is documented at https://www.vietqr.io/qr-dong.

In `public/config.js`, the adult account holder managing the store must set `BANK_ACCOUNT_NUMBER` and `BANK_ACCOUNT_NAME`. `BANK_BIN` is prefilled as `970407` (Techcombank). These are public receiving-account details shown to customers; do not put passwords, OTPs, API secrets, webhook secrets, or Supabase service-role keys here. If the account details are blank, the order is still saved but the checkout intentionally warns customers not to transfer until a valid QR can be displayed.

The migration `202611060001_order_payment_init.sql` creates a pending payment record for each new order with an amount due. Zero-total orders do not need a transfer. Pending does not mean paid. A payment must only be marked confirmed after a verified bank transaction webhook or a trusted admin confirmation. Migration `202611060003_order_payment_safety.sql` prevents duplicate payment confirmation, reuses the pending payment row when a customer reports a transfer, applies server-side free shipping, and adds guarded cancellation with inventory/points/coupon restoration. Cancellation is blocked once status is `shipping` or later; confirmed receipts require manual refund handling.


### Chính sách vận chuyển VERUS STORE
- Miễn phí vận chuyển toàn quốc cho mọi đơn hàng, không yêu cầu giá trị đơn tối thiểu.
- Giỏ hàng trống: phí vận chuyển 0đ, tổng thanh toán 0đ và ẩn nút đặt hàng.
- Migrations `202611060002_free_shipping_all_orders.sql` và `202611060003_order_payment_safety.sql` cập nhật cấu hình và ép phí vận chuyển = 0 ở server cho đơn mới; đơn cũ giữ nguyên số liệu lịch sử.


## V5 customer-page update

If the existing database has successfully applied migrations through `202611060003_order_payment_safety.sql`, apply `supabase/migrations/202611060004_customer_tracking_payment_polish.sql` once. This fixes the public order-tracking payload (items + timeline) and prevents duplicate pending payment rows. For a new database, apply all migration files in filename order.

After applying, test order tracking with both the correct order code and matching phone number. The lookup returns only order summary, item lines, payment method/amounts, carrier/tracking details and status history; it does not return the customer's street address. Test repeated transfer reports and confirm they update one pending payment row rather than creating duplicates.

## V5 customer tracking and payment-report patch

When the database already has migrations through `202611060003_order_payment_safety.sql`, run `supabase/migrations/202611060004_customer_tracking_payment_polish.sql` once. It repairs the tracking response and protects against duplicate pending payment records. For a new project, run all migrations in filename order. Review `docs/QA_V5.md` and perform its staging test checklist before production.
