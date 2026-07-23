import json
import logging
import os
import uuid
from functools import wraps
from pathlib import Path

from flask import Flask, g, jsonify, request, send_from_directory
from flask_cors import CORS
from itsdangerous import BadSignature, SignatureExpired, URLSafeTimedSerializer
from werkzeug.utils import secure_filename

import database as db
from config import (
    ALLOWED_EXTENSIONS,
    BASE_DIR,
    FLASK_SECRET_KEY,
    MAX_CONTENT_LENGTH,
    OPENAI_API_KEY,
    UPLOAD_DIR,
)
from invoice_extractor import extract_invoice_fields

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("delivery_api")

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
app = Flask(__name__)
app.config["SECRET_KEY"] = FLASK_SECRET_KEY
app.config["MAX_CONTENT_LENGTH"] = MAX_CONTENT_LENGTH

# يسمح للواجهة (driver.html / restaurant.html) بالاتصال بالسيرفر دون قيود CORS
CORS(app)

token_serializer = URLSafeTimedSerializer(FLASK_SECRET_KEY, salt="driver-auth")
TOKEN_MAX_AGE_SECONDS = 60 * 60 * 24 * 7  # 7 days


def allowed_file(filename: str) -> bool:
    return (
        "." in filename
        and filename.rsplit(".", 1)[1].lower() in ALLOWED_EXTENSIONS
    )


def row_to_dict(row) -> dict:
    return dict(row) if row is not None else {}


def error_response(message: str, status: int = 400, **extra):
    payload = {"success": False, "error": message, **extra}
    logger.warning("HTTP %s — %s", status, message)
    return jsonify(payload), status


def require_driver_token(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth = request.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            return error_response("Missing or invalid Authorization header", 401)
        token = auth[7:].strip()
        if not token:
            return error_response("Empty bearer token", 401)
        try:
            driver_id = token_serializer.loads(
                token, max_age=TOKEN_MAX_AGE_SECONDS
            )
        except SignatureExpired:
            return error_response("Token expired; please log in again", 401)
        except BadSignature:
            return error_response("Invalid token", 401)

        driver = db.find_driver_by_id(int(driver_id))
        if not driver:
            return error_response("Driver not found", 401)
        g.driver = driver
        return f(*args, **kwargs)

    return decorated


def create_driver_token(driver_id: int) -> str:
    return token_serializer.dumps(driver_id)


@app.before_request
def log_request():
    if request.path.startswith("/api/"):
        logger.info("%s %s", request.method, request.path)


_STATIC_DIR = str(BASE_DIR)


def _send_page(filename: str):
    path = BASE_DIR / filename
    if not path.is_file():
        logger.error("Missing page file: %s", path)
        return error_response(f"Page not found: {filename}", 404)
    return send_from_directory(_STATIC_DIR, filename)


@app.route("/")
@app.route("/driver")
@app.route("/driver.html")
def driver_page():
    return _send_page("driver.html")


@app.route("/restaurant")
@app.route("/restaurant.html")
def restaurant_page():
    return _send_page("restaurant.html")


@app.route("/api/health", methods=["GET"])
def health():
    return jsonify(
        {
            "success": True,
            "status": "ok",
            "openai_configured": bool(OPENAI_API_KEY),
        }
    )


@app.route("/api/config", methods=["GET"])
def api_config():
    """Helps the frontend discover the correct API base URL."""
    return jsonify(
        {
            "success": True,
            "api_base": request.host_url.rstrip("/"),
            "openai_configured": bool(OPENAI_API_KEY),
        }
    )


@app.route("/api/driver/login", methods=["POST"])
def driver_login():
    data = request.get_json(silent=True) or {}
    phone = (data.get("phone") or "").strip()
    password = data.get("password") or ""

    if not phone or not password:
        return error_response("phone and password are required")

    driver = db.find_driver_by_phone(phone)
    if not driver or not db.verify_driver_password(driver, password):
        logger.info("Failed login attempt for phone=%s", phone)
        return error_response("Invalid phone or password", 401)

    token = create_driver_token(driver["id"])
    logger.info("Driver logged in — id=%s name=%s", driver["id"], driver["name"])

    return jsonify(
        {
            "success": True,
            "token": token,
            "driver": {
                "id": driver["id"],
                "name": driver["name"],
                "phone": driver["phone"],
            },
        }
    )


@app.route("/api/driver/upload", methods=["POST"])
@require_driver_token
def driver_upload():
    if "image" not in request.files:
        return error_response("image file is required (multipart field: image)")

    file = request.files["image"]
    if not file or not file.filename:
        return error_response("No file selected")

    if not allowed_file(file.filename):
        return error_response(
            f"Unsupported file type. Allowed: {', '.join(sorted(ALLOWED_EXTENSIONS))}"
        )

    ext = file.filename.rsplit(".", 1)[1].lower()
    safe_name = secure_filename(file.filename)
    unique_name = f"{uuid.uuid4().hex}_{safe_name or 'invoice.' + ext}"
    save_path = UPLOAD_DIR / unique_name

    try:
        file.save(save_path)
        logger.info(
            "Invoice image saved — driver_id=%s path=%s",
            g.driver["id"],
            save_path.name,
        )

        fields = extract_invoice_fields(save_path)

        if not any(
            fields.get(k)
            for k in ("customer_name", "customer_phone", "invoice_number")
        ):
            return error_response(
                "Could not extract invoice data from the image", 422
            )

        order_id = db.insert_order(
            driver_id=g.driver["id"],
            customer_name=fields["customer_name"] or "Unknown",
            customer_phone=fields["customer_phone"] or "N/A",
            invoice_number=fields["invoice_number"] or f"INV-{uuid.uuid4().hex[:8].upper()}",
            image_path=str(save_path.relative_to(UPLOAD_DIR.parent)),
            status="pending",
        )

        logger.info(
            "Order created — id=%s driver_id=%s invoice=%s",
            order_id,
            g.driver["id"],
            fields["invoice_number"],
        )

        return jsonify(
            {
                "success": True,
                "order_id": order_id,
                "extracted": fields,
                "order": {
                    "id": order_id,
                    "customer_name": fields["customer_name"] or "Unknown",
                    "customer_phone": fields["customer_phone"] or "N/A",
                    "invoice_number": fields["invoice_number"]
                    or f"INV-{uuid.uuid4().hex[:8].upper()}",
                    "status": "pending",
                    "created_at": db.utc_now_iso(),
                },
                "message": "Invoice processed and order saved",
            }
        ), 201

    except json.JSONDecodeError:
        logger.exception("Failed to parse OpenAI JSON response")
        return error_response("تعذّر قراءة بيانات الفاتورة من رد الذكاء الاصطناعي", 502)
    except Exception as exc:
        logger.exception("Upload processing failed")
        if save_path.exists():
            try:
                save_path.unlink()
            except OSError:
                pass
        return error_response(f"فشل معالجة الفاتورة: {exc}", 500)


@app.route("/api/driver/orders", methods=["GET"])
@require_driver_token
def driver_orders():
    try:
        rows = db.list_orders_for_driver(g.driver["id"])
        orders = [row_to_dict(row) for row in rows]
        current = [o for o in orders if o.get("status") != "completed"]
        past = [o for o in orders if o.get("status") == "completed"]
        return jsonify(
            {
                "success": True,
                "current": current,
                "past": past,
                "orders": orders,
            }
        )
    except Exception as exc:
        logger.exception("Failed to fetch driver orders")
        return error_response(f"Failed to fetch orders: {exc}", 500)


@app.route("/api/order/complete/<int:order_id>", methods=["POST"])
@require_driver_token
def complete_order(order_id: int):
    try:
        order = db.get_order_by_id(order_id)
        if not order:
            return error_response("Order not found", 404)

        if order["driver_id"] != g.driver["id"]:
            return error_response("Not allowed to update this order", 403)

        if order["status"] == "completed":
            logger.info("Order %s already completed", order_id)
            return jsonify(
                {
                    "success": True,
                    "order_id": order_id,
                    "status": "completed",
                    "message": "Order was already marked as completed",
                }
            )

        if not db.update_order_status(order_id, "completed"):
            return error_response("Failed to update order status", 500)

        logger.info("Order %s marked as completed", order_id)
        return jsonify(
            {
                "success": True,
                "order_id": order_id,
                "status": "completed",
                "message": "Order status updated to completed",
            }
        )
    except Exception as exc:
        logger.exception("Failed to complete order %s", order_id)
        return error_response(f"Failed to complete order: {exc}", 500)


@app.route("/api/restaurant/orders", methods=["GET"])
def restaurant_orders():
    try:
        rows = db.list_orders_with_drivers()
        orders = []
        for row in rows:
            item = row_to_dict(row)
            orders.append(
                {
                    "id": item["id"],
                    "driver_id": item["driver_id"],
                    "driver_name": item["driver_name"],
                    "driver_phone": item["driver_phone"],
                    "customer_name": item["customer_name"],
                    "customer_phone": item["customer_phone"],
                    "invoice_number": item["invoice_number"],
                    "status": item["status"],
                    "image_path": item.get("image_path"),
                    "created_at": item["created_at"],
                }
            )
        logger.info("Restaurant dashboard fetched %s order(s)", len(orders))
        return jsonify({"success": True, "count": len(orders), "orders": orders})
    except Exception as exc:
        logger.exception("Failed to fetch orders")
        return error_response(f"Failed to fetch orders: {exc}", 500)


@app.errorhandler(413)
def request_entity_too_large(_):
    return error_response("File too large (max 16 MB)", 413)


def bootstrap():
    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    try:
        db.init_db()
        db.ensure_demo_driver()
    except Exception as e:
        logger.error(f"Bootstrap db error: {e}")
    logger.info("Upload directory: %s", UPLOAD_DIR)

# لا تستدعي bootstrap() بشكل عام هنا!
@app.route('/api/items', methods=['GET'])
def get_items():
    try:
        with db.db_cursor() as cursor:
            cursor.execute("SELECT * FROM items")
            items = [dict(row) for row in cursor.fetchall()]
            return jsonify(items)
except Exception as e:
    logger.error(f"Error fetching items: {str(e)}")
    return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    port = int(os.getenv("PORT", "5050"))
    logger.info("Driver app:     http://127.0.0.1:%s/", port)
    logger.info("Restaurant app: http://127.0.0.1:%s/restaurant.html", port)
    app.run(host="0.0.0.0", port=port, debug=os.getenv("FLASK_DEBUG") == "1")
    if __name__ == "__main__":
    bootstrap()  # 👈 إضافة الاستدعاء هنا
    port = int(os.getenv("PORT", "5050"))
    # ... باقي الكود كما هو
