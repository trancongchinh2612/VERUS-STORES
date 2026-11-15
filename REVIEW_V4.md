# VERUS STORE V5 — customer-page review and fixes

## Changes carried forward from V4 and added in V5

- Free shipping is enforced in the checkout RPC for every new order; `shipping_fee` is written as zero. Empty-cart checkout remains blocked by the customer page and by `place_order`.
- The checkout idempotency key is retained in the browser session for the same cart, so a retry after a network interruption can return the existing order instead of creating a duplicate.
- Payment reporting updates the existing pending payment row for the order/payment type rather than creating a new pending row every time the customer reports a transfer.
- Admin confirmation only accepts a pending payment once, checks the amount against the unpaid amount due, and writes the ledger credit once.
- Admin rejection only accepts a pending payment and recalculates the order's payment state.
- Customer and admin cancellation now go through guarded database functions. Cancellation is rejected at `shipping` or later and when a payment has already been confirmed. For eligible cancellations, the database restores reserved size stock, redeemed points, and coupon usage, rejects pending payment reports, writes an order event, and audits the action.
- Admin bulk cancellation verifies website orders on Supabase before changing the local admin copy.
- Customer order details distinguish COD deposit/balance from full bank transfer, show free shipping, and display the confirmed payment amount using the order's safe customer-readable status field.
- Zero-total orders do not create a zero-value pending payment.
- Customer order tracking now receives a complete, customer-safe payload from SQL: order line items and chronological status events, matching the exact fields consumed by the page.
- Tracking UI handles missing item/event arrays safely and clearly distinguishes COD deposit/balance from 100% bank transfer.
- Customer transfer reporting uses a proper form instead of a browser prompt, validates the reference field, and explicitly tells customers that a report is not payment confirmation.
- Migration 004 consolidates older duplicate pending payment rows, adds a partial unique index to prevent new pending duplicates, and redefines the tracking and transfer-report RPCs.
- Customer-facing shipping copy is consistent with free shipping on every order.
- Setup documentation and pre-launch test checklist were updated.

## Static checks performed

- V5 customer and admin HTML syntax checks are recorded in the package QA report.
- No duplicate HTML IDs were found by the static scan.
- SQL migration dollar-quote delimiters were checked for balance; migration order and expected functions were inspected.
- ZIP integrity was checked after packaging.

## Not represented as completed

- No live Supabase SQL execution or end-to-end test was possible from this source-only review. Run the migrations in a staging Supabase project first.
- No bank transaction webhook/reconciliation provider is connected. QR generation is not proof of receipt; staff must verify the actual bank transaction before confirming a payment.
- No automatic bank refund, carrier booking/tracking API, email/SMS/Zalo delivery notification, or live payment settlement is included.
- Some legacy/demo administrative UI code remains in the HTML source. The production guard blocks customer checkout/account/admin operations when Supabase is unavailable, but this package has not had a full browser penetration/security test.
- CRM, wallet/withdrawal, review, chat, coupon and product-media modules still require end-to-end testing against real staff/customer accounts before production use.

## Required rollout

1. Back up the current GitHub repository and Supabase database.
2. Replace the repository contents with this package.
3. If migrations `202611040001` through `202611060003` have already been applied successfully, run only `202611060004_customer_tracking_payment_polish.sql`. If starting from a fresh project, run every migration in filename order.
4. Test with a separate staging Supabase project and test customer/admin accounts. Do not test by moving real customer orders or real money.
5. Configure receiving bank account details with the adult account holder responsible for the shop. Never publish passwords, OTPs, database credentials, service-role keys or webhook secrets.

## V5 additions

See `docs/QA_V5.md` for the V5 customer-page fixes, static checks, known limits, and staging test matrix. V5 adds migration `202611060004_customer_tracking_payment_polish.sql`; apply it after migration 003 only when 001–003 have already succeeded.
