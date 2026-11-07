# VERUS STORE V5 — customer page QA notes

## Changes in V5

- Fixed the customer tracking RPC response so it includes `items` and chronological `events`, which the tracking UI expects.
- Tracking UI now handles missing arrays safely and displays order lines, total, COD deposit/balance or full-transfer due amount, and status history.
- Transfer reporting is a proper in-page form instead of `window.prompt`; the page tells the customer that reporting a transfer is not proof of payment.
- Added migration `202611060004_customer_tracking_payment_polish.sql`: consolidates older duplicate pending payment rows, prevents new duplicate pending rows per order/payment type, returns customer-safe tracking data, and updates an existing pending payment row when a customer reports a transfer again.
- Removed inconsistent shipping copy and corrected the customer page title to avoid an unsupported authenticity claim.
- Checkout now prefills customer name/phone only from the authenticated Supabase profile, not the legacy demo name.
- The customer page's Admin link now navigates to `admin.html` when the Supabase client is configured; when not configured it displays a setup message.
- Kept the address dataset and address selection behavior unchanged, as requested.

## Static verification performed

- `public/index.html`: 16 inline JavaScript blocks passed `node --check`.
- `public/admin.html`: 2 inline JavaScript blocks passed `node --check`.
- Static HTML scan: no duplicate IDs in either page.
- SQL migration dollar-quote delimiters balanced.
- New tracking function field names match the customer page (`items[].name`, `variant`, `size`, `qty`, `line_total`; `events[].status`, `note`, `at`).
- New pending-payment unique index is preceded by cleanup of older duplicate pending rows.
- ZIP integrity checked after packaging.

## Not verified / must test before launch

- No live SQL execution against the user's Supabase project was performed.
- No browser-based end-to-end checkout, Google OAuth redirect, QR scan, order tracking, admin confirmation, or mobile-device test was performed in this pass.
- No real bank webhook/reconciliation, carrier API, automatic bank refund, email/SMS/Zalo notification, or payment settlement is implemented.
- QR generation still requires correct receiving-account configuration. A QR image is not proof that money was received.
- Public order lookup is protected by requiring both order code and matching phone number, but production should additionally use edge/server rate limiting and monitoring against repeated guessing.
- Existing legacy/demo code remains in parts of the original HTML. Customer-facing checkout/account/admin actions are guarded by the production connection check; do not treat local demo finance or demo admin data as real transactions.

## Apply and test

If migrations through `202611060003_order_payment_safety.sql` are already applied, run only `202611060004_customer_tracking_payment_polish.sql` once. For a fresh Supabase project, run all migration files in filename order.

Then test in a staging project with test accounts and test products:

1. Empty cart: shipping 0, total 0, checkout disabled.
2. Add item: all orders remain free shipping; totals and discount match server calculation.
3. COD order: create order, show 20% deposit QR, remaining 80% due on delivery.
4. Full bank transfer: create order, show 100% QR, no COD balance.
5. Re-report a transfer: same pending payment row is updated; no second pending row appears.
6. Admin confirms once: second confirmation attempt is rejected.
7. Track by correct code + phone: items and full event timeline appear.
8. Track by wrong code or phone: no order details are returned.
9. Customer cancellation before shipping: stock/points/coupon usage restored once.
10. Customer/admin cancellation at shipping or later: database rejects it.
11. Refresh/retry after simulated network interruption: idempotency key returns the original order rather than creating a duplicate.
12. Test Google login, sign-out, mobile layout, image failures and browser back/refresh.
