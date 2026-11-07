# PremiumSlots mobile API (v1) — backend install

The iOS app talks to the live site through the JSON endpoints in
`api_v1.py`. The live site has no public JSON API today (see ANALYSIS.md
§3), so this blueprint is the missing half of the v2 app. Until it is
deployed, the app shows the bundled catalogue and says so plainly.

## What it adds

- `GET /api/v1/services` and `GET /api/v1/services/<id>` — live
  catalogue from the `Services` table (price, `inventory_count`).
- `POST /api/v1/auth/register`, `POST /api/v1/auth/login`,
  `POST /api/v1/auth/logout`, `GET /api/v1/auth/me` — JSON auth using
  the same Flask session cookie as the website.
- `GET /api/v1/me/subscriptions`, one-time vault reveal
  `GET /api/v1/me/subscriptions/<id>/vault`, `GET /api/v1/me/notifications`.
- `POST /api/v1/request` — manual M-PESA buy, mirroring web
  `POST /request`: 10-alphanumeric code, duplicate codes rejected,
  subscription created as Pending.
- `POST /api/v1/waitlist/join`, report-issue, toggle-auto-renew.
- `GET /api/v1/wallet`, `POST /api/v1/wallet/deposit`,
  `GET /api/v1/referrals`.
- Admin JSON: `POST /api/v1/admin/login` (password only, compared to
  the `ADMIN_PASSWORD` environment variable, session flag
  `admin_authenticated`), stats, pending subscriptions, approve with
  vault credentials, reject, customers, services create/edit/delete.
- `GET /api/v1/health`.

Nothing in this file contains a password, a secret, or the web admin
URL prefix. Admin API auth is the session flag only.

## Install on the laptop

1. Copy `api_v1.py` to the live project:
   `C:\Users\theegr8strr\Downloads\Projects\PremiumSlots\app\blueprints\api_v1.py`
2. In `app/__init__.py`, next to the other blueprint registrations
   (around lines 474-493), add:
   ```python
   from app.blueprints.api_v1 import api_v1
   app.register_blueprint(api_v1)
   ```
3. Push with the normal cPanel flow (`.cpanel.yml` copies the project
   to the server and touches `tmp/restart.txt`). Or, if the GitHub
   webhook is live, push to GitHub and let it pull and restart.
4. Check it live:
   ```text
   GET https://premiumslots.tech/api/v1/health
   -> {"ok": true, "service": "premiumslots", "api": "v1"}
   GET https://premiumslots.tech/api/v1/services
   -> {"ok": true, "services": [...], "platforms": 8, "slots_in_rotation": 67}
   ```
   The services list is public; every other endpoint needs a login
   session (user) or the admin session flag (admin).

## Notes

- The blueprint uses the same tables, columns and rules as the web
  code (see ANALYSIS.md §2, §5, §6). It does not invent a table or
  a field. `locked_price` is deliberately not used: the web code
  reads it but it is not in the `CREATE TABLE`, so it may not exist
  on production.
- Wallet balance reads `Users.wallet_balance`, which the web code
  reads elsewhere in the codebase.
- The vault endpoint mirrors the web one-time reveal: the first
  request after approval arms it, the second returns the credentials
  once and marks the subscription viewed.
- Rate limits from the web routes are not re-applied here; the
  existing Flask-Limiter setup on the app applies to the blueprint
  only if it is registered app-wide. If the admin wants per-route
  limits, add them in `app/__init__.py` the same way the web
  blueprints do.

## v3 additions (7 Nov 2026, Fix #1 + Fix #2)

- `POST /api/v1/auth/clerk-sync` — accepts a Clerk session token, verifies
  it server-side with the Clerk Backend API (`CLERK_SECRET_KEY` env var,
  never in code), finds or creates the Users row, sets the Flask session,
  returns the user + `needs_onboarding`.
- `POST /api/v1/auth/forgot-password` + `POST /api/v1/auth/reset-password`
  — 15-minute reset token, always returns success (no enumeration),
  strong-password rule (8+ chars, upper + lower + digit).
- `POST /api/v1/auth/verify` — legacy 6-digit email verification code.
- `POST /api/v1/auth/magic` + `POST /api/v1/auth/magic/consume` —
  one-time magic-link sign-in, via the web's own helpers in `app/utils.py`.
- `GET/POST /api/v1/me/onboarding` (+ `POST /api/v1/auth/onboarding`
  alias) — WhatsApp number + date of birth after Clerk sign-in.
- `GET /api/v1/me/sessions` + `POST /api/v1/me/sessions/revoke` —
  LoginActivity rows (max 3 sessions per user on the web).
- Fixed: `GET /api/v1/referrals` now queries `referrer_id` (was the
  non-existent `user_id` column) and returns counts, my code, referral
  link and inviter. `_subscription_row` now returns the real `created_at`
  and `locked_price` when present.

### CSRF: the 9 new POST endpoints must be exempted on deploy

The site's `protect_post_requests` guard in `app/__init__.py` exempts by
endpoint name. Add these to `exempt_endpoints` in the same deploy commit
(the 14 v2 entries went in as commit 3a0c88a):

```
"api_v1.clerk_sync",
"api_v1.forgot_password",
"api_v1.reset_password",
"api_v1.verify_email",
"api_v1.magic_link",
"api_v1.magic_consume",
"api_v1.post_onboarding",
"api_v1.post_onboarding_alias",
"api_v1.revoke_session",
```

Until they are exempted, each one returns 400 "Invalid or missing CSRF
token" live. Session auth still applies to every one of them.

## Fix #4 additions (7 Nov 2026, customer + admin parity, PARITY_CHECKLIST.md §6.2/§6.3)

`api_v1.py` grew from 1,215 to ~5,291 lines (151 routes total, 110 new).
All new endpoints mirror web routes/tables in ANALYSIS.md; tables or
columns whose existence is unconfirmed on production (e.g.
`locked_price`, `wallet_balance`, `GiftCards`/`Coupons` column sets)
are accessed through guarded helpers (`_table_columns`,
`_insert_row`, `_update_row`) that fall back to empty lists / defaults
instead of crashing the endpoint. No new table or field is invented.

### Customer (user session required unless noted)

- `GET /api/v1/me/dashboard` — subs + FinancialLedger (last 50) +
  waitlist positions + unread count + `global_alert` (Settings).
- `GET /api/v1/me/waitlist`, `GET/POST /api/v1/suggestions`
  (public GET: top 10 by votes).
- `POST /api/v1/coupons/validate` — previews the discount
  (`validate_coupon` rules: active, expiry, max redemptions,
  min amount, per-user limit, customer type, service restriction,
  percent/flat with max discount).
- `POST /api/v1/request` is now gateway-aware (existing endpoint,
  response shape unchanged for manual M-PESA): `payment_method`
  `mpesa` (default, status Pending) / `stk` / `wallet`. Wallet pays
  instantly with the KES 25,000 daily velocity cap, reference
  `WALLET-NEW-<hex>` / `WALLET-RNW-<hex>`; a wallet renewal is
  Approved immediately with extended expiry. Locked (grandfathered)
  price wins when a previous subscription for that user+service
  carries one; a valid coupon reduces the amount.
- `GET /api/v1/checkout/status/<ref>`,
  `POST /api/v1/pay/retry/<id>`,
  `POST /api/v1/pay/verify-manual/<id>` (records a manual
  verification request; the IntaSend status-check call shape is not
  in the workspace).
- `POST /api/v1/wallet/instant-renew/<id>`,
  `POST /api/v1/wallet/redeem-gift-card`,
  `GET /api/v1/wallet/statement` (JSON) +
  `GET /api/v1/wallet/statement/pdf` (PDF bytes).
  `GET /api/v1/wallet` now also returns `metrics`
  (total deposited/spent/redeemed), `denominations`
  [200, 500, 1000, 2000, 5000], `renewable_subscriptions` and
  `daily_spend_limit` (25,000).
- `GET /api/v1/me/subscriptions/<id>/timeline` (OrderEvents, with a
  fallback timeline from the subscription row),
  `POST /api/v1/me/subscriptions/<id>/request-review`.
- `GET/POST /api/v1/gift-cards`, `POST /api/v1/gift-cards/redeem`,
  `GET /api/v1/gift-cards/verify/<code>` (public).
- `GET /api/v1/store`, `POST /api/v1/store/redeem/<id>`
  (discount_coupon rewards generate a `PS-XXXXXXXX` code).
- `GET /api/v1/me/loyalty` (points, tier, next tier, streak,
  LoyaltyLedger), `GET /api/v1/me/achievements`
  (BadgeDefinitions + earned set + stats),
  `GET /api/v1/leaderboard` (public: monthly + all-time).
- `GET /api/v1/wishlist` (`category`/`status`/`sort`/`q`),
  `POST /api/v1/wishlist/vote|notify|submit`.
- `POST /api/v1/feedback`, `GET /api/v1/me/tickets`,
  `POST /api/v1/tickets`.
- `GET /api/v1/help`, `GET /api/v1/help/<slug>` (public),
  `GET /api/v1/blog`, `GET /api/v1/blog/<slug>` (public).
- `GET /api/v1/receipts/<id>` (PDF bytes),
  `GET /api/v1/receipts/verify?payload=&signature=` (public).
- `GET/POST /api/v1/me/gdpr-consent`,
  `POST /api/v1/me/export-request`.
- `PUT /api/v1/me/profile`, `POST /api/v1/me/password`,
  `PUT /api/v1/me/privacy`, `DELETE /api/v1/me`
  (requires `{"confirm": true}`), `GET/POST /api/v1/me/birthday`.
- `POST /api/v1/me/notifications/read`; `GET /api/v1/me/notifications`
  now also returns `unread_count`.

### Admin (admin session flag required on every one)

- `GET /api/v1/admin/analytics` (`days`/`service`/`status` filters,
  daily revenue from FinancialLedger; churn returns the real list
  only if `_build_churn_users` imports from the web admin module —
  otherwise the web stub's empty list, with a note),
  `GET /api/v1/admin/financial-engine`,
  `GET /api/v1/admin/export/csv` (`kind=subscriptions|customers|ledger`),
  `GET /api/v1/admin/report/pdf`.
- Subscriptions: `POST /api/v1/admin/subscriptions/bulk-update`,
  `PUT /api/v1/admin/subscriptions/<id>`,
  `POST .../renew`, `POST .../cancel`, `DELETE ...`,
  `POST .../unhide` (returns vault credentials to the admin only),
  `POST .../remind-expiry`.
- Customers: `POST .../toggle-emails`, `DELETE /api/v1/admin/customers/<id>`,
  `POST .../adjust-wallet`, `POST .../adjust-points`,
  `POST .../reset-password` (returns a one-time temporary password),
  `POST .../send-email`, `POST /api/v1/admin/customers`,
  `GET /api/v1/admin/customers/export`,
  `POST /api/v1/admin/customers/bulk-action`.
- Wallet: `GET /api/v1/admin/wallet`,
  `POST /api/v1/admin/wallet/deposit/<id>/approve|reject`,
  `POST /api/v1/admin/wallet/adjust`.
- Gift cards: `GET /api/v1/admin/gift-cards`,
  `POST /api/v1/admin/gift-cards/issue|resend|approve|reject`,
  `POST /api/v1/admin/settings/gift-cards`.
- `GET /api/v1/admin/transactions`,
  `POST /api/v1/admin/transactions/<id>/verify`,
  `GET/POST /api/v1/admin/payment-methods`,
  `POST /api/v1/admin/settings/gateway`.
- Coupons: `GET/POST /api/v1/admin/coupons`,
  `PUT/DELETE /api/v1/admin/coupons/<id>`,
  `GET .../<id>/redemptions`, `POST /api/v1/admin/coupons/blast`.
- Blog/help: `GET/POST /api/v1/admin/blog`,
  `PUT/DELETE /api/v1/admin/blog/<id>`, same for `/admin/help`.
- `GET /api/v1/admin/tickets`,
  `POST /api/v1/admin/tickets/<id>/resolve|delete`,
  `POST /api/v1/admin/waitlist/message`,
  `GET /api/v1/admin/suggestions`,
  `DELETE /api/v1/admin/suggestions/<id>` (id is the service name —
  SuggestedServices has no id column in ANALYSIS.md).
- `POST /api/v1/admin/bulk-email`, `POST /api/v1/admin/broadcast`,
  `POST /api/v1/admin/settings/promo-banner`.
- `GET /api/v1/admin/security-logs` (AuditLog, LoginActivity fallback),
  `POST /api/v1/admin/security-logs/purge`,
  `POST /api/v1/admin/security-logs/revoke/<id>`.
- `GET /api/v1/admin/recycle-bin`,
  `POST /api/v1/admin/recycle-bin/restore`.
- `GET /api/v1/admin/backup/status` — tables + row counts ONLY.
  Backup download/upload/restore stay web-only by design (§6.4).

### Deliberately NOT built

- WebAuthn passkeys (6 JSON endpoints): the workspace has only the
  route list (`auth.py:479-759`, webauthn 3.x, `WebAuthnCredentials`
  table). Missing and needed before anyone builds them: RP id/name,
  origin, the session key the challenge is stored under, credential
  field names, and the webauthn 3.x begin/complete call shapes.
- Raw DB query endpoint, backup download/upload, fix-db, spin wheel,
  cron/SEO routes (checklist §6.4).
- Clerk Backend API calls (ban/unban/delete/provision): the existing
  `toggle-ban` does local DB only, so no new Clerk call was added.
  Customer create/delete and account delete do the local DB action
  and carry a `TODO server-side` code comment for the Clerk sync
  (env var name `CLERK_SECRET_KEY` only, never a value). Note:
  contrary to the checklist's assumption, the deployed `toggle-ban`
  does NOT do a Clerk sync — that gap is unchanged, flagged here
  rather than silently "fixed" by adding a new Clerk call.

### Deploy-time verification needed (live Flask app / PostgreSQL)

- **STK push**: `POST /request` with `payment_method=stk` calls
  `app.intasend_client.intasend_client.initiate_stk_push(amount,
  phone, email, narrative=...)` when that module is importable. If
  it is not importable (or the call fails), the endpoint still creates
  the subscription as `Initiated` with a placeholder
  `tuma_reference` (`INTASEND-INIT-<id>`) and returns
  `stk_initiated: false` + a note — verify the import path and the
  return shape (`invoice_id` / `checkout_request_id` /
  `merchant_request_id`) on the live app before relying on a real
  push. The same applies to `POST /pay/retry/<id>` (returns 503 when
  no live push can be made) and `POST /pay/verify-manual/<id>`
  (records a manual verification request; the IntaSend status-check
  call shape is not in the workspace).
- **Receipt HMAC**: `GET /api/v1/receipts/verify` checks the
  HMAC-SHA256 signature only when env `RECEIPT_HMAC_KEY` (fallback
  `SECRET_KEY`) is set; otherwise it verifies by subscription
  existence only and says so in the response. Confirm the key matches
  the web's `sign_receipt`/`verify_receipt` key before trusting it.
- **Exact column sets** for `Coupons`, `GiftCards`, `RewardItems`,
  `SupportTickets`, `WishlistItems`, `BlogPosts`, `HelpArticles`,
  `BadgeDefinitions`, `LoyaltyLedger`, `StreakLedger`,
  `NotificationQueue` (read flag), `Settings` (key/value), `AuditLog`,
  `Archive_Users`/`Archive_Subscriptions` were not in the workspace;
  the guarded helpers tolerate missing columns, but live behaviour
  (e.g. coupon validation, gift-card create fields, security-log
  source table) must be checked against the production schema.
- **Churn**: verify whether `_build_churn_users` is importable from
  the live admin module; otherwise analytics returns the web stub's
  empty churn list, as documented in the response.
- **PDFs** (receipt, wallet statement, admin report) are generated by
  a minimal built-in PDF writer in the blueprint, not fpdf2 as on the
  web — same fields, equivalent printable bytes; check the layout
  live once.

### CSRF: the 69 new POST/PUT/DELETE endpoints must be exempted on deploy

Add these endpoint names to `exempt_endpoints` in
`protect_post_requests` (`app/__init__.py`), alongside the v2 list
(commit 3a0c88a) and the v3 list above. Until they are exempted, each
one returns 400 "Invalid or missing CSRF token" live. Session auth
still applies to every one of them.

```
"api_v1.submit_suggestion",
"api_v1.validate_coupon_endpoint",
"api_v1.pay_retry",
"api_v1.pay_verify_manual",
"api_v1.wallet_instant_renew",
"api_v1.wallet_redeem_gift_card",
"api_v1.request_review",
"api_v1.create_gift_card",
"api_v1.redeem_gift_card",
"api_v1.redeem_reward",
"api_v1.wishlist_vote",
"api_v1.wishlist_notify",
"api_v1.wishlist_submit",
"api_v1.submit_feedback",
"api_v1.create_ticket",
"api_v1.post_gdpr_consent",
"api_v1.export_request",
"api_v1.update_profile",
"api_v1.change_password",
"api_v1.update_privacy",
"api_v1.delete_account",
"api_v1.post_birthday",
"api_v1.mark_notifications_read",
"api_v1.admin_subscriptions_bulk_update",
"api_v1.admin_update_subscription",
"api_v1.admin_renew_subscription",
"api_v1.admin_cancel_subscription",
"api_v1.admin_delete_subscription",
"api_v1.admin_unhide_subscription",
"api_v1.admin_remind_expiry",
"api_v1.admin_toggle_emails",
"api_v1.admin_delete_customer",
"api_v1.admin_adjust_wallet",
"api_v1.admin_adjust_points",
"api_v1.admin_reset_customer_password",
"api_v1.admin_send_customer_email",
"api_v1.admin_create_customer",
"api_v1.admin_customers_bulk_action",
"api_v1.admin_wallet_deposit_approve",
"api_v1.admin_wallet_deposit_reject",
"api_v1.admin_wallet_adjust",
"api_v1.admin_issue_gift_card",
"api_v1.admin_resend_gift_card",
"api_v1.admin_approve_gift_card",
"api_v1.admin_reject_gift_card",
"api_v1.admin_settings_gift_cards",
"api_v1.admin_verify_transaction",
"api_v1.admin_update_payment_methods",
"api_v1.admin_settings_gateway",
"api_v1.admin_create_coupon",
"api_v1.admin_update_coupon",
"api_v1.admin_delete_coupon",
"api_v1.admin_coupon_blast",
"api_v1.admin_create_blog",
"api_v1.admin_update_blog",
"api_v1.admin_delete_blog",
"api_v1.admin_create_help",
"api_v1.admin_update_help",
"api_v1.admin_delete_help",
"api_v1.admin_resolve_ticket",
"api_v1.admin_delete_ticket",
"api_v1.admin_waitlist_message",
"api_v1.admin_delete_suggestion",
"api_v1.admin_bulk_email",
"api_v1.admin_broadcast",
"api_v1.admin_settings_promo_banner",
"api_v1.admin_security_logs_purge",
"api_v1.admin_security_logs_revoke",
"api_v1.admin_recycle_bin_restore",
```
