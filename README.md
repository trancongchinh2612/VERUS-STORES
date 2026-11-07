# VERUS STORE

Customer storefront (`index.html`) and administration (`admin.html`) share one Supabase project. The browser uses only the public publishable/anon key; never commit a `service_role` key, database password, OAuth client secret, or other privileged credential.

## Local preview

```sh
npm run serve
```

Open `http://localhost:8080/` for the store and `http://localhost:8080/admin.html` for administration.

## Supabase

Apply the SQL files in ascending filename order in the Supabase SQL Editor (or with the Supabase CLI). Existing applied migrations must not be edited retroactively. The latest hardening migration is `202611070002_checkout_payment_hardening.sql`.

The admin account must have `profiles.role` set to `admin` or `staff` for the intended permissions. Do not disable RLS. Configure Google OAuth redirect URLs in Supabase Authentication for the production GitHub Pages URL and local preview URL.

## GitHub Pages

The repository root is the Pages artifact. The workflow is `.github/workflows/pages.yml`; it deploys the root containing `index.html`, `admin.html`, `config.js`, and `.nojekyll`. For the current project site, use `https://trancongchinh2612.github.io/VERUS-STORES/` and `/VERUS-STORES/admin.html`.

## Public configuration

`config.js` contains the Supabase project URL, publishable key, public MB Bank receiving details used by VietQR, and the official Zalo link. These values are intentionally public. Never add a Supabase secret/service-role key.

Payment terms are enforced in SQL: COD prepays 20% and collects 80% on delivery; bank transfer prepays 100% and has zero delivery balance. A customer report is not proof of receipt: staff must verify the actual bank transaction and confirm it in Admin.
