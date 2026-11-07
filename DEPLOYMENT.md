# VERUS STORE — hướng dẫn triển khai

1. Sao lưu database hiện tại trước khi chạy migration mới.
2. Kiểm tra các migration đã áp dụng; chỉ chạy các migration còn thiếu theo thứ tự tên. Không chạy lại các migration cũ đã chỉnh tay trên production.
3. Chạy `202611070002_checkout_payment_hardening.sql` sau `202611070001_v13_hardening.sql`.
4. Kiểm tra Google OAuth trong Supabase: Site URL và Redirect URLs phải có `https://trancongchinh2612.github.io/VERUS-STORES/` và URL local nếu dùng.
5. Đảm bảo GitHub Pages dùng GitHub Actions. Workflow đã nằm ở `.github/workflows/pages.yml` và deploy thư mục gốc.
6. Đẩy toàn bộ repository lên nhánh `main`; đợi workflow Pages hoàn tất.
7. Kiểm tra trang khách `/VERUS-STORES/` và trang quản trị `/VERUS-STORES/admin.html`. Tài khoản quản trị phải có `profiles.role` là `admin` hoặc `staff`.
8. Đặt một đơn thử có kiểm soát trên staging trước. COD phải có `deposit_amount = ceil(total*20%)`, `balance_amount = total-deposit_amount`; chuyển khoản phải có `deposit_amount = total`, `balance_amount = 0`. Đối chiếu QR MB Bank và nội dung `transfer_reference` trước khi nhận tiền thật. Nếu khách đã báo chuyển khoản (`pending_review`), cần xử lý đối soát/từ chối khoản báo trước khi hủy đơn.

Không xác nhận thanh toán dựa trên ảnh chụp hoặc nút “đã chuyển”. Admin chỉ xác nhận sau khi đối soát giao dịch ngân hàng. Việc hủy đơn đã có khoản thanh toán được xác nhận bị chặn; hoàn tiền phải được xử lý thực tế riêng.
