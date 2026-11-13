# VERUS STORE V13 — báo cáo (bản vá một phần, CHƯA kiểm thử thực tế)

## Đã làm
| # | Vấn đề | Nguyên nhân (bằng chứng trong mã) | Sửa |
|---|---|---|---|
| 1 | Bấm "Gửi đơn hàng" không thấy gì | `.modalbg{z-index:100!important}` che `.toast{z-index:50}` nên mọi thông báo lỗi bị khuất sau cửa sổ đặt hàng | Toast z-index 100000; lỗi hiện ngay trong form (#ckErr); mã lỗi SQL được dịch sang tiếng Việt |
| 2 | Đặt hàng có thể lỗi 42883 | `place_order` pin `search_path=public,auth` nhưng gọi `gen_random_bytes` (pgcrypto thường ở schema `extensions`) — CẦN KIỂM CHỨNG trên DB thật | Migration tạo `public.gen_random_bytes` nếu chưa có |
| 3 | Tim yêu thích không đỏ | `vIsWished` chỉ đọc localStorage/`__customerData`; khách đã đăng nhập thì luôn false | Một nguồn `V.wishSet` (đồng bộ khi đăng nhập/bấm/bỏ), tim đỏ |
| 4 | Chỉ liên hệ Zalo | Trung tâm hỗ trợ ghi "chưa phải chat trực tiếp"; admin chỉ có sổ ghi chú cục bộ, không đọc `chat_threads` | Nút "Nhắn trực tiếp trên website", khung chat tự cập nhật 4s, trang admin "Tin nhắn website" (5s) |
| 5 | Lỗ hổng bảo mật | khách tự sửa `points`; admin/anon gọi RPC; spam chat/events; sổ cái sửa được | Migration 202611070001 |

## Chưa làm / chưa kiểm chứng
- Tổng tiền bất thường 2.000.000.000: KHÔNG tìm được nguyên nhân trong bản V5 này (giá lưu `bigint`, tính ở server). Cần dữ liệu sản phẩm thật hoặc bản file đang chạy.
- Ảnh chụp site đang chạy có nút "Chat Zalo" và khối "Nhắn Zalo với shop" — KHÔNG có trong zip V5, nên site thật là bản khác. Cần file index.html/admin.html đang deploy để vá đúng.
- Không có kiểm thử trình duyệt, Google OAuth, QR, Supabase. Chỉ kiểm tra cú pháp JS (node --check).
- Chưa gỡ code demo, chưa gộp checkout, chưa đổi QR sang MB Bank, chưa làm refund hoàn kho, ghi COD, đối soát.
