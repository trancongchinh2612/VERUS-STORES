-- VERUS STORE: miễn phí vận chuyển toàn quốc cho mọi đơn hàng.
-- Không sửa lại các đơn cũ; chỉ áp dụng cho đơn tạo từ sau migration này.
insert into public.site_settings(key,value) values
 ('shipping_fee','0'::jsonb),
 ('free_shipping_threshold','0'::jsonb)
on conflict (key) do update set value=excluded.value, updated_at=now();
