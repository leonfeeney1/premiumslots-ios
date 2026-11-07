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
