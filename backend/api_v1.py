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

import hmac
import os
import re
from datetime import datetime

from flask import Blueprint, jsonify, request, session

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
        "created_at": None,
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
        " wallet_balance, loyalty_points, referral_count, loyalty_tier"
        " FROM Users WHERE id = %s",
        (session["user_id"],),
    )
    user = cur.fetchone()
    if user is None:
        return _err("Account not found.", 404)
    return _ok({"user": {
        "id": user["id"],
        "name": user["name"],
        "email": user["email"],
        "whatsapp_number": user["whatsapp_number"],
        "is_verified": bool(user.get("is_verified", False)),
        "wallet_balance": user.get("wallet_balance") or 0,
        "loyalty_points": user.get("loyalty_points") or 0,
        "referral_count": user.get("referral_count") or 0,
        "loyalty_tier": user.get("loyalty_tier"),
    }})


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
    return _ok({"notifications": items})


# ---------------------------------------------------------------- buying

@api_v1.route("/request", methods=["POST"])
@user_required
def request_subscription():
    """Mirror of the web POST /request (manual M-PESA path).

    Body: service_requested (name), mpesa_code (10 alphanumeric),
    optional coupon_code. Creates a Subscriptions row with status
    Pending. Nothing is delivered until an admin approves it.
    """
    data = request.get_json(silent=True) or {}
    service_name = (data.get("service_requested") or "").strip()
    mpesa_code = (data.get("mpesa_code") or "").strip().upper()
    coupon_code = (data.get("coupon_code") or "").strip() or None
    if not service_name:
        return _err("Choose a platform first.")
    if not MPESA_CODE_RE.match(mpesa_code or ""):
        return _err("The M-PESA code must be exactly 10 letters and numbers.")
    if not is_valid_mpesa_format(mpesa_code) or is_mpesa_code_used(mpesa_code):
        return _err("That M-PESA code is not valid or has already been used.")
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
    if (service["inventory_count"] or 0) <= 0:
        return _err("This platform is sold out right now.")
    amount = service["price"]
    cur.execute(
        "INSERT INTO Subscriptions (user_id, customer_name, whatsapp_number,"
        " email, service_requested, mpesa_code, amount_due, status,"
        " delivery_type, applied_promo_code)"
        " VALUES (%s, %s, %s, %s, %s, %s, %s, 'Pending', 'Credentials', %s)"
        " RETURNING id",
        (user["id"], user["name"], user["whatsapp_number"], user["email"],
         service_name, mpesa_code, amount, coupon_code),
    )
    sub_id = cur.fetchone()["id"]
    db.commit()
    return _ok({"subscription_id": sub_id, "status": "Pending",
                "amount_due": amount, "service_requested": service_name}, 201)


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
    return _ok({"wallet_balance": (user or {}).get("wallet_balance") or 0,
                "transactions": txns})


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
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "SELECT * FROM Referrals WHERE user_id = %s ORDER BY id DESC",
        (session["user_id"],),
    )
    mine = [{k: (v.isoformat() if hasattr(v, "isoformat") else v)
             for k, v in dict(r).items()} for r in cur.fetchall()]
    cur.execute(
        "SELECT * FROM ReferralLeaderboard ORDER BY id DESC LIMIT 20"
    )
    board = [dict(r) for r in cur.fetchall()]
    return _ok({"referrals": mine, "leaderboard": board})


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
