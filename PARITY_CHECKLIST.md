# PremiumSlots — Web-to-App Parity Checklist (100% feature + auth parity)

Audited 7 November 2026, read-only, from the live project on Kerry's laptop:
`C:\Users\theegr8strr\Downloads\Projects\PremiumSlots` (Flask + PostgreSQL, cPanel).
Audit scripts ran on the laptop and were deleted afterwards (verified: `dir _audit*` = File Not Found).
Builds on [ANALYSIS.md](sandbox://workspace/premiumslots-ios/ANALYSIS.md) (920 lines, 7 Nov 2026) — this file does not
repeat it; it verifies the facts that matter for parity and adds what ANALYSIS.md did not cover
(Clerk flow in full, theme tokens, the exact loader, launch-logo diagnosis, per-feature API gaps).

## How to read this file

- Each item is a checkbox. `- [ ]` = not in the v2 iOS app yet. `- [x]` = already in v2 (or in the
  deployed API). Check items off only after they are verified on a real device against the live site.
- **Web route** = the exact Flask route/template/function. **API** = status of the deployed
  `/api/v1` blueprint (`backend/api_v1.py`, live since 7 Nov 2026, commit 6ccc8ed; CSRF exemption
  commit 3a0c88a):
  - `COVERED` — an `/api/v1` endpoint already returns everything the screen needs.
  - `PARTIAL` — an endpoint exists but is missing fields/actions the web screen has.
  - `GAP` — no `/api/v1` endpoint; a new one must be added (see §6 for the endpoint list).
- **v2** = status in the current iOS v2 app (`~/workspace/premiumslots-ios/`, version 2.0, commit a6aec2d):
  5 tabs — Catalogue, My Slots, How it works, Admin, Settings. AuthView (email/password via api_v1),
  APIClient (all api_v1 calls), AdminView (stats, approve/reject, subscriptions, customers, services).
- Counts (verified this audit): **customer routes 92** across 15 blueprints, **admin routes 78**
  (admin.py 67 + blog admin 4 + help admin 4 + coupons admin 3), **templates 58 + 7 error pages**,
  **checklist items 122** (customer 65, admin 53, Clerk 4). Cron (5) and SEO (3) routes are server-side
  jobs/files, not app screens — listed in §1.9 for completeness, not as screens to port.
- Never copy secrets into the app or this file: no `ADMIN_PASSWORD`, no `CLERK_SECRET_KEY`,
  no `CLERK_WEBHOOK_SECRET`, no publishable-key *value* (env var *names* only, §3), no M-PESA
  secret keys. The M-PESA PayBill/Account/Number are public payment instructions shown on the
  site itself (PayBill 400200, Account 1192526, Number 0734460218).

---

## 1. CUSTOMER features (65 items)

### 1.1 Home / catalogue / discovery

- [x] **Homepage catalogue** — Web: `GET /` (`main.py:19 index()`, `templates/index.html`,
  partials `user_catalog.html`). `SELECT * FROM Services`; shows name, price, description,
  `inventory_count` (slots left), icon. Live 7 Nov 2026: 8 platforms, 67 slots.
  API: `COVERED` (`GET /api/v1/services`). v2: Catalogue tab, live fetch + bundled offline fallback.
- [x] **Homepage dashboard (logged-in)** — Web: `GET /` same route; when logged in also loads the — DONE v3 Fix #3/#4: DashboardView.swift
  user's Subscriptions, FinancialLedger (last 50), Waitlist positions, unread NotificationQueue
  count, `global_alert` from Settings, and runs a passive auto-renewal check
  (`process_auto_renewals`) on every load. API: `PARTIAL` (subs + notifications covered;
  ledger, waitlist positions, global alert not exposed). v2: not present (no dashboard aggregate).
  New endpoint needed: `GET /api/v1/me/dashboard`.
- [x] **Hero / stats strip / marquee / process / rankings / FAQ sections** — Web: `index.html` — DONE v3 Fix #3/#4: DashboardView.swift
  partials `user_hero.html`, `user_stats_strip.html`, `user_marquee.html` ("SECURE M-PESA CHECKOUT /
  INSTANT DELIVERY / ENCRYPTED VAULT"), `user_process.html`, `user_rankings.html`, `user_faq.html`.
  Static marketing content + live counts. API: `GAP` (no endpoint; content is static — port as
  in-app copy, counts from `/api/v1/services` + stats). v2: How it works tab covers the process
  only; hero/stats/marquee/rankings/FAQ missing.
- [x] **Platform detail** — Web: no dedicated route; detail lives in the catalogue card + request — DONE v3 Fix #3/#4: PlatformDetailView.swift + CheckoutView.swift (coupon field; locked price in MySlotsView detail sheet)
  modal (`templates/partials/modals/request_modal.html`) with price, locked (grandfathered) price
  if any, coupon field, gateway instructions. API: `COVERED` (`GET /api/v1/services/<id>`).
  v2: PlatformDetailView exists (price, stock, buy) — add locked-price display + coupon field.
- [x] **Community suggestions ("Don't see your favourite platform?")** — Web: `POST /suggest_service` — DONE v3 Fix #3/#4: DashboardView.swift
  (`subscriptions.py:553`), `SuggestedServices` table, top 10 shown on homepage
  (`user_suggestions.html`), `GET /` GROUP BY count. Inputs: service name (text), email.
  API: `GAP`. v2: missing. New endpoint: `GET/POST /api/v1/suggestions`.
- [x] **Waitlist — join + position** — Web: `POST /waitlist/join` (`subscriptions.py:453`), — DONE v3 Fix #3/#4: DashboardView.swift
  `Waitlist` table (user_id, service_requested, priority_pos); position shown in a dialog on the
  homepage (`waitlist-dialog`, `waitlist-position-card`); admin can message waitlisted users.
  API: `PARTIAL` (join covered: `POST /api/v1/waitlist/join`; position lookup not exposed).
  v2: join exists in checkout flow; position display missing. New endpoint: `GET /api/v1/me/waitlist`.
- [x] **Global alert banner** — Web: `Settings.global_alert` shown on homepage when logged in. — DONE v3 Fix #3/#4: DashboardView.swift
  API: `GAP` (fold into `GET /api/v1/me/dashboard` or `GET /api/v1/user/status` equivalent).
  v2: missing.
- [x] **Offline page / PWA** — Web: `GET /offline` (`offline.html`), `static/manifest.json`, — DONE v3 Fix #3/#4: PSComponents.swift + CatalogView.swift (offline banner, labelled saved catalogue, error states; no separate offline page)
  `static/sw.js`, `push-client.js`. API: n/a. v2: offline banner + bundled catalogue already exist;
  add a proper offline state screen (cached data + queued actions) to match.

### 1.2 Buying — manual M-PESA (default gateway)

- [x] **Buy with manual M-PESA** — Web: `POST /request` (`subscriptions.py:11`), `payment_method=mpesa`,
  fields: service_requested, mpesa_code, optional coupon_code, optional sub_id (renewal).
  PayBill 400200, Account 1192526, Number 0734460218 (`app/utils.py:17-19`, overridable by env
  `MPESA_PAYBILL` / `MPESA_ACCOUNT` / `MPESA_NUMBER` and Settings keys). Exact amount must be paid
  first. Creates Subscription status `Pending`. Rate limit 5/min.
  API: `COVERED` (`POST /api/v1/request`). v2: CheckoutView (copy buttons, 10-char code field).
- [x] **M-PESA code validation** — Web: `is_valid_mpesa_format` (`app/utils.py:164`): exactly
  10 characters, `^[A-Z][A-Z0-9]{9}$` (starts with a letter), not all the same character, blocklist
  (`AAAAAAAAAA`, `XXXXXXXXXX`, `TESTCODE12`, `TESTPAY123`, `MPESAPAY12`, `0000000000`).
  `is_mpesa_code_used` (`utils.py:177`): rejects duplicates across Subscriptions,
  WalletTransactions and GiftCards. API: `COVERED` (same checks in api_v1). v2: client-side
  validation present; keep the blocklist in sync.
- [x] **Coupon at checkout** — Web: `validate_coupon` (`app/loyalty.py:320`): code, active, not — DONE v3 Fix #3/#4: CheckoutView.swift
  expired, max_redemptions, min_amount, max_redemptions_per_user (default 1), customer_type
  (new/existing/all), service_restriction, discount_type percent/flat with max_discount_amount.
  `POST /api/coupons/validate` (`coupons.py:13`). Applied in `POST /request` via `coupon_code`.
  API: `GAP` (api_v1 `/request` accepts a coupon code but there is no validate endpoint to preview
  the discount). v2: missing. New endpoint: `POST /api/v1/coupons/validate`.
- [x] **Grandfathered (locked) price** — Web: `Subscriptions.locked_price` (read in code, NOT in — DONE v3 Fix #3/#4: APIClient.swift (locked_price on APISubscription) + Models.swift + MySlotsView.swift detail sheet
  `CREATE TABLE` — likely a migration; verify on production before relying on it). If present for
  that service, the locked price applies instead of `Services.price`.
  API: `PARTIAL` (`_subscription_row` returns `amount_due` but no locked_price field).
  v2: missing. New endpoint field: include `locked_price` in service/subscription responses.
- [x] **STK push / IntaSend checkout** — Web: gateway Settings value `payment_gateway` (default — DONE v3 Fix #3/#4: CheckoutView.swift
  `mpesa`, admin can switch to `stk`/`intasend`). `POST /request` with `payment_method=stk` calls
  `intasend_client.initiate_stk_push(amount, phone, email)`; phone normalised to 254 format;
  Subscription status `Initiated`, `mpesa_code` = dummy `INTASEND-INIT-<id>`,
  `tuma_reference` = invoice_id. Webhook `POST /intasend/callback` flips to `Approved` on success
  and stores the real receipt. `GET /checkout/<tuma_ref>` (`checkout.html`, receipt-printer
  animation) + `GET /api/checkout/status/<tuma_ref>`. `POST /pay/retry/<sub_id>`,
  `POST /pay/verify_manual/<sub_id>`. API: `GAP` (api_v1 `/request` is manual-M-PESA only;
  no STK initiation, no checkout status). v2: missing. New endpoints:
  `POST /api/v1/request` (gateway-aware), `GET /api/v1/checkout/status/<ref>`,
  `POST /api/v1/pay/retry/<id>`, `POST /api/v1/pay/verify-manual/<id>`.
- [x] **Wallet payment at checkout** — Web: `POST /request` with wallet method; balance debited — DONE v3 Fix #3/#4: CheckoutView.swift
  with velocity/spend-cap check (`check_wallet_velocity_limit`, max daily spend KES 25,000) and
  `SELECT ... FOR UPDATE` row lock; reference `WALLET-NEW-<hex>` (new) or `WALLET-RNW-<hex>`
  (renewal); renewal extends expiry immediately, status `Approved` (1-click renewal).
  API: `GAP`. v2: missing. New endpoint: `POST /api/v1/request` (payment_method=wallet) and/or
  `POST /api/v1/wallet/instant-renew/<id>`.
- [x] **Checkout success / receipt-printer screen** — Web: `GET /checkout/<tuma_ref>` — DONE v3 Fix #3/#4: CheckoutView.swift (staged status screen)
  (`checkout.html`): status indicator with spinning icon, receipt-printer staged animation
  (processing → printing → complete). API: `GAP` (see STK status above). v2: missing; port the
  staged status UI (use the spinner recipe in §4).

### 1.3 My Subscriptions / vault

- [x] **My Subscriptions list** — Web: homepage partials `user_active_subscriptions.html` +
  `user_past_subscriptions.html` (active vs past, days left via `calculate_days_left`,
  expiry formatted). Statuses: `Initiated`, `Pending`, `Approved` (+ `Completed`/`Delivered`
  in loyalty code, `Rejected` in coupon checks). API: `COVERED` (`GET /api/v1/me/subscriptions`).
  v2: My Slots tab.
- [x] **One-time vault reveal** — Web: `main.py:100-102` pops `session["viewing_sub_<id>"]` and
  exposes `revealed_email` / `revealed_password` / `revealed_details` once; vault columns
  `vault_email` / `vault_password` (plain TEXT), `access_details` (`'See Vault'` on approval),
  `account_group` (default `Unassigned`). Delivery types: `Credentials`, `Invite Link`,
  `Direct Activation`. Rule shown to users: "1 Slot = 1 Device".
  API: `COVERED` (`GET /api/v1/me/subscriptions/<id>/vault`, two-step arm-then-reveal).
  v2: MySlotsView vault reveal present.
- [x] **Subscription detail / timeline** — Web: `GET /subscription/<id>/timeline` — DONE v3 Fix #3/#4: MySlotsView.swift (SubscriptionDetailSheet)
  (`subscriptions.py:594`, `templates/timeline.html`, from `OrderEvents`).
  API: `GAP`. v2: missing. New endpoint: `GET /api/v1/me/subscriptions/<id>/timeline`.
- [x] **Mark/view a subscription** — Web: `POST /subscription/view` (`subscriptions.py:491`). — DONE v3 Fix #3/#4: MySlotsView.swift (folded into timeline/detail)
  API: `GAP` (vault endpoint marks viewed as a side effect; no standalone view endpoint).
  v2: missing (fold into timeline/detail endpoint).
- [x] **Report an issue** — Web: `POST /subscription/report-issue` (`subscriptions.py:479`), — DONE v3 Fix #3/#4: MySlotsView.swift
  sets `issue_reported`. API: `COVERED` (`POST /api/v1/subscription/<id>/report-issue`).
  v2: MySlotsView report-issue present.
- [x] **Request a review** — Web: `POST /subscription/request-review` (`subscriptions.py:506`), — DONE v3 Fix #3/#4: MySlotsView.swift
  sets `review_requested`. API: `GAP`. v2: missing.
  New endpoint: `POST /api/v1/me/subscriptions/<id>/request-review`.
- [x] **Toggle auto-renew** — Web: `POST /subscription/<id>/toggle-auto-renew`
  (`subscriptions.py:866`), `auto_renew` flag; renewals processed by cron
  (`process_auto_renewals`). API: `COVERED` (`POST /api/v1/subscription/<id>/toggle-auto-renew`).
  v2: present.
- [x] **Expiry rules** — Web: `calculate_subscription_expiry` (`utils.py:24`): adds the calendar — DONE v3 Fix #3/#4: MySlotsView.swift (days-left + expiry display, server-side rules)
  month's days; stacks on remaining expiry if still active; deducts late days if expired within
  a 7-day grace period; starts fresh if expired >7 days ago or cancelled. API: server-side
  (no client work, but the app must display `expiry_date` + days-left exactly as the API returns).
  v2: days-left shown; verify grace-period wording matches the site.

### 1.4 Wallet

- [x] **Wallet balance + transactions** — Web: `GET /wallet` (`wallet.py:12`, `wallet.html`):
  balance, last 60 `WalletTransactions`, metrics (total deposited / total spent / total redeemed
  from gift cards), denominations [200, 500, 1000, 2000, 5000], M-PESA instructions.
  API: `PARTIAL` (`GET /api/v1/wallet` returns balance + last 50 transactions; metrics,
  denominations and renewable-subs list not included). v2: SettingsView shows balance (verify
  transactions list is shown). New fields: add metrics + denominations to the wallet response.
- [x] **Wallet deposit (manual M-PESA)** — Web: `POST /wallet/deposit` (`wallet.py:102`):
  amount + 10-char code, logged in `WalletTransactions`, **admin-approved** before the balance
  moves. API: `COVERED` (`POST /api/v1/wallet/deposit`). v2: present in Settings (verify).
- [x] **Wallet instant renewal (1-click)** — Web: `POST /wallet/instant-renew/<sub_id>` — DONE v3 Fix #3/#4: WalletView.swift
  (`wallet.py:394`): pays a renewal from balance instantly (see §1.2 wallet payment).
  API: `GAP`. v2: missing. New endpoint: `POST /api/v1/wallet/instant-renew/<id>`.
- [x] **Redeem gift card into wallet** — Web: `POST /wallet/redeem-gift-card` (`wallet.py:222`). — DONE v3 Fix #3/#4: WalletView.swift
  API: `GAP`. v2: missing. New endpoint: `POST /api/v1/wallet/redeem-gift-card`.
- [x] **Wallet statement + PDF** — Web: `GET /wallet/statement/pdf` (`wallet.py:532`, — DONE v3 Fix #3/#4: WalletView.swift
  `receipts.py:592 generate_wallet_statement_pdf_bytes`). (Note: no `GET /wallet/statement` page
  route exists — the statement is the PDF only.) API: `GAP`. v2: missing.
  New endpoint: `GET /api/v1/wallet/statement` (JSON) + PDF download link.
- [x] **Wallet velocity / spend cap surfacing** — Web: `check_wallet_velocity_limit` — DONE v3 Fix #3/#4: WalletView.swift (API error surfaced)
  (max daily spend KES 25,000). API: server-side; the app must surface the error message
  returned by the API on a blocked payment. v2: verify error surfacing.

### 1.5 Gift cards

- [x] **Gift cards page** — Web: `GET /gift-cards` (`giftcards.py:117`, `gift_cards.html`, 46 KB): — DONE v3 Fix #3/#4: GiftCardsView.swift
  feature toggle (`is_gift_cards_enabled`, admin can switch it off), denominations
  [200, 500, 1000, 2000, 5000], 5 themes (Cyber Gold #d97706/#fbbf24/#b45309;
  Electric Blue #1d4ed8/#3b82f6/#06b6d4; Emerald Luxe #047857/#10b981/#059669;
  Neon Violet #6d28d9/#8b5cf6/#ec4899; Crimson Ruby #991b1b/#ef4444/#f43f5e),
  my issued cards (last 20), my redeemed cards (last 20), prefill `?code=` (redirects to login
  if logged out). API: `GAP`. v2: missing entirely.
- [x] **Create / buy a gift card** — Web: `POST /gift-cards/create` (`giftcards.py:178`): — DONE v3 Fix #3/#4: GiftCardsView.swift
  amount, recipient name/email, custom message, theme_style, paid by manual M-PESA code
  (code checked by `is_mpesa_code_used`); generates code, sends styled email
  (`send_gift_card_email`). API: `GAP`. v2: missing.
  New endpoints: `GET /api/v1/gift-cards`, `POST /api/v1/gift-cards`,
  `GET /api/v1/gift-cards/<code>/verify`.
- [x] **Redeem a gift card** — Web: `POST /gift-cards/redeem` (`giftcards.py:362`) → wallet — DONE v3 Fix #3/#4: GiftCardsView.swift
  credit; `GET /gift-cards/verify/<code>` (`giftcards.py:474`) returns code, amount, status,
  expiry, theme, sender/recipient. API: `GAP`. v2: missing.
  New endpoints: `POST /api/v1/gift-cards/redeem`, `GET /api/v1/gift-cards/verify/<code>`.

### 1.6 Referrals, leaderboard, loyalty, achievements

- [x] **Referrals dashboard** — Web: `GET /referrals` (`referrals.py:63`, `referrals.html`):
  my code (auto-generated 6-hex uppercase if missing), ref link, ref count, completed vs pending
  refs (last 100), total referral points (100 pts per completed referral, both sides),
  inviter (who referred me), top-3 monthly referrers preview. `apply_referral_on_signup`
  (`loyalty.py:300`): code captured at register (`?ref=` → `session["pending_ref_code"]`),
  Referrals row Pending → Completed, +100 pts each side.
  API: `PARTIAL` (`GET /api/v1/referrals` returns referrals + leaderboard rows — **but it queries
  `Referrals WHERE user_id = %s`, while the web table uses `referrer_id`/`referee_id`; verify live,
  it may 500 or return nothing**). v2: referrals shown in Settings (verify it works live).
  Fix: rewrite the endpoint against `referrer_id`, add my code/link/counts/inviter/top-3.
- [x] **Referral landing + public leaderboard** — Web: `GET /r/<code>` (`referrals.py:50`, — DONE v3 Fix #3/#4: StoreLoyaltyView.swift (LeaderboardRootView)
  shows referrer name/count, then `referrals.html`), `GET /leaderboard` (`referrals.py:10`,
  `leaderboard.html`, monthly + all-time), `GET /referrals/leaderboard` (`referrals.py:128`,
  `referral_leaderboard.html`). API: `PARTIAL` (leaderboard rows included in `/api/v1/referrals`;
  monthly/all-time split + public view not exposed). v2: missing as a screen.
  New endpoint: `GET /api/v1/leaderboard` (monthly + all-time).
- [x] **Loyalty tiers + points** — Web: `app/loyalty.py`: tiers Bronze 0 / Silver 250 (−5%) / — DONE v3 Fix #3/#4: StoreLoyaltyView.swift (LoyaltyRootView)
  Gold 750 (−10%) / Platinum 2000 (−15%); 1 pt per KES spent; 2 pts per day of tenure;
  100 pts per referral; 50 pts per review; streak milestones 1mo=50, 3mo=120, 6mo=300, 12mo=800;
  birthday bonus 200 pts (within 3 days before birthday, once per year). Streak = consecutive
  months of active coverage (`compute_streak`, grace for previous month).
  API: `PARTIAL` (`/api/v1/auth/me` returns loyalty_points + loyalty_tier only; no points
  history, no streak, no next-tier progress). v2: tier shown in Settings (verify).
  New endpoint: `GET /api/v1/me/loyalty` (points, tier, next tier, streak months, Ledger).
- [x] **Achievements / badges** — Web: `GET /achievements` (`achievements.py:10`, — DONE v3 Fix #3/#4: StoreLoyaltyView.swift (AchievementsRootView)
  `achievements.html`): all `BadgeDefinitions` (code, name, description, icon, category, tier),
  earned set from `UserBadges`, stats (points, streak_months, referral_count); badges evaluated
  by `evaluate_badges` (first_sub, five/ten/twenty_subs, streak_3/6/12/max, first_ref, ref_five,
  ref_ten, coupon_used, bday_bonus). API: `GAP`. v2: missing.
  New endpoint: `GET /api/v1/me/achievements`.
- [x] **Loyalty rewards store** — Web: `GET /store` (`store.py:11`, `store.html`): active — DONE v3 Fix #3/#4: StoreLoyaltyView.swift (StoreRootView)
  `RewardItems` ordered by points_cost (id, name, description, reward_type, points_cost, value,
  stock), my points, my last 50 `RewardRedemptions`, total spent, total claims, active coupons,
  my tier. `POST /store/redeem/<reward_id>` (`store.py:52`, 10/hour): `redeem_reward`
  (discount_coupon rewards generate a `PS-XXXXXXXX` code; redemption status Pending; stock −1).
  API: `GAP`. v2: missing. New endpoints: `GET /api/v1/store`, `POST /api/v1/store/redeem/<id>`.
- [ ] **Spin wheel** — Web: `SpinWheelRewards` table seeded in `database.py:736,928` (labels,
  probabilities, reward_type/value/coupon_code). **No route, blueprint or template references a
  spin wheel** — the table is seeded but there is no customer-facing spin feature in the code
  audited. Treat as **not a parity item** unless Kerry says the wheel exists somewhere else;
  do not build it on the strength of the table alone.
- [x] **Birthday rewards** — Web: `GET/POST /auth/birthday` (`auth.py:385`, `birthday.html`): — DONE v3 Fix #3/#4: StoreLoyaltyView.swift (BirthdaySaveView)
  save date_of_birth (YYYY-MM-DD), shows last credit year; cron `daily-birthdays` awards the
  200-pt bonus. API: `GAP`. v2: missing. New endpoint: `GET/POST /api/v1/me/birthday`.

### 1.7 Wishlist, suggestions, feedback, tickets

- [x] **Wishlist** — Web: `GET /wishlist` (`wishlist.py:9`, `wishlist.html`): filters — DONE v3 Fix #3/#4: WishlistView.swift
  category (All, AI Tools, Streaming, Productivity, Developer, Design, Security), status
  (all/planned/available/...), sort (votes / newest / price_asc), search `q` (title/description),
  category counts, roadmap KPIs (total items, total votes, planned count, available count),
  my voted ids, my notify-me ids. `POST /wishlist/vote` (30/min), `POST /wishlist/notify`
  (toggle notify-me), `POST /wishlist/submit` (new item). API: `GAP`. v2: missing.
  New endpoints: `GET /api/v1/wishlist` (with query params), `POST /api/v1/wishlist/vote`,
  `POST /api/v1/wishlist/notify`, `POST /api/v1/wishlist/submit`.
- [x] **Message admin / feedback** — Web: `POST /submit_feedback` (`subscriptions.py:518`, — DONE v3 Fix #3/#4: TicketsView.swift
  dialog `feedback-dialog` on homepage): message_type (Site Feedback / Suggestion, General
  Inquiry, Payment Issue) + message → SupportTickets. API: `GAP`. v2: missing.
  New endpoint: `POST /api/v1/feedback`.
- [x] **Support tickets** — Web: `POST /submit-ticket` (`main.py:361`), `GET /my-tickets` — DONE v3 Fix #3/#4: TicketsView.swift
  (`main.py:405`, `my_tickets.html`): list my tickets + status. API: `GAP`. v2: missing.
  New endpoints: `GET /api/v1/me/tickets`, `POST /api/v1/tickets`.
- [x] **Notifications** — Web: `GET /api/notifications` (last 30 from `NotificationQueue` + — DONE v3 Fix #3/#4: NotificationsView.swift
  unread count), `POST /api/notifications/mark-read` (`api.py:34,65`); kinds seen in code:
  system, subscription, referral, achievement. Web Push via `api/push/*` (VAPID, pywebpush)
  — not available on iOS; use polling + APNs later. API: `PARTIAL`
  (`GET /api/v1/me/notifications` returns last 30; no unread count, no mark-read).
  v2: missing as a screen. New endpoints: add unread count + `POST /api/v1/me/notifications/read`.

### 1.8 Content pages

- [x] **Help centre + articles** — Web: `GET /help` (`help.py:10`, `help_center.html`: search `q`, — DONE v3 Fix #3/#4: HelpBlogView.swift
  category filter), `GET /help/<slug>` (`help.py:49`, `help_article.html`); `HelpArticles`
  table (also seeded with the M-PESA/credentials FAQ text in `database.py:959`).
  API: `GAP`. v2: How it works tab is static copy only. New endpoints:
  `GET /api/v1/help`, `GET /api/v1/help/<slug>`.
- [x] **Blog** — Web: `GET /blog` (`blog.py:15`, `blog_index.html`), `GET /blog/<slug>` — DONE v3 Fix #3/#4: HelpBlogView.swift
  (`blog.py:30`, `blog_post.html` + related posts). API: `GAP`. v2: missing.
  New endpoints: `GET /api/v1/blog`, `GET /api/v1/blog/<slug>`.
- [x] **Privacy / Terms** — Web: `GET /privacy` (`privacy_policy.html`), `GET /terms` — DONE v3 Fix #3/#4: HelpBlogView.swift (PrivacyView, TermsView)
  (`terms_of_service.html`): auth handled exclusively by Clerk; admin cannot see passwords.
  API: n/a (static). v2: missing. Port as in-app text screens (copy the live pages verbatim).
- [x] **GDPR consent + data export** — Web: `GET/POST /gdpr/consent` (`main.py:253`, — DONE v3 Fix #3/#4: AccountView.swift
  `gdpr_consent.html`), `POST /gdpr/export-request` (`main.py:317`, `DataExportRequests`).
  API: `GAP`. v2: missing. New endpoints: `GET/POST /api/v1/me/gdpr-consent`,
  `POST /api/v1/me/export-request`.
- [x] **Email unsubscribe** — Web: `GET /unsubscribe` (`main.py:9`, `unsubscribe.html`). — DONE v3 Fix #3/#4: AccountView.swift (folded into notification preferences)
  API: `GAP` (minor; fold into notification preferences). v2: missing.
- [x] **Receipts + verification** — Web: `GET /receipt/<id>` (`receipts.py:380`): PDF receipt — DONE v3 Fix #3/#4: HelpBlogView.swift (ReceiptsView)
  (fpdf2, `generate_receipt_pdf_bytes`); `GET /verify` + `GET /receipt/verify`
  (`receipts.py:402`): HMAC-SHA256 verify (`sign_receipt` / `verify_receipt`, `utils.py:415-446`).
  API: `GAP`. v2: missing. New endpoints: `GET /api/v1/receipts/<id>` (PDF),
  `GET /api/v1/receipts/verify?payload=&signature=`.
- [x] **Error / status pages** — Web: `templates/errors/` (400, 401, 403, 404, 429, 500, 503). — DONE v3 Fix #3/#4: PSComponents.swift (PSErrorState on every list)
  API: n/a. v2: add matching empty/error states (offline, not found, rate-limited, server error)
  with retry — do not show raw HTML error pages.

### 1.9 Server-side only (do NOT port as screens; port their effects)

- [x] **Cron jobs** — Web: `GET/POST /api/cron/daily-reminders`, `/auto-renewals`, — DONE v3 Fix #3/#4: DashboardView.swift + NotificationsView.swift + StoreLoyaltyView.swift (effects surface)
  `/daily-streaks`, `/daily-birthdays`, `/review-requests` (`cron.py`). These run server-side.
  The app surfaces their effects only: renewal reminders, auto-renewal processing, streak
  updates, birthday bonus, review requests. API: n/a. v2: effects surface via subscriptions/
  notifications/loyalty endpoints above.
- [x] **SEO files** — Web: `GET /sitemap.xml`, `/robots.txt`, `/.well-known/security.txt`, — DONE v3 Fix #3/#4: server-side only, not app features, by design
  `/llms.txt`, `/llms-full.txt` (`seo.py`, `main.py:227`). Not app features. API: n/a.

### 1.10 Account / settings / security (customer)

- [x] **Onboarding** — v3 (backend `GET/POST /api/v1/me/onboarding` + `POST /api/v1/auth/onboarding`, app `OnboardingView`, gated from `ContentView`). Web: `GET/POST /auth/onboarding` (`auth.py:187`, `onboarding.html`):
  required after Clerk sign-in if `whatsapp_number` or `date_of_birth` is missing; collects both.
  API: `GAP`. v2: missing (Clerk sign-in currently lands without onboarding).
  New endpoint: `GET/POST /api/v1/me/onboarding`.
- [x] **Profile update** — Web: `POST /auth/profile/update` (`auth.py:337`, 5/hour): name + — DONE v3 Fix #3/#4: AccountView.swift
  whatsapp_number (both required). Also editable from the homepage profile dialog.
  API: `GAP` (`/api/v1/auth/me` is read-only). v2: missing.
  New endpoint: `PUT /api/v1/me/profile`.
- [x] **Change password** — Web: `POST /auth/profile/password` (`auth.py:356`, 5/hour): — DONE v3 Fix #3/#4: AccountView.swift
  current password checked with Werkzeug hash; new password must satisfy `is_strong_password`
  (min 8 chars, upper + lower + digit, `utils.py:157`). API: `GAP`. v2: missing.
  New endpoint: `POST /api/v1/me/password`.
- [x] **Forgot / reset password** — v3 (backend `POST /api/v1/auth/forgot-password` + `/reset-password`, app `ForgotPasswordView` in `AuthView.swift`). Web: `GET/POST /auth/forgot_password` (`auth.py:306`,
  3/hour, always returns success to prevent enumeration; token `secrets.token_urlsafe(32)`,
  **expires in 15 minutes**; reset link goes to homepage with `?reset_token=`),
  `POST /auth/reset_password_confirm` (`auth.py:272`). API: `GAP`. v2: missing.
  New endpoints: `POST /api/v1/auth/forgot-password`, `POST /api/v1/auth/reset-password`.
- [x] **Email verification (legacy)** — v3 (backend `POST /api/v1/auth/verify`). Web: `POST /auth/verify` (`auth.py:44`): 6-digit
  `verification_code` against `session["pending_verification_id"]`; sets `is_verified`.
  (Clerk users are created verified; this is the legacy own-auth path.) API: `GAP`.
  v2: missing. New endpoint: `POST /api/v1/auth/verify` (only if legacy auth is kept).
- [x] **Magic-link sign-in** — v3 (backend `POST /api/v1/auth/magic` + `/magic/consume`, app `MagicLinkView` in `AuthView.swift`). Web: `GET/POST /auth/magic` (`auth.py:223`) + `GET /auth/magic/<token>`
  (`auth.py:245`): `create_magic_link` / `consume_magic_link` (`utils.py:493,509`), one-time
  token in `MagicLinkTokens`, emailed link, signs in + notifies ("Signed in via magic link").
  API: `GAP`. v2: missing. New endpoints: `POST /api/v1/auth/magic`,
  `GET /api/v1/auth/magic/<token>` (or a JSON consume endpoint).
- [ ] **Passkeys (WebAuthn)** — Web: `POST /auth/webauthn/register/begin|complete`,
  `POST /auth/webauthn/authenticate/begin|complete`, `GET /auth/webauthn/list`,
  `POST /auth/webauthn/remove` (`auth.py:479-759`, `webauthn` 3.x lib, `WebAuthnCredentials`
  table); UI in `security.html` (add with device name e.g. "iPhone Face ID", list, remove).
  iOS native equivalent: `ASAuthorizationPlatformPublicKeyCredentialProvider`.
  API: `GAP`. v2: missing. New endpoints: JSON variants of the 6 WebAuthn routes.
- [x] **Sessions list + revoke** — v3 (backend `GET /api/v1/me/sessions` + `POST /api/v1/me/sessions/revoke`, app `APIClient.mySessions/revokeSession`). Web: `GET /auth/sessions` (`auth.py:411`, `sessions.html`),
  `POST /auth/sessions/revoke` (`auth.py:432`): `LoginActivity` rows (device label from UA,
  IP, signed_in_at, last_seen_at, revoked_at). Max 3 sessions per user
  (`MAX_SESSIONS_PER_USER = 3`, `enforce_session_limit`, `utils.py:782`); new-IP logins raise a
  "New Login Detected" notification + admin email (`track_login`, `utils.py:714`).
  API: `GAP`. v2: missing. New endpoints: `GET /api/v1/me/sessions`,
  `POST /api/v1/me/sessions/revoke`.
- [x] **Security settings page** — Web: `GET /auth/security` (`auth.py:784`, `security.html`): — DONE v3 Fix #3/#4: AccountView.swift (AccSecurityView; passkeys honestly unavailable)
  passkeys + sessions + password in one place. API: `GAP` (covered by the three endpoints above).
  v2: missing as a screen.
- [x] **Settings page** — Web: `GET /settings` (`auth.py:799`, `settings.html`): tabs — — DONE v3 Fix #3/#4: SettingsView.swift (Features links + Account/Privacy sections)
  Account Profile (Clerk UserProfile mount, see §3), Privacy & Notifications, Billing &
  Subscriptions (list with status). API: `PARTIAL` (auth/me + subscriptions covered; privacy
  toggles + Clerk profile not). v2: SettingsView exists (theme, account, wallet, referrals,
  catalogue state) — extend to the three web tabs.
- [x] **Privacy / notification toggles** — Web: `POST /settings/privacy` (`auth.py:814`): — DONE v3 Fix #3/#4: AccountView.swift
  `receive_email_notifications`, `receive_whatsapp_notifications` (columns on Users).
  API: `GAP`. v2: missing. New endpoint: `PUT /api/v1/me/privacy`.
- [x] **Delete account (GDPR)** — Web: `POST /settings/delete-account` (`auth.py:830`): — DONE v3 Fix #3/#4: AccountView.swift
  deletes the account (and Clerk cloud account when linked — see admin delete, §2).
  API: `GAP`. v2: missing. New endpoint: `DELETE /api/v1/me` (with confirm + Clerk unlink).
- [x] **Sign out** — Web: `POST/GET /auth/logout` (`auth.py:294`) pops `user_id`; — DONE v3 Fix #3/#4: Models.swift (AppState.logout clears Clerk + Flask sessions, v3)
  `GET /auth/clerk_logout_sync` (`auth.py:300`) same + Clerk sign-out (navbar UserButton
  `afterSignOutUrl`). API: `COVERED` (`POST /api/v1/auth/logout`). v2: present (verify it also
  clears the Clerk session when Clerk is adopted, §3).

---

## 2. ADMIN features (53 items)

Admin prefix: **every admin route lives under `/admin-xyz1331`** (not `/admin`).
Admin auth: `POST /admin-xyz1331/login` — single `password` field vs `ADMIN_PASSWORD` env var
(5/hour rate limit); success sets `session["admin_authenticated"] = True`.
`admin_required` (`admin.py:10`) checks ONLY that flag. **There is no admin role on Users** —
a normal user session and an admin session are independent; an admin is not a "user" in the app.
Admin email default `admin@premiumslots.tech`. Templates: `admin.html`, `admin_analytics.html`,
`admin_backup.html`, `admin_customers.html`, `admin_financial_engine.html`, `admin_gift_cards.html`,
`admin_payment_methods.html`, `admin_security_logs.html`, `admin_transactions.html`,
`admin_wallet.html`, `app_admin_base.html`, `base_admin.html`, partials `admin_sidebar.html`,
`admin_flash.html`, `admin_modals.html`, `admin_fulfillment_queue.html`, `admin_hero_kpi.html`,
`admin_services_catalog.html`, `admin_support_tickets.html`, `admin_waitlist_suggestions.html`,
`admin_churn_risk.html`, `admin_export_rotation.html`, `admin_bulk_email_global.html`,
`admin_analytics_charts.html`, `app_admin_bottom_bar.html`.
Admin CSS is deliberately monochrome (white primary, §4) — the iOS admin screens should use the
public blue/cyan brand unless Kerry says otherwise (ANALYSIS.md §8).

### 2.1 Dashboard, stats, analytics

- [x] **Admin login / logout** — Web: `POST /admin-xyz1331/login`, `POST /admin-xyz1331/logout`
  (`admin.py:1224,1233`). API: `COVERED` (`POST /api/v1/admin/login|logout`).
  v2: Admin tab login present.
- [x] **Admin dashboard** — Web: `GET /admin-xyz1331` (`admin.py:989`, `admin.html`): hero KPI,
  fulfilment queue, sections queue / catalog / waitlist / suggestions / customers / support /
  churn / export / bulk-email. Stats helper `_build_public_stats` (`admin.py:19`): active slots,
  total approved, verified users, services offered, unique services used, tickets resolved/total,
  total revenue + revenue this month (from `FinancialLedger`), days active, daily approvals
  (30 days), top services (6). API: `PARTIAL` (`GET /api/v1/admin/stats` — verify it returns
  the same fields; fulfilment queue is not a separate endpoint). v2: AdminView dashboard cards
  (pending, approved, issues, users, revenue, slots) present — verify against live stats.
- [x] **Stats page** — Web: `GET /admin-xyz1331/stats` (`admin.py:160`, `stats.html`). — DONE v3 Fix #3/#4: AdminAnalyticsView.swift
  API: `PARTIAL` (same stats endpoint; no dedicated page payload). v2: missing as a screen.
- [x] **Analytics page + data** — Web: `GET /admin-xyz1331/analytics` (`admin.py:218`, — DONE v3 Fix #3/#4: AdminAnalyticsView.swift
  `admin_analytics.html`), `GET /admin-xyz1331/analytics/data` (`admin.py:347`),
  `GET /admin-xyz1331/api/analytics` (`admin.py:2163`). API: `GAP`. v2: missing.
  New endpoint: `GET /api/v1/admin/analytics` (with `days`/`service`/`status` filters).
- [x] **Revenue analytics** — Web: `GET /api/admin/analytics/revenue` (`api.py:143`): daily — DONE v3 Fix #3/#4: AdminAnalyticsView.swift
  revenue from `FinancialLedger`, filters `days`, `service`, `status`.
  API: `GAP` (fold into the analytics endpoint above). v2: missing.
- [x] **Churn prediction** — Web: `GET /api/admin/analytics/churn` (`api.py:235`): currently a — DONE v3 Fix #3/#4: AdminAnalyticsView.swift (honest empty state; web is a stub)
  **stub** returning `{"churn_users": [], "churn_count": 0}`; `_build_churn_users` exists in
  admin.py:938. `GET /admin-xyz1331/api/stats` (`api.py:240`) returns admin stats JSON.
  API: `GAP`. v2: missing. Note: port the real churn list when the backend computes it; do not
  ship a fake churn screen.
- [x] **Admin status counts** — Web: `GET /api/admin/status` (`api.py:122`): pending/issue/ — DONE v3 Fix #3/#4: AdminView.swift + AdminAnalyticsView.swift (folded into stats)
  ticket counts. API: `GAP` (fold into admin stats). v2: partial (counts shown from stats).
- [x] **Financial engine** — Web: `GET /admin-xyz1331/financial-engine` (`admin.py:1782`, — DONE v3 Fix #3/#4: AdminAnalyticsView.swift (AdminFinancialEngineView)
  `admin_financial_engine.html`). API: `GAP`. v2: missing.
  New endpoint: `GET /api/v1/admin/financial-engine`.
- [x] **Export CSV** — Web: `GET /admin-xyz1331/export/csv` (`admin.py:473`). — DONE v3 Fix #3/#4: AdminAnalyticsView.swift
  API: `GAP`. v2: missing. New endpoint: `GET /api/v1/admin/export/csv` (or per-list exports).
- [x] **Report PDF** — Web: `GET /admin-xyz1331/report/pdf` (`admin.py:617`, fpdf2 KPI report — DONE v3 Fix #3/#4: AdminAnalyticsView.swift
  with `kpi_card`/`kpi_table` helpers). API: `GAP`. v2: missing.
  New endpoint: `GET /api/v1/admin/report/pdf`.
- [ ] **Test email** — Web: `GET/POST /admin-xyz1331/test_email` (`admin.py:114`,
  `admin_email_test.html`). API: `GAP`. v2: missing (low priority; keep web-only if short on time).
  New endpoint: `POST /api/v1/admin/test-email`.
- [ ] **Fix DB** — Web: `GET /admin-xyz1331/fix-db` (`admin.py:1467`). API: `GAP`.
  v2: missing. **Recommendation: keep web-only** (one-off maintenance action, not a mobile job).

### 2.2 Subscriptions (fulfilment — the core admin job)

- [x] **Approve a subscription** — Web: `POST /admin-xyz1331/approve/` (`admin.py:1348`):
  sets `Approved`, `expiry_date` (one calendar month), decrements `Services.inventory_count`,
  delivers vault credentials (admin sets vault email/password + `access_details = 'See Vault'`).
  API: `COVERED` (`POST /api/v1/admin/subscriptions/<id>/approve` with vault email/password +
  account group). v2: AdminView approve present.
- [x] **Reject a subscription** — Web: no dedicated reject route in admin.py (rejection is via
  delete/cancel flows); api_v1 adds an explicit reject. API: `COVERED`
  (`POST /api/v1/admin/subscriptions/<id>/reject`). v2: present.
- [x] **Subscriptions list** — Web: part of the dashboard + customers detail; no standalone
  admin subscriptions page route (list is rendered inside `admin.html` fulfilment queue).
  API: `COVERED` (`GET /api/v1/admin/subscriptions`, optional `status` filter).
  v2: AdminView subscriptions list present — add search + status filter to match the queue.
- [x] **Bulk subscription update** — Web: `POST /admin-xyz1331/subscription/bulk-update` — DONE v3 Fix #3/#4: AdminSubscriptionsView.swift
  (`admin.py:1148`). API: `GAP`. v2: missing.
  New endpoint: `POST /api/v1/admin/subscriptions/bulk-update`.
- [x] **Edit a subscription** — Web: `POST /admin-xyz1331/subscription/edit` (`admin.py:1551`). — DONE v3 Fix #3/#4: AdminSubscriptionsView.swift
  API: `GAP`. v2: missing. New endpoint: `PUT /api/v1/admin/subscriptions/<id>`.
- [x] **Renew a subscription (admin)** — Web: `POST /admin-xyz1331/subscription/renew` — DONE v3 Fix #3/#4: AdminSubscriptionsView.swift
  (`admin.py:1569`). API: `GAP`. v2: missing.
  New endpoint: `POST /api/v1/admin/subscriptions/<id>/renew`.
- [x] **Cancel a subscription (admin)** — Web: `POST /admin-xyz1331/subscription/cancel` — DONE v3 Fix #3/#4: AdminSubscriptionsView.swift
  (`admin.py:1667`). API: `GAP`. v2: missing.
  New endpoint: `POST /api/v1/admin/subscriptions/<id>/cancel`.
- [x] **Delete a subscription** — Web: `POST /admin-xyz1331/delete/` (`admin.py:1702`). — DONE v3 Fix #3/#4: AdminSubscriptionsView.swift
  API: `GAP`. v2: missing. New endpoint: `DELETE /api/v1/admin/subscriptions/<id>`.
- [x] **Unhide credentials** — Web: `POST /admin-xyz1331/subscription/unhide` (`admin.py:1488`). — DONE v3 Fix #3/#4: AdminSubscriptionsView.swift
  API: `GAP`. v2: missing. New endpoint: `POST /api/v1/admin/subscriptions/<id>/unhide`.
- [x] **Send expiry reminder** — Web: `POST /admin-xyz1331/subscription/remind-expiry` — DONE v3 Fix #3/#4: AdminSubscriptionsView.swift
  (`admin.py:1500`). API: `GAP`. v2: missing.
  New endpoint: `POST /api/v1/admin/subscriptions/<id>/remind-expiry`.

### 2.3 Customers

- [x] **Customers list** — Web: `GET /admin-xyz1331/customers` (`admin.py:3140`,
  `admin_customers.html`, 55 KB): live search (name/email/phone, `/` keyboard shortcut),
  filter pills (all / active / VIP / has-wallet / banned), sort (id asc/desc, LTV desc,
  wallet desc, name asc), per-customer drawer (email, registered date, Clerk badge if
  `clerk_id` present, LTV, wallet, subscriptions). API: `PARTIAL`
  (`GET /api/v1/admin/customers` — verify search/filter/sort params exist; the web list is
  client-side filtered over the full list, so the endpoint must return the fields the filters
  need: is_active, is_vip, has_wallet, is_banned, LTV). v2: AdminView customers present —
  add search + filter pills + sort + detail drawer.
- [x] **Customer detail** — Web: `GET /admin-xyz1331/customer/api/details/<user_id>`
  (`admin.py:3288`). API: `COVERED` (`GET /api/v1/admin/customers/<id>`). v2: present (verify
  fields match the drawer).
- [x] **Ban / unban a customer** — Web: `POST /admin-xyz1331/user/toggle_ban` (`admin.py:1239`):
  flips `is_banned` **and syncs to Clerk** (`POST https://api.clerk.com/v1/users/<clerk_id>/ban`
  or `/unban` with `CLERK_SECRET_KEY`). API: `COVERED`
  (`POST /api/v1/admin/customers/<id>/toggle-ban`). v2: present.
  **Note:** api_v1's toggle-ban must also do the Clerk sync — verify it does; if not, add it.
- [x] **Toggle a customer's emails** — Web: `POST /admin-xyz1331/user/toggle_emails` — DONE v3 Fix #3/#4: AdminCustomersView.swift
  (`admin.py:1283`). API: `GAP`. v2: missing.
  New endpoint: `POST /api/v1/admin/customers/<id>/toggle-emails`.
- [x] **Delete a customer** — Web: `POST /admin-xyz1331/user/delete` (`admin.py:1299`): — DONE v3 Fix #3/#4: AdminCustomersView.swift
  deletes the user **and their Clerk cloud account** (`DELETE https://api.clerk.com/v1/users/<id>`
  when `clerk_id` present). API: `GAP`. v2: missing.
  New endpoint: `DELETE /api/v1/admin/customers/<id>` (with Clerk delete).
- [x] **Adjust customer wallet** — Web: `POST /admin-xyz1331/customer/adjust-wallet` — DONE v3 Fix #3/#4: AdminCustomersView.swift
  (`admin.py:3381`). API: `GAP`. v2: missing.
  New endpoint: `POST /api/v1/admin/customers/<id>/adjust-wallet`.
- [x] **Adjust customer loyalty points** — Web: `POST /admin-xyz1331/customer/adjust-points` — DONE v3 Fix #3/#4: AdminCustomersView.swift
  (`admin.py:3461`). API: `GAP`. v2: missing.
  New endpoint: `POST /api/v1/admin/customers/<id>/adjust-points`.
- [x] **Reset a customer password** — Web: `POST /admin-xyz1331/customer/reset-password` — DONE v3 Fix #3/#4: AdminCustomersView.swift
  (`admin.py:3495`). API: `GAP`. v2: missing.
  New endpoint: `POST /api/v1/admin/customers/<id>/reset-password`.
- [x] **Email a customer** — Web: `POST /admin-xyz1331/customer/send-email` (`admin.py:3545`). — DONE v3 Fix #3/#4: AdminCustomersView.swift
  API: `GAP`. v2: missing. New endpoint: `POST /api/v1/admin/customers/<id>/send-email`.
- [x] **Create a customer** — Web: `POST /admin-xyz1331/customer/create` (`admin.py:3578`): — DONE v3 Fix #3/#4: AdminCustomersView.swift
  name/email/phone, temp password, initial wallet balance; **provisions a Clerk user**
  (`POST https://api.clerk.com/v1/users`, or links the existing Clerk user by email).
  API: `GAP`. v2: missing. New endpoint: `POST /api/v1/admin/customers` (with Clerk provision).
- [x] **Export customers** — Web: `GET /admin-xyz1331/customer/export` (`admin.py:3699`). — DONE v3 Fix #3/#4: AdminCustomersView.swift
  API: `GAP`. v2: missing. New endpoint: `GET /api/v1/admin/customers/export`.
- [x] **Bulk customer action** — Web: `POST /admin-xyz1331/customer/bulk-action` — DONE v3 Fix #3/#4: AdminCustomersView.swift
  (`admin.py:3777`). API: `GAP`. v2: missing.
  New endpoint: `POST /api/v1/admin/customers/bulk-action`.

### 2.4 Services (platforms)

- [x] **Services list + create + edit + delete** — Web: `POST /admin-xyz1331/services/add`
  (`admin.py:1717`), `/services/edit` (`admin.py:1738`), `/services/delete` (`admin.py:1770`);
  list rendered in the dashboard catalog section (`admin_services_catalog.html`).
  API: `COVERED` (`GET/POST /api/v1/admin/services`, `PUT/DELETE /api/v1/admin/services/<id>`).
  v2: AdminView services with stock edit present — verify create/delete work live.

### 2.5 Wallet, gift cards, transactions, payment methods

- [x] **Wallet deposits (admin)** — Web: `GET /admin-xyz1331/wallet` (`admin.py:2666`, — DONE v3 Fix #3/#4: AdminWalletView.swift
  `admin_wallet.html`), `POST /admin-xyz1331/wallet/deposit/approve` (`admin.py:2735`),
  `/wallet/deposit/reject` (`admin.py:2825`), `/wallet/adjust` (`admin.py:2870`).
  API: `GAP`. v2: missing. New endpoints: `GET /api/v1/admin/wallet`,
  `POST /api/v1/admin/wallet/deposit/<id>/approve|reject`, `POST /api/v1/admin/wallet/adjust`.
- [x] **Gift cards (admin)** — Web: `GET /admin-xyz1331/gift-cards` (`admin.py:2358`, — DONE v3 Fix #3/#4: AdminWalletView.swift
  `admin_gift_cards.html`), `POST .../gift-cards/issue` (`admin.py:2417`),
  `/resend` (`admin.py:2481`), `/approve` (`admin.py:2519`), `/reject` (`admin.py:2590`),
  `POST /admin-xyz1331/settings/gift-cards` (feature toggle, `admin.py:2636`).
  API: `GAP`. v2: missing. New endpoints: `GET /api/v1/admin/gift-cards`,
  `POST /api/v1/admin/gift-cards/issue|resend|approve|reject`,
  `POST /api/v1/admin/settings/gift-cards`.
- [x] **Transactions** — Web: `GET /admin-xyz1331/transactions` (`admin.py:2282`, — DONE v3 Fix #3/#4: AdminWalletView.swift
  `admin_transactions.html`), `POST /admin-xyz1331/transactions/verify` (`admin.py:2303`).
  API: `GAP`. v2: missing. New endpoints: `GET /api/v1/admin/transactions`,
  `POST /api/v1/admin/transactions/<id>/verify`.
- [x] **Payment methods + gateway switch** — Web: `GET/POST /admin-xyz1331/payment-methods` — DONE v3 Fix #3/#4: AdminWalletView.swift
  (`admin.py:2960`, `admin_payment_methods.html`, 45 KB), `POST .../quick-switch`
  (`admin.py:3110`), `POST /admin-xyz1331/settings/gateway` (`admin.py:1098`, mpesa vs
  stk/intasend). API: `GAP`. v2: missing. New endpoints:
  `GET/POST /api/v1/admin/payment-methods`, `POST /api/v1/admin/settings/gateway`.
- [x] **Coupons (admin)** — Web: `GET/POST /admin-xyz1331/coupons` (`coupons.py:72`, — DONE v3 Fix #3/#4: AdminContentView.swift
  `coupons.html`, 30 KB: create/edit/list with expiry, max redemptions, min amount,
  customer type, service restriction, discount type/value), `GET /api/admin/coupons/<id>/redemptions`
  (`coupons.py:134`), `POST /admin-xyz1331/coupons/blast` (`coupons.py:154`, email a coupon
  to customers). API: `GAP`. v2: missing. New endpoints: `GET/POST /api/v1/admin/coupons`,
  `PUT/DELETE /api/v1/admin/coupons/<id>`, `GET /api/v1/admin/coupons/<id>/redemptions`,
  `POST /api/v1/admin/coupons/blast`.

### 2.6 Content, tickets, waitlist, broadcast, settings

- [x] **Blog (admin)** — Web: `GET /admin-xyz1331/blog` (`blog.py:51`, `admin_blog.html`), — DONE v3 Fix #3/#4: AdminContentView.swift
  `GET/POST /admin-xyz1331/blog/new` (`blog.py:61`), `/blog/<id>/edit` (`blog.py:96`),
  `POST /admin-xyz1331/blog/<id>/delete` (`blog.py:136`); editor `admin_blog_edit.html`.
  API: `GAP`. v2: missing. New endpoints: `GET/POST /api/v1/admin/blog`,
  `PUT/DELETE /api/v1/admin/blog/<id>`.
- [x] **Help articles (admin)** — Web: `GET /admin-xyz1331/help` (`help.py:66`, `admin_help.html`), — DONE v3 Fix #3/#4: AdminContentView.swift
  `GET/POST /admin-xyz1331/help/new` (`help.py:76`), `/help/<id>/edit` (`help.py:112`),
  `POST /admin-xyz1331/help/<id>/delete` (`help.py:147`); editor `admin_help_edit.html`.
  API: `GAP`. v2: missing. New endpoints: `GET/POST /api/v1/admin/help`,
  `PUT/DELETE /api/v1/admin/help/<id>`.
- [x] **Support tickets** — Web: `POST /admin-xyz1331/ticket/resolve` (`admin.py:1177`), — DONE v3 Fix #3/#4: AdminOpsView.swift
  `POST /admin-xyz1331/ticket/delete` (`admin.py:1199`); tickets listed in the dashboard
  support section (`admin_support_tickets.html`). API: `GAP`. v2: missing.
  New endpoints: `GET /api/v1/admin/tickets`, `POST /api/v1/admin/tickets/<id>/resolve|delete`.
- [x] **Waitlist message** — Web: `POST /admin-xyz1331/waitlist/message` (`admin.py:1118`). — DONE v3 Fix #3/#4: AdminOpsView.swift
  API: `GAP`. v2: missing. New endpoint: `POST /api/v1/admin/waitlist/message`.
- [x] **Suggested services (admin)** — Web: `POST /admin-xyz1331/suggestion/delete` — DONE v3 Fix #3/#4: AdminOpsView.swift
  (`admin.py:1211`); list in `admin_waitlist_suggestions.html`. API: `GAP`. v2: missing.
  New endpoints: `GET /api/v1/admin/suggestions`, `DELETE /api/v1/admin/suggestions/<id>`.
- [x] **Bulk email** — Web: `POST /admin-xyz1331/bulk-email` (`admin.py:564`), — DONE v3 Fix #3/#4: AdminOpsView.swift
  `admin_bulk_email_global.html`. API: `GAP`. v2: missing.
  New endpoint: `POST /api/v1/admin/bulk-email`.
- [x] **Broadcast message** — Web: `POST /admin-xyz1331/broadcast` (`admin.py:1075`). — DONE v3 Fix #3/#4: AdminOpsView.swift
  API: `GAP`. v2: missing. New endpoint: `POST /api/v1/admin/broadcast`.
- [x] **Promo banner settings** — Web: `POST /admin-xyz1331/settings/promo_banner` — DONE v3 Fix #3/#4: AdminOpsView.swift
  (`admin.py:2211`). API: `GAP`. v2: missing.
  New endpoint: `POST /api/v1/admin/settings/promo-banner`.
- [x] **Gift-card feature toggle** — Web: `POST /admin-xyz1331/settings/gift-cards` — DONE v3 Fix #3/#4: AdminWalletView.swift
  (`admin.py:2636`). API: `GAP` (see §2.5). v2: missing.

### 2.7 Security, backup, recycle bin

- [x] **Security logs** — Web: `GET /admin-xyz1331/security-logs` (`admin.py:1852`, — DONE v3 Fix #3/#4: AdminOpsView.swift
  `admin_security_logs.html`), `GET .../security-logs/export` (`admin.py:1919`),
  `POST .../security-logs/purge` (`admin.py:1962`),
  `POST .../security-logs/revoke/<log_id>` (`admin.py:1974`). API: `GAP`. v2: missing.
  New endpoints: `GET /api/v1/admin/security-logs`,
  `POST /api/v1/admin/security-logs/purge|revoke/<id>`.
- [x] **Backup** — Web: `GET /admin-xyz1331/backup` (`admin.py:1985`, `admin_backup.html`: — DONE v3 Fix #3/#4: AdminOpsView.swift (AdminBackupStatusView: status only, no download/upload)
  DB tables + stats), `GET /admin-xyz1331/backup/download` (`admin.py:2049`),
  `POST /admin-xyz1331/backup/upload` (`admin.py:2110`). API: `GAP`. v2: missing.
  **Recommendation: keep backup download/upload web-only** (large files, destructive restore);
  a mobile backup *status* view is the most that belongs in the app.
- [ ] **Raw DB query** — Web: `POST /admin-xyz1331/db/query` (`admin.py:2012`).
  API: none, and **do not build one** — a raw-SQL endpoint in a mobile API is a security
  hole, not parity. Keep web-only, permanently.
- [x] **Recycle bin** — Web: `GET /admin-xyz1331/recycle-bin` (`admin.py:2226`, — DONE v3 Fix #3/#4: AdminOpsView.swift
  `recycle_bin.html`: `Archive_Users` / `Archive_Subscriptions`),
  `POST /admin-xyz1331/recycle-bin/restore` (`admin.py:2246`). API: `GAP`. v2: missing.
  New endpoints: `GET /api/v1/admin/recycle-bin`, `POST /api/v1/admin/recycle-bin/restore`.

---

## 3. CLERK AUTH — the exact web flow (verified in code)

### 3.1 What Clerk is on the web

- Clerk JS SDK v5, loaded from CDN in every base template:
  `https://cdn.jsdelivr.net/npm/@clerk/clerk-js@5/dist/clerk.browser.js`
  (`templates/base.html:100`, `app_base.html:91`, `auth_base.html:43`, `app_auth_base.html:40`,
  `clerk_sync.html:28`). Publishable key comes from env var **`NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY`**
  or **`CLERK_PUBLISHABLE_KEY`** (jinja global `clerk_publishable_key`, `app/__init__.py:155`).
  **Record the env var names only — never the key value.**
- Clerk domain in CSP (`app/__init__.py:437-443`): `https://clerk.premiumslots.tech`,
  `https://*.clerk.accounts.dev`, `https://*.clerk.com`, images `https://images.clerk.dev` /
  `https://img.clerk.com`, `https://challenges.cloudflare.com` (Cloudflare Turnstile).
- Server-side: `clerk_backend_api` (Clerk Python SDK) + `svix` for webhooks.
  Secrets (env names only): `CLERK_SECRET_KEY`, `CLERK_WEBHOOK_SECRET`. Both live server-side only.
- Privacy policy + Terms state it plainly: "Account authentication (passwords, social logins, and
  secure sessions) is securely handled by our identity provider Clerk… Our administrators cannot
  see your password."

### 3.2 Sign-in / sign-up (the live flow)

1. `GET /auth/login` → renders `clerk_login.html`; `GET /auth/register` → `clerk_register.html`
   (referral code `?ref=` is captured into `session["pending_ref_code"]` first).
   Both pages mount the Clerk component into a div (`#clerk-sign-in` / `#clerk-sign-up`) after
   `Clerk.load({ appearance: { variables: { colorPrimary: '#2D9CE5',
   colorBackground: light '#ffffff' / dark '#141414', colorText: light '#141414' / dark '#ffffff',
   colorInputBackground: light '#f5f5f5' / dark '#1a1a1a', colorInputText, colorTextSecondary
   (light '#3C6480' / dark '#9a9a9a'), colorNeutral, colorTextOnPrimaryBackground: '#ffffff' } } })`.
   In the app webview (`g.is_app` true) the Clerk social buttons + divider are hidden
   (`socialButtonsBlockButton: 'hidden'`, `dividerRow: 'hidden'`).
2. `Clerk.mountSignIn` / `mountSignUp` with `fallbackRedirectUrl` = `forceRedirectUrl` =
   `/auth/clerk_sync` (plus `?next=` passthrough when present).
3. `POST /auth/login` and `POST /auth/register` return **400 `{"error": "Login is handled via
   Clerk"}` / `{"error": "Registration is handled via Clerk"}`** — there is no working
   email/password login through these routes. (The deployed `api_v1` login/register are a
   separate, parallel own-auth path — see §3.5.)
4. Loading state on both pages: a 40px ring spinner (border 4px, track `var(--border)`,
   `border-left-color: var(--primary)`, `spin 1s linear infinite`) + "Loading Secure Portal...".
   Error states: "Error loading Clerk: …" / "Clerk failed to load completely. Check your
   adblocker or publishable key."

### 3.3 Session sync (the bridge between Clerk and the Flask session)

`GET/POST /auth/clerk_sync` (`auth.py:80`):

1. Takes the Clerk session JWT from the `__session` cookie (fallback: any `__session_*` or
   `__clerk_db_jwt` cookie, or a POSTed `token` field from `clerk_sync.html`).
2. Base64-decodes the JWT payload and reads `sub` (the Clerk user id). **No signature
   verification happens in Python** — trust comes from step 3.
3. Calls Clerk Backend API `GET https://api.clerk.com/v1/users/<clerk_user_id>` with
   `CLERK_SECRET_KEY`. On non-200 it flashes "Clerk API error" and redirects home.
4. Takes the first email address + first/last name. Looks up `Users` by email; if none, inserts
   `(name, email, is_verified=TRUE, whatsapp_number='', password_hash='', clerk_id)`; if found,
   updates `clerk_id`. Sets `session["user_id"]`, `session.permanent = True`, `track_login()`.
5. If `whatsapp_number` or `date_of_birth` is missing → redirect `/auth/onboarding`; else
   redirect `/` (or `?next=` if it starts with `/`).
6. Failure mode is explicit: `clerk_sync.html` shows "Session Sync Failed — this happens if your
   browser blocks third-party cookies…" with a "Return to Homepage" link.

### 3.4 Session persistence, refresh, logout

- Flask session: server-side sessions (Redis when configured, else filesystem),
  `SESSION_COOKIE_HTTPONLY=True`, `SESSION_COOKIE_SAMESITE='Lax'`, `SESSION_COOKIE_SECURE=True`,
  `SESSION_PERMANENT=True`, **`PERMANENT_SESSION_LIFETIME = 7 days`** (`app/__init__.py:79-106`).
  There is **no refresh endpoint on the server** — the 7-day Flask session is the session;
  Clerk's own JS SDK refreshes the Clerk token in the browser automatically (`getToken()`).
- Max 3 sessions per user (`MAX_SESSIONS_PER_USER = 3`, `enforce_session_limit`); every login is
  tracked in `LoginActivity` (device label from user-agent, IP, signed_in_at, last_seen_at,
  revoked_at); a login from a new IP raises a "New Login Detected" notification + admin email.
- Logout: `POST/GET /auth/logout` pops `user_id`; `GET /auth/clerk_logout_sync` does the same
  after Clerk signs out. The navbar mounts a Clerk `UserButton` with
  `afterSignOutUrl: '/auth/clerk_logout_sync'`, and auto-syncs: if `Clerk.session` exists but
  Python has no `user_id`, the navbar JS posts the token to `/auth/clerk_sync` immediately.
- Settings page mounts `Clerk.mountUserProfile` (`settings.html:341-347`) — profile editing is
  Clerk-managed on the web, not a custom form.

### 3.5 The parallel own-auth path (still live — do not delete it in the audit)

- Own email/password still works end-to-end in parallel: `POST /auth/verify` (email code),
  `POST /auth/forgot_password` (15-min reset token), `POST /auth/reset_password_confirm`,
  `POST /auth/magic` + `GET /auth/magic/<token>` (one-time magic link, `MagicLinkTokens`),
  `POST /auth/profile/password` (change, strong-password rule), WebAuthn passkeys (§1.10).
  `Users.password_hash` is a Werkzeug hash; Clerk-created users have an empty hash.
- The deployed `api_v1` auth (`POST /api/v1/auth/register|login|logout`, `GET /api/v1/auth/me`)
  uses this own-auth path (Werkzeug hashes + Flask session cookie), **not Clerk**.
  Consequence: a user who signed up through Clerk has no usable password, so api_v1 login
  cannot sign them in — the v2 app's current AuthView only works for own-auth accounts.
- Admin ↔ Clerk sync (server-side, `CLERK_SECRET_KEY`): ban/unban syncs to Clerk
  (`/v1/users/<id>/ban|unban`); deleting a customer deletes the Clerk user; creating a customer
  provisions (or links) a Clerk user. The app must never call the Clerk Backend API directly
  with the secret key — all of this stays server-side.
- Webhook: `POST /api/webhooks/clerk` (`api.py:252`, Svix-verified with `CLERK_WEBHOOK_SECRET`):
  `user.created` → insert verified user; `user.updated` → ban sync; `user.deleted` → delete
  Subscriptions, SupportTickets, Waitlist, FinancialLedger, NotificationQueue, hostlistings,
  then the user. The app needs no webhook handling.

### 3.6 What iOS needs for Clerk (decision, not code)

- [ ] **Option A (recommended): Clerk iOS SDK** — EVALUATED in v3 and NOT taken: the SPM dependency cannot be verified on a Linux machine (no Swift toolchain), and adding it risks breaking the green Actions build; the WKWebView route (Option B) is implemented instead. Clerk ships a native Swift SDK
  (`clerk/clerk-ios`). Use the same publishable key (env var name as above; the value must be
  supplied at build time, never committed). Native sign-in/sign-up, `Clerk.session.getToken()`,
  automatic token refresh. **Then a new backend endpoint is required**:
  `POST /api/v1/auth/clerk-sync` accepting `{ "token": "<Clerk JWT>" }`, doing exactly what
  `auth.py:clerk_sync` does (Backend API lookup, find-or-create user, set Flask session,
  onboarding check) but returning JSON `{"ok": true, "user": {...}, "needs_onboarding": bool}`
  and setting the session cookie — the current `clerk_sync` returns redirects/HTML and cannot
  be used from native code as-is. Role routing: Clerk has **no admin concept here** — admin
  stays the separate password session (`POST /api/v1/admin/login`); the app must keep the two
  sessions separate exactly as the web does.
- [x] **Option B (fallback): hosted Clerk in a WKWebView** — IMPLEMENTED in v3 (`PremiumSlots/Views/ClerkAuthView.swift`): load `/auth/login` in a web view,
  let Clerk JS run, then the redirect to `/auth/clerk_sync` sets the Flask session cookie in
  the shared cookie jar, which `APIClient` already uses. Works with zero new backend code, but
  the sign-in UI is a web page, not native, and `g.is_app` already hides social buttons in
  that webview. Keep as the fallback if the native SDK integration stalls.
- [x] **Clerk sign-out must clear both sessions**: v3 (`AppState.logout()` calls `POST /api/v1/auth/logout` + `ClerkSessionStore.clearAll()`): Clerk `signOut()` + `POST /api/v1/auth/logout`
  (and the admin session separately). Verify the Flask cookie is actually cleared on sign-out.
- [x] **Clerk UserProfile parity**: the web settings page mounts Clerk's UserProfile. On iOS — DONE v3 Fix #3/#4: AccountView.swift (native port of the fields; not a Clerk SDK mount)
  either mount Clerk's profile UI (SDK) or port the fields (name, WhatsApp, email, password,
  passkeys, sessions, delete account) as native screens backed by the §1.10 endpoints.

---

## 4. THEME + SPINNER (exact web values)

### 4.1 Light mode exists on the web — it is real and complete

- Theme system: `data-theme="dark"` (default) / `data-theme="light"` on `<html>`, bootstrapped
  before render in every base template (`base.html`, `app_base.html`, `auth_base.html`,
  `app_auth_base.html`, `base_admin.html`, `app_admin_base.html`): stored value from
  `localStorage['theme']`, else `prefers-color-scheme`, else `'dark'` (admin bases default to
  `'dark'` even without a stored value). Toggle: `window.PS_setTheme` / `PS_toggleTheme`
  (footer + admin sidebar), `meta[name="theme-color"]` flips `#0a0a0a` ↔ `#f5f5f0`,
  `[data-theme-switching]` disables all transitions for one frame so the flip renders cleanly,
  logo swaps `logo.svg` ↔ `logo-light.svg`, Clerk appearance variables switch with `isLight`.
  **The v2 app currently has dark mode only. Light mode is missing — that is Fix #1, not a
  web gap.**

### 4.2 Public site tokens — `static/style.css` `:root` (dark) + `[data-theme="light"]`

```css
:root { /* Void Dark Theme */
  --bg: #0a0a0a; --bg-darker: #050505;
  --surface: #141414; --surface-hover: #1a1a1a;
  --border: #1f1f1f; --border-light: #2a2a2a;
  --text-main: #f5f5f5; --text-dim: #c0c0c0; --text-muted: #6a6a6a;
  --primary: #2D9CE5; --primary-hover: #55B7F7; --primary-dim: #1E85CC;
  --primary-soft: rgba(45,156,229,0.14); --primary-glow: rgba(45,156,229,0.45);
  --accent-gradient: linear-gradient(135deg, #7FCDFF 0%, #2D9CE5 50%, #1E85CC 100%);
  --btn-gradient: linear-gradient(135deg, #55B7F7 0%, #2D9CE5 100%);
  --nav-glass: rgba(10,10,10,0.85);
  --card-shadow: 0 24px 48px -24px rgba(0,0,0,0.6);
  --danger: #f43f5e; --danger-bg: rgba(244,63,94,0.1);
  --success: #10b981; --success-bg: rgba(16,185,129,0.1);
  --warning: #f59e0b; --warning-bg: rgba(245,158,11,0.1);
  --silver: #C8C8C8; --silver-dim: #5a5a5a;
  --radius-sm: 4px; --radius-md: 12px; --radius-lg: 16px;
  --ease: cubic-bezier(0.22,1,0.36,1);
}
[data-theme="light"] {
  --bg: #f5f5f0; --bg-darker: #ebeae4;
  --surface: #ffffff; --surface-hover: #f0f0ec;
  --border: #d9d9d4; --border-light: #e5e5e0;
  --text-main: #1a1a1a; --text-dim: #404040; --text-muted: #7a7a7a;
  --primary: #1E85CC; --primary-hover: #176FB0; --primary-dim: #135E95;
  --primary-soft: rgba(30,133,204,0.12); --primary-glow: rgba(30,133,204,0.3);
  --accent-gradient: linear-gradient(135deg, #55B7F7 0%, #1E85CC 50%, #135E95 100%);
  --btn-gradient: linear-gradient(135deg, #4FB2F0 0%, #1E85CC 100%);
  --nav-glass: rgba(245,245,240,0.85);
  --card-shadow: 0 24px 48px -24px rgba(0,0,0,0.12);
  --danger: #ef4444; --danger-bg: rgba(239,68,68,0.1);
  --success: #10b981; --success-bg: rgba(16,185,129,0.1);
  --warning: #f59e0b; --warning-bg: rgba(245,158,11,0.1);
  --silver: #7a7a7a; --silver-dim: #404040;
}
```

### 4.3 App shell tokens — `static/app_style.css` `:root`

```css
:root {
  --app-bottom-nav-height: 72px;
  --app-primary: #1E85CC;
  --app-bg: #f5f5f0;
  --app-ease: cubic-bezier(0.23,1,0.32,1);
  --bg: #0a0a0a; --text-main: #f5f5f5;   /* dark default */
}
[data-theme="light"] { --bg: #f5f5f0; --text-main: #1a1a1a; }
```

Bottom nav (the web's app shell, 72px + safe-area): glass background
(`blur(18px) saturate(1.4)`), 24px icons, active item lifts −2px / scales 1.08 with a
36×3px gradient top indicator (`linear-gradient(90deg, #55B7F7, #1E85CC)`), tap scales 0.88.
Auth screens: gradient background `linear-gradient(160deg, #55B7F7, #1E85CC 55%, #176FB0)`,
white card `rgba(255,255,255,0.96)`, radius 28px, entry animation `appCardIn`
(translateY 22px → 0, scale 0.98 → 1, 0.6s). **This is the closest web equivalent of the
iOS tab bar + sheet — port its metrics, not just its colours.**

### 4.4 Admin tokens — `static/admin_style.css` `:root` (monochrome, deliberately not blue)

```css
:root { /* dark */
  --bg: #050505;
  --surface: rgba(255,255,255,0.02); --surface-hover: rgba(255,255,255,0.04);
  --border: rgba(255,255,255,0.06);
  --text-main: #ffffff; --text-muted: #8b9bb4;
  --primary: #ffffff; --primary-hover: #e2e8f0; --primary-dim: #94a3b8;
  --primary-soft: rgba(255,255,255,0.05); --primary-glow: rgba(255,255,255,0.1);
  --accent-gradient: linear-gradient(135deg, #ffffff 0%, #cbd5e1 100%);
  --btn-gradient: linear-gradient(135deg, #ffffff 0%, #e2e8f0 100%);
  --danger: #f43f5e; --success: #10b981; --warning: #f59e0b;
  --radius-sm: 6px; --radius-md: 10px; --radius-lg: 14px;
  --ease: cubic-bezier(0.23,1,0.32,1);
  --chart-grid: rgba(255,255,255,0.06);
}
[data-theme="light"] {
  --bg: #f8fafc; --surface: #ffffff; --surface-hover: #f1f5f9;
  --border: rgba(0,0,0,0.08);
  --text-main: #0f172a; --text-muted: #64748b;
  --primary: #0f172a; --primary-hover: #334155; --primary-dim: #475569;
}
```

Auth pages (`static/auth_style.css`): hue 205, bg-deep #0a0a0a, primary #2D9CE5,
btn gradient 135deg #55B7F7 → #1E85CC, glass panels, sidebar image `auth_sidebar.jpg`;
light overrides exist (`[data-theme="light"]` block at line 32; left visual panel keeps its
dark photo treatment in both themes).

### 4.5 Fonts (web)

- Body/headings: **Archivo**, **Plus Jakarta Sans**. Display: **Bebas Neue** (hero),
  **Oswald** (section heads, labels). Mono: **JetBrains Mono** (codes, stats, HUD lines).
  App shell / stat cards: **Space Grotesk**. iOS mapping: use SF Pro (system) with matching
  weights, SF Mono for JetBrains Mono; Bebas/Oswald display type → system bold with tight
  tracking, or bundle the real fonts if licensed. **Do not invent a new typeface.**

### 4.6 The exact loading spinner (the site's real loader — HUD loader)

The live homepage loader is `templates/partials/loader.html` (171 lines, included at
`index.html:13` as "FULLSCREEN CUSTOM UIVERSE LOADER"). It is **not** a plain ring — it is a
HUD scene. Exact spec, copy faithfully:

- **Wrapper**: `#loader-wrapper`, fixed inset 0, `z-index: 9999`, background `var(--bg, #0a0a0a)`,
  flex center, fade out over 0.6s (`opacity` + `visibility`) after `window load + 1500ms`,
  then removed from the DOM after a further 600ms.
- **Background**: `.ps-hud-grid` — absolute, inset −50%, 50px grid of
  `rgba(45,156,229,0.15)` lines, `perspective(600px) rotateX(60deg) translateY(-100px)
  translateZ(-200px)`, animating `psGridMove` 8s linear infinite (translateY 0 → 50px).
- **Rings** (container 240×240, `margin-bottom: 50px`):
  - outer: 2px dashed `rgba(85,183,247,0.3)` circle, `psSpinRight` **20s linear infinite**;
  - middle: inset 15px, 3px transparent border with top `#55B7F7` / bottom `#2D9CE5`,
    `psSpinLeft` **3s cubic-bezier(0.68,-0.55,0.265,1.55)** infinite (counter-clockwise);
  - inner: inset 35px, 1px border, left edge 2px `#7FCDFF`, `psSpinRight` **5s linear infinite**;
  - core: inset 55px, radial gradient `rgba(45,156,229,0.2)` → transparent,
    `psPulseOpacity` 2s ease-in-out infinite alternate (opacity 0.3 → 1).
- **Logo**: `.ps-hud-logo`, **60×60**, `logo-icon.svg`, `object-fit: contain`,
  `border-radius: 12px`, pulsing `psHudPulse` 2s ease-in-out infinite alternate
  (scale 0.95 → 1.05, opacity 0.75 → 1). **This is the correct launch/logo size on the web —
  60px, not 512px (see §5).**
- **Progress bar**: 320×4px container, track `rgba(45,156,229,0.2)`; bar gradient
  `linear-gradient(90deg, #1E85CC, #2D9CE5, #7FCDFF)` with `box-shadow: 0 0 10px #2D9CE5`,
  `psProgressFill` 2s `cubic-bezier(0.77,0,0.175,1)` infinite — scaleX 0→1 from the left,
  then 1→0 from the right.
- **Text**: `.ps-hud-text` — Space Grotesk, 0.9rem, letter-spacing 0.3em, uppercase, weight 700,
  colour `#7FCDFF`, glow `0 0 8px rgba(45,156,229,0.5)`, text **"ESTABLISHING CONNECTION"**.
- **Corner data** (JetBrains Mono, 0.75rem, `#55B7F7`, opacity 0.5, absolute corners 30px):
  TL `SYS.INIT... / MEM: OK / NET: SECURE`; TR `AUTH: PENDING / KEY: 0x9A2F / ENC: AES-256`;
  BL `LOC: NAIROBI / LAT: -1.2921 / LNG: 36.8219`; BR `VER: 2.4.1 / BULD: 9812 / STS: ONLINE`.
  (These are decorative HUD strings on the web page; in the app, keep them only on the
  launch/loading screen, and do not present the version/build numbers as the app's own.)
- **SwiftUI reproduction**: 3 concentric `Circle().stroke` rings with `.rotationEffect` driven by
  `withAnimation(.linear(duration: 20/3/5).repeatForever(autoreverses: false))` (middle reversed),
  core `RadialGradient` with opacity pulse, logo `Image("LaunchLogo")` 60×60 with scale/opacity
  pulse, progress bar as a `GeometryReader` scaleX animation (left-origin then right-origin),
  mono corner labels. Use `ProgressView` nowhere — the HUD loader replaces it everywhere.

### 4.7 Secondary spinners (use these in buttons / inline loading, not the HUD loader)

- **Inline ring** (used identically on login, register, Clerk sync, settings, security pages):
  40px circle, 4px border, track `var(--border)` / `rgba(255,255,255,0.1)`,
  `border-left-color: #2D9CE5`, `border-radius: 50%`, `spin 1s linear infinite`
  (`@keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }`).
  Small variants: 32px/3px (`animation: spin 0.8s`), 24px/2px and 20px/2px (`spin 1s`),
  18px/2px and 14px/2px white track (`spin 1s ease-in-out`) inside buttons.
- **Button spinner** (`style.css:734` + `:1181`): 14px (later override 15px), 2px border,
  `border-top-color: currentColor`, `btnSpin 0.7s linear infinite`; modern conic variant:
  `background: conic-gradient(from 0deg, transparent 0deg 50deg, currentColor 360deg)` with a
  radial mask ring (2.5px). Button in loading state: `pointer-events: none; opacity: 0.85`,
  label opacity 0.6, spinner shown after the label with 8px left margin.
- **Checkout receipt spinner** (`checkout.html:279-284`): 18px SVG icon, `spin 1s linear infinite`,
  inside `.icon-spin-wrapper`, shown during processing/printing stages, hidden on complete.
- **`.pl` Uiverse loader** (`style.css:355-377`, `admin_style.css:211-236`): 9.375em (150px) SVG
  with 4 animation groups (`arrows42` rotate 45°→405°, `ringRotate42` 0°→720°,
  `ringStroke42` dashoffset 452→169.5, `tick42` dashoffset −12→0, all 2s linear infinite,
  8 ticks staggered −0.25s each). **Usage not verified**: no template in the audited set was
  confirmed to render the `.pl` SVG markup — the live homepage loader is the HUD loader (§4.6).
  Do not port `.pl` as "the" site loader; port the HUD loader, and only add `.pl` if a page is
  later found using it.
- **No skeleton loaders anywhere** (0 hits for "skeleton" in app/templates/static).

---

## 5. LAUNCH SCREEN — why the v2 logo is over-zoomed (verified in the workspace project)

- **Current state** (`PremiumSlots/Info.plist:23-31`): `UILaunchScreen` dict with
  `UIColorName` = `LaunchBackground` (#050505 — colorset rgba 0.02,0.02,0.02),
  `UIImageName` = `LaunchLogo`, `UIImageRespectsSafeAreaInsets` = true.
- **The asset** (`PremiumSlots/Assets.xcassets/LaunchLogo.imageset/Contents.json`): **a single
  entry, `1x` universal, filename `launch-logo.png`, 512×512 RGBA (50,786 bytes)**,
  `template-rendering-intent: original`. There are no @2x/@3x variants.
- **Exact cause**: `UILaunchScreen` has **no contentMode / resizeMode control** — it lays the
  image out at its intrinsic point size. A 512px asset at 1x = **512pt wide on a ~390pt-wide
  iPhone screen**, so the shield is cropped and over-zoomed. Compounding it, the artwork is
  full-bleed: `logo-icon.svg` (viewBox 0 0 100) fills its frame edge-to-edge, and
  `brand/generated/launch-logo.png` is a full-bleed 512×512 render of it — no padding at all.
  (For comparison, the web loader shows the same logo at **60×60** — §4.6.)
- **Exact fix** (do one of these, in order of preference):
  1. **Regenerate the launch asset at the right size**: target **~120pt** wide on screen.
     Imageset with three scales from the real `brand/logo-icon.svg`, with the shield drawn at
     **~60–70% of the canvas** (transparent padding around it): 1x = 120px, 2x = 240px,
     3x = 360px. Keep `LaunchBackground` #050505.
  2. **Or replace `UILaunchScreen` with a `LaunchScreen.storyboard`**: a `UIImageView` with
     `contentMode = scaleAspectFit` (the `resizeMode="contain"` equivalent) and a width
     constraint of ~120pt, centred, on a #050505 background. This is the only way to get a
     true "contain" behaviour — `UILaunchScreen` cannot do it.
  3. Do **not** fix it by shrinking the PNG to 512px-but-smaller-file or by adding a second
     1x asset — the point size is what matters, not the file size.
- **Verify on device**: launch logo must read as a centred ~120pt shield with clear black
  space around it on every iPhone size (SE → Pro Max), in both orientations, in light and
  dark mode (the launch background stays #050505 in both — the web's loader is dark in both
  themes too).

---

## 6. API GAPS — what `/api/v1` still needs (endpoint list)

Deployed `/api/v1` today (`backend/api_v1.py`, 776 lines) covers: health, services (+detail),
auth register/login/logout/me, my subscriptions, one-time vault, notifications (list),
request (manual M-PESA), waitlist join, report-issue, toggle-auto-renew, wallet (balance +
last 50 transactions) + deposit, referrals (see defect below), admin login/logout/stats/
subscriptions (+approve/reject)/customers (+detail/toggle-ban)/services (CRUD).
**Known defects in the deployed API to fix first (FIXED in v3, 7 Nov 2026):**
1. `GET /api/v1/referrals` queried `Referrals WHERE user_id = %s`, but the web table has
   `referrer_id`/`referee_id` (no `user_id` column) — verify live; it likely errors or
   returns nothing. Rewrite against `referrer_id` and add my code/link/counts/inviter/top-3.
2. `_subscription_row` hardcoded `created_at: None` — v3 returns the real timestamp plus `locked_price` when present.
3. No `locked_price` anywhere — add it once the production column is confirmed.

### 6.1 New endpoints for Fix #2 (Clerk auth)

| Endpoint | Purpose |
|---|---|
| `POST /api/v1/auth/clerk-sync` | Accept Clerk JWT, do the `clerk_sync` flow, return JSON + set Flask session cookie (§3.6 A) |
| `POST /api/v1/auth/forgot-password` | 15-min reset token email |
| `POST /api/v1/auth/reset-password` | Consume reset token, set new password |
| `POST /api/v1/auth/verify` | Email verification code (legacy path) |
| `POST /api/v1/auth/magic` + `POST /api/v1/auth/magic/consume` | One-time magic-link sign-in |
| `GET/POST /api/v1/me/onboarding` | WhatsApp + date of birth after Clerk sign-in |
| `GET /api/v1/me/sessions` + `POST /api/v1/me/sessions/revoke` | Session list (device/IP) + revoke (max 3) |
| `POST /api/v1/auth/webauthn/register/begin|complete` | Passkey registration (JSON) |
| `POST /api/v1/auth/webauthn/authenticate/begin|complete` | Passkey sign-in (JSON) |
| `GET /api/v1/auth/webauthn/list` + `POST /api/v1/auth/webauthn/remove` | Passkey management |

### 6.2 New endpoints for Fix #4 (customer parity)

| Endpoint | Purpose |
|---|---|
| `GET /api/v1/me/dashboard` | Subs + ledger (50) + waitlist positions + unread count + global alert |
| `GET /api/v1/me/waitlist` | My waitlist positions |
| `GET/POST /api/v1/suggestions` | Community suggestions (top 10 + submit) |
| `POST /api/v1/coupons/validate` | Preview discount at checkout |
| `GET /api/v1/checkout/status/<ref>` + `POST /api/v1/pay/retry/<id>` + `POST /api/v1/pay/verify-manual/<id>` | STK checkout flow |
| `POST /api/v1/wallet/instant-renew/<id>` | 1-click wallet renewal |
| `POST /api/v1/wallet/redeem-gift-card` | Gift card → wallet |
| `GET /api/v1/wallet/statement` (+ PDF) | Wallet statement |
| `GET /api/v1/me/subscriptions/<id>/timeline` | Order timeline (OrderEvents) |
| `POST /api/v1/me/subscriptions/<id>/request-review` | Request a review |
| `GET /api/v1/gift-cards` + `POST /api/v1/gift-cards` + `POST /api/v1/gift-cards/redeem` + `GET /api/v1/gift-cards/verify/<code>` | Gift cards (page, create, redeem, verify) |
| `GET /api/v1/store` + `POST /api/v1/store/redeem/<id>` | Loyalty rewards store |
| `GET /api/v1/me/loyalty` | Points, tier, next tier, streak, Ledger |
| `GET /api/v1/me/achievements` | Badge definitions + earned set + stats |
| `GET /api/v1/leaderboard` | Monthly + all-time referral leaderboard |
| `GET /api/v1/wishlist` (query: category/status/sort/q) + `POST /api/v1/wishlist/vote|notify|submit` | Wishlist |
| `POST /api/v1/feedback` | Message admin |
| `GET /api/v1/me/tickets` + `POST /api/v1/tickets` | Support tickets |
| `GET /api/v1/help` + `GET /api/v1/help/<slug>` | Help centre |
| `GET /api/v1/blog` + `GET /api/v1/blog/<slug>` | Blog |
| `GET /api/v1/receipts/<id>` + `GET /api/v1/receipts/verify` | Receipt PDF + HMAC verify |
| `GET/POST /api/v1/me/gdpr-consent` + `POST /api/v1/me/export-request` | GDPR |
| `PUT /api/v1/me/profile` + `POST /api/v1/me/password` + `PUT /api/v1/me/privacy` + `DELETE /api/v1/me` | Profile, password, privacy, delete account |
| `GET /api/v1/me/birthday` + `POST /api/v1/me/birthday` | Birthday rewards |
| `POST /api/v1/me/notifications/read` (+ unread count on the list endpoint) | Notifications |

### 6.3 New endpoints for Fix #4 (admin parity)

| Endpoint | Purpose |
|---|---|
| `GET /api/v1/admin/analytics` (+ revenue, churn when real) | Analytics page + data |
| `GET /api/v1/admin/financial-engine` | Financial engine |
| `GET /api/v1/admin/export/csv` + `GET /api/v1/admin/report/pdf` | Exports |
| `POST /api/v1/admin/subscriptions/bulk-update` | Bulk update |
| `PUT /api/v1/admin/subscriptions/<id>` + `POST .../renew` + `POST .../cancel` + `DELETE ...` + `POST .../unhide` + `POST .../remind-expiry` | Subscription management |
| `POST /api/v1/admin/customers/<id>/toggle-emails` + `DELETE /api/v1/admin/customers/<id>` + `POST .../adjust-wallet` + `POST .../adjust-points` + `POST .../reset-password` + `POST .../send-email` + `POST /api/v1/admin/customers` + `GET /api/v1/admin/customers/export` + `POST /api/v1/admin/customers/bulk-action` | Customer management |
| `GET /api/v1/admin/wallet` + `POST /api/v1/admin/wallet/deposit/<id>/approve|reject` + `POST /api/v1/admin/wallet/adjust` | Wallet (admin) |
| `GET /api/v1/admin/gift-cards` + `POST /api/v1/admin/gift-cards/issue|resend|approve|reject` + `POST /api/v1/admin/settings/gift-cards` | Gift cards (admin) |
| `GET /api/v1/admin/transactions` + `POST /api/v1/admin/transactions/<id>/verify` | Transactions |
| `GET/POST /api/v1/admin/payment-methods` + `POST /api/v1/admin/settings/gateway` | Payment methods + gateway |
| `GET/POST /api/v1/admin/coupons` + `PUT/DELETE /api/v1/admin/coupons/<id>` + `GET .../redemptions` + `POST /api/v1/admin/coupons/blast` | Coupons (admin) |
| `GET/POST /api/v1/admin/blog` + `PUT/DELETE /api/v1/admin/blog/<id>` | Blog (admin) |
| `GET/POST /api/v1/admin/help` + `PUT/DELETE /api/v1/admin/help/<id>` | Help (admin) |
| `GET /api/v1/admin/tickets` + `POST /api/v1/admin/tickets/<id>/resolve|delete` | Support tickets |
| `POST /api/v1/admin/waitlist/message` + `GET /api/v1/admin/suggestions` + `DELETE /api/v1/admin/suggestions/<id>` | Waitlist + suggestions |
| `POST /api/v1/admin/bulk-email` + `POST /api/v1/admin/broadcast` + `POST /api/v1/admin/settings/promo-banner` | Comms + promo |
| `GET /api/v1/admin/security-logs` (+ export/purge/revoke) | Security logs |
| `GET /api/v1/admin/recycle-bin` + `POST /api/v1/admin/recycle-bin/restore` | Recycle bin |

### 6.4 Deliberately NOT ported (keep web-only)

- `POST /admin-xyz1331/db/query` — raw SQL from a mobile client is a security hole. Never build it.
- Backup download/upload — large files + destructive restore; a mobile backup *status* view at most.
- `GET /admin-xyz1331/fix-db` — one-off maintenance action.
- Spin wheel — no customer-facing feature exists in code; do not build it from the table alone.
- Cron endpoints + SEO files — server-side jobs/files, not screens.
- Clerk Backend API calls (ban/unban/delete/provision with `CLERK_SECRET_KEY`) — server-side only.

---

## 7. PRIORITISED BUILD ORDER

### Fix #1 — Launch + spinner + theme (no backend change; do first)

1. Regenerate the launch logo at 120/240/360px with padding (§5) — DONE in v3 (120/240/360 PNGs, visible shield ~66% of canvas) — or switch to a
   `LaunchScreen.storyboard` with `scaleAspectFit`. Verify on SE → Pro Max, both orientations.
2. Port the HUD loader (§4.6) as a SwiftUI view — DONE in v3 (`Views/PSLoaderView.swift`, used at app launch) — use it for app launch + full-screen loads.
   Port the inline ring + button spinner (§4.7) — DONE in v3 (`PSRingSpinner`, all `ProgressView()` calls replaced) — for buttons and inline loading. Remove all
   generic `ProgressView` usage.
3. Implement the full theme system from §4.2–§4.4 — DONE in v3 (dynamic `ps*` tokens in `Theme.swift`, `PSThemeMode` system/light/dark, default System): dark (default) + light, system-synced
   (follow `prefers-color-scheme` until the user chooses manually, exactly as the web does),
   persisted choice, both logo variants (`logo.svg` dark / `logo-light.svg` light), Clerk
   appearance variables switching with the theme, and the admin monochrome tokens for admin
   screens (or the public blue/cyan brand if Kerry chooses). Verify contrast on every screen.
4. Rebuild the IPA and have Kerry sideload to confirm the launch logo + theme before any
   feature work (same lesson as v2 Phase 0).

### Fix #2 — Clerk auth (backend first, then app)

1. Decide: Clerk iOS SDK (Option A, §3.6) or WKWebView hosted sign-in (Option B, fallback) — DECIDED in v3: Option B (`Views/ClerkAuthView.swift`); Option A evaluated and rejected as unverifiable on Linux.
   Option A needs `POST /api/v1/auth/clerk-sync` (JSON) on the server first.
2. Deploy the §6.1 auth endpoints (forgot/reset, magic link, onboarding, sessions, WebAuthn JSON) — DONE in v3 except WebAuthn JSON (not built: the web implementation was not available in the workspace to mirror exactly; deferred to Fix #4).
3. Replace AuthView with the Clerk flow — DONE in v3 (`Views/AuthView.swift` Clerk-first, `Views/ClerkAuthView.swift`, `AppState.checkSession/clerkSignedIn`): sign-in, sign-up, session persistence (7-day Flask
   session + Clerk token refresh), onboarding gate (WhatsApp + DOB), role-based routing —
   **customer session → customer tabs; admin password session → Admin tab; the two sessions
   stay separate, exactly as the web does** (there is no Clerk admin role to route on).
4. Sign-out must clear both the Clerk session and the Flask cookie — DONE in v3 (`AppState.logout()` + `ClerkSessionStore.clearAll()`). Verify with a Clerk-created
   account (which has no password — the current api_v1 login cannot sign such a user in).

### Fix #3 — iOS UI overhaul (HIG; app only, after Fix #1)

1. Navigation: 5 tabs kept (Catalogue, My Slots, How it works, Admin, Settings) + a real
   dashboard home (the web homepage is a dashboard, not a bare catalogue — §1.1).
2. Components from the web's own app shell (§4.3): 72px glass tab bar with the 36×3px gradient
   active indicator, 24px icons, 44px minimum touch targets (the web enforces 44px on coarse
   pointers), bottom sheets/modals with the web's `sheetUp` / `modalEnter` motion
   (translateY 48px → 0 / scale 0.95 → 1, ~0.35s, `cubic-bezier(0.22,1,0.36,1)`),
   card radii 12/16px (public) and 6/10/14px (admin), consistent 16/24px spacing.
3. Typography: capped scale (headings 22pt semibold max, body 15pt, captions 12pt — already in
   v2), Dynamic Type respected, SF Mono for codes/stats (JetBrains Mono equivalent).
4. States on every screen: loading (HUD/inline spinner), empty, error-with-retry, offline
   (labelled bundled data). No raw HTML error pages, no fake data.

### Fix #4 — Full customer + admin parity (backend + app, the long phase)

Order inside Fix #4 (dependencies first):
1. Fix the two deployed-API defects (§6, top): referrals query + `created_at`.
2. Customer core: dashboard aggregate, STK checkout, wallet instant-renew + statement,
   coupons validate, timeline, request-review, notifications read/unread.
3. Customer breadth: gift cards, store, loyalty, achievements, leaderboard, wishlist,
   help, blog, receipts, tickets, feedback, suggestions, GDPR, birthday, profile/password/
   privacy/delete, sessions, passkeys, magic link, forgot/reset.
4. Admin breadth: analytics, financial engine, subscription management (edit/renew/cancel/
   delete/unhide/remind/bulk), customer management (all 9 actions), wallet admin, gift-card
   admin, transactions, payment methods + gateway, coupons admin, blog/help admin, tickets,
   waitlist/suggestions, bulk email, broadcast, promo banner, security logs, recycle bin.
5. Keep web-only forever: raw DB query, backup download/upload, fix-db (§6.4).
6. Final verification: every checkbox in §1–§2 checked against the live site on a real device,
   with a Clerk-created account and an own-auth account, in light and dark mode.

---

## Appendix — sources

- Routes/templates/CSS: read from the laptop project 7 Nov 2026 via bridge audit scripts
  (route extraction + keyword hits + targeted file dumps; scratch deleted afterwards).
- Live API: `~/workspace/premiumslots-ios/backend/api_v1.py` (776 lines, deployed 7 Nov 2026).
- Brand assets: `~/workspace/premiumslots-ios/brand/` (logo SVGs, `app_style.css`,
  `admin_style.css`, `brand-vars.json`, `generated/` PNGs).
- v2 app: `~/workspace/premiumslots-ios/PremiumSlots/` (version 2.0, commit a6aec2d).
- Still unverified: whether the `.pl` Uiverse loader SVG is rendered by any page; whether
  `locked_price` exists on production; the live `payment_gateway` value; whether
  `GET /api/v1/referrals` works live (suspected broken query — test it); whether the
  Capacitor iOS wrapper was ever shipped; Clerk publishable-key *value* (by design — env var
  names only in this file).
