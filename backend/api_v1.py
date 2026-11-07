"""
PremiumSlots mobile JSON API, v1.

Drop-in blueprint for the live Flask site. It exposes, as JSON, the data
the native iOS app needs. Every route below mirrors a route or table that
already exists in the live project (see ANALYSIS.md in the iOS repo):

  - Services table: id, name, price, description, icon_name,
    inventory_count, monthly_cost. inventory_count is the slots-left number.
  - Subscriptions table: id, user_id, customer_name, whatsapp_number,
    email, service_requested, mpesa_code, tuma_reference,
    tuma_checkout_request_id, amount_due, delivery_type, access_details,
    status, viewed, expiry_date, review_requested, issue_reported,
    account_group, vault_email, vault_password, applied_promo_code.
  - Users table: id, name, email, whatsapp_number, password_hash,
    is_verified, is_banned, plus wallet_balance / loyalty_points /
    referral_count / loyalty_tier as read elsewhere in the codebase.
  - WalletTransactions, Referrals, Waitlist, NotificationQueue,
    FinancialLedger as used by the existing blueprints.
  - Buying flow: POST /request on the web, M-PESA code validated as
    10 alphanumeric characters, duplicate codes rejected, subscription
    created with status Pending, admin approval sets Approved, sets
    expiry_date and decrements Services.inventory_count.
  - Admin: a separate password-only session flag
    session["admin_authenticated"], compared to the ADMIN_PASSWORD
    environment variable. There is no admin role on the Users table.

Security notes:
  - User routes reuse the existing Flask session cookie
    (session["user_id"]) and the existing login_required decorator,
    so no new auth system is introduced.
  - Admin routes use only session["admin_authenticated"]. The admin
    password is never stored in this file and is never returned.
  - Vault credentials are returned ONLY through the one-time vault
    endpoint, mirroring the web dashboard reveal, and only to the
    subscription owner.
  - No route in this file uses or reveals the web admin URL prefix.
    Admin API auth is the session flag above, nothing else.

Install: copy this file to app/blueprints/api_v1.py on the laptop, add
    from app.blueprints.api_v1 import api_v1
    app.register_blueprint(api_v1)
to app/__init__.py next to the other blueprint registrations, then
deploy with the normal cPanel push (see backend/README.md).
"""

import base64
import hmac
import json
import os
import re
import secrets
from datetime import datetime, timedelta

from flask import Blueprint, Response, jsonify, request, session

from functools import wraps

from app.database import get_db

try:
    from app.utils import is_valid_mpesa_format, is_mpesa_code_used
except ImportError:  # pragma: no cover - fallback if utils moves
    def is_valid_mpesa_format(code):
        return bool(code) and bool(re.fullmatch(r"[A-Za-z0-9]{10}", code or ""))

    def is_mpesa_code_used(code):
        db = get_db()
        cur = db.cursor()
        cur.execute(
            "SELECT 1 FROM Subscriptions WHERE mpesa_code = %s LIMIT 1", (code,)
        )
        return cur.fetchone() is not None

try:
    from app.utils import create_magic_link as _create_magic_link
    from app.utils import consume_magic_link as _consume_magic_link
except ImportError:  # pragma: no cover - magic links need the web helpers
    _create_magic_link = None
    _consume_magic_link = None

try:
    import requests as _requests
except ImportError:  # pragma: no cover
    _requests = None


api_v1 = Blueprint("api_v1", __name__, url_prefix="/api/v1")

MPESA_CODE_RE = re.compile(r"^[A-Za-z0-9]{10}$")


def _err(message, status=400):
    return jsonify({"ok": False, "error": message}), status


def _ok(data=None, status=200):
    body = {"ok": True}
    if data is not None:
        body.update(data)
    return jsonify(body), status


def _service_row(row):
    return {
        "id": row["id"],
        "name": row["name"],
        "price": row["price"],
        "description": row["description"],
        "icon_name": row["icon_name"],
        "inventory_count": row["inventory_count"],
        "monthly_cost": row["monthly_cost"],
    }


def _subscription_row(row):
    created_at = row.get("created_at")
    return {
        "id": row["id"],
        "service_requested": row["service_requested"],
        "amount_due": row["amount_due"],
        "mpesa_code": row["mpesa_code"],
        "delivery_type": row["delivery_type"],
        "status": row["status"],
        "expiry_date": (
            row["expiry_date"].isoformat() if row.get("expiry_date") else None
        ),
        "viewed": bool(row.get("viewed", 0)),
        "issue_reported": bool(row.get("issue_reported", 0)),
        "account_group": row.get("account_group"),
        "created_at": (
            created_at.isoformat() if hasattr(created_at, "isoformat") else created_at
        ),
        "locked_price": row.get("locked_price"),
    }


def user_required(view):
    """JSON version of the web login_required: session["user_id"] must
    be set. The web decorator redirects to a login page, which is wrong
    for a JSON API, so this returns a 401 JSON body instead."""
    @wraps(view)
    def wrapped(*args, **kwargs):
        if not session.get("user_id"):
            return _err("Login required.", 401)
        return view(*args, **kwargs)
    return wrapped


def _admin_required():
    if not session.get("admin_authenticated"):
        return _err("Admin login required.", 401)
    return None


# ---------------------------------------------------------------- health

@api_v1.route("/health", methods=["GET"])
def health():
    return _ok({"service": "premiumslots", "api": "v1"})


# ---------------------------------------------------------------- services

@api_v1.route("/services", methods=["GET"])
def list_services():
    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT * FROM Services ORDER BY name")
    services = [_service_row(r) for r in cur.fetchall()]
    total_slots = sum(s["inventory_count"] or 0 for s in services)
    return _ok({"services": services, "platforms": len(services),
                "slots_in_rotation": total_slots})


@api_v1.route("/services/<int:service_id>", methods=["GET"])
def get_service(service_id):
    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT * FROM Services WHERE id = %s", (service_id,))
    row = cur.fetchone()
    if row is None:
        return _err("Service not found.", 404)
    cur.execute(
        "SELECT COUNT(*) AS n FROM Waitlist WHERE service_requested = %s",
        (row["name"],),
    )
    waitlist_count = cur.fetchone()["n"]
    data = _service_row(row)
    data["waitlist_count"] = waitlist_count
    return _ok({"service": data})


# ---------------------------------------------------------------- auth

@api_v1.route("/auth/register", methods=["POST"])
def register():
    data = request.get_json(silent=True) or {}
    name = (data.get("name") or "").strip()
    email = (data.get("email") or "").strip().lower()
    password = data.get("password") or ""
    whatsapp_number = (data.get("whatsapp_number") or "").strip()
    referral_code = (data.get("referral_code") or "").strip() or None
    if not name or not email or not password or not whatsapp_number:
        return _err("Name, email, password and WhatsApp number are required.")
    from werkzeug.security import generate_password_hash

    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT id FROM Users WHERE email = %s", (email,))
    if cur.fetchone() is not None:
        return _err("An account with that email already exists.", 409)
    cur.execute(
        "INSERT INTO Users (name, email, whatsapp_number, password_hash)"
        " VALUES (%s, %s, %s, %s) RETURNING id",
        (name, email, whatsapp_number, generate_password_hash(password)),
    )
    user_id = cur.fetchone()["id"]
    db.commit()
    session["user_id"] = user_id
    return _ok({"user_id": user_id, "name": name, "email": email}, 201)


@api_v1.route("/auth/login", methods=["POST"])
def login():
    data = request.get_json(silent=True) or {}
    email = (data.get("email") or "").strip().lower()
    password = data.get("password") or ""
    if not email or not password:
        return _err("Email and password are required.")
    from werkzeug.security import check_password_hash

    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT * FROM Users WHERE email = %s", (email,))
    user = cur.fetchone()
    if user is None or not check_password_hash(
        user["password_hash"] or "", password
    ):
        return _err("Email or password is incorrect.", 401)
    if user.get("is_banned"):
        return _err("This account is suspended.", 403)
    session["user_id"] = user["id"]
    return _ok({"user_id": user["id"], "name": user["name"],
                "email": user["email"]})


@api_v1.route("/auth/logout", methods=["POST"])
@user_required
def logout():
    session.pop("user_id", None)
    return _ok({})


@api_v1.route("/auth/me", methods=["GET"])
@user_required
def me():
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT id, name, email, whatsapp_number, is_verified,"
        " date_of_birth, wallet_balance, loyalty_points, referral_count,"
        " loyalty_tier FROM Users WHERE id = %s",
        (session["user_id"],),
    )
    user = cur.fetchone()
    if user is None:
        return _err("Account not found.", 404)
    dob = user.get("date_of_birth")
    needs_onboarding = not (user.get("whatsapp_number") or "") or dob is None
    return _ok({"user": {
        "id": user["id"],
        "name": user["name"],
        "email": user["email"],
        "whatsapp_number": user["whatsapp_number"],
        "is_verified": bool(user.get("is_verified", False)),
        "date_of_birth": (
            dob.isoformat() if hasattr(dob, "isoformat") else dob
        ),
        "needs_onboarding": needs_onboarding,
        "wallet_balance": user.get("wallet_balance") or 0,
        "loyalty_points": user.get("loyalty_points") or 0,
        "referral_count": user.get("referral_count") or 0,
        "loyalty_tier": user.get("loyalty_tier"),
    }})


# ---------------------------------------------------------------- clerk auth
# The web signs customers in with Clerk (Clerk JS v5) and then syncs the
# Clerk session into the Flask session at GET/POST /auth/clerk_sync
# (auth.py:80): decode the __session JWT, read sub, verify server-side
# with the Clerk Backend API, find-or-create the Users row, set
# session["user_id"] for 7 days, redirect to onboarding if WhatsApp or
# date of birth is missing. This JSON endpoint does exactly that, but
# returns JSON + sets the session cookie instead of redirecting, so the
# native app can use it. The Clerk secret key stays server-side
# (CLERK_SECRET_KEY env var); the app only ever sends the session JWT.

def _decode_jwt_sub(token):
    """Read sub from a Clerk session JWT payload without verifying the
    signature here, exactly as the web clerk_sync does. Trust comes
    from the Clerk Backend API lookup below, not from this decode."""
    try:
        parts = (token or "").split(".")
        if len(parts) != 3:
            return None
        payload = parts[1]
        payload += "=" * (-len(payload) % 4)
        data = json.loads(base64.urlsafe_b64decode(payload).decode("utf-8"))
        return data.get("sub")
    except Exception:
        return None


@api_v1.route("/auth/clerk-sync", methods=["POST"])
def clerk_sync():
    data = request.get_json(silent=True) or {}
    token = data.get("token") or ""
    if not token and request.headers.get("Authorization", "").startswith("Bearer "):
        token = request.headers["Authorization"][7:]
    if not token:
        return _err("A Clerk session token is required.")
    clerk_user_id = _decode_jwt_sub(token)
    if not clerk_user_id:
        return _err("That Clerk session token could not be read.", 401)
    secret = os.environ.get("CLERK_SECRET_KEY") or ""
    if not secret or _requests is None:
        return _err("Clerk is not configured on this server.", 503)
    try:
        resp = _requests.get(
            "https://api.clerk.com/v1/users/%s" % clerk_user_id,
            headers={"Authorization": "Bearer %s" % secret},
            timeout=10,
        )
    except Exception:
        return _err("Could not reach Clerk. Try again.", 502)
    if resp.status_code != 200:
        return _err("Clerk could not verify that session.", 401)
    clerk_user = resp.json()
    emails = clerk_user.get("email_addresses") or []
    email = (emails[0].get("email_address") if emails else "") or ""
    email = email.strip().lower()
    if not email:
        return _err("Clerk returned no email address for that session.", 401)
    first = clerk_user.get("first_name") or ""
    last = clerk_user.get("last_name") or ""
    name = (first + " " + last).strip() or email.split("@")[0]
    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT * FROM Users WHERE email = %s", (email,))
    user = cur.fetchone()
    if user is None:
        cur.execute(
            "INSERT INTO Users (name, email, is_verified, whatsapp_number,"
            " password_hash, clerk_id) VALUES (%s, %s, TRUE, '', '', %s)"
            " RETURNING id",
            (name, email, clerk_user_id),
        )
        user_id = cur.fetchone()["id"]
        db.commit()
        cur.execute("SELECT * FROM Users WHERE id = %s", (user_id,))
        user = cur.fetchone()
    else:
        if user.get("clerk_id") != clerk_user_id:
            cur.execute(
                "UPDATE Users SET clerk_id = %s WHERE id = %s",
                (clerk_user_id, user["id"]),
            )
            db.commit()
    if user.get("is_banned"):
        return _err("This account is suspended.", 403)
    session["user_id"] = user["id"]
    session.permanent = True
    needs_onboarding = not (user.get("whatsapp_number") or "") or not user.get(
        "date_of_birth"
    )
    return _ok({"user_id": user["id"], "name": user["name"],
                "email": user["email"],
                "needs_onboarding": needs_onboarding})


# ---------------------------------------------------------------- own-auth
# account recovery (legacy own-auth path, still live on the web)

def _is_strong_password(password):
    """Mirror of is_strong_password (utils.py:157): min 8 chars, upper +
    lower + digit."""
    if not password or len(password) < 8:
        return False
    return (
        any(c.isupper() for c in password)
        and any(c.islower() for c in password)
        and any(c.isdigit() for c in password)
    )


def _send_account_email(to_email, subject, body):
    """Best-effort account email via the site's Flask-Mail setup. The
    caller always returns success to the client (no enumeration), so a
    mail failure must never surface as an error."""
    try:
        from flask import current_app
        from flask_mail import Message

        mail = current_app.extensions.get("mail")
        if mail is None:
            return
        msg = Message(subject=subject, recipients=[to_email], body=body)
        mail.send(msg)
    except Exception:
        pass


@api_v1.route("/auth/forgot-password", methods=["POST"])
def forgot_password():
    """Web: GET/POST /auth/forgot_password (auth.py:306), 3/hour, always
    returns success to prevent enumeration; token expires in 15 min."""
    data = request.get_json(silent=True) or {}
    email = (data.get("email") or "").strip().lower()
    if email:
        db = get_db()
        cur = db.cursor()
        cur.execute("SELECT id FROM Users WHERE email = %s", (email,))
        row = cur.fetchone()
        if row is not None:
            token = secrets.token_urlsafe(32)
            expiry = datetime.utcnow() + timedelta(minutes=15)
            cur.execute(
                "UPDATE Users SET reset_token = %s, reset_token_expiry = %s"
                " WHERE id = %s",
                (token, expiry, row["id"]),
            )
            db.commit()
            _send_account_email(
                email,
                "Reset your PremiumSlots password",
                "Reset your password within 15 minutes:\n"
                "https://premiumslots.tech/?reset_token=%s\n\n"
                "If you did not ask for this, ignore this email." % token,
            )
    return _ok({"message": "If that email has an account, a reset link is on its way."})


@api_v1.route("/auth/reset-password", methods=["POST"])
def reset_password():
    """Web: POST /auth/reset_password_confirm (auth.py:272)."""
    data = request.get_json(silent=True) or {}
    token = data.get("token") or ""
    password = data.get("password") or ""
    if not token or not _is_strong_password(password):
        return _err(
            "A valid reset token and a strong password are required "
            "(8+ characters, upper and lower case, and a number)."
        )
    from werkzeug.security import generate_password_hash

    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT id, reset_token_expiry FROM Users WHERE reset_token = %s",
        (token,),
    )
    row = cur.fetchone()
    if row is None:
        return _err("That reset link is not valid.", 401)
    expiry = row.get("reset_token_expiry")
    if expiry is not None and hasattr(expiry, "isoformat"):
        if expiry < datetime.utcnow():
            return _err("That reset link has expired. Ask for a new one.", 401)
    cur.execute(
        "UPDATE Users SET password_hash = %s, reset_token = NULL,"
        " reset_token_expiry = NULL WHERE id = %s",
        (generate_password_hash(password), row["id"]),
    )
    db.commit()
    return _ok({})


@api_v1.route("/auth/verify", methods=["POST"])
def verify_email():
    """Legacy email verification. Web: POST /auth/verify (auth.py:44):
    6-digit verification_code, sets is_verified. Clerk users are
    created verified; this is the own-auth path only."""
    data = request.get_json(silent=True) or {}
    email = (data.get("email") or "").strip().lower()
    code = (data.get("code") or "").strip()
    if not email or not code:
        return _err("Email and verification code are required.")
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT id, verification_code FROM Users WHERE email = %s", (email,)
    )
    row = cur.fetchone()
    if row is None or (row.get("verification_code") or "") != code:
        return _err("That verification code is not correct.", 401)
    cur.execute(
        "UPDATE Users SET is_verified = TRUE, verification_code = NULL"
        " WHERE id = %s",
        (row["id"],),
    )
    db.commit()
    return _ok({})


@api_v1.route("/auth/magic", methods=["POST"])
def magic_link():
    """Web: GET/POST /auth/magic (auth.py:223): one-time token in
    MagicLinkTokens, emailed link, signs in on consume. Uses the web's
    own create_magic_link helper so the token format matches."""
    data = request.get_json(silent=True) or {}
    email = (data.get("email") or "").strip().lower()
    if email and _create_magic_link is not None:
        try:
            token = _create_magic_link(email)
            _send_account_email(
                email,
                "Your PremiumSlots sign-in link",
                "Sign in with this one-time link:\n"
                "https://premiumslots.tech/auth/magic/%s\n\n"
                "If you did not ask for this, ignore this email." % token,
            )
        except Exception:
            pass
    return _ok({"message": "If that email has an account, a sign-in link is on its way."})


@api_v1.route("/auth/magic/consume", methods=["POST"])
def magic_consume():
    """Web: GET /auth/magic/<token> (auth.py:245), as JSON."""
    if _consume_magic_link is None:
        return _err("Magic links are not available right now.", 503)
    data = request.get_json(silent=True) or {}
    token = data.get("token") or ""
    if not token:
        return _err("A magic link token is required.")
    try:
        user_id = _consume_magic_link(token)
    except Exception:
        return _err("That sign-in link is not valid or has expired.", 401)
    if not user_id:
        return _err("That sign-in link is not valid or has expired.", 401)
    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT is_banned FROM Users WHERE id = %s", (user_id,))
    row = cur.fetchone()
    if row is None:
        return _err("Account not found.", 404)
    if row.get("is_banned"):
        return _err("This account is suspended.", 403)
    session["user_id"] = user_id
    session.permanent = True
    return _ok({"user_id": user_id})


# ---------------------------------------------------------------- onboarding

@api_v1.route("/me/onboarding", methods=["GET"])
@user_required
def get_onboarding():
    """Web: GET /auth/onboarding (auth.py:187)."""
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT whatsapp_number, date_of_birth FROM Users WHERE id = %s",
        (session["user_id"],),
    )
    row = cur.fetchone()
    if row is None:
        return _err("Account not found.", 404)
    dob = row.get("date_of_birth")
    return _ok({
        "whatsapp_number": row.get("whatsapp_number") or "",
        "date_of_birth": dob.isoformat() if hasattr(dob, "isoformat") else dob,
        "needs_onboarding": not (row.get("whatsapp_number") or "") or dob is None,
    })


@api_v1.route("/me/onboarding", methods=["POST"])
@user_required
def post_onboarding():
    """Web: POST /auth/onboarding: collects whatsapp_number +
    date_of_birth (YYYY-MM-DD) when either is missing after sign-in."""
    data = request.get_json(silent=True) or {}
    whatsapp = (data.get("whatsapp_number") or "").strip()
    dob_text = (data.get("date_of_birth") or "").strip()
    if not whatsapp:
        return _err("WhatsApp number is required.")
    dob = None
    if dob_text:
        try:
            dob = datetime.strptime(dob_text, "%Y-%m-%d").date()
        except ValueError:
            return _err("Date of birth must be YYYY-MM-DD.")
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "UPDATE Users SET whatsapp_number = %s, date_of_birth = %s"
        " WHERE id = %s",
        (whatsapp, dob, session["user_id"]),
    )
    db.commit()
    return _ok({"needs_onboarding": False})


@api_v1.route("/auth/onboarding", methods=["POST"])
@user_required
def post_onboarding_alias():
    """Alias of POST /api/v1/me/onboarding, kept so clients using the
    /auth/onboarding path also work."""
    return post_onboarding()


# ---------------------------------------------------------------- sessions

@api_v1.route("/me/sessions", methods=["GET"])
@user_required
def my_sessions():
    """Web: GET /auth/sessions (auth.py:411): LoginActivity rows.
    Max 3 sessions per user (MAX_SESSIONS_PER_USER)."""
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT * FROM LoginActivity WHERE user_id = %s"
        " ORDER BY id DESC LIMIT 20",
        (session["user_id"],),
    )
    items = []
    for row in cur.fetchall():
        items.append({k: (v.isoformat() if hasattr(v, "isoformat") else v)
                      for k, v in dict(row).items()
                      if k not in ("user_id",)})
    return _ok({"sessions": items})


@api_v1.route("/me/sessions/revoke", methods=["POST"])
@user_required
def revoke_session():
    """Web: POST /auth/sessions/revoke (auth.py:432)."""
    data = request.get_json(silent=True) or {}
    session_id = data.get("session_id")
    if session_id is None:
        return _err("A session id is required.")
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "UPDATE LoginActivity SET revoked_at = NOW()"
        " WHERE id = %s AND user_id = %s",
        (session_id, session["user_id"]),
    )
    if cur.rowcount == 0:
        return _err("Session not found.", 404)
    db.commit()
    return _ok({})


# ---------------------------------------------------------------- my subs

@api_v1.route("/me/subscriptions", methods=["GET"])
@user_required
def my_subscriptions():
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT * FROM Subscriptions WHERE user_id = %s ORDER BY id DESC",
        (session["user_id"],),
    )
    return _ok({"subscriptions": [_subscription_row(r) for r in cur.fetchall()]})


@api_v1.route("/me/subscriptions/<int:sub_id>/vault", methods=["GET"])
@user_required
def subscription_vault(sub_id):
    """One-time vault reveal, mirroring the web dashboard reveal.

    The web app pops session[f"viewing_sub_{sub_id}"] and exposes the
    credentials once. We do the same: the first GET after approval
    returns the credentials and marks them viewed; later GETs return
    only a flag that they were already revealed.
    """
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT * FROM Subscriptions WHERE id = %s AND user_id = %s",
        (sub_id, session["user_id"]),
    )
    row = cur.fetchone()
    if row is None:
        return _err("Subscription not found.", 404)
    if row["status"] != "Approved":
        return _err("Vault details are available once the slot is approved.", 403)
    key = "viewing_sub_%s" % sub_id
    if session.get(key):
        session.pop(key, None)
        cur.execute(
            "UPDATE Subscriptions SET viewed = 1 WHERE id = %s", (sub_id,)
        )
        db.commit()
        return _ok({"revealed": True,
                    "vault_email": row.get("vault_email"),
                    "vault_password": row.get("vault_password"),
                    "access_details": row.get("access_details"),
                    "account_group": row.get("account_group")})
    session[key] = True
    return _ok({"revealed": False,
                "message": "Request the vault again to reveal the credentials once."})


@api_v1.route("/me/notifications", methods=["GET"])
@user_required
def my_notifications():
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT * FROM NotificationQueue WHERE user_id = %s"
        " ORDER BY id DESC LIMIT 30",
        (session["user_id"],),
    )
    items = []
    for row in cur.fetchall():
        items.append({k: (v.isoformat() if hasattr(v, "isoformat") else v)
                      for k, v in dict(row).items()})
    unread_count = 0
    try:
        if _has_column("NotificationQueue", "is_read"):
            cur.execute(
                "SELECT COUNT(*) AS n FROM NotificationQueue"
                " WHERE user_id = %s AND is_read = FALSE",
                (session["user_id"],),
            )
        elif _has_column("NotificationQueue", "read_at"):
            cur.execute(
                "SELECT COUNT(*) AS n FROM NotificationQueue"
                " WHERE user_id = %s AND read_at IS NULL",
                (session["user_id"],),
            )
        else:
            cur.execute(
                "SELECT COUNT(*) AS n FROM NotificationQueue"
                " WHERE user_id = %s",
                (session["user_id"],),
            )
            # No read flag on this table: unread count is not knowable.
            unread_count = None
            return _ok({"notifications": items,
                        "unread_count": unread_count})
        unread_count = cur.fetchone()["n"]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        unread_count = None
    return _ok({"notifications": items, "unread_count": unread_count})


# ---------------------------------------------------------------- buying

@api_v1.route("/request", methods=["POST"])
@user_required
def request_subscription():
    """Mirror of the web POST /request (subscriptions.py:11), gateway-aware.

    Body: service_requested (name), payment_method mpesa (default) /
    stk / wallet, optional coupon_code, optional sub_id (renewal).
    - mpesa: 10-alphanumeric code, duplicate codes rejected, status
      Pending (unchanged from v2).
    - wallet: balance debited with the KES 25,000 daily velocity cap,
      reference WALLET-NEW-<hex> / WALLET-RNW-<hex>; a renewal is
      Approved immediately with extended expiry (web wallet.py).
    - stk: calls the web's own intasend_client.initiate_stk_push when
      that module is importable; otherwise creates the subscription
      with status Initiated and a tuma_reference placeholder and
      returns it, so the client can poll /checkout/status/<ref>.
      NOTE (deploy): verify the live STK push call — the intasend
      client import and its return shape (invoice_id /
      checkout_request_id) were not in the workspace; see README.
    """
    data = request.get_json(silent=True) or {}
    service_name = (data.get("service_requested") or "").strip()
    payment_method = (data.get("payment_method") or "mpesa").strip().lower()
    if payment_method in ("intasend",):
        payment_method = "stk"
    mpesa_code = (data.get("mpesa_code") or "").strip().upper()
    coupon_code = (data.get("coupon_code") or "").strip() or None
    sub_id = data.get("sub_id")
    phone = (data.get("phone") or data.get("phone_number") or "").strip()
    if not service_name:
        return _err("Choose a platform first.")
    if payment_method not in ("mpesa", "stk", "wallet"):
        return _err("payment_method must be mpesa, stk or wallet.")
    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT * FROM Users WHERE id = %s", (session["user_id"],))
    user = cur.fetchone()
    if user is None:
        return _err("Account not found.", 404)
    if user.get("is_banned"):
        session.pop("user_id", None)
        return _err("This account is suspended.", 403)
    cur.execute("SELECT * FROM Services WHERE name = %s", (service_name,))
    service = cur.fetchone()
    if service is None:
        return _err("Platform not found.", 404)
    if payment_method == "mpesa" and (service["inventory_count"] or 0) <= 0:
        return _err("This platform is sold out right now.")
    # Amount: locked (grandfathered) price wins when a previous
    # subscription for this user+service carries one; else the live
    # Services price; a valid coupon then reduces it. Every lookup is
    # guarded — locked_price may not exist on production.
    amount = service["price"]
    try:
        cur.execute(
            "SELECT locked_price FROM Subscriptions WHERE user_id = %s"
            " AND service_requested = %s AND locked_price IS NOT NULL"
            " ORDER BY id DESC LIMIT 1",
            (session["user_id"], service_name),
        )
        locked = cur.fetchone()
        if locked is not None and locked.get("locked_price"):
            amount = locked["locked_price"]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    discount = 0
    if coupon_code:
        check = _validate_coupon(coupon_code, session["user_id"],
                                 service_name, amount)
        if not check.get("valid"):
            return _err(check.get("error") or "That coupon is not valid.")
        discount = check.get("discount") or 0
        amount = max(0, amount - discount)
    is_renewal = sub_id is not None
    if payment_method == "mpesa":
        if not MPESA_CODE_RE.match(mpesa_code or ""):
            return _err("The M-PESA code must be exactly 10 letters and numbers.")
        if not is_valid_mpesa_format(mpesa_code) or is_mpesa_code_used(mpesa_code):
            return _err("That M-PESA code is not valid or has already been used.")
        cur.execute(
            "INSERT INTO Subscriptions (user_id, customer_name, whatsapp_number,"
            " email, service_requested, mpesa_code, amount_due, status,"
            " delivery_type, applied_promo_code)"
            " VALUES (%s, %s, %s, %s, %s, %s, %s, 'Pending', 'Credentials', %s)"
            " RETURNING id",
            (user["id"], user["name"], user["whatsapp_number"], user["email"],
             service_name, mpesa_code, amount, coupon_code),
        )
        new_id = cur.fetchone()["id"]
        db.commit()
        return _ok({"subscription_id": new_id, "status": "Pending",
                    "amount_due": amount, "discount": discount,
                    "service_requested": service_name}, 201)
    if payment_method == "wallet":
        balance = user.get("wallet_balance") or 0
        if balance < amount:
            return _err("Your wallet balance is not enough for this slot.")
        spent_today = _wallet_daily_spent(session["user_id"])
        if spent_today + amount > 25000:
            return _err("That payment would pass the KES 25,000 daily wallet spend limit.")
        ref = "WALLET-%s-%s" % ("RNW" if is_renewal else "NEW",
                                secrets.token_hex(4).upper())
        expiry = None
        status = "Approved"
        if is_renewal:
            try:
                from app.utils import calculate_subscription_expiry
                cur.execute(
                    "SELECT expiry_date FROM Subscriptions WHERE id = %s"
                    " AND user_id = %s",
                    (sub_id, session["user_id"]),
                )
                old = cur.fetchone()
                expiry = calculate_subscription_expiry(
                    old.get("expiry_date") if old else None)
            except Exception:
                expiry = datetime.utcnow() + timedelta(days=30)
        cur.execute(
            "UPDATE Users SET wallet_balance = wallet_balance - %s"
            " WHERE id = %s",
            (amount, session["user_id"]),
        )
        try:
            cur.execute(
                "INSERT INTO WalletTransactions (user_id, action_type,"
                " amount, mpesa_code) VALUES (%s, 'spend', %s, %s)",
                (session["user_id"], amount, ref),
            )
        except Exception:
            try:
                db.rollback()
            except Exception:
                pass
            cur.execute(
                "UPDATE Users SET wallet_balance = wallet_balance - %s"
                " WHERE id = %s",
                (amount, session["user_id"]),
            )
        if is_renewal:
            cur.execute(
                "UPDATE Subscriptions SET status = 'Approved',"
                " expiry_date = %s, amount_due = %s WHERE id = %s"
                " AND user_id = %s",
                (expiry, amount, sub_id, session["user_id"]),
            )
            new_id = sub_id
        else:
            cur.execute(
                "INSERT INTO Subscriptions (user_id, customer_name,"
                " whatsapp_number, email, service_requested, mpesa_code,"
                " amount_due, status, delivery_type, applied_promo_code,"
                " expiry_date)"
                " VALUES (%s, %s, %s, %s, %s, %s, %s, 'Approved',"
                " 'Credentials', %s, %s) RETURNING id",
                (user["id"], user["name"], user["whatsapp_number"],
                 user["email"], service_name, ref, amount, coupon_code,
                 expiry),
            )
            new_id = cur.fetchone()["id"]
        db.commit()
        return _ok({"subscription_id": new_id, "status": status,
                    "amount_due": amount, "discount": discount,
                    "reference": ref, "wallet_balance": balance - amount,
                    "expiry_date": expiry.isoformat() if expiry and hasattr(
                        expiry, "isoformat") else expiry}, 201)
    # --- stk / IntaSend ---
    phone_norm = _normalise_ke_phone(phone or user.get("whatsapp_number") or "")
    stk_result = _initiate_stk_push(amount, phone_norm, user["email"])
    cur.execute(
        "INSERT INTO Subscriptions (user_id, customer_name, whatsapp_number,"
        " email, service_requested, mpesa_code, amount_due, status,"
        " delivery_type, applied_promo_code, tuma_reference,"
        " tuma_checkout_request_id)"
        " VALUES (%s, %s, %s, %s, %s, %s, %s, 'Initiated', 'Credentials',"
        " %s, %s, %s) RETURNING id",
        (user["id"], user["name"], user["whatsapp_number"], user["email"],
         service_name, "INTASEND-INIT-pending", amount, coupon_code,
         (stk_result or {}).get("invoice_id"),
         (stk_result or {}).get("checkout_request_id")),
    )
    new_id = cur.fetchone()["id"]
    if stk_result and stk_result.get("invoice_id"):
        cur.execute(
            "UPDATE Subscriptions SET mpesa_code = %s,"
            " tuma_reference = %s WHERE id = %s",
            ("INTASEND-INIT-%s" % stk_result.get(
                "merchant_request_id", new_id),
             stk_result["invoice_id"], new_id),
        )
        tuma_ref = stk_result["invoice_id"]
    else:
        # IntaSend client not importable / no live push made (see README):
        # keep the Initiated row so the client can poll, with a
        # placeholder reference tied to the subscription id.
        tuma_ref = "INTASEND-INIT-%s" % new_id
        cur.execute(
            "UPDATE Subscriptions SET mpesa_code = %s, tuma_reference = %s"
            " WHERE id = %s",
            (tuma_ref, tuma_ref, new_id),
        )
    db.commit()
    return _ok({"subscription_id": new_id, "status": "Initiated",
                "amount_due": amount, "discount": discount,
                "service_requested": service_name,
                "tuma_reference": tuma_ref,
                "stk_initiated": bool(stk_result),
                "stk_note": None if stk_result else (
                    "Live STK push was not made: the IntaSend client"
                    " import needs verifying at deploy time (see README).")}, 201)


@api_v1.route("/waitlist/join", methods=["POST"])
@user_required
def join_waitlist():
    data = request.get_json(silent=True) or {}
    service_name = (data.get("service_requested") or "").strip()
    if not service_name:
        return _err("Choose a platform first.")
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT 1 FROM Waitlist WHERE user_id = %s AND service_requested = %s",
        (session["user_id"], service_name),
    )
    if cur.fetchone() is None:
        cur.execute(
            "INSERT INTO Waitlist (user_id, service_requested) VALUES (%s, %s)",
            (session["user_id"], service_name),
        )
        db.commit()
    return _ok({})


@api_v1.route("/subscription/<int:sub_id>/report-issue", methods=["POST"])
@user_required
def report_issue(sub_id):
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "UPDATE Subscriptions SET issue_reported = TRUE"
        " WHERE id = %s AND user_id = %s",
        (sub_id, session["user_id"]),
    )
    if cur.rowcount == 0:
        return _err("Subscription not found.", 404)
    db.commit()
    return _ok({})


@api_v1.route("/subscription/<int:sub_id>/toggle-auto-renew",
              methods=["POST"])
@user_required
def toggle_auto_renew(sub_id):
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT auto_renew FROM Subscriptions WHERE id = %s AND user_id = %s",
        (sub_id, session["user_id"]),
    )
    row = cur.fetchone()
    if row is None:
        return _err("Subscription not found.", 404)
    new_value = not bool(row.get("auto_renew", False))
    cur.execute(
        "UPDATE Subscriptions SET auto_renew = %s WHERE id = %s",
        (new_value, sub_id),
    )
    db.commit()
    return _ok({"auto_renew": new_value})


# ---------------------------------------------------------------- wallet

@api_v1.route("/wallet", methods=["GET"])
@user_required
def wallet():
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT wallet_balance FROM Users WHERE id = %s",
        (session["user_id"],),
    )
    user = cur.fetchone()
    cur.execute(
        "SELECT * FROM WalletTransactions WHERE user_id = %s"
        " ORDER BY id DESC LIMIT 50",
        (session["user_id"],),
    )
    txns = [{k: (v.isoformat() if hasattr(v, "isoformat") else v)
             for k, v in dict(r).items()} for r in cur.fetchall()]
    # Metrics + denominations (web GET /wallet, wallet.py:12): the v2
    # response only had balance + transactions. Totals are computed
    # from WalletTransactions action_type values when present; unknown
    # action spellings fall back to 0 rather than failing the endpoint.
    metrics = {"total_deposited": 0, "total_spent": 0,
               "total_redeemed": 0}
    try:
        cur.execute(
            "SELECT action_type, COALESCE(SUM(amount), 0) AS total"
            " FROM WalletTransactions WHERE user_id = %s"
            " GROUP BY action_type",
            (session["user_id"],),
        )
        for row in cur.fetchall():
            action = (row.get("action_type") or "").lower()
            total = row.get("total") or 0
            if action in ("deposit", "deposited"):
                metrics["total_deposited"] = total
            elif action in ("spend", "spent", "payment", "purchase",
                            "renewal", "debit"):
                metrics["total_spent"] += total
            elif action in ("redeem", "redeemed", "gift_card",
                            "gift-card"):
                metrics["total_redeemed"] += total
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    renewable = []
    try:
        cur.execute(
            "SELECT * FROM Subscriptions WHERE user_id = %s"
            " AND status = 'Approved' ORDER BY expiry_date ASC",
            (session["user_id"],),
        )
        renewable = [_subscription_row(r) for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    return _ok({"wallet_balance": (user or {}).get("wallet_balance") or 0,
                "transactions": txns, "metrics": metrics,
                "denominations": [200, 500, 1000, 2000, 5000],
                "renewable_subscriptions": renewable,
                "daily_spend_limit": 25000})


@api_v1.route("/wallet/deposit", methods=["POST"])
@user_required
def wallet_deposit():
    """Manual M-PESA wallet deposit, as on the web: the code is submitted
    and an admin approves the deposit before the balance moves."""
    data = request.get_json(silent=True) or {}
    mpesa_code = (data.get("mpesa_code") or "").strip().upper()
    try:
        amount = int(data.get("amount") or 0)
    except (TypeError, ValueError):
        amount = 0
    if amount <= 0:
        return _err("Enter the amount you sent.")
    if not MPESA_CODE_RE.match(mpesa_code or ""):
        return _err("The M-PESA code must be exactly 10 letters and numbers.")
    if is_mpesa_code_used(mpesa_code):
        return _err("That M-PESA code has already been used.")
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "INSERT INTO WalletTransactions (user_id, action_type, amount,"
        " mpesa_code) VALUES (%s, 'deposit', %s, %s)",
        (session["user_id"], amount, mpesa_code),
    )
    db.commit()
    return _ok({"status": "Pending", "amount": amount}, 201)


# ---------------------------------------------------------------- referrals

@api_v1.route("/referrals", methods=["GET"])
@user_required
def referrals():
    """Fixed 7 Nov 2026 (v3): the v2 endpoint queried
    Referrals WHERE user_id, but the web table uses referrer_id /
    referee_id (no user_id column), so it errored or returned
    nothing. This version queries referrer_id, as the web does
    (referrals.py / loyalty.py), and adds my code, counts, inviter
    and the top-3 monthly referrers preview."""
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT * FROM Referrals WHERE referrer_id = %s ORDER BY id DESC",
        (session["user_id"],),
    )
    mine = [{k: (v.isoformat() if hasattr(v, "isoformat") else v)
             for k, v in dict(r).items()} for r in cur.fetchall()]
    completed = None
    try:
        cur.execute(
            "SELECT COUNT(*) AS n FROM Referrals WHERE referrer_id = %s"
            " AND status = 'Completed'",
            (session["user_id"],),
        )
        completed = cur.fetchone()["n"]
    except Exception:
        db.rollback()
    code = None
    try:
        cur.execute(
            "SELECT referral_code FROM Users WHERE id = %s",
            (session["user_id"],),
        )
        row = cur.fetchone()
        code = (row or {}).get("referral_code")
    except Exception:
        db.rollback()
    inviter = None
    try:
        cur.execute(
            "SELECT u.name, u.email FROM Referrals r"
            " JOIN Users u ON u.id = r.referrer_id"
            " WHERE r.referee_id = %s LIMIT 1",
            (session["user_id"],),
        )
        row = cur.fetchone()
        if row is not None:
            inviter = dict(row)
    except Exception:
        db.rollback()
    cur.execute(
        "SELECT * FROM ReferralLeaderboard ORDER BY id DESC LIMIT 20"
    )
    board = [dict(r) for r in cur.fetchall()]
    return _ok({"referrals": mine, "leaderboard": board,
                "referral_count": len(mine), "completed_count": completed,
                "my_code": code,
                "referral_link": (
                    "https://premiumslots.tech/r/%s" % code if code else None
                ),
                "inviter": inviter})


# ---------------------------------------------------------------- admin

@api_v1.route("/admin/login", methods=["POST"])
def admin_login():
    data = request.get_json(silent=True) or {}
    password = data.get("password") or ""
    admin_password = os.environ.get("ADMIN_PASSWORD") or ""
    if not admin_password or not hmac.compare_digest(password, admin_password):
        return _err("Admin password is incorrect.", 401)
    session["admin_authenticated"] = True
    return _ok({})


@api_v1.route("/admin/logout", methods=["POST"])
def admin_logout():
    session.pop("admin_authenticated", None)
    return _ok({})


@api_v1.route("/admin/stats", methods=["GET"])
def admin_stats():
    guard = _admin_required()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT COUNT(*) AS n FROM Subscriptions WHERE status = 'Pending'")
    pending = cur.fetchone()["n"]
    cur.execute("SELECT COUNT(*) AS n FROM Subscriptions WHERE status = 'Approved'")
    approved = cur.fetchone()["n"]
    cur.execute("SELECT COUNT(*) AS n FROM Subscriptions WHERE issue_reported = TRUE")
    issues = cur.fetchone()["n"]
    cur.execute("SELECT COUNT(*) AS n FROM Users")
    users = cur.fetchone()["n"]
    cur.execute("SELECT COALESCE(SUM(amount), 0) AS total FROM FinancialLedger")
    revenue = cur.fetchone()["total"]
    cur.execute("SELECT COALESCE(SUM(inventory_count), 0) AS total FROM Services")
    slots = cur.fetchone()["total"]
    return _ok({"pending": pending, "approved": approved,
                "issues": issues, "users": users,
                "total_revenue": revenue, "slots_in_rotation": slots})


@api_v1.route("/admin/subscriptions", methods=["GET"])
def admin_subscriptions():
    guard = _admin_required()
    if guard is not None:
        return guard
    status = request.args.get("status")
    db = get_db()
    cur = db.cursor()
    if status:
        cur.execute(
            "SELECT * FROM Subscriptions WHERE status = %s ORDER BY id DESC",
            (status,),
        )
    else:
        cur.execute("SELECT * FROM Subscriptions ORDER BY id DESC LIMIT 200")
    return _ok({"subscriptions": [_subscription_row(r) for r in cur.fetchall()]})


@api_v1.route("/admin/subscriptions/<int:sub_id>/approve", methods=["POST"])
def admin_approve(sub_id):
    """Mirror of the web approve action: set Approved, set expiry_date,
    decrement Services.inventory_count, deliver vault credentials."""
    guard = _admin_required()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    vault_email = (data.get("vault_email") or "").strip()
    vault_password = data.get("vault_password") or ""
    account_group = (data.get("account_group") or "").strip() or "Unassigned"
    if not vault_email or not vault_password:
        return _err("Vault email and password are required to approve.")
    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT * FROM Subscriptions WHERE id = %s", (sub_id,))
    row = cur.fetchone()
    if row is None:
        return _err("Subscription not found.", 404)
    if row["status"] == "Approved":
        return _err("This subscription is already approved.", 409)
    from app.utils import calculate_subscription_expiry

    expiry = calculate_subscription_expiry(row.get("expiry_date"))
    cur.execute(
        "UPDATE Subscriptions SET status = 'Approved', expiry_date = %s,"
        " vault_email = %s, vault_password = %s, account_group = %s,"
        " access_details = 'See Vault' WHERE id = %s",
        (expiry, vault_email, vault_password, account_group, sub_id),
    )
    cur.execute(
        "UPDATE Services SET inventory_count ="
        " GREATEST(0, inventory_count - 1) WHERE name = %s",
        (row["service_requested"],),
    )
    db.commit()
    return _ok({"status": "Approved", "expiry_date": expiry.isoformat()
                if hasattr(expiry, "isoformat") else str(expiry)})


@api_v1.route("/admin/subscriptions/<int:sub_id>/reject", methods=["POST"])
def admin_reject(sub_id):
    guard = _admin_required()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "UPDATE Subscriptions SET status = 'Cancelled' WHERE id = %s",
        (sub_id,),
    )
    if cur.rowcount == 0:
        return _err("Subscription not found.", 404)
    db.commit()
    return _ok({"status": "Cancelled"})


@api_v1.route("/admin/customers", methods=["GET"])
def admin_customers():
    guard = _admin_required()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT id, name, email, whatsapp_number, is_verified, is_banned,"
        " wallet_balance, loyalty_points, referral_count, created_at"
        " FROM Users ORDER BY id DESC LIMIT 200"
    )
    customers = []
    for row in cur.fetchall():
        item = dict(row)
        if item.get("created_at") is not None:
            item["created_at"] = item["created_at"].isoformat()
        customers.append(item)
    return _ok({"customers": customers})


@api_v1.route("/admin/customers/<int:user_id>", methods=["GET"])
def admin_customer_detail(user_id):
    guard = _admin_required()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT * FROM Users WHERE id = %s", (user_id,))
    user = cur.fetchone()
    if user is None:
        return _err("Customer not found.", 404)
    cur.execute(
        "SELECT * FROM Subscriptions WHERE user_id = %s ORDER BY id DESC",
        (user_id,),
    )
    subs = [_subscription_row(r) for r in cur.fetchall()]
    safe_user = {k: v for k, v in dict(user).items()
                 if k not in ("password_hash", "verification_code",
                              "reset_token")}
    if safe_user.get("created_at") is not None:
        safe_user["created_at"] = safe_user["created_at"].isoformat()
    return _ok({"customer": safe_user, "subscriptions": subs})


@api_v1.route("/admin/customers/<int:user_id>/toggle-ban",
              methods=["POST"])
def admin_toggle_ban(user_id):
    guard = _admin_required()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT is_banned FROM Users WHERE id = %s", (user_id,))
    row = cur.fetchone()
    if row is None:
        return _err("Customer not found.", 404)
    new_value = not bool(row.get("is_banned", False))
    cur.execute(
        "UPDATE Users SET is_banned = %s WHERE id = %s", (new_value, user_id)
    )
    db.commit()
    return _ok({"is_banned": new_value})


@api_v1.route("/admin/services", methods=["GET"])
def admin_services():
    guard = _admin_required()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT * FROM Services ORDER BY name")
    return _ok({"services": [_service_row(r) for r in cur.fetchall()]})


@api_v1.route("/admin/services", methods=["POST"])
def admin_create_service():
    guard = _admin_required()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    name = (data.get("name") or "").strip()
    try:
        price = int(data.get("price") or 0)
        inventory = int(data.get("inventory_count") or 0)
        monthly_cost = int(data.get("monthly_cost") or 0)
    except (TypeError, ValueError):
        return _err("Price, stock and monthly cost must be numbers.")
    if not name or price < 0:
        return _err("A name and a price of 0 or more are required.")
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "INSERT INTO Services (name, price, description, icon_name,"
        " inventory_count, monthly_cost) VALUES (%s, %s, %s, %s, %s, %s)"
        " RETURNING id",
        (name, price, data.get("description") or "",
         data.get("icon_name") or "sparkles", inventory, monthly_cost),
    )
    service_id = cur.fetchone()["id"]
    db.commit()
    return _ok({"service_id": service_id}, 201)


@api_v1.route("/admin/services/<int:service_id>", methods=["PUT"])
def admin_update_service(service_id):
    guard = _admin_required()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    db = get_db()
    cur = db.cursor()
    fields = []
    values = []
    for column in ("name", "price", "description", "icon_name",
                   "inventory_count", "monthly_cost"):
        if column in data:
            fields.append("%s = %%s" % column)
            values.append(data[column])
    if not fields:
        return _err("Nothing to update.")
    values.append(service_id)
    cur.execute(
        "UPDATE Services SET %s WHERE id = %%s" % ", ".join(fields), values
    )
    if cur.rowcount == 0:
        return _err("Service not found.", 404)
    db.commit()
    return _ok({})


@api_v1.route("/admin/services/<int:service_id>", methods=["DELETE"])
def admin_delete_service(service_id):
    guard = _admin_required()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    cur.execute("DELETE FROM Services WHERE id = %s", (service_id,))
    if cur.rowcount == 0:
        return _err("Service not found.", 404)
    db.commit()
    return _ok({})

# ================================================================ Fix #4
# Customer + admin parity (PARITY_CHECKLIST.md §6.2 / §6.3).
# Every endpoint below mirrors a web route/table documented in
# ANALYSIS.md. Tables/columns that are only documented as "read in
# code, not in CREATE TABLE" (locked_price, wallet_balance, ...) or
# whose exact columns were not in the workspace are accessed through
# the guarded helpers here: a missing table/column returns an empty
# list / fallback value, never a 500. Nothing here invents a table.
# WebAuthn is deliberately NOT built: the workspace has only the route
# list (auth.py:479-759, webauthn 3.x, WebAuthnCredentials table) —
# missing: RP id/name, origin, challenge storage key, credential
# field names, and the webauthn 3.x begin/complete call shapes.
# Clerk Backend API calls (ban/unban/delete/provision) are NOT made
# here: the existing toggle-ban does local DB only, and §6.4 keeps
# Clerk server-side calls web-only. Customer create/delete below do
# the local DB action and carry a TODO comment for the server-side
# Clerk sync — env var names only, never a secret value.
# Deliberately NOT built: raw DB query, backup download/upload,
# fix-db, spin wheel, cron/SEO routes (see README).

_COLUMN_CACHE = {}


def _row_dict(row):
    out = {}
    for k, v in dict(row).items():
        out[k] = v.isoformat() if hasattr(v, "isoformat") else v
    return out


def _table_columns(table):
    """Column names for a table, cached; [] when the table is absent."""
    if table in _COLUMN_CACHE:
        return _COLUMN_CACHE[table]
    cols = []
    try:
        db = get_db()
        cur = db.cursor()
        cur.execute(
            "SELECT column_name FROM information_schema.columns"
            " WHERE table_name = %s",
            (table.lower(),),
        )
        cols = [r["column_name"] for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        cols = []
    _COLUMN_CACHE[table] = cols
    return cols


def _has_column(table, column):
    return column in _table_columns(table)


def _table_exists(table):
    return bool(_table_columns(table))


def _setting(key, default=None):
    try:
        db = get_db()
        cur = db.cursor()
        cur.execute("SELECT value FROM Settings WHERE key = %s", (key,))
        row = cur.fetchone()
        return row["value"] if row is not None else default
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        return default


def _set_setting(key, value):
    """Upsert a Settings key/value row; no-op when the table differs."""
    if not _has_column("Settings", "key"):
        return False
    db = get_db()
    cur = db.cursor()
    try:
        cur.execute(
            "INSERT INTO Settings (key, value) VALUES (%s, %s)",
            (key, str(value)),
        )
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        try:
            cur.execute(
                "UPDATE Settings SET value = %s WHERE key = %s",
                (str(value), key),
            )
        except Exception:
            try:
                db.rollback()
            except Exception:
                pass
            return False
    db.commit()
    return True


def _insert_row(table, data):
    """Insert only the keys that actually exist as columns; returns
    the new id when the table has one, else None. Never raises for a
    missing column/table — returns None."""
    cols = _table_columns(table)
    if not cols:
        return None
    keep = {k: v for k, v in data.items() if k in cols and v is not None}
    if not keep:
        return None
    db = get_db()
    cur = db.cursor()
    names = ", ".join(keep.keys())
    placeholders = ", ".join(["%s"] * len(keep))
    try:
        if "id" in cols:
            cur.execute(
                "INSERT INTO %s (%s) VALUES (%s) RETURNING id"
                % (table, names, placeholders),
                list(keep.values()),
            )
            row = cur.fetchone()
            new_id = row["id"] if row else None
        else:
            cur.execute(
                "INSERT INTO %s (%s) VALUES (%s)"
                % (table, names, placeholders),
                list(keep.values()),
            )
            new_id = None
        db.commit()
        return new_id
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        return None


def _update_row(table, where_sql, where_params, data):
    """UPDATE with only existing columns; returns rows affected."""
    cols = _table_columns(table)
    keep = {k: v for k, v in data.items() if k in cols}
    if not keep:
        return 0
    db = get_db()
    cur = db.cursor()
    sets = ", ".join("%s = %%s" % k for k in keep.keys())
    try:
        cur.execute(
            "UPDATE %s SET %s WHERE %s" % (table, sets, where_sql),
            list(keep.values()) + list(where_params),
        )
        db.commit()
        return cur.rowcount
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        return 0


def _notify_user(user_id, title, message, kind="system"):
    """Best-effort NotificationQueue insert; never raises."""
    if not _table_exists("NotificationQueue"):
        return
    _insert_row("NotificationQueue", {
        "user_id": user_id, "title": title, "message": message,
        "type": kind, "kind": kind, "is_read": False,
    })


def _log_order_event(sub_id, event_type, message=""):
    if not _table_exists("OrderEvents"):
        return
    _insert_row("OrderEvents", {
        "subscription_id": sub_id, "event_type": event_type,
        "message": message, "description": message,
    })


def _normalise_ke_phone(phone):
    digits = re.sub(r"\D", "", phone or "")
    if digits.startswith("0"):
        digits = "254" + digits[1:]
    elif digits.startswith("7") or digits.startswith("1"):
        digits = "254" + digits
    return digits


def _initiate_stk_push(amount, phone, email):
    """Call the web's own IntaSend client exactly as ANALYSIS.md §5(b)
    documents it (intasend_client.initiate_stk_push(amount, phone,
    email, narrative=...)). Returns a dict with invoice_id /
    checkout_request_id / merchant_request_id, or None when the client
    is not importable or the call fails. The caller then falls back to
    an Initiated subscription with a placeholder reference — the live
    STK push call shape must be verified at deploy time (see README)."""
    try:
        from app.intasend_client import intasend_client
    except ImportError:
        try:
            from app.utils import intasend_client
        except ImportError:
            return None
    try:
        result = intasend_client.initiate_stk_push(
            amount, phone, email, narrative="PremiumSlots Subscription")
    except TypeError:
        try:
            result = intasend_client.initiate_stk_push(amount, phone, email)
        except Exception:
            return None
    except Exception:
        return None
    if not isinstance(result, dict):
        return None
    invoice = result.get("invoice_id")
    if not invoice and isinstance(result.get("invoice"), dict):
        invoice = result["invoice"].get("invoice_id")
    if not invoice and isinstance(result.get("invoice"), str):
        invoice = result["invoice"]
    return {
        "invoice_id": invoice,
        "checkout_request_id": result.get("checkout_request_id")
        or result.get("tuma_checkout_request_id"),
        "merchant_request_id": result.get("merchant_request_id")
        or result.get("request_id"),
        "raw": result,
    }


def _wallet_daily_spent(user_id):
    """KES spent from the wallet today (velocity cap: 25,000/day)."""
    try:
        db = get_db()
        cur = db.cursor()
        cur.execute(
            "SELECT COALESCE(SUM(amount), 0) AS total"
            " FROM WalletTransactions WHERE user_id = %s"
            " AND action_type IN ('spend', 'spent', 'payment',"
            " 'purchase', 'renewal', 'debit')"
            " AND created_at >= CURRENT_DATE",
            (user_id,),
        )
        return cur.fetchone()["total"] or 0
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        return 0


def _validate_coupon(code, user_id, service_name, amount):
    """Mirror of validate_coupon (app/loyalty.py:320): code, active,
    not expired, max_redemptions, min_amount, max_redemptions_per_user
    (default 1), customer_type, service_restriction, discount_type
    percent/flat with max_discount_amount. Column names are read
    defensively — the exact Coupons columns were not in the workspace."""
    if not _table_exists("Coupons"):
        return {"valid": False, "error": "Coupons are not available."}
    db = get_db()
    cur = db.cursor()
    try:
        cur.execute("SELECT * FROM Coupons WHERE code = %s", (code,))
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        return {"valid": False, "error": "That coupon is not valid."}
    row = cur.fetchone()
    if row is None:
        return {"valid": False, "error": "That coupon does not exist."}
    active = row.get("is_active")
    if active is None:
        active = row.get("active", True)
    if not active:
        return {"valid": False, "error": "That coupon is no longer active."}
    expiry = row.get("expires_at") or row.get("expiry_date") or row.get("expires")
    if expiry is not None and hasattr(expiry, "isoformat"):
        if expiry < datetime.utcnow():
            return {"valid": False, "error": "That coupon has expired."}
    min_amount = row.get("min_amount") or 0
    if amount < (min_amount or 0):
        return {"valid": False,
                "error": "That coupon needs a minimum spend of KES %s."
                         % min_amount}
    restriction = row.get("service_restriction") or row.get("service")
    if restriction and restriction != service_name:
        return {"valid": False,
                "error": "That coupon does not apply to this platform."}
    customer_type = (row.get("customer_type") or "all").lower()
    if customer_type in ("new", "existing"):
        try:
            cur.execute(
                "SELECT COUNT(*) AS n FROM Subscriptions WHERE user_id = %s"
                " AND status = 'Approved'",
                (user_id,),
            )
            has_subs = cur.fetchone()["n"] > 0
            if customer_type == "new" and has_subs:
                return {"valid": False,
                        "error": "That coupon is for new customers only."}
            if customer_type == "existing" and not has_subs:
                return {"valid": False,
                        "error": "That coupon is for existing customers only."}
        except Exception:
            try:
                db.rollback()
            except Exception:
                pass
    max_red = row.get("max_redemptions")
    if max_red:
        try:
            cur.execute(
                "SELECT COUNT(*) AS n FROM CouponRedemptions"
                " WHERE coupon_id = %s",
                (row["id"],),
            )
            if cur.fetchone()["n"] >= max_red:
                return {"valid": False,
                        "error": "That coupon has reached its redemption limit."}
        except Exception:
            try:
                db.rollback()
            except Exception:
                pass
    max_per_user = row.get("max_redemptions_per_user") or 1
    try:
        cur.execute(
            "SELECT COUNT(*) AS n FROM CouponRedemptions"
            " WHERE coupon_id = %s AND user_id = %s",
            (row["id"], user_id),
        )
        if cur.fetchone()["n"] >= max_per_user:
            return {"valid": False,
                    "error": "You have already used that coupon."}
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    dtype = (row.get("discount_type") or "percent").lower()
    value = row.get("discount_value")
    if value is None:
        value = row.get("value") or row.get("discount") or 0
    if dtype == "flat":
        discount = value
    else:
        discount = amount * (value or 0) / 100.0
    max_discount = row.get("max_discount_amount")
    if max_discount:
        discount = min(discount, max_discount)
    discount = int(min(discount, amount))
    return {"valid": True, "discount": discount,
            "discount_type": dtype, "code": code,
            "amount_after_discount": amount - discount}


LOYALTY_TIERS = [
    ("Bronze", 0, 0), ("Silver", 250, 5),
    ("Gold", 750, 10), ("Platinum", 2000, 15),
]


def _loyalty_tier_for(points):
    tier = "Bronze"
    discount = 0
    for name, threshold, pct in LOYALTY_TIERS:
        if points >= threshold:
            tier, discount = name, pct
    return tier, discount


def _simple_pdf(title, lines):
    """Minimal valid PDF (Helvetica) — used for receipts, wallet
    statements and the admin report. The web uses fpdf2 for these;
    this produces equivalent printable bytes without depending on the
    fpdf2 import at blueprint load time."""
    def esc(text):
        return (str(text).replace("\\", "\\\\").replace("(", "\\(")
                .replace(")", "\\)"))
    content = ["BT /F1 16 Tf 40 780 Td (%s) Tj ET" % esc(title)]
    y = 750
    for line in lines:
        content.append(
            "BT /F1 11 Tf 40 %d Td (%s) Tj ET" % (y, esc(line)))
        y -= 18
        if y < 40:
            break
    stream = "\n".join(content).encode("utf-8")
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842]"
        b" /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        b"<< /Length %d >>\nstream\n" % len(stream)
        + stream + b"\nendstream",
    ]
    pdf = b"%PDF-1.4\n"
    offsets = []
    for i, obj in enumerate(objects, start=1):
        offsets.append(len(pdf))
        pdf += b"%d 0 obj\n" % i + obj + b"\nendobj\n"
    xref = len(pdf)
    pdf += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1)
    for off in offsets:
        pdf += b"%010d 00000 n \n" % off
    pdf += (b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF"
            % (len(objects) + 1, xref))
    return pdf


def _sign_receipt(payload):
    """HMAC-SHA256 receipt signature, mirroring sign_receipt
    (utils.py:415-446). The web's signing key is not in the workspace,
    so this uses env RECEIPT_HMAC_KEY (falling back to SECRET_KEY);
    verify live that it matches the web key before trusting the
    verify endpoint — see README."""
    key = (os.environ.get("RECEIPT_HMAC_KEY")
           or os.environ.get("SECRET_KEY") or "")
    if not key:
        return None
    return hmac.new(key.encode("utf-8"), payload.encode("utf-8"),
                    "sha256").hexdigest()


def _admin_guard():
    return _admin_required()


# ---------------------------------------------------------------- dashboard

@api_v1.route("/me/dashboard", methods=["GET"])
@user_required
def my_dashboard():
    """Web GET / (main.py:19) when logged in: subs, FinancialLedger
    (last 50), Waitlist positions, unread NotificationQueue count,
    global_alert from Settings."""
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT * FROM Subscriptions WHERE user_id = %s ORDER BY id DESC",
        (session["user_id"],),
    )
    subs = [_subscription_row(r) for r in cur.fetchall()]
    ledger = []
    try:
        cur.execute(
            "SELECT * FROM FinancialLedger WHERE user_id = %s"
            " ORDER BY id DESC LIMIT 50",
            (session["user_id"],),
        )
        ledger = [_row_dict(r) for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    waitlist = []
    try:
        cur.execute(
            "SELECT * FROM Waitlist WHERE user_id = %s",
            (session["user_id"],),
        )
        for row in cur.fetchall():
            item = _row_dict(row)
            try:
                cur.execute(
                    "SELECT COUNT(*) AS n FROM Waitlist"
                    " WHERE service_requested = %s AND id < %s",
                    (row.get("service_requested"), row.get("id")),
                )
                item["position"] = cur.fetchone()["n"] + 1
            except Exception:
                try:
                    db.rollback()
                except Exception:
                    pass
                item["position"] = row.get("priority_pos")
            waitlist.append(item)
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    unread = 0
    try:
        if _has_column("NotificationQueue", "is_read"):
            cur.execute(
                "SELECT COUNT(*) AS n FROM NotificationQueue"
                " WHERE user_id = %s AND is_read = FALSE",
                (session["user_id"],),
            )
            unread = cur.fetchone()["n"]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    approved_count = sum(1 for s in subs if s["status"] == "Approved")
    return _ok({"subscriptions": subs, "ledger": ledger,
                "waitlist": waitlist, "unread_count": unread,
                "approved_count": approved_count,
                "global_alert": _setting("global_alert")})


@api_v1.route("/me/waitlist", methods=["GET"])
@user_required
def my_waitlist():
    db = get_db()
    cur = db.cursor()
    try:
        cur.execute(
            "SELECT * FROM Waitlist WHERE user_id = %s ORDER BY id",
            (session["user_id"],),
        )
        items = []
        for row in cur.fetchall():
            item = _row_dict(row)
            try:
                cur.execute(
                    "SELECT COUNT(*) AS n FROM Waitlist"
                    " WHERE service_requested = %s AND id < %s",
                    (row.get("service_requested"), row.get("id")),
                )
                item["position"] = cur.fetchone()["n"] + 1
            except Exception:
                try:
                    db.rollback()
                except Exception:
                    pass
                item["position"] = row.get("priority_pos")
            items.append(item)
        return _ok({"waitlist": items})
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        return _ok({"waitlist": []})


# ---------------------------------------------------------------- suggestions

@api_v1.route("/suggestions", methods=["GET"])
def list_suggestions():
    """Top 10 community suggestions (SuggestedServices GROUP BY)."""
    try:
        db = get_db()
    except Exception:
        return _ok({"suggestions": []})
    cur = db.cursor()
    try:
        cur.execute(
            "SELECT service_name, COUNT(*) AS votes FROM SuggestedServices"
            " GROUP BY service_name ORDER BY votes DESC LIMIT 10"
        )
        items = [{"service_name": r["service_name"],
                  "votes": r["votes"]} for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        items = []
    return _ok({"suggestions": items})


@api_v1.route("/suggestions", methods=["POST"])
@user_required
def submit_suggestion():
    """Web POST /suggest_service (subscriptions.py:553)."""
    data = request.get_json(silent=True) or {}
    name = (data.get("service_name") or data.get("name") or "").strip()
    if not name:
        return _err("Tell us the platform name.")
    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT email FROM Users WHERE id = %s",
                (session["user_id"],))
    user = cur.fetchone()
    email = (data.get("email") or (user or {}).get("email") or "").strip()
    _insert_row("SuggestedServices",
                {"service_name": name, "email": email})
    return _ok({"service_name": name}, 201)


# ---------------------------------------------------------------- coupons

@api_v1.route("/coupons/validate", methods=["POST"])
@user_required
def validate_coupon_endpoint():
    """Web POST /api/coupons/validate (coupons.py:13)."""
    data = request.get_json(silent=True) or {}
    code = (data.get("code") or data.get("coupon_code") or "").strip()
    service_name = (data.get("service_requested") or "").strip()
    try:
        amount = int(data.get("amount") or 0)
    except (TypeError, ValueError):
        amount = 0
    if not code:
        return _err("Enter a coupon code.")
    if amount <= 0 and service_name:
        db = get_db()
        cur = db.cursor()
        cur.execute("SELECT price FROM Services WHERE name = %s",
                    (service_name,))
        row = cur.fetchone()
        amount = row["price"] if row else 0
    result = _validate_coupon(code, session["user_id"], service_name, amount)
    if not result.get("valid"):
        return _err(result.get("error") or "That coupon is not valid.")
    return _ok({"valid": True, "code": code, "discount": result["discount"],
                "discount_type": result["discount_type"],
                "amount": amount,
                "amount_after_discount": result["amount_after_discount"]})


# ---------------------------------------------------------------- STK checkout

@api_v1.route("/checkout/status/<ref>", methods=["GET"])
@user_required
def checkout_status(ref):
    """Web GET /api/checkout/status/<tuma_ref>."""
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT * FROM Subscriptions WHERE tuma_reference = %s"
        " AND user_id = %s",
        (ref, session["user_id"]),
    )
    row = cur.fetchone()
    if row is None:
        return _err("Checkout not found.", 404)
    return _ok({"subscription": _subscription_row(row),
                "status": row["status"],
                "tuma_reference": row.get("tuma_reference"),
                "receipt": row.get("mpesa_code"),
                "amount_due": row.get("amount_due")})


@api_v1.route("/pay/retry/<int:sub_id>", methods=["POST"])
@user_required
def pay_retry(sub_id):
    """Web POST /pay/retry/<sub_id>: re-initiate the STK push."""
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT * FROM Subscriptions WHERE id = %s AND user_id = %s",
        (sub_id, session["user_id"]),
    )
    row = cur.fetchone()
    if row is None:
        return _err("Subscription not found.", 404)
    cur.execute("SELECT * FROM Users WHERE id = %s", (session["user_id"],))
    user = cur.fetchone()
    phone = _normalise_ke_phone(
        (user or {}).get("whatsapp_number") or "")
    result = _initiate_stk_push(row.get("amount_due") or 0, phone,
                                (user or {}).get("email") or "")
    if not result or not result.get("invoice_id"):
        return _err(
            "STK push could not be started: the IntaSend client needs"
            " verifying at deploy time (see README).", 503)
    cur.execute(
        "UPDATE Subscriptions SET tuma_reference = %s,"
        " tuma_checkout_request_id = %s, mpesa_code = %s, status = 'Initiated'"
        " WHERE id = %s",
        (result["invoice_id"], result.get("checkout_request_id"),
         "INTASEND-INIT-%s" % result.get("merchant_request_id", sub_id),
         sub_id),
    )
    db.commit()
    return _ok({"status": "Initiated",
                "tuma_reference": result["invoice_id"]})


@api_v1.route("/pay/verify-manual/<int:sub_id>", methods=["POST"])
@user_required
def pay_verify_manual(sub_id):
    """Web POST /pay/verify_manual/<sub_id>: tries an IntaSend status
    check first, else records a manual verification request. The
    IntaSend status-check call shape is not in the workspace, so this
    records the manual verification request (OrderEvents + admin
    notification) and returns it for admin confirmation."""
    data = request.get_json(silent=True) or {}
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT * FROM Subscriptions WHERE id = %s AND user_id = %s",
        (sub_id, session["user_id"]),
    )
    row = cur.fetchone()
    if row is None:
        return _err("Subscription not found.", 404)
    if data.get("mpesa_code"):
        code = str(data["mpesa_code"]).strip().upper()
        cur.execute(
            "UPDATE Subscriptions SET mpesa_code = %s WHERE id = %s",
            (code, sub_id),
        )
        db.commit()
    _log_order_event(sub_id, "manual_verification_requested",
                     "Customer requested manual payment verification.")
    return _ok({"status": row["status"],
                "message": "Manual verification requested. An admin will"
                           " confirm your payment."})


# ---------------------------------------------------------------- wallet (new)

@api_v1.route("/wallet/instant-renew/<int:sub_id>", methods=["POST"])
@user_required
def wallet_instant_renew(sub_id):
    """Web POST /wallet/instant-renew/<sub_id> (wallet.py:394): pay a
    renewal from balance instantly (1-click renewal)."""
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT * FROM Subscriptions WHERE id = %s AND user_id = %s",
        (sub_id, session["user_id"]),
    )
    row = cur.fetchone()
    if row is None:
        return _err("Subscription not found.", 404)
    cur.execute("SELECT * FROM Services WHERE name = %s",
                (row["service_requested"],))
    service = cur.fetchone()
    amount = row.get("locked_price") or (service or {}).get("price") \
        or row.get("amount_due") or 0
    cur.execute("SELECT wallet_balance FROM Users WHERE id = %s",
                (session["user_id"],))
    user = cur.fetchone()
    balance = (user or {}).get("wallet_balance") or 0
    if balance < amount:
        return _err("Your wallet balance is not enough to renew this slot.")
    if _wallet_daily_spent(session["user_id"]) + amount > 25000:
        return _err("That renewal would pass the KES 25,000 daily wallet spend limit.")
    ref = "WALLET-RNW-%s" % secrets.token_hex(4).upper()
    try:
        from app.utils import calculate_subscription_expiry
        expiry = calculate_subscription_expiry(row.get("expiry_date"))
    except Exception:
        expiry = datetime.utcnow() + timedelta(days=30)
    cur.execute(
        "UPDATE Users SET wallet_balance = wallet_balance - %s WHERE id = %s",
        (amount, session["user_id"]),
    )
    try:
        cur.execute(
            "INSERT INTO WalletTransactions (user_id, action_type, amount,"
            " mpesa_code) VALUES (%s, 'spend', %s, %s)",
            (session["user_id"], amount, ref),
        )
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        cur.execute(
            "UPDATE Users SET wallet_balance = wallet_balance - %s"
            " WHERE id = %s",
            (amount, session["user_id"]),
        )
    cur.execute(
        "UPDATE Subscriptions SET status = 'Approved', expiry_date = %s,"
        " amount_due = %s WHERE id = %s",
        (expiry, amount, sub_id),
    )
    db.commit()
    return _ok({"status": "Approved", "amount": amount,
                "wallet_balance": balance - amount, "reference": ref,
                "expiry_date": expiry.isoformat() if hasattr(
                    expiry, "isoformat") else str(expiry)})


@api_v1.route("/wallet/redeem-gift-card", methods=["POST"])
@user_required
def wallet_redeem_gift_card():
    """Web POST /wallet/redeem-gift-card (wallet.py:222)."""
    data = request.get_json(silent=True) or {}
    code = (data.get("code") or "").strip().upper()
    if not code:
        return _err("Enter a gift card code.")
    db = get_db()
    cur = db.cursor()
    try:
        cur.execute("SELECT * FROM GiftCards WHERE code = %s", (code,))
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        return _err("Gift cards are not available.", 503)
    card = cur.fetchone()
    if card is None:
        return _err("That gift card does not exist.", 404)
    status = (card.get("status") or "").lower()
    if status in ("redeemed", "used", "expired", "rejected"):
        return _err("That gift card has already been used or is not valid.")
    amount = card.get("amount") or 0
    if amount <= 0:
        return _err("That gift card has no value.")
    cur.execute(
        "UPDATE Users SET wallet_balance = wallet_balance + %s WHERE id = %s",
        (amount, session["user_id"]),
    )
    try:
        cur.execute(
            "INSERT INTO WalletTransactions (user_id, action_type, amount,"
            " mpesa_code) VALUES (%s, 'redeem', %s, %s)",
            (session["user_id"], amount, code),
        )
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        cur.execute(
            "UPDATE Users SET wallet_balance = wallet_balance + %s"
            " WHERE id = %s",
            (amount, session["user_id"]),
        )
    _update_row("GiftCards", "code = %s", (code,),
                {"status": "redeemed", "redeemed_by": session["user_id"],
                 "redeemed_at": datetime.utcnow()})
    db.commit()
    cur.execute("SELECT wallet_balance FROM Users WHERE id = %s",
                (session["user_id"],))
    balance = cur.fetchone()["wallet_balance"]
    return _ok({"amount": amount, "wallet_balance": balance})


@api_v1.route("/wallet/statement", methods=["GET"])
@user_required
def wallet_statement():
    """JSON wallet statement (the web has no GET /wallet/statement
    page route — the statement is the PDF only; this JSON mirrors the
    same data for the app)."""
    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT wallet_balance FROM Users WHERE id = %s",
                (session["user_id"],))
    user = cur.fetchone()
    cur.execute(
        "SELECT * FROM WalletTransactions WHERE user_id = %s"
        " ORDER BY id DESC LIMIT 200",
        (session["user_id"],),
    )
    txns = [_row_dict(r) for r in cur.fetchall()]
    totals = {}
    for row in txns:
        action = (row.get("action_type") or "other").lower()
        totals[action] = totals.get(action, 0) + (row.get("amount") or 0)
    return _ok({"wallet_balance": (user or {}).get("wallet_balance") or 0,
                "transactions": txns, "totals": totals,
                "pdf_url": "/api/v1/wallet/statement/pdf"})


@api_v1.route("/wallet/statement/pdf", methods=["GET"])
@user_required
def wallet_statement_pdf():
    """Web GET /wallet/statement/pdf (wallet.py:532)."""
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT name, email, wallet_balance FROM Users WHERE id = %s",
        (session["user_id"],),
    )
    user = cur.fetchone() or {}
    cur.execute(
        "SELECT * FROM WalletTransactions WHERE user_id = %s"
        " ORDER BY id DESC LIMIT 100",
        (session["user_id"],),
    )
    lines = ["PremiumSlots wallet statement",
             "Account: %s <%s>" % (user.get("name") or "",
                                   user.get("email") or ""),
             "Balance: KES %s" % (user.get("wallet_balance") or 0),
             "Generated: %s" % datetime.utcnow().isoformat(), ""]
    for row in cur.fetchall():
        lines.append("%s  %s  KES %s" % (
            row.get("created_at"), row.get("action_type"),
            row.get("amount")))
    pdf = _simple_pdf("PremiumSlots — Wallet Statement", lines)
    return Response(pdf, mimetype="application/pdf",
                    headers={"Content-Disposition":
                             "attachment; filename=wallet-statement.pdf"})


# ---------------------------------------------------------------- subs detail

@api_v1.route("/me/subscriptions/<int:sub_id>/timeline", methods=["GET"])
@user_required
def subscription_timeline(sub_id):
    """Web GET /subscription/<id>/timeline (subscriptions.py:594),
    from OrderEvents."""
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT * FROM Subscriptions WHERE id = %s AND user_id = %s",
        (sub_id, session["user_id"]),
    )
    row = cur.fetchone()
    if row is None:
        return _err("Subscription not found.", 404)
    events = []
    try:
        cur.execute(
            "SELECT * FROM OrderEvents WHERE subscription_id = %s"
            " ORDER BY id",
            (sub_id,),
        )
        events = [_row_dict(r) for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    if not events:
        # Fallback timeline from the subscription row itself.
        events = [{"event_type": "created",
                   "message": "Subscription requested (%s)."
                              % row.get("status"),
                   "created_at": _row_dict(row).get("created_at")},
                  {"event_type": "status",
                   "message": "Status: %s." % row.get("status"),
                   "created_at": None}]
    return _ok({"subscription": _subscription_row(row),
                "timeline": events})


@api_v1.route("/me/subscriptions/<int:sub_id>/request-review",
              methods=["POST"])
@user_required
def request_review(sub_id):
    """Web POST /subscription/request-review (subscriptions.py:506):
    sets review_requested."""
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "UPDATE Subscriptions SET review_requested = TRUE"
        " WHERE id = %s AND user_id = %s",
        (sub_id, session["user_id"]),
    )
    if cur.rowcount == 0:
        return _err("Subscription not found.", 404)
    db.commit()
    return _ok({})


# ---------------------------------------------------------------- gift cards

@api_v1.route("/gift-cards", methods=["GET"])
@user_required
def list_gift_cards():
    """Web GET /gift-cards (giftcards.py:117): feature toggle,
    denominations, 5 themes, my issued (last 20) + redeemed (last 20)."""
    enabled = _setting("is_gift_cards_enabled", "true")
    if isinstance(enabled, str):
        enabled = enabled.lower() not in ("false", "0", "no", "off")
    db = get_db()
    cur = db.cursor()
    issued, redeemed = [], []
    try:
        cur.execute(
            "SELECT * FROM GiftCards WHERE sender_id = %s"
            " ORDER BY id DESC LIMIT 20",
            (session["user_id"],),
        )
        issued = [_row_dict(r) for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    try:
        cur.execute(
            "SELECT * FROM GiftCards WHERE redeemed_by = %s"
            " ORDER BY id DESC LIMIT 20",
            (session["user_id"],),
        )
        redeemed = [_row_dict(r) for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    return _ok({"enabled": bool(enabled),
                "denominations": [200, 500, 1000, 2000, 5000],
                "themes": ["Cyber Gold", "Electric Blue", "Emerald Luxe",
                           "Neon Violet", "Crimson Ruby"],
                "issued": issued, "redeemed": redeemed})


@api_v1.route("/gift-cards", methods=["POST"])
@user_required
def create_gift_card():
    """Web POST /gift-cards/create (giftcards.py:178): paid by manual
    M-PESA code; generates a code and (on the web) emails it. Email
    sending here is best-effort via the account-mail helper."""
    data = request.get_json(silent=True) or {}
    try:
        amount = int(data.get("amount") or 0)
    except (TypeError, ValueError):
        return _err("Choose a gift card amount.")
    if amount <= 0:
        return _err("Choose a gift card amount.")
    mpesa_code = (data.get("mpesa_code") or "").strip().upper()
    if not MPESA_CODE_RE.match(mpesa_code or ""):
        return _err("The M-PESA code must be exactly 10 letters and numbers.")
    if is_mpesa_code_used(mpesa_code):
        return _err("That M-PESA code has already been used.")
    code = "PS-%s" % secrets.token_hex(4).upper()
    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT name, email FROM Users WHERE id = %s",
                (session["user_id"],))
    user = cur.fetchone() or {}
    new_id = _insert_row("GiftCards", {
        "code": code, "amount": amount, "status": "active",
        "sender_id": session["user_id"],
        "sender_name": user.get("name"),
        "recipient_name": (data.get("recipient_name") or "").strip(),
        "recipient_email": (data.get("recipient_email") or "").strip(),
        "message": data.get("message") or data.get("custom_message") or "",
        "theme_style": data.get("theme_style") or data.get("theme") or "",
        "mpesa_code": mpesa_code,
    })
    if new_id is None:
        return _err("Gift cards could not be created right now.", 503)
    recipient = (data.get("recipient_email") or "").strip()
    if recipient:
        _send_account_email(
            recipient, "You received a PremiumSlots gift card",
            "You received a KES %s PremiumSlots gift card from %s.\n"
            "Code: %s\nRedeem it in the PremiumSlots app wallet."
            % (amount, user.get("name") or "a friend", code))
    return _ok({"gift_card_id": new_id, "code": code,
                "amount": amount, "status": "active"}, 201)


@api_v1.route("/gift-cards/redeem", methods=["POST"])
@user_required
def redeem_gift_card():
    """Web POST /gift-cards/redeem (giftcards.py:362) → wallet credit."""
    return wallet_redeem_gift_card()


@api_v1.route("/gift-cards/verify/<code>", methods=["GET"])
def verify_gift_card(code):
    """Web GET /gift-cards/verify/<code> (giftcards.py:474). Public:
    returns code, amount, status, expiry, theme, sender/recipient."""
    db = get_db()
    cur = db.cursor()
    try:
        cur.execute("SELECT * FROM GiftCards WHERE code = %s",
                    (code or "").strip().upper(),)
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        return _err("Gift cards are not available.", 503)
    row = cur.fetchone()
    if row is None:
        return _err("That gift card does not exist.", 404)
    item = _row_dict(row)
    return _ok({"gift_card": {
        "code": item.get("code"), "amount": item.get("amount"),
        "status": item.get("status"),
        "expiry": item.get("expiry_date") or item.get("expires_at"),
        "theme": item.get("theme_style"),
        "sender": item.get("sender_name"),
        "recipient": item.get("recipient_name")
        or item.get("recipient_email")}})

# ---------------------------------------------------------------- store

@api_v1.route("/store", methods=["GET"])
@user_required
def loyalty_store():
    """Web GET /store (store.py:11): active RewardItems, my points,
    my last 50 RewardRedemptions, totals, active coupons, my tier."""
    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT loyalty_points FROM Users WHERE id = %s",
                (session["user_id"],))
    user = cur.fetchone()
    points = (user or {}).get("loyalty_points") or 0
    items = []
    try:
        cur.execute(
            "SELECT * FROM RewardItems WHERE is_active = TRUE"
            " ORDER BY points_cost",
        )
        items = [_row_dict(r) for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        try:
            cur.execute("SELECT * FROM RewardItems ORDER BY points_cost")
            items = [_row_dict(r) for r in cur.fetchall()]
        except Exception:
            try:
                db.rollback()
            except Exception:
                pass
            items = []
    redemptions = []
    try:
        cur.execute(
            "SELECT * FROM RewardRedemptions WHERE user_id = %s"
            " ORDER BY id DESC LIMIT 50",
            (session["user_id"],),
        )
        redemptions = [_row_dict(r) for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    coupons = []
    try:
        cur.execute("SELECT * FROM Coupons WHERE is_active = TRUE")
        coupons = [_row_dict(r) for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    tier, discount = _loyalty_tier_for(points)
    return _ok({"items": items, "points": points, "loyalty_tier": tier,
                "tier_discount_percent": discount,
                "redemptions": redemptions,
                "total_spent": sum(r.get("points_cost") or 0
                                   for r in redemptions),
                "total_claims": len(redemptions),
                "active_coupons": coupons})


@api_v1.route("/store/redeem/<int:reward_id>", methods=["POST"])
@user_required
def redeem_reward(reward_id):
    """Web POST /store/redeem/<reward_id> (store.py:52), 10/hour.
    discount_coupon rewards generate a PS-XXXXXXXX code; redemption
    status Pending; stock -1."""
    db = get_db()
    cur = db.cursor()
    try:
        cur.execute(
            "SELECT COUNT(*) AS n FROM RewardRedemptions"
            " WHERE user_id = %s AND created_at >= NOW() - INTERVAL '1 hour'",
            (session["user_id"],),
        )
        if cur.fetchone()["n"] >= 10:
            return _err("You have reached the limit of 10 redemptions per hour.", 429)
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    try:
        cur.execute("SELECT * FROM RewardItems WHERE id = %s", (reward_id,))
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        return _err("Rewards are not available.", 503)
    item = cur.fetchone()
    if item is None:
        return _err("Reward not found.", 404)
    cost = item.get("points_cost") or 0
    cur.execute("SELECT loyalty_points FROM Users WHERE id = %s",
                (session["user_id"],))
    user = cur.fetchone()
    points = (user or {}).get("loyalty_points") or 0
    if points < cost:
        return _err("You do not have enough points for this reward.")
    stock = item.get("stock")
    if stock is not None and stock <= 0:
        return _err("This reward is out of stock.")
    coupon_code = None
    if (item.get("reward_type") or "").lower() == "discount_coupon":
        coupon_code = "PS-%s" % secrets.token_hex(4).upper()
    cur.execute(
        "UPDATE Users SET loyalty_points = loyalty_points - %s WHERE id = %s",
        (cost, session["user_id"]),
    )
    if stock is not None:
        try:
            cur.execute(
                "UPDATE RewardItems SET stock = stock - 1 WHERE id = %s",
                (reward_id,),
            )
        except Exception:
            try:
                db.rollback()
            except Exception:
                pass
            cur.execute(
                "UPDATE Users SET loyalty_points = loyalty_points - %s"
                " WHERE id = %s",
                (cost, session["user_id"]),
            )
    new_id = _insert_row("RewardRedemptions", {
        "user_id": session["user_id"], "reward_id": reward_id,
        "status": "Pending", "points_cost": cost,
        "coupon_code": coupon_code,
    })
    db.commit()
    return _ok({"redemption_id": new_id, "status": "Pending",
                "coupon_code": coupon_code, "points": points - cost}, 201)


# ---------------------------------------------------------------- loyalty

@api_v1.route("/me/loyalty", methods=["GET"])
@user_required
def my_loyalty():
    """Web app/loyalty.py tiers: Bronze 0 / Silver 250 (-5%) /
    Gold 750 (-10%) / Platinum 2000 (-15%); 1 pt per KES spent;
    2 pts per day of tenure; streak = consecutive months of active
    coverage (compute_streak, grace for previous month)."""
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT loyalty_points, loyalty_tier, referral_count FROM Users"
        " WHERE id = %s",
        (session["user_id"],),
    )
    user = cur.fetchone() or {}
    points = user.get("loyalty_points") or 0
    tier, discount = _loyalty_tier_for(points)
    next_tier = None
    for name, threshold, pct in LOYALTY_TIERS:
        if points < threshold:
            next_tier = {"tier": name, "points_needed": threshold - points,
                         "discount_percent": pct}
            break
    streak_months = 0
    try:
        cur.execute(
            "SELECT * FROM StreakLedger WHERE user_id = %s"
            " ORDER BY id DESC LIMIT 1",
            (session["user_id"],),
        )
        row = cur.fetchone()
        if row is not None:
            streak_months = (row.get("streak_months")
                             or row.get("streak") or 0)
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    ledger = []
    try:
        cur.execute(
            "SELECT * FROM LoyaltyLedger WHERE user_id = %s"
            " ORDER BY id DESC LIMIT 100",
            (session["user_id"],),
        )
        ledger = [_row_dict(r) for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    return _ok({"points": points, "loyalty_tier": tier,
                "tier_discount_percent": discount,
                "next_tier": next_tier, "streak_months": streak_months,
                "referral_count": user.get("referral_count") or 0,
                "ledger": ledger})


@api_v1.route("/me/achievements", methods=["GET"])
@user_required
def my_achievements():
    """Web GET /achievements (achievements.py:10): all
    BadgeDefinitions, earned set from UserBadges, stats (points,
    streak_months, referral_count). Badges evaluated by evaluate_badges
    (first_sub, five/ten/twenty_subs, streak_3/6/12/max, first_ref,
    ref_five, ref_ten, coupon_used, bday_bonus)."""
    db = get_db()
    cur = db.cursor()
    definitions = []
    try:
        cur.execute("SELECT * FROM BadgeDefinitions ORDER BY id")
        definitions = [_row_dict(r) for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    earned = []
    try:
        cur.execute(
            "SELECT * FROM UserBadges WHERE user_id = %s",
            (session["user_id"],),
        )
        earned = [_row_dict(r) for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    cur.execute(
        "SELECT loyalty_points, referral_count FROM Users WHERE id = %s",
        (session["user_id"],),
    )
    user = cur.fetchone() or {}
    streak_months = 0
    try:
        cur.execute(
            "SELECT streak_months FROM StreakLedger WHERE user_id = %s"
            " ORDER BY id DESC LIMIT 1",
            (session["user_id"],),
        )
        row = cur.fetchone()
        if row is not None:
            streak_months = row.get("streak_months") or 0
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    earned_codes = {str(e.get("badge_id") or e.get("badge_code") or e.get("code"))
                    for e in earned}
    for definition in definitions:
        key = str(definition.get("id"))
        code = str(definition.get("code") or "")
        definition["earned"] = key in earned_codes or code in earned_codes
    return _ok({"badges": definitions, "earned": earned,
                "stats": {"points": user.get("loyalty_points") or 0,
                          "streak_months": streak_months,
                          "referral_count": user.get("referral_count") or 0}})


@api_v1.route("/leaderboard", methods=["GET"])
def leaderboard():
    """Web GET /leaderboard (referrals.py:10) + GET
    /referrals/leaderboard (referrals.py:128): monthly + all-time."""
    try:
        db = get_db()
    except Exception:
        return _ok({"monthly": [], "all_time": [], "leaderboard": []})
    cur = db.cursor()
    monthly, all_time = [], []
    try:
        cur.execute(
            "SELECT u.name, COUNT(*) AS referrals FROM Referrals r"
            " JOIN Users u ON u.id = r.referrer_id"
            " WHERE r.status = 'Completed'"
            " AND r.created_at >= NOW() - INTERVAL '30 days'"
            " GROUP BY u.id, u.name ORDER BY referrals DESC LIMIT 20"
        )
        monthly = [dict(r) for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    try:
        cur.execute(
            "SELECT u.name, COUNT(*) AS referrals FROM Referrals r"
            " JOIN Users u ON u.id = r.referrer_id"
            " WHERE r.status = 'Completed'"
            " GROUP BY u.id, u.name ORDER BY referrals DESC LIMIT 20"
        )
        all_time = [dict(r) for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    stored = []
    try:
        cur.execute("SELECT * FROM ReferralLeaderboard ORDER BY id DESC LIMIT 20")
        stored = [_row_dict(r) for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    return _ok({"monthly": monthly, "all_time": all_time,
                "leaderboard": stored})


# ---------------------------------------------------------------- wishlist

@api_v1.route("/wishlist", methods=["GET"])
@user_required
def wishlist():
    """Web GET /wishlist (wishlist.py:9): category / status / sort /
    search q, category counts, roadmap KPIs, my voted + notify ids."""
    category = request.args.get("category") or ""
    status = request.args.get("status") or ""
    sort = request.args.get("sort") or "votes"
    q = (request.args.get("q") or "").strip()
    db = get_db()
    cur = db.cursor()
    if not _table_exists("WishlistItems"):
        return _ok({"items": [], "category_counts": {}, "kpis": {
            "total_items": 0, "total_votes": 0, "planned_count": 0,
            "available_count": 0}, "my_voted_ids": [],
            "my_notify_ids": []})
    where = []
    params = []
    if category and category.lower() != "all":
        where.append("category = %s")
        params.append(category)
    if status and status.lower() != "all":
        where.append("status = %s")
        params.append(status)
    if q:
        where.append("(title ILIKE %s OR description ILIKE %s)")
        params.extend(["%%%s%%" % q, "%%%s%%" % q])
    order = {"votes": "votes DESC NULLS LAST",
             "newest": "id DESC",
             "price_asc": "price ASC NULLS LAST"}.get(
        sort, "votes DESC NULLS LAST")
    sql = "SELECT * FROM WishlistItems"
    if where:
        sql += " WHERE " + " AND ".join(where)
    sql += " ORDER BY %s" % order
    try:
        cur.execute(sql, params)
        items = [_row_dict(r) for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        items = []
    counts, kpis = {}, {"total_items": len(items), "total_votes": 0,
                        "planned_count": 0, "available_count": 0}
    try:
        cur.execute(
            "SELECT category, COUNT(*) AS n FROM WishlistItems"
            " GROUP BY category")
        counts = {r["category"]: r["n"] for r in cur.fetchall()}
        cur.execute("SELECT COUNT(*) AS n FROM WishlistItems"
                    " WHERE status = 'planned'")
        kpis["planned_count"] = cur.fetchone()["n"]
        cur.execute("SELECT COUNT(*) AS n FROM WishlistItems"
                    " WHERE status = 'available'")
        kpis["available_count"] = cur.fetchone()["n"]
        cur.execute("SELECT COUNT(*) AS n FROM WishlistVotes")
        kpis["total_votes"] = cur.fetchone()["n"]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    my_voted, my_notify = [], []
    try:
        cur.execute(
            "SELECT wishlist_item_id FROM WishlistVotes WHERE user_id = %s",
            (session["user_id"],))
        my_voted = [r["wishlist_item_id"] for r in cur.fetchall()]
        cur.execute(
            "SELECT wishlist_item_id FROM WishlistNotifications"
            " WHERE user_id = %s",
            (session["user_id"],))
        my_notify = [r["wishlist_item_id"] for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    return _ok({"items": items, "category_counts": counts, "kpis": kpis,
                "my_voted_ids": my_voted, "my_notify_ids": my_notify})


@api_v1.route("/wishlist/vote", methods=["POST"])
@user_required
def wishlist_vote():
    """Web POST /wishlist/vote (30/min)."""
    data = request.get_json(silent=True) or {}
    item_id = data.get("item_id") or data.get("wishlist_item_id")
    if item_id is None:
        return _err("A wishlist item id is required.")
    db = get_db()
    cur = db.cursor()
    try:
        cur.execute(
            "SELECT 1 FROM WishlistVotes WHERE user_id = %s"
            " AND wishlist_item_id = %s",
            (session["user_id"], item_id),
        )
        if cur.fetchone() is None:
            _insert_row("WishlistVotes", {
                "user_id": session["user_id"],
                "wishlist_item_id": item_id})
            try:
                cur.execute(
                    "UPDATE WishlistItems SET votes = COALESCE(votes, 0) + 1"
                    " WHERE id = %s",
                    (item_id,),
                )
                db.commit()
            except Exception:
                try:
                    db.rollback()
                except Exception:
                    pass
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    return _ok({})


@api_v1.route("/wishlist/notify", methods=["POST"])
@user_required
def wishlist_notify():
    """Web POST /wishlist/notify (toggle notify-me)."""
    data = request.get_json(silent=True) or {}
    item_id = data.get("item_id") or data.get("wishlist_item_id")
    if item_id is None:
        return _err("A wishlist item id is required.")
    db = get_db()
    cur = db.cursor()
    enabled = True
    try:
        cur.execute(
            "SELECT 1 FROM WishlistNotifications WHERE user_id = %s"
            " AND wishlist_item_id = %s",
            (session["user_id"], item_id),
        )
        if cur.fetchone() is not None:
            cur.execute(
                "DELETE FROM WishlistNotifications WHERE user_id = %s"
                " AND wishlist_item_id = %s",
                (session["user_id"], item_id),
            )
            db.commit()
            enabled = False
        else:
            _insert_row("WishlistNotifications", {
                "user_id": session["user_id"],
                "wishlist_item_id": item_id})
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    return _ok({"notify_me": enabled})


@api_v1.route("/wishlist/submit", methods=["POST"])
@user_required
def wishlist_submit():
    """Web POST /wishlist/submit (new item)."""
    data = request.get_json(silent=True) or {}
    title = (data.get("title") or "").strip()
    if not title:
        return _err("Give the wishlist item a title.")
    new_id = _insert_row("WishlistItems", {
        "title": title,
        "description": data.get("description") or "",
        "category": data.get("category") or "",
        "status": "suggested", "votes": 0,
        "submitted_by": session["user_id"],
        "user_id": session["user_id"],
    })
    if new_id is None:
        return _err("Wishlist is not available right now.", 503)
    return _ok({"item_id": new_id}, 201)


# ---------------------------------------------------------------- feedback/tickets

@api_v1.route("/feedback", methods=["POST"])
@user_required
def submit_feedback():
    """Web POST /submit_feedback (subscriptions.py:518): message_type
    (Site Feedback / Suggestion, General Inquiry, Payment Issue) +
    message → SupportTickets."""
    data = request.get_json(silent=True) or {}
    message = (data.get("message") or "").strip()
    if not message:
        return _err("Write your message first.")
    new_id = _insert_row("SupportTickets", {
        "user_id": session["user_id"],
        "message_type": data.get("message_type") or "Site Feedback",
        "subject": data.get("subject") or data.get("message_type")
        or "Site Feedback",
        "message": message, "status": "open",
    })
    if new_id is None:
        return _err("Feedback could not be sent right now.", 503)
    return _ok({"ticket_id": new_id}, 201)


@api_v1.route("/me/tickets", methods=["GET"])
@user_required
def my_tickets():
    """Web GET /my-tickets (main.py:405)."""
    db = get_db()
    cur = db.cursor()
    try:
        cur.execute(
            "SELECT * FROM SupportTickets WHERE user_id = %s"
            " ORDER BY id DESC",
            (session["user_id"],),
        )
        return _ok({"tickets": [_row_dict(r) for r in cur.fetchall()]})
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        return _ok({"tickets": []})


@api_v1.route("/tickets", methods=["POST"])
@user_required
def create_ticket():
    """Web POST /submit-ticket (main.py:361)."""
    data = request.get_json(silent=True) or {}
    message = (data.get("message") or data.get("description") or "").strip()
    if not message:
        return _err("Describe the issue first.")
    new_id = _insert_row("SupportTickets", {
        "user_id": session["user_id"],
        "subject": data.get("subject") or "Support ticket",
        "message": message,
        "message_type": data.get("message_type") or "General Inquiry",
        "status": "open",
    })
    if new_id is None:
        return _err("Tickets could not be created right now.", 503)
    return _ok({"ticket_id": new_id}, 201)


# ---------------------------------------------------------------- help / blog

@api_v1.route("/help", methods=["GET"])
def help_centre():
    """Web GET /help (help.py:10): search q, category filter."""
    q = (request.args.get("q") or "").strip()
    category = request.args.get("category") or ""
    try:
        db = get_db()
    except Exception:
        return _ok({"articles": []})
    cur = db.cursor()
    if not _table_exists("HelpArticles"):
        return _ok({"articles": []})
    where, params = [], []
    if q:
        where.append("(title ILIKE %s OR content ILIKE %s)")
        params.extend(["%%%s%%" % q, "%%%s%%" % q])
    if category:
        where.append("category = %s")
        params.append(category)
    sql = "SELECT * FROM HelpArticles"
    if where:
        sql += " WHERE " + " AND ".join(where)
    sql += " ORDER BY id"
    try:
        cur.execute(sql, params)
        return _ok({"articles": [_row_dict(r) for r in cur.fetchall()]})
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        return _ok({"articles": []})


@api_v1.route("/help/<slug>", methods=["GET"])
def help_article(slug):
    """Web GET /help/<slug> (help.py:49)."""
    db = get_db()
    cur = db.cursor()
    try:
        cur.execute("SELECT * FROM HelpArticles WHERE slug = %s", (slug,))
        row = cur.fetchone()
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        row = None
    if row is None:
        return _err("Help article not found.", 404)
    return _ok({"article": _row_dict(row)})


@api_v1.route("/blog", methods=["GET"])
def blog_index():
    """Web GET /blog (blog.py:15)."""
    try:
        db = get_db()
    except Exception:
        return _ok({"posts": []})
    cur = db.cursor()
    if not _table_exists("BlogPosts"):
        return _ok({"posts": []})
    try:
        cur.execute("SELECT * FROM BlogPosts ORDER BY id DESC")
        return _ok({"posts": [_row_dict(r) for r in cur.fetchall()]})
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        return _ok({"posts": []})


@api_v1.route("/blog/<slug>", methods=["GET"])
def blog_post(slug):
    """Web GET /blog/<slug> (blog.py:30) + related posts."""
    db = get_db()
    cur = db.cursor()
    try:
        cur.execute("SELECT * FROM BlogPosts WHERE slug = %s", (slug,))
        row = cur.fetchone()
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        row = None
    if row is None:
        return _err("Blog post not found.", 404)
    related = []
    try:
        cur.execute(
            "SELECT * FROM BlogPosts WHERE slug != %s ORDER BY id DESC"
            " LIMIT 3",
            (slug,),
        )
        related = [_row_dict(r) for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    return _ok({"post": _row_dict(row), "related": related})


# ---------------------------------------------------------------- receipts

@api_v1.route("/receipts/<int:receipt_id>", methods=["GET"])
@user_required
def receipt_pdf(receipt_id):
    """Web GET /receipt/<id> (receipts.py:380): PDF receipt (fpdf2,
    generate_receipt_pdf_bytes). The id is a Subscriptions id; the
    PDF here carries the same fields (service, amount, code, status,
    expiry) in equivalent printable form."""
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT * FROM Subscriptions WHERE id = %s AND user_id = %s",
        (receipt_id, session["user_id"]),
    )
    row = cur.fetchone()
    if row is None:
        return _err("Receipt not found.", 404)
    payload = "receipt:%s" % receipt_id
    signature = _sign_receipt(payload)
    lines = ["PremiumSlots receipt",
             "Receipt: %s" % payload,
             "Service: %s" % row.get("service_requested"),
             "Amount: KES %s" % row.get("amount_due"),
             "Status: %s" % row.get("status"),
             "M-PESA code: %s" % (row.get("mpesa_code") or "-"),
             "Expiry: %s" % (row.get("expiry_date") or "-"),
             "Verify: /api/v1/receipts/verify?payload=%s&signature=%s"
             % (payload, signature or "")]
    pdf = _simple_pdf("PremiumSlots — Receipt", lines)
    return Response(pdf, mimetype="application/pdf",
                    headers={"Content-Disposition":
                             "attachment; filename=receipt-%s.pdf"
                             % receipt_id})


@api_v1.route("/receipts/verify", methods=["GET"])
def receipt_verify():
    """Web GET /verify + GET /receipt/verify (receipts.py:402):
    HMAC-SHA256 verify (sign_receipt / verify_receipt, utils.py).
    The web signing key is not in the workspace: when env
    RECEIPT_HMAC_KEY (or SECRET_KEY) is set, the signature is checked
    with HMAC; otherwise verification is existence-only and the
    response says so — verify the key at deploy time (see README)."""
    payload = request.args.get("payload") or ""
    signature = request.args.get("signature") or ""
    expected = _sign_receipt(payload) if payload else None
    if expected is not None and signature:
        verified = hmac.compare_digest(expected, signature)
        return _ok({"verified": verified, "payload": payload,
                    "method": "hmac"})
    # Existence-only fallback: payload "receipt:<subscription id>".
    exists = False
    if payload.startswith("receipt:"):
        try:
            sub_id = int(payload.split(":", 1)[1])
            db = get_db()
            cur = db.cursor()
            cur.execute("SELECT 1 FROM Subscriptions WHERE id = %s",
                        (sub_id,))
            exists = cur.fetchone() is not None
        except Exception:
            exists = False
    return _ok({"verified": exists, "payload": payload,
                "method": "existence-only",
                "note": "No HMAC key is configured on this server, so"
                        " the signature could not be checked."})

# ---------------------------------------------------------------- GDPR / account

@api_v1.route("/me/gdpr-consent", methods=["GET"])
@user_required
def get_gdpr_consent():
    """Web GET /gdpr/consent (main.py:253)."""
    db = get_db()
    cur = db.cursor()
    consent = None
    try:
        cur.execute(
            "SELECT * FROM GdprConsent WHERE user_id = %s"
            " ORDER BY id DESC LIMIT 1",
            (session["user_id"],),
        )
        row = cur.fetchone()
        consent = _row_dict(row) if row else None
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    return _ok({"consent": consent})


@api_v1.route("/me/gdpr-consent", methods=["POST"])
@user_required
def post_gdpr_consent():
    """Web POST /gdpr/consent (main.py:253)."""
    data = request.get_json(silent=True) or {}
    _insert_row("GdprConsent", {
        "user_id": session["user_id"],
        "consented": bool(data.get("consented", True)),
        "marketing": bool(data.get("marketing", False)),
        "analytics": bool(data.get("analytics", False)),
    })
    return _ok({})


@api_v1.route("/me/export-request", methods=["POST"])
@user_required
def export_request():
    """Web POST /gdpr/export-request (main.py:317, DataExportRequests)."""
    _insert_row("DataExportRequests", {
        "user_id": session["user_id"], "status": "pending",
    })
    return _ok({"status": "pending",
                "message": "Your data export request was recorded."}, 201)


@api_v1.route("/me/profile", methods=["PUT"])
@user_required
def update_profile():
    """Web POST /auth/profile/update (auth.py:337, 5/hour): name +
    whatsapp_number (both required)."""
    data = request.get_json(silent=True) or {}
    name = (data.get("name") or "").strip()
    whatsapp = (data.get("whatsapp_number") or "").strip()
    if not name or not whatsapp:
        return _err("Name and WhatsApp number are both required.")
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "UPDATE Users SET name = %s, whatsapp_number = %s WHERE id = %s",
        (name, whatsapp, session["user_id"]),
    )
    if cur.rowcount == 0:
        return _err("Account not found.", 404)
    db.commit()
    return _ok({"name": name, "whatsapp_number": whatsapp})


@api_v1.route("/me/password", methods=["POST"])
@user_required
def change_password():
    """Web POST /auth/profile/password (auth.py:356, 5/hour): current
    password checked with Werkzeug hash; new password must satisfy
    is_strong_password (min 8 chars, upper + lower + digit)."""
    data = request.get_json(silent=True) or {}
    current = data.get("current_password") or ""
    new = data.get("new_password") or ""
    if not current or not _is_strong_password(new):
        return _err("Enter your current password and a strong new one"
                    " (8+ characters, upper and lower case, and a number).")
    from werkzeug.security import check_password_hash, generate_password_hash
    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT password_hash FROM Users WHERE id = %s",
                (session["user_id"],))
    row = cur.fetchone()
    if row is None:
        return _err("Account not found.", 404)
    if not row.get("password_hash") or not check_password_hash(
            row["password_hash"], current):
        return _err("Your current password is not correct.", 401)
    cur.execute(
        "UPDATE Users SET password_hash = %s WHERE id = %s",
        (generate_password_hash(new), session["user_id"]),
    )
    db.commit()
    return _ok({})


@api_v1.route("/me/privacy", methods=["PUT"])
@user_required
def update_privacy():
    """Web POST /settings/privacy (auth.py:814):
    receive_email_notifications, receive_whatsapp_notifications
    (columns on Users)."""
    data = request.get_json(silent=True) or {}
    updates = {}
    if "receive_email_notifications" in data:
        updates["receive_email_notifications"] = bool(
            data["receive_email_notifications"])
    if "receive_whatsapp_notifications" in data:
        updates["receive_whatsapp_notifications"] = bool(
            data["receive_whatsapp_notifications"])
    if not updates:
        return _err("Nothing to update.")
    changed = _update_row("Users", "id = %s", (session["user_id"],), updates)
    if changed == 0:
        return _err("Privacy settings could not be saved.", 503)
    return _ok(updates)


@api_v1.route("/me", methods=["DELETE"])
@user_required
def delete_account():
    """Web POST /settings/delete-account (auth.py:830). Requires
    {"confirm": true} in the body. Local DB delete only — the Clerk
    cloud account unlink is a server-side TODO: the existing blueprint
    makes no Clerk Backend API calls (see §6.4), so do NOT add one
    here; the deploy checklist in README carries the TODO."""
    data = request.get_json(silent=True) or {}
    if not data.get("confirm"):
        return _err("Confirm account deletion with {\"confirm\": true}.")
    user_id = session["user_id"]
    db = get_db()
    cur = db.cursor()
    try:
        cur.execute("SELECT clerk_id FROM Users WHERE id = %s", (user_id,))
        row = cur.fetchone()
        clerk_id = (row or {}).get("clerk_id")
    except Exception:
        clerk_id = None
    _insert_row("DeletionAuditLog", {
        "user_id": user_id, "reason": "user requested account deletion",
    })
    # TODO (server-side, deploy): when clerk_id is present, delete the
    # Clerk cloud account via the Clerk Backend API with
    # CLERK_SECRET_KEY — deliberately not done in this blueprint.
    cur.execute("DELETE FROM Users WHERE id = %s", (user_id,))
    db.commit()
    session.pop("user_id", None)
    return _ok({"deleted": True, "had_clerk_id": bool(clerk_id),
                "clerk_unlink": "TODO server-side (see code comment)"})


@api_v1.route("/me/birthday", methods=["GET"])
@user_required
def get_birthday():
    """Web GET /auth/birthday (auth.py:385, birthday.html): date_of_birth
    (YYYY-MM-DD), last credit year. Cron daily-birthdays awards the
    200-pt bonus."""
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT date_of_birth FROM Users WHERE id = %s",
        (session["user_id"],),
    )
    row = cur.fetchone()
    if row is None:
        return _err("Account not found.", 404)
    dob = row.get("date_of_birth")
    last_credit_year = None
    try:
        if _has_column("Users", "birthday_bonus_last_year"):
            cur.execute(
                "SELECT birthday_bonus_last_year FROM Users WHERE id = %s",
                (session["user_id"],),
            )
            last_credit_year = cur.fetchone()["birthday_bonus_last_year"]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    return _ok({"date_of_birth": dob.isoformat() if hasattr(
        dob, "isoformat") else dob,
        "last_credit_year": last_credit_year})


@api_v1.route("/me/birthday", methods=["POST"])
@user_required
def post_birthday():
    """Web POST /auth/birthday (auth.py:385)."""
    data = request.get_json(silent=True) or {}
    dob_text = (data.get("date_of_birth") or "").strip()
    if not dob_text:
        return _err("Enter your date of birth (YYYY-MM-DD).")
    try:
        dob = datetime.strptime(dob_text, "%Y-%m-%d").date()
    except ValueError:
        return _err("Date of birth must be YYYY-MM-DD.")
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "UPDATE Users SET date_of_birth = %s WHERE id = %s",
        (dob, session["user_id"]),
    )
    db.commit()
    return _ok({"date_of_birth": dob_text})


@api_v1.route("/me/notifications/read", methods=["POST"])
@user_required
def mark_notifications_read():
    """Web POST /api/notifications/mark-read (api.py:65). Marks all,
    or the ids given in {"ids": [...]}, as read."""
    data = request.get_json(silent=True) or {}
    ids = data.get("ids") or data.get("notification_ids") or []
    db = get_db()
    cur = db.cursor()
    try:
        if _has_column("NotificationQueue", "is_read"):
            if ids:
                cur.execute(
                    "UPDATE NotificationQueue SET is_read = TRUE"
                    " WHERE user_id = %s AND id = ANY(%s)",
                    (session["user_id"], list(ids)),
                )
            else:
                cur.execute(
                    "UPDATE NotificationQueue SET is_read = TRUE"
                    " WHERE user_id = %s",
                    (session["user_id"],),
                )
        elif _has_column("NotificationQueue", "read_at"):
            if ids:
                cur.execute(
                    "UPDATE NotificationQueue SET read_at = NOW()"
                    " WHERE user_id = %s AND id = ANY(%s)",
                    (session["user_id"], list(ids)),
                )
            else:
                cur.execute(
                    "UPDATE NotificationQueue SET read_at = NOW()"
                    " WHERE user_id = %s",
                    (session["user_id"],),
                )
        else:
            return _ok({"marked_read": 0,
                        "note": "This NotificationQueue table has no"
                                " read flag."})
        db.commit()
        return _ok({"marked_read": cur.rowcount})
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        return _err("Notifications could not be marked read.", 503)


# ================================================================ admin

@api_v1.route("/admin/analytics", methods=["GET"])
def admin_analytics():
    """Web GET web-admin/analytics + /analytics/data +
    /api/analytics (admin.py:218,347,2163) and GET
    /api/admin/analytics/revenue (api.py:143): daily revenue from
    FinancialLedger, filters days / service / status. Churn: the web
    endpoint is a stub returning an empty list (api.py:235); this
    returns the real computed list only if _build_churn_users can be
    imported from the web admin module, else the same empty list."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    try:
        days = int(request.args.get("days") or 30)
    except ValueError:
        days = 30
    service = request.args.get("service") or ""
    status = request.args.get("status") or ""
    db = get_db()
    cur = db.cursor()
    revenue = []
    try:
        where = ["created_at >= NOW() - INTERVAL '%s days'" % days]
        params = []
        if service:
            where.append("service_requested = %s")
            params.append(service)
        if status:
            where.append("status = %s")
            params.append(status)
        cur.execute(
            "SELECT DATE(created_at) AS day,"
            " COALESCE(SUM(amount), 0) AS revenue, COUNT(*) AS orders"
            " FROM FinancialLedger WHERE %s"
            " GROUP BY DATE(created_at) ORDER BY day"
            % " AND ".join(where),
            params,
        )
        revenue = [_row_dict(r) for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    totals = {"revenue": sum(r.get("revenue") or 0 for r in revenue),
              "orders": sum(r.get("orders") or 0 for r in revenue)}
    churn_users, churn_note = [], None
    try:
        from app.blueprints.admin import _build_churn_users
        churn_users = _build_churn_users() or []
    except Exception:
        churn_users = []
        churn_note = ("Churn is a stub on the web (api.py:235 returns an"
                      " empty list); _build_churn_users could not be"
                      " imported here, so this returns the same empty list.")
    return _ok({"days": days, "service": service, "status": status,
                "daily_revenue": revenue, "totals": totals,
                "churn_users": churn_users, "churn_count": len(churn_users),
                "churn_note": churn_note})


@api_v1.route("/admin/financial-engine", methods=["GET"])
def admin_financial_engine():
    """Web GET web-admin/financial-engine (admin.py:1782)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    out = {}
    try:
        cur.execute(
            "SELECT COALESCE(SUM(amount), 0) AS total,"
            " COUNT(*) AS n FROM FinancialLedger")
        row = cur.fetchone()
        out["total_revenue"] = row["total"]
        out["ledger_entries"] = row["n"]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        out["total_revenue"] = 0
        out["ledger_entries"] = 0
    try:
        cur.execute(
            "SELECT COALESCE(SUM(amount), 0) AS total FROM FinancialLedger"
            " WHERE created_at >= DATE_TRUNC('month', CURRENT_DATE)")
        out["revenue_this_month"] = cur.fetchone()["total"]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        out["revenue_this_month"] = 0
    try:
        cur.execute(
            "SELECT service_requested, COALESCE(SUM(amount), 0) AS revenue,"
            " COUNT(*) AS orders FROM FinancialLedger"
            " GROUP BY service_requested ORDER BY revenue DESC LIMIT 10")
        out["by_service"] = [_row_dict(r) for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        out["by_service"] = []
    try:
        cur.execute(
            "SELECT COALESCE(SUM(wallet_balance), 0) AS total FROM Users")
        out["total_wallet_balances"] = cur.fetchone()["total"]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        out["total_wallet_balances"] = 0
    try:
        cur.execute(
            "SELECT action_type, COALESCE(SUM(amount), 0) AS total,"
            " COUNT(*) AS n FROM WalletTransactions GROUP BY action_type")
        out["wallet_by_action"] = [_row_dict(r) for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        out["wallet_by_action"] = []
    return _ok(out)


@api_v1.route("/admin/export/csv", methods=["GET"])
def admin_export_csv():
    """Web GET web-admin/export/csv (admin.py:473). kind=
    subscriptions (default) | customers | ledger."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    import csv
    import io
    kind = request.args.get("kind") or "subscriptions"
    db = get_db()
    cur = db.cursor()
    buf = io.StringIO()
    writer = csv.writer(buf)
    try:
        if kind == "customers":
            cur.execute("SELECT id, name, email, whatsapp_number,"
                        " wallet_balance, loyalty_points, created_at"
                        " FROM Users ORDER BY id")
            writer.writerow(["id", "name", "email", "whatsapp_number",
                             "wallet_balance", "loyalty_points",
                             "created_at"])
            for r in cur.fetchall():
                writer.writerow([r["id"], r["name"], r["email"],
                                 r["whatsapp_number"],
                                 r.get("wallet_balance"),
                                 r.get("loyalty_points"),
                                 r.get("created_at")])
        elif kind == "ledger":
            cur.execute("SELECT * FROM FinancialLedger ORDER BY id")
            rows = cur.fetchall()
            if rows:
                writer.writerow(list(dict(rows[0]).keys()))
                for r in rows:
                    writer.writerow(list(dict(r).values()))
        else:
            cur.execute("SELECT * FROM Subscriptions ORDER BY id")
            rows = cur.fetchall()
            if rows:
                writer.writerow(list(dict(rows[0]).keys()))
                for r in rows:
                    writer.writerow(list(dict(r).values()))
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    return Response(buf.getvalue(), mimetype="text/csv",
                    headers={"Content-Disposition":
                             "attachment; filename=premiumslots-%s.csv"
                             % kind})


@api_v1.route("/admin/report/pdf", methods=["GET"])
def admin_report_pdf():
    """Web GET web-admin/report/pdf (admin.py:617, fpdf2 KPI
    report). Equivalent KPI lines in PDF form."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    lines = ["PremiumSlots admin report",
             "Generated: %s" % datetime.utcnow().isoformat(), ""]
    queries = [
        ("Pending subscriptions",
         "SELECT COUNT(*) AS n FROM Subscriptions WHERE status = 'Pending'"),
        ("Approved subscriptions",
         "SELECT COUNT(*) AS n FROM Subscriptions WHERE status = 'Approved'"),
        ("Total users", "SELECT COUNT(*) AS n FROM Users"),
        ("Total revenue",
         "SELECT COALESCE(SUM(amount), 0) AS n FROM FinancialLedger"),
        ("Slots in rotation",
         "SELECT COALESCE(SUM(inventory_count), 0) AS n FROM Services"),
        ("Open tickets",
         "SELECT COUNT(*) AS n FROM SupportTickets WHERE status = 'open'"),
    ]
    for label, sql in queries:
        try:
            cur.execute(sql)
            lines.append("%s: %s" % (label, cur.fetchone()["n"]))
        except Exception:
            try:
                db.rollback()
            except Exception:
                pass
            lines.append("%s: unavailable" % label)
    pdf = _simple_pdf("PremiumSlots — Admin Report", lines)
    return Response(pdf, mimetype="application/pdf",
                    headers={"Content-Disposition":
                             "attachment; filename=premiumslots-report.pdf"})


# ---------------------------------------------------------------- admin subs

@api_v1.route("/admin/subscriptions/bulk-update", methods=["POST"])
def admin_subscriptions_bulk_update():
    """Web POST web-admin/subscription/bulk-update (admin.py:1148).
    Body: {"ids": [...], "status": "..."} and/or other subscription
    fields; only whitelisted columns are written."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    ids = data.get("ids") or []
    if not ids:
        return _err("Give the subscription ids to update.")
    allowed = {"status", "delivery_type", "account_group",
               "access_details", "review_requested", "issue_reported",
               "auto_renew"}
    updates = {k: v for k, v in data.items() if k in allowed}
    if not updates:
        return _err("Nothing to update.")
    cols = _table_columns("Subscriptions")
    updates = {k: v for k, v in updates.items() if k in cols}
    if not updates:
        return _err("Nothing to update.")
    db = get_db()
    cur = db.cursor()
    sets = ", ".join("%s = %%s" % k for k in updates.keys())
    try:
        cur.execute(
            "UPDATE Subscriptions SET %s WHERE id = ANY(%%s)" % sets,
            list(updates.values()) + [list(ids)],
        )
        db.commit()
        return _ok({"updated": cur.rowcount})
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        return _err("Bulk update failed.", 500)


@api_v1.route("/admin/subscriptions/<int:sub_id>", methods=["PUT"])
def admin_update_subscription(sub_id):
    """Web POST web-admin/subscription/edit (admin.py:1551)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    allowed = {"service_requested", "status", "delivery_type",
               "account_group", "access_details", "amount_due",
               "expiry_date", "mpesa_code", "vault_email",
               "vault_password", "review_requested", "issue_reported",
               "auto_renew", "locked_price"}
    updates = {k: v for k, v in data.items() if k in allowed}
    if not updates:
        return _err("Nothing to update.")
    changed = _update_row("Subscriptions", "id = %s", (sub_id,), updates)
    if changed == 0:
        return _err("Subscription not found.", 404)
    return _ok({})


@api_v1.route("/admin/subscriptions/<int:sub_id>/renew", methods=["POST"])
def admin_renew_subscription(sub_id):
    """Web POST web-admin/subscription/renew (admin.py:1569)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT * FROM Subscriptions WHERE id = %s", (sub_id,))
    row = cur.fetchone()
    if row is None:
        return _err("Subscription not found.", 404)
    try:
        from app.utils import calculate_subscription_expiry
        expiry = calculate_subscription_expiry(row.get("expiry_date"))
    except Exception:
        expiry = datetime.utcnow() + timedelta(days=30)
    cur.execute(
        "UPDATE Subscriptions SET status = 'Approved', expiry_date = %s"
        " WHERE id = %s",
        (expiry, sub_id),
    )
    db.commit()
    _log_order_event(sub_id, "renewed", "Renewed by admin.")
    return _ok({"status": "Approved",
                "expiry_date": expiry.isoformat() if hasattr(
                    expiry, "isoformat") else str(expiry)})


@api_v1.route("/admin/subscriptions/<int:sub_id>/cancel", methods=["POST"])
def admin_cancel_subscription(sub_id):
    """Web POST web-admin/subscription/cancel (admin.py:1667)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "UPDATE Subscriptions SET status = 'Cancelled' WHERE id = %s",
        (sub_id,),
    )
    if cur.rowcount == 0:
        return _err("Subscription not found.", 404)
    db.commit()
    _log_order_event(sub_id, "cancelled", "Cancelled by admin.")
    return _ok({"status": "Cancelled"})


@api_v1.route("/admin/subscriptions/<int:sub_id>", methods=["DELETE"])
def admin_delete_subscription(sub_id):
    """Web POST web-admin/delete/ (admin.py:1702). The row is
    archived to Archive_Subscriptions when that table exists, then
    deleted (so the recycle bin can restore it)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT * FROM Subscriptions WHERE id = %s", (sub_id,))
    row = cur.fetchone()
    if row is None:
        return _err("Subscription not found.", 404)
    _insert_row("Archive_Subscriptions", _row_dict(row))
    cur.execute("DELETE FROM Subscriptions WHERE id = %s", (sub_id,))
    db.commit()
    return _ok({})


@api_v1.route("/admin/subscriptions/<int:sub_id>/unhide", methods=["POST"])
def admin_unhide_subscription(sub_id):
    """Web POST web-admin/subscription/unhide (admin.py:1488):
    returns the vault credentials to the admin (never to a customer
    except through the one-time vault endpoint)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT vault_email, vault_password, access_details, account_group"
        " FROM Subscriptions WHERE id = %s",
        (sub_id,),
    )
    row = cur.fetchone()
    if row is None:
        return _err("Subscription not found.", 404)
    return _ok({"vault_email": row.get("vault_email"),
                "vault_password": row.get("vault_password"),
                "access_details": row.get("access_details"),
                "account_group": row.get("account_group")})


@api_v1.route("/admin/subscriptions/<int:sub_id>/remind-expiry",
              methods=["POST"])
def admin_remind_expiry(sub_id):
    """Web POST web-admin/subscription/remind-expiry
    (admin.py:1500): queues an expiry reminder notification for the
    subscription owner (email sending is the web's mail path; here the
    in-app notification is recorded and the email is best-effort)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT * FROM Subscriptions WHERE id = %s", (sub_id,))
    row = cur.fetchone()
    if row is None:
        return _err("Subscription not found.", 404)
    _notify_user(row.get("user_id"), "Your slot is about to expire",
                 "Your %s slot expires on %s. Renew it in the app."
                 % (row.get("service_requested"), row.get("expiry_date")),
                 kind="subscription")
    if row.get("email"):
        _send_account_email(
            row["email"], "Your PremiumSlots slot is about to expire",
            "Your %s slot expires on %s. Renew it in the app."
            % (row.get("service_requested"), row.get("expiry_date")))
    return _ok({})


# ---------------------------------------------------------------- admin customers

@api_v1.route("/admin/customers/<int:user_id>/toggle-emails",
              methods=["POST"])
def admin_toggle_emails(user_id):
    """Web POST web-admin/user/toggle_emails (admin.py:1283):
    flips receive_email_notifications."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT receive_email_notifications FROM Users WHERE id = %s",
        (user_id,),
    )
    row = cur.fetchone()
    if row is None:
        return _err("Customer not found.", 404)
    new_value = not bool(row.get("receive_email_notifications", True))
    _update_row("Users", "id = %s", (user_id,),
                {"receive_email_notifications": new_value})
    return _ok({"receive_email_notifications": new_value})


@api_v1.route("/admin/customers/<int:user_id>", methods=["DELETE"])
def admin_delete_customer(user_id):
    """Web POST web-admin/user/delete (admin.py:1299). Local DB
    delete only (row archived to Archive_Users when present).
    TODO (server-side, deploy): when the user has a clerk_id, delete
    the Clerk cloud account via the Clerk Backend API with
    CLERK_SECRET_KEY — deliberately not done in this blueprint (§6.4)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT * FROM Users WHERE id = %s", (user_id,))
    row = cur.fetchone()
    if row is None:
        return _err("Customer not found.", 404)
    _insert_row("Archive_Users", _row_dict(row))
    cur.execute("DELETE FROM Users WHERE id = %s", (user_id,))
    db.commit()
    return _ok({})


@api_v1.route("/admin/customers/<int:user_id>/adjust-wallet",
              methods=["POST"])
def admin_adjust_wallet(user_id):
    """Web POST web-admin/customer/adjust-wallet (admin.py:3381)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    try:
        amount = int(data.get("amount") or 0)
    except (TypeError, ValueError):
        return _err("Enter an amount.")
    if amount == 0:
        return _err("Enter a non-zero amount.")
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "UPDATE Users SET wallet_balance = wallet_balance + %s WHERE id = %s",
        (amount, user_id),
    )
    if cur.rowcount == 0:
        return _err("Customer not found.", 404)
    try:
        cur.execute(
            "INSERT INTO WalletTransactions (user_id, action_type, amount)"
            " VALUES (%s, 'adjust', %s)",
            (user_id, amount),
        )
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        cur.execute(
            "UPDATE Users SET wallet_balance = wallet_balance + %s"
            " WHERE id = %s",
            (amount, user_id),
        )
    db.commit()
    cur.execute("SELECT wallet_balance FROM Users WHERE id = %s", (user_id,))
    return _ok({"wallet_balance": cur.fetchone()["wallet_balance"]})


@api_v1.route("/admin/customers/<int:user_id>/adjust-points",
              methods=["POST"])
def admin_adjust_points(user_id):
    """Web POST web-admin/customer/adjust-points (admin.py:3461)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    try:
        amount = int(data.get("amount") or data.get("points") or 0)
    except (TypeError, ValueError):
        return _err("Enter a points amount.")
    if amount == 0:
        return _err("Enter a non-zero points amount.")
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "UPDATE Users SET loyalty_points = loyalty_points + %s WHERE id = %s",
        (amount, user_id),
    )
    if cur.rowcount == 0:
        return _err("Customer not found.", 404)
    _insert_row("LoyaltyLedger", {
        "user_id": user_id, "points": amount,
        "reason": data.get("reason") or "Admin adjustment",
    })
    db.commit()
    cur.execute("SELECT loyalty_points FROM Users WHERE id = %s", (user_id,))
    return _ok({"loyalty_points": cur.fetchone()["loyalty_points"]})


@api_v1.route("/admin/customers/<int:user_id>/reset-password",
              methods=["POST"])
def admin_reset_customer_password(user_id):
    """Web POST web-admin/customer/reset-password (admin.py:3495):
    sets a temporary password and returns it once to the admin (the
    web emails it; here it is returned in the response and optionally
    emailed best-effort)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    from werkzeug.security import generate_password_hash
    temp_password = secrets.token_urlsafe(10)
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "UPDATE Users SET password_hash = %s WHERE id = %s",
        (generate_password_hash(temp_password), user_id),
    )
    if cur.rowcount == 0:
        return _err("Customer not found.", 404)
    db.commit()
    cur.execute("SELECT email FROM Users WHERE id = %s", (user_id,))
    email = cur.fetchone()["email"]
    if email:
        _send_account_email(
            email, "Your PremiumSlots password was reset",
            "An admin reset your password. Your temporary password is:\n"
            "%s\n\nSign in and change it right away." % temp_password)
    return _ok({"temporary_password": temp_password})


@api_v1.route("/admin/customers/<int:user_id>/send-email",
              methods=["POST"])
def admin_send_customer_email(user_id):
    """Web POST web-admin/customer/send-email (admin.py:3545)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    subject = (data.get("subject") or "").strip()
    body = (data.get("body") or data.get("message") or "").strip()
    if not subject or not body:
        return _err("Subject and message are required.")
    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT email FROM Users WHERE id = %s", (user_id,))
    row = cur.fetchone()
    if row is None:
        return _err("Customer not found.", 404)
    _send_account_email(row["email"], subject, body)
    return _ok({"sent_to": row["email"]})


@api_v1.route("/admin/customers", methods=["POST"])
def admin_create_customer():
    """Web POST web-admin/customer/create (admin.py:3578):
    name/email/phone, temp password, initial wallet balance.
    TODO (server-side, deploy): provision a Clerk user (or link the
    existing Clerk user by email) via the Clerk Backend API with
    CLERK_SECRET_KEY — deliberately not done in this blueprint (§6.4)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    name = (data.get("name") or "").strip()
    email = (data.get("email") or "").strip().lower()
    phone = (data.get("phone") or data.get("whatsapp_number") or "").strip()
    if not name or not email or not phone:
        return _err("Name, email and phone are required.")
    from werkzeug.security import generate_password_hash
    temp_password = (data.get("password")
                     or secrets.token_urlsafe(10))
    try:
        wallet = int(data.get("wallet_balance") or data.get("initial_wallet") or 0)
    except (TypeError, ValueError):
        wallet = 0
    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT id FROM Users WHERE email = %s", (email,))
    if cur.fetchone() is not None:
        return _err("An account with that email already exists.", 409)
    cur.execute(
        "INSERT INTO Users (name, email, whatsapp_number, password_hash,"
        " is_verified, wallet_balance) VALUES (%s, %s, %s, %s, TRUE, %s)"
        " RETURNING id",
        (name, email, phone, generate_password_hash(temp_password), wallet),
    )
    user_id = cur.fetchone()["id"]
    db.commit()
    return _ok({"user_id": user_id,
                "temporary_password": temp_password,
                "clerk_provision": "TODO server-side (see code comment)"}, 201)


@api_v1.route("/admin/customers/export", methods=["GET"])
def admin_customers_export():
    """Web GET web-admin/customer/export (admin.py:3699)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    import csv
    import io
    db = get_db()
    cur = db.cursor()
    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(["id", "name", "email", "whatsapp_number",
                     "is_verified", "is_banned", "wallet_balance",
                     "loyalty_points", "referral_count", "created_at"])
    try:
        cur.execute(
            "SELECT id, name, email, whatsapp_number, is_verified,"
            " is_banned, wallet_balance, loyalty_points, referral_count,"
            " created_at FROM Users ORDER BY id")
        for r in cur.fetchall():
            writer.writerow([r["id"], r["name"], r["email"],
                             r["whatsapp_number"], r.get("is_verified"),
                             r.get("is_banned"), r.get("wallet_balance"),
                             r.get("loyalty_points"),
                             r.get("referral_count"), r.get("created_at")])
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    return Response(buf.getvalue(), mimetype="text/csv",
                    headers={"Content-Disposition":
                             "attachment; filename=premiumslots-customers.csv"})


@api_v1.route("/admin/customers/bulk-action", methods=["POST"])
def admin_customers_bulk_action():
    """Web POST web-admin/customer/bulk-action (admin.py:3777).
    Body: {"action": "ban"|"unban"|"delete"|"toggle_emails",
    "ids": [...]}."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    action = (data.get("action") or "").strip().lower()
    ids = data.get("ids") or []
    if action not in ("ban", "unban", "delete", "toggle_emails"):
        return _err("action must be ban, unban, delete or toggle_emails.")
    if not ids:
        return _err("Give the customer ids.")
    db = get_db()
    cur = db.cursor()
    try:
        if action == "ban":
            cur.execute("UPDATE Users SET is_banned = TRUE WHERE id = ANY(%s)",
                        (list(ids),))
        elif action == "unban":
            cur.execute("UPDATE Users SET is_banned = FALSE WHERE id = ANY(%s)",
                        (list(ids),))
        elif action == "toggle_emails":
            cur.execute(
                "UPDATE Users SET receive_email_notifications ="
                " NOT COALESCE(receive_email_notifications, TRUE)"
                " WHERE id = ANY(%s)",
                (list(ids),))
        else:
            cur.execute("SELECT * FROM Users WHERE id = ANY(%s)",
                        (list(ids),))
            for row in cur.fetchall():
                _insert_row("Archive_Users", _row_dict(row))
            cur.execute("DELETE FROM Users WHERE id = ANY(%s)", (list(ids),))
        db.commit()
        return _ok({"action": action, "affected": cur.rowcount})
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        return _err("Bulk action failed.", 500)

# ---------------------------------------------------------------- admin wallet

@api_v1.route("/admin/wallet", methods=["GET"])
def admin_wallet():
    """Web GET web-admin/wallet (admin.py:2666): pending wallet
    deposits (WalletTransactions action deposit, admin-approved)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    deposits = []
    try:
        cur.execute(
            "SELECT * FROM WalletTransactions WHERE action_type = 'deposit'"
            " ORDER BY id DESC LIMIT 200")
        deposits = [_row_dict(r) for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    pending = [d for d in deposits
               if (d.get("status") or "pending").lower() == "pending"]
    return _ok({"deposits": deposits, "pending": pending})


@api_v1.route("/admin/wallet/deposit/<int:deposit_id>/approve",
              methods=["POST"])
def admin_wallet_deposit_approve(deposit_id):
    """Web POST web-admin/wallet/deposit/approve (admin.py:2735):
    credits the user's balance."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT * FROM WalletTransactions WHERE id = %s", (deposit_id,))
    row = cur.fetchone()
    if row is None:
        return _err("Deposit not found.", 404)
    if (row.get("status") or "").lower() == "approved":
        return _err("This deposit is already approved.", 409)
    cur.execute(
        "UPDATE Users SET wallet_balance = wallet_balance + %s WHERE id = %s",
        (row.get("amount") or 0, row.get("user_id")),
    )
    _update_row("WalletTransactions", "id = %s", (deposit_id,),
                {"status": "approved"})
    db.commit()
    return _ok({"status": "approved"})


@api_v1.route("/admin/wallet/deposit/<int:deposit_id>/reject",
              methods=["POST"])
def admin_wallet_deposit_reject(deposit_id):
    """Web POST web-admin/wallet/deposit/reject (admin.py:2825)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    changed = _update_row("WalletTransactions", "id = %s", (deposit_id,),
                          {"status": "rejected"})
    if changed == 0:
        # Fall back to a direct update when the column filter dropped it.
        db = get_db()
        cur = db.cursor()
        try:
            cur.execute(
                "UPDATE WalletTransactions SET status = 'rejected'"
                " WHERE id = %s",
                (deposit_id,),
            )
            db.commit()
            changed = cur.rowcount
        except Exception:
            try:
                db.rollback()
            except Exception:
                pass
    if changed == 0:
        return _err("Deposit not found.", 404)
    return _ok({"status": "rejected"})


@api_v1.route("/admin/wallet/adjust", methods=["POST"])
def admin_wallet_adjust():
    """Web POST web-admin/wallet/adjust (admin.py:2870).
    Body: {"user_id": ..., "amount": ...} (positive or negative)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    user_id = data.get("user_id")
    try:
        amount = int(data.get("amount") or 0)
    except (TypeError, ValueError):
        return _err("Enter an amount.")
    if user_id is None or amount == 0:
        return _err("A user id and a non-zero amount are required.")
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "UPDATE Users SET wallet_balance = wallet_balance + %s WHERE id = %s",
        (amount, user_id),
    )
    if cur.rowcount == 0:
        return _err("Customer not found.", 404)
    db.commit()
    cur.execute("SELECT wallet_balance FROM Users WHERE id = %s", (user_id,))
    return _ok({"wallet_balance": cur.fetchone()["wallet_balance"]})


# ---------------------------------------------------------------- admin gift cards

@api_v1.route("/admin/gift-cards", methods=["GET"])
def admin_gift_cards():
    """Web GET web-admin/gift-cards (admin.py:2358)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    try:
        cur.execute("SELECT * FROM GiftCards ORDER BY id DESC LIMIT 200")
        cards = [_row_dict(r) for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        cards = []
    return _ok({"gift_cards": cards,
                "enabled": _setting("is_gift_cards_enabled", "true")})


@api_v1.route("/admin/gift-cards/issue", methods=["POST"])
def admin_issue_gift_card():
    """Web POST .../gift-cards/issue (admin.py:2417)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    try:
        amount = int(data.get("amount") or 0)
    except (TypeError, ValueError):
        return _err("Enter an amount.")
    if amount <= 0:
        return _err("Enter an amount.")
    code = (data.get("code") or "PS-%s" % secrets.token_hex(4).upper())
    code = code.strip().upper()
    new_id = _insert_row("GiftCards", {
        "code": code, "amount": amount, "status": "active",
        "recipient_name": (data.get("recipient_name") or "").strip(),
        "recipient_email": (data.get("recipient_email") or "").strip(),
        "sender_name": "PremiumSlots",
        "message": data.get("message") or "",
        "theme_style": data.get("theme_style") or "",
    })
    if new_id is None:
        return _err("Gift cards could not be issued right now.", 503)
    return _ok({"gift_card_id": new_id, "code": code,
                "amount": amount}, 201)


@api_v1.route("/admin/gift-cards/resend", methods=["POST"])
def admin_resend_gift_card():
    """Web POST .../gift-cards/resend (admin.py:2481)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    code = (data.get("code") or "").strip().upper()
    if not code:
        return _err("A gift card code is required.")
    db = get_db()
    cur = db.cursor()
    cur.execute("SELECT * FROM GiftCards WHERE code = %s", (code,))
    row = cur.fetchone()
    if row is None:
        return _err("Gift card not found.", 404)
    recipient = row.get("recipient_email")
    if recipient:
        _send_account_email(
            recipient, "Your PremiumSlots gift card",
            "Your KES %s PremiumSlots gift card.\nCode: %s"
            % (row.get("amount"), code))
    return _ok({"resent_to": recipient})


@api_v1.route("/admin/gift-cards/approve", methods=["POST"])
def admin_approve_gift_card():
    """Web POST .../gift-cards/approve (admin.py:2519)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    code = (data.get("code") or "").strip().upper()
    gift_id = data.get("id")
    if gift_id is not None:
        changed = _update_row("GiftCards", "id = %s", (gift_id,),
                              {"status": "active"})
    elif code:
        changed = _update_row("GiftCards", "code = %s", (code,),
                              {"status": "active"})
    else:
        return _err("A gift card id or code is required.")
    if changed == 0:
        return _err("Gift card not found.", 404)
    return _ok({"status": "active"})


@api_v1.route("/admin/gift-cards/reject", methods=["POST"])
def admin_reject_gift_card():
    """Web POST .../gift-cards/reject (admin.py:2590)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    code = (data.get("code") or "").strip().upper()
    gift_id = data.get("id")
    if gift_id is not None:
        changed = _update_row("GiftCards", "id = %s", (gift_id,),
                              {"status": "rejected"})
    elif code:
        changed = _update_row("GiftCards", "code = %s", (code,),
                              {"status": "rejected"})
    else:
        return _err("A gift card id or code is required.")
    if changed == 0:
        return _err("Gift card not found.", 404)
    return _ok({"status": "rejected"})


@api_v1.route("/admin/settings/gift-cards", methods=["POST"])
def admin_settings_gift_cards():
    """Web POST web-admin/settings/gift-cards (admin.py:2636):
    feature toggle. Body: {"enabled": true|false}."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    enabled = data.get("enabled")
    if enabled is None:
        enabled = data.get("is_gift_cards_enabled")
    if enabled is None:
        return _err("Send {\"enabled\": true|false}.")
    _set_setting("is_gift_cards_enabled",
                 "true" if enabled else "false")
    return _ok({"enabled": bool(enabled)})


# ---------------------------------------------------------------- admin transactions

@api_v1.route("/admin/transactions", methods=["GET"])
def admin_transactions():
    """Web GET web-admin/transactions (admin.py:2282)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    txns = []
    try:
        cur.execute(
            "SELECT * FROM WalletTransactions ORDER BY id DESC LIMIT 200")
        txns = [_row_dict(r) for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    ledger = []
    try:
        cur.execute(
            "SELECT * FROM FinancialLedger ORDER BY id DESC LIMIT 200")
        ledger = [_row_dict(r) for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    return _ok({"transactions": txns, "ledger": ledger})


@api_v1.route("/admin/transactions/<int:txn_id>/verify", methods=["POST"])
def admin_verify_transaction(txn_id):
    """Web POST web-admin/transactions/verify (admin.py:2303)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    changed = _update_row("WalletTransactions", "id = %s", (txn_id,),
                          {"status": "verified"})
    if changed == 0:
        changed = _update_row("FinancialLedger", "id = %s", (txn_id,),
                              {"status": "verified"})
    if changed == 0:
        return _err("Transaction not found.", 404)
    return _ok({"status": "verified"})


# ---------------------------------------------------------------- admin payment methods

@api_v1.route("/admin/payment-methods", methods=["GET"])
def admin_payment_methods():
    """Web GET/POST web-admin/payment-methods (admin.py:2960)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    return _ok({
        "payment_gateway": _setting("payment_gateway", "mpesa"),
        "mpesa_paybill": _setting("mpesa_paybill",
                                  os.environ.get("MPESA_PAYBILL", "400200")),
        "mpesa_account": _setting("mpesa_account",
                                  os.environ.get("MPESA_ACCOUNT", "1192526")),
        "mpesa_phone": _setting("mpesa_phone",
                                os.environ.get("MPESA_NUMBER", "0734460218")),
        "intasend_enabled": bool(os.environ.get("INTASEND_PUBLISHABLE_KEY")),
    })


@api_v1.route("/admin/payment-methods", methods=["POST"])
def admin_update_payment_methods():
    """Web POST web-admin/payment-methods (admin.py:2960) +
    /payment-methods/quick-switch (admin.py:3110)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    for key in ("payment_gateway", "mpesa_paybill", "mpesa_account",
                "mpesa_phone"):
        if key in data:
            _set_setting(key, data[key])
    if "gateway" in data:
        _set_setting("payment_gateway", data["gateway"])
    return _ok({"payment_gateway": _setting("payment_gateway", "mpesa")})


@api_v1.route("/admin/settings/gateway", methods=["POST"])
def admin_settings_gateway():
    """Web POST web-admin/settings/gateway (admin.py:1098):
    mpesa vs stk/intasend. Body: {"gateway": "mpesa"|"stk"|"intasend"}."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    gateway = (data.get("gateway") or data.get("payment_gateway") or "").strip().lower()
    if gateway not in ("mpesa", "stk", "intasend"):
        return _err("gateway must be mpesa, stk or intasend.")
    _set_setting("payment_gateway", gateway)
    return _ok({"payment_gateway": gateway})


# ---------------------------------------------------------------- admin coupons

@api_v1.route("/admin/coupons", methods=["GET"])
def admin_coupons():
    """Web GET web-admin/coupons (coupons.py:72)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    try:
        cur.execute("SELECT * FROM Coupons ORDER BY id DESC")
        return _ok({"coupons": [_row_dict(r) for r in cur.fetchall()]})
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        return _ok({"coupons": []})


@api_v1.route("/admin/coupons", methods=["POST"])
def admin_create_coupon():
    """Web POST web-admin/coupons (coupons.py:72)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    code = (data.get("code") or "").strip().upper()
    if not code:
        return _err("A coupon code is required.")
    new_id = _insert_row("Coupons", {
        "code": code,
        "discount_type": data.get("discount_type") or "percent",
        "discount_value": data.get("discount_value") or data.get("value"),
        "value": data.get("discount_value") or data.get("value"),
        "discount": data.get("discount_value") or data.get("value"),
        "max_discount_amount": data.get("max_discount_amount"),
        "min_amount": data.get("min_amount"),
        "max_redemptions": data.get("max_redemptions"),
        "max_redemptions_per_user":
            data.get("max_redemptions_per_user"),
        "customer_type": data.get("customer_type"),
        "service_restriction": data.get("service_restriction"),
        "expires_at": data.get("expires_at") or data.get("expiry_date"),
        "expiry_date": data.get("expires_at") or data.get("expiry_date"),
        "is_active": bool(data.get("is_active", True)),
        "active": bool(data.get("is_active", True)),
    })
    if new_id is None:
        return _err("Coupons could not be created right now.", 503)
    return _ok({"coupon_id": new_id, "code": code}, 201)


@api_v1.route("/admin/coupons/<int:coupon_id>", methods=["PUT"])
def admin_update_coupon(coupon_id):
    guard = _admin_guard()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    changed = _update_row("Coupons", "id = %s", (coupon_id,), data)
    if changed == 0:
        return _err("Coupon not found.", 404)
    return _ok({})


@api_v1.route("/admin/coupons/<int:coupon_id>", methods=["DELETE"])
def admin_delete_coupon(coupon_id):
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    cur.execute("DELETE FROM Coupons WHERE id = %s", (coupon_id,))
    if cur.rowcount == 0:
        return _err("Coupon not found.", 404)
    db.commit()
    return _ok({})


@api_v1.route("/admin/coupons/<int:coupon_id>/redemptions", methods=["GET"])
def admin_coupon_redemptions(coupon_id):
    """Web GET /api/admin/coupons/<id>/redemptions (coupons.py:134)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    try:
        cur.execute(
            "SELECT * FROM CouponRedemptions WHERE coupon_id = %s"
            " ORDER BY id DESC",
            (coupon_id,),
        )
        return _ok({"redemptions": [_row_dict(r) for r in cur.fetchall()]})
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        return _ok({"redemptions": []})


@api_v1.route("/admin/coupons/blast", methods=["POST"])
def admin_coupon_blast():
    """Web POST web-admin/coupons/blast (coupons.py:154): email a
    coupon to customers. Body: {"code": ..., "user_ids": [...] (optional,
    all verified users when omitted), "subject": ..., "message": ...}.
    Emails are sent best-effort; the response reports how many were
    attempted, not a delivery guarantee."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    code = (data.get("code") or "").strip()
    if not code:
        return _err("A coupon code is required.")
    db = get_db()
    cur = db.cursor()
    ids = data.get("user_ids") or []
    try:
        if ids:
            cur.execute(
                "SELECT email FROM Users WHERE id = ANY(%s)"
                " AND is_verified = TRUE",
                (list(ids),),
            )
        else:
            cur.execute(
                "SELECT email FROM Users WHERE is_verified = TRUE")
        emails = [r["email"] for r in cur.fetchall() if r.get("email")]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        emails = []
    subject = data.get("subject") or "A PremiumSlots coupon for you"
    body = (data.get("message") or
            "Use coupon code %s on your next PremiumSlots slot." % code)
    for email in emails:
        _send_account_email(email, subject, body)
    return _ok({"code": code, "emailed": len(emails)})


# ---------------------------------------------------------------- admin blog/help

@api_v1.route("/admin/blog", methods=["GET"])
def admin_blog_list():
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    try:
        cur.execute("SELECT * FROM BlogPosts ORDER BY id DESC")
        return _ok({"posts": [_row_dict(r) for r in cur.fetchall()]})
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        return _ok({"posts": []})


@api_v1.route("/admin/blog", methods=["POST"])
def admin_create_blog():
    """Web GET/POST web-admin/blog/new (blog.py:61)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    title = (data.get("title") or "").strip()
    if not title:
        return _err("A title is required.")
    slug = (data.get("slug") or re.sub(r"[^a-z0-9]+", "-",
                                       title.lower()).strip("-"))
    new_id = _insert_row("BlogPosts", {
        "title": title, "slug": slug,
        "content": data.get("content") or "",
        "excerpt": data.get("excerpt") or "",
        "author": data.get("author") or "",
        "is_published": bool(data.get("is_published", True)),
        "published": bool(data.get("is_published", True)),
    })
    if new_id is None:
        return _err("Blog posts could not be created right now.", 503)
    return _ok({"post_id": new_id, "slug": slug}, 201)


@api_v1.route("/admin/blog/<int:post_id>", methods=["PUT"])
def admin_update_blog(post_id):
    """Web /blog/<id>/edit (blog.py:96)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    changed = _update_row("BlogPosts", "id = %s", (post_id,), data)
    if changed == 0:
        return _err("Blog post not found.", 404)
    return _ok({})


@api_v1.route("/admin/blog/<int:post_id>", methods=["DELETE"])
def admin_delete_blog(post_id):
    """Web POST web-admin/blog/<id>/delete (blog.py:136)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    cur.execute("DELETE FROM BlogPosts WHERE id = %s", (post_id,))
    if cur.rowcount == 0:
        return _err("Blog post not found.", 404)
    db.commit()
    return _ok({})


@api_v1.route("/admin/help", methods=["GET"])
def admin_help_list():
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    try:
        cur.execute("SELECT * FROM HelpArticles ORDER BY id")
        return _ok({"articles": [_row_dict(r) for r in cur.fetchall()]})
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        return _ok({"articles": []})


@api_v1.route("/admin/help", methods=["POST"])
def admin_create_help():
    """Web GET/POST web-admin/help/new (help.py:76)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    title = (data.get("title") or "").strip()
    if not title:
        return _err("A title is required.")
    slug = (data.get("slug") or re.sub(r"[^a-z0-9]+", "-",
                                       title.lower()).strip("-"))
    new_id = _insert_row("HelpArticles", {
        "title": title, "slug": slug,
        "content": data.get("content") or "",
        "category": data.get("category") or "",
        "is_published": bool(data.get("is_published", True)),
    })
    if new_id is None:
        return _err("Help articles could not be created right now.", 503)
    return _ok({"article_id": new_id, "slug": slug}, 201)


@api_v1.route("/admin/help/<int:article_id>", methods=["PUT"])
def admin_update_help(article_id):
    """Web /help/<id>/edit (help.py:112)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    changed = _update_row("HelpArticles", "id = %s", (article_id,), data)
    if changed == 0:
        return _err("Help article not found.", 404)
    return _ok({})


@api_v1.route("/admin/help/<int:article_id>", methods=["DELETE"])
def admin_delete_help(article_id):
    """Web POST web-admin/help/<id>/delete (help.py:147)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    cur.execute("DELETE FROM HelpArticles WHERE id = %s", (article_id,))
    if cur.rowcount == 0:
        return _err("Help article not found.", 404)
    db.commit()
    return _ok({})


# ---------------------------------------------------------------- admin tickets etc

@api_v1.route("/admin/tickets", methods=["GET"])
def admin_tickets():
    """Support tickets listed in the dashboard support section
    (admin_support_tickets.html)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    try:
        cur.execute("SELECT * FROM SupportTickets ORDER BY id DESC LIMIT 200")
        return _ok({"tickets": [_row_dict(r) for r in cur.fetchall()]})
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        return _ok({"tickets": []})


@api_v1.route("/admin/tickets/<int:ticket_id>/resolve", methods=["POST"])
def admin_resolve_ticket(ticket_id):
    """Web POST web-admin/ticket/resolve (admin.py:1177)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    changed = _update_row("SupportTickets", "id = %s", (ticket_id,),
                          {"status": "resolved"})
    if changed == 0:
        return _err("Ticket not found.", 404)
    return _ok({"status": "resolved"})


@api_v1.route("/admin/tickets/<int:ticket_id>/delete", methods=["POST"])
def admin_delete_ticket(ticket_id):
    """Web POST web-admin/ticket/delete (admin.py:1199)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    cur.execute("DELETE FROM SupportTickets WHERE id = %s", (ticket_id,))
    if cur.rowcount == 0:
        return _err("Ticket not found.", 404)
    db.commit()
    return _ok({})


@api_v1.route("/admin/waitlist/message", methods=["POST"])
def admin_waitlist_message():
    """Web POST web-admin/waitlist/message (admin.py:1118).
    Queues a notification for every waitlisted user for the given
    service (all services when omitted); email is best-effort."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    message = (data.get("message") or "").strip()
    service = (data.get("service_requested") or "").strip()
    if not message:
        return _err("Write the message first.")
    db = get_db()
    cur = db.cursor()
    try:
        if service:
            cur.execute(
                "SELECT DISTINCT user_id FROM Waitlist"
                " WHERE service_requested = %s",
                (service,),
            )
        else:
            cur.execute("SELECT DISTINCT user_id FROM Waitlist")
        user_ids = [r["user_id"] for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        user_ids = []
    for user_id in user_ids:
        _notify_user(user_id, "PremiumSlots waitlist update", message,
                     kind="system")
    return _ok({"messaged": len(user_ids)})


@api_v1.route("/admin/suggestions", methods=["GET"])
def admin_suggestions():
    """Suggested services list (admin_waitlist_suggestions.html)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    try:
        cur.execute(
            "SELECT service_name, email, COUNT(*) AS votes"
            " FROM SuggestedServices GROUP BY service_name, email"
            " ORDER BY votes DESC")
        return _ok({"suggestions": [_row_dict(r) for r in cur.fetchall()]})
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        return _ok({"suggestions": []})


@api_v1.route("/admin/suggestions/<suggestion_id>", methods=["DELETE"])
def admin_delete_suggestion(suggestion_id):
    """Web POST web-admin/suggestion/delete (admin.py:1211).
    SuggestedServices has no id column in ANALYSIS.md (service_name,
    email), so the id is treated as a service name first, then as a
    numeric id when the table has one."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "DELETE FROM SuggestedServices WHERE service_name = %s",
        (suggestion_id,),
    )
    if cur.rowcount == 0 and suggestion_id.isdigit():
        cur.execute(
            "DELETE FROM SuggestedServices WHERE id = %s",
            (int(suggestion_id),),
        )
    if cur.rowcount == 0:
        return _err("Suggestion not found.", 404)
    db.commit()
    return _ok({})


@api_v1.route("/admin/bulk-email", methods=["POST"])
def admin_bulk_email():
    """Web POST web-admin/bulk-email (admin.py:564). Body:
    {"subject": ..., "body": ..., "user_ids": [...] (optional, all
    users when omitted), "audience": "all"|"verified"|"active" }."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    subject = (data.get("subject") or "").strip()
    body = (data.get("body") or data.get("message") or "").strip()
    if not subject or not body:
        return _err("Subject and message are required.")
    db = get_db()
    cur = db.cursor()
    ids = data.get("user_ids") or []
    audience = (data.get("audience") or "all").lower()
    try:
        if ids:
            cur.execute("SELECT email FROM Users WHERE id = ANY(%s)",
                        (list(ids),))
        elif audience == "verified":
            cur.execute("SELECT email FROM Users WHERE is_verified = TRUE")
        else:
            cur.execute("SELECT email FROM Users")
        emails = [r["email"] for r in cur.fetchall() if r.get("email")]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        emails = []
    for email in emails:
        _send_account_email(email, subject, body)
    return _ok({"emailed": len(emails)})


@api_v1.route("/admin/broadcast", methods=["POST"])
def admin_broadcast():
    """Web POST web-admin/broadcast (admin.py:1075): queues a
    notification for every user (and stores the global alert when
    the body asks for it via {"global_alert": ...})."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    message = (data.get("message") or "").strip()
    title = (data.get("title") or "PremiumSlots update").strip()
    if not message:
        return _err("Write the broadcast message first.")
    if data.get("global_alert"):
        _set_setting("global_alert", data["global_alert"])
    db = get_db()
    cur = db.cursor()
    try:
        cur.execute("SELECT id FROM Users")
        user_ids = [r["id"] for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        user_ids = []
    for user_id in user_ids:
        _notify_user(user_id, title, message, kind="system")
    return _ok({"broadcast_to": len(user_ids)})


@api_v1.route("/admin/settings/promo-banner", methods=["POST"])
def admin_settings_promo_banner():
    """Web POST web-admin/settings/promo_banner (admin.py:2211).
    Body: {"text": ..., "enabled": ...} (any promo_banner_* keys are
    stored as Settings rows)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    if "text" in data:
        _set_setting("promo_banner_text", data["text"])
    if "enabled" in data:
        _set_setting("promo_banner_enabled",
                     "true" if data["enabled"] else "false")
    for key, value in data.items():
        if key.startswith("promo_banner"):
            _set_setting(key, value)
    return _ok({"promo_banner_text": _setting("promo_banner_text"),
                "promo_banner_enabled": _setting("promo_banner_enabled")})


# ---------------------------------------------------------------- admin security

@api_v1.route("/admin/security-logs", methods=["GET"])
def admin_security_logs():
    """Web GET web-admin/security-logs (admin.py:1852). The web
    security-log table is AuditLog (ANALYSIS.md §2); LoginActivity is
    the fallback when AuditLog is absent."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    table = "AuditLog" if _table_exists("AuditLog") else "LoginActivity"
    try:
        cur.execute("SELECT * FROM %s ORDER BY id DESC LIMIT 200" % table)
        return _ok({"logs": [_row_dict(r) for r in cur.fetchall()],
                    "source_table": table})
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        return _ok({"logs": [], "source_table": table})


@api_v1.route("/admin/security-logs/purge", methods=["POST"])
def admin_security_logs_purge():
    """Web POST .../security-logs/purge (admin.py:1962)."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    table = "AuditLog" if _table_exists("AuditLog") else "LoginActivity"
    try:
        cur.execute("DELETE FROM %s" % table)
        db.commit()
        return _ok({"purged": cur.rowcount, "source_table": table})
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        return _err("Security logs could not be purged.", 500)


@api_v1.route("/admin/security-logs/revoke/<int:log_id>", methods=["POST"])
def admin_security_logs_revoke(log_id):
    """Web POST .../security-logs/revoke/<log_id> (admin.py:1974):
    revokes the session the log entry refers to."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    try:
        cur.execute(
            "UPDATE LoginActivity SET revoked_at = NOW() WHERE id = %s",
            (log_id,),
        )
        if cur.rowcount:
            db.commit()
            return _ok({"revoked": True})
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    return _err("Log entry not found.", 404)


# ---------------------------------------------------------------- admin recycle/backup

@api_v1.route("/admin/recycle-bin", methods=["GET"])
def admin_recycle_bin():
    """Web GET web-admin/recycle-bin (admin.py:2226):
    Archive_Users / Archive_Subscriptions."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    db = get_db()
    cur = db.cursor()
    users, subs = [], []
    try:
        cur.execute("SELECT * FROM Archive_Users ORDER BY id DESC")
        users = [_row_dict(r) for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    try:
        cur.execute("SELECT * FROM Archive_Subscriptions ORDER BY id DESC")
        subs = [_row_dict(r) for r in cur.fetchall()]
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
    return _ok({"archived_users": users, "archived_subscriptions": subs})


@api_v1.route("/admin/recycle-bin/restore", methods=["POST"])
def admin_recycle_bin_restore():
    """Web POST web-admin/recycle-bin/restore (admin.py:2246).
    Body: {"kind": "user"|"subscription", "id": ...}. The archived row
    is re-inserted into the live table (only columns that exist) and
    removed from the archive."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    data = request.get_json(silent=True) or {}
    kind = (data.get("kind") or "").strip().lower()
    row_id = data.get("id")
    if kind not in ("user", "subscription") or row_id is None:
        return _err("Send {\"kind\": \"user\"|\"subscription\", \"id\": ...}.")
    archive_table = "Archive_Users" if kind == "user" else "Archive_Subscriptions"
    live_table = "Users" if kind == "user" else "Subscriptions"
    db = get_db()
    cur = db.cursor()
    try:
        cur.execute("SELECT * FROM %s WHERE id = %%s" % archive_table,
                    (row_id,))
        row = cur.fetchone()
    except Exception:
        try:
            db.rollback()
        except Exception:
            pass
        return _err("Recycle bin is not available.", 503)
    if row is None:
        return _err("Archived item not found.", 404)
    restored_id = _insert_row(live_table, _row_dict(row))
    if restored_id is None:
        return _err("That item could not be restored.", 500)
    cur.execute("DELETE FROM %s WHERE id = %%s" % archive_table, (row_id,))
    db.commit()
    return _ok({"restored_id": restored_id, "kind": kind})


@api_v1.route("/admin/backup/status", methods=["GET"])
def admin_backup_status():
    """Backup STATUS view only (deliberate scope, §6.4): DB tables +
    stats, as on the web backup page (admin.py:1985). No download,
    no upload, no restore — those stay web-only."""
    guard = _admin_guard()
    if guard is not None:
        return guard
    known = ["Users", "Services", "Subscriptions", "FinancialLedger",
             "WalletTransactions", "GiftCards", "Coupons", "Referrals",
             "SupportTickets", "BlogPosts", "HelpArticles",
             "WishlistItems", "RewardItems", "NotificationQueue"]
    db = get_db()
    cur = db.cursor()
    tables = []
    for table in known:
        count = None
        try:
            cur.execute("SELECT COUNT(*) AS n FROM %s" % table)
            count = cur.fetchone()["n"]
        except Exception:
            try:
                db.rollback()
            except Exception:
                pass
        tables.append({"table": table, "rows": count,
                       "exists": count is not None})
    return _ok({"tables": tables,
                "note": "Status only. Backup download/upload/restore stay"
                        " web-only by design."})
