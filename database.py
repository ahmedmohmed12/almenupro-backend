import logging
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from typing import Any

from werkzeug.security import check_password_hash, generate_password_hash

from config import DATABASE_PATH

logger = logging.getLogger(__name__)

_schema_initialized = False


def _ensure_schema() -> None:
    """Lazy init for serverless: runs once per instance on first DB access."""
    global _schema_initialized
    if _schema_initialized:
        return
    _schema_initialized = True
    init_db()
    ensure_demo_driver()


def _row_to_dict(row: sqlite3.Row | None) -> dict[str, Any] | None:
    return dict(row) if row is not None else None


def _rows_to_dicts(rows: list[sqlite3.Row]) -> list[dict[str, Any]]:
    return [dict(row) for row in rows]


def get_connection() -> sqlite3.Connection:
    """Internal only — use db_cursor() for all queries."""
    conn = sqlite3.connect(DATABASE_PATH, check_same_thread=False, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


@contextmanager
def db_cursor():
    """Single entry point for SQLite access (safe for serverless/Vercel)."""
    _ensure_schema()
    conn = get_connection()
    try:
        cursor = conn.cursor()
        yield cursor
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        try:
            conn.close()
        except Exception:
            pass


def init_db() -> None:
    conn = get_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS drivers (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                phone TEXT NOT NULL UNIQUE,
                password TEXT NOT NULL
            )
            """
        )
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS orders (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                driver_id INTEGER NOT NULL,
                customer_name TEXT NOT NULL,
                customer_phone TEXT NOT NULL,
                invoice_number TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'pending',
                image_path TEXT,
                created_at TEXT NOT NULL,
                FOREIGN KEY (driver_id) REFERENCES drivers (id)
            )
            """
        )
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS items (
                id INTEGER PRIMARY KEY,
                category_id INTEGER NOT NULL DEFAULT 1,
                category_name TEXT NOT NULL DEFAULT 'عام',
                name TEXT NOT NULL,
                description TEXT NOT NULL DEFAULT '',
                price REAL NOT NULL DEFAULT 0,
                image_url TEXT NOT NULL DEFAULT '',
                is_available INTEGER NOT NULL DEFAULT 1,
                talabat_id TEXT,
                source TEXT NOT NULL DEFAULT 'Talabat'
            )
            """
        )
        cur.execute(
            "CREATE INDEX IF NOT EXISTS idx_orders_driver_id ON orders (driver_id)"
        )
        cur.execute(
            "CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders (created_at DESC)"
        )
        cur.execute(
            "CREATE INDEX IF NOT EXISTS idx_items_category ON items (category_name)"
        )
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
    logger.info("Database initialized at %s", DATABASE_PATH)


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def find_driver_by_phone(phone: str) -> dict[str, Any] | None:
    with db_cursor() as cur:
        cur.execute("SELECT * FROM drivers WHERE phone = ?", (phone.strip(),))
        return _row_to_dict(cur.fetchone())


def find_driver_by_id(driver_id: int) -> dict[str, Any] | None:
    with db_cursor() as cur:
        cur.execute(
            "SELECT id, name, phone FROM drivers WHERE id = ?", (driver_id,)
        )
        return _row_to_dict(cur.fetchone())


def verify_driver_password(driver: dict[str, Any] | sqlite3.Row, password: str) -> bool:
    stored = driver["password"]
    if stored.startswith("pbkdf2:") or stored.startswith("scrypt:"):
        return check_password_hash(stored, password)
    return stored == password


def create_driver(name: str, phone: str, password: str) -> int:
    hashed = generate_password_hash(password)
    with db_cursor() as cur:
        cur.execute(
            "INSERT INTO drivers (name, phone, password) VALUES (?, ?, ?)",
            (name.strip(), phone.strip(), hashed),
        )
        return int(cur.lastrowid)


def insert_order(
    driver_id: int,
    customer_name: str,
    customer_phone: str,
    invoice_number: str,
    image_path: str | None = None,
    status: str = "pending",
) -> int:
    with db_cursor() as cur:
        cur.execute(
            """
            INSERT INTO orders (
                driver_id, customer_name, customer_phone,
                invoice_number, status, image_path, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                driver_id,
                customer_name.strip(),
                customer_phone.strip(),
                invoice_number.strip(),
                status,
                image_path,
                utc_now_iso(),
            ),
        )
        return int(cur.lastrowid)


DEMO_DRIVER_NAME = "سائق تجريبي"
DEMO_DRIVER_PHONE = "012345"
DEMO_DRIVER_PASSWORD = "123456"


def ensure_demo_driver() -> int | None:
    existing = find_driver_by_phone(DEMO_DRIVER_PHONE)
    if existing:
        logger.debug(
            "Demo driver already exists — phone=%s id=%s",
            DEMO_DRIVER_PHONE,
            existing["id"],
        )
        return int(existing["id"])
    driver_id = create_driver(DEMO_DRIVER_NAME, DEMO_DRIVER_PHONE, DEMO_DRIVER_PASSWORD)
    logger.info(
        "Demo driver created — id=%s phone=%s password=%s",
        driver_id,
        DEMO_DRIVER_PHONE,
        DEMO_DRIVER_PASSWORD,
    )
    return driver_id


def get_order_by_id(order_id: int) -> dict[str, Any] | None:
    with db_cursor() as cur:
        cur.execute("SELECT * FROM orders WHERE id = ?", (order_id,))
        return _row_to_dict(cur.fetchone())


def update_order_status(order_id: int, status: str) -> bool:
    with db_cursor() as cur:
        cur.execute(
            "UPDATE orders SET status = ? WHERE id = ?",
            (status.strip(), order_id),
        )
        return cur.rowcount > 0


def list_orders_for_driver(driver_id: int) -> list[dict[str, Any]]:
    with db_cursor() as cur:
        cur.execute(
            """
            SELECT
                id, driver_id, customer_name, customer_phone,
                invoice_number, status, image_path, created_at
            FROM orders
            WHERE driver_id = ?
            ORDER BY created_at DESC
            """,
            (driver_id,),
        )
        return _rows_to_dicts(cur.fetchall())


def list_orders_with_drivers() -> list[dict[str, Any]]:
    with db_cursor() as cur:
        cur.execute(
            """
            SELECT
                o.id,
                o.driver_id,
                o.customer_name,
                o.customer_phone,
                o.invoice_number,
                o.status,
                o.image_path,
                o.created_at,
                d.name AS driver_name,
                d.phone AS driver_phone
            FROM orders o
            INNER JOIN drivers d ON d.id = o.driver_id
            ORDER BY o.created_at DESC
            """
        )
        return _rows_to_dicts(cur.fetchall())


def list_items() -> list[dict[str, Any]]:
    with db_cursor() as cur:
        cur.execute(
            """
            SELECT
                id, category_id, category_name, name, description,
                price, image_url, is_available, talabat_id, source
            FROM items
            ORDER BY category_name, name
            """
        )
        return _rows_to_dicts(cur.fetchall())


def count_items() -> int:
    with db_cursor() as cur:
        cur.execute("SELECT COUNT(*) AS c FROM items")
        row = cur.fetchone()
        return int(row["c"]) if row else 0


def _category_id_for(cur: sqlite3.Cursor, category_name: str, cache: dict[str, int]) -> int:
    key = (category_name or "عام").strip() or "عام"
    if key in cache:
        return cache[key]
    cur.execute(
        "SELECT DISTINCT category_id FROM items WHERE category_name = ? LIMIT 1",
        (key,),
    )
    row = cur.fetchone()
    if row:
        cache[key] = int(row["category_id"])
        return cache[key]
    next_id = (max(cache.values()) if cache else 0) + 1
    cache[key] = next_id
    return next_id


def _normalize_item(raw: dict[str, Any], index: int, category_cache: dict[str, int], cur: sqlite3.Cursor) -> dict[str, Any] | None:
    category_name = (
        raw.get("category_name") or raw.get("categoryName") or raw.get("category") or "عام"
    )
    category_name = str(category_name).strip() or "عام"
    name = str(raw.get("name") or "").strip()
    if not name:
        return None

    talabat_id = raw.get("talabat_id") if raw.get("talabat_id") is not None else raw.get("talabatId")
    talabat_key = str(talabat_id) if talabat_id is not None else None

    is_available = raw.get("is_available", raw.get("isAvailable", 1))
    if is_available in (0, False, "0"):
        available = 0
    else:
        available = 1

    item_id = raw.get("id")
    if item_id is None:
        item_id = talabat_id if talabat_id is not None else index + 1

    return {
        "id": int(item_id),
        "category_id": int(
            raw.get("category_id") or raw.get("categoryId") or _category_id_for(cur, category_name, category_cache)
        ),
        "category_name": category_name,
        "name": name,
        "description": str(raw.get("description") or ""),
        "price": float(raw.get("price") or 0),
        "image_url": str(raw.get("image_url") or raw.get("imageUrl") or ""),
        "is_available": available,
        "talabat_id": talabat_key,
        "source": str(raw.get("source") or "Talabat"),
    }


def sync_menu_items(incoming: list[dict[str, Any]]) -> dict[str, Any]:
    """Merge incoming menu items into SQLite (almenupro /api/items/sync)."""
    with db_cursor() as cur:
        cur.execute(
            """
            SELECT
                id, category_id, category_name, name, description,
                price, image_url, is_available, talabat_id, source
            FROM items
            """
        )
        existing_rows = _rows_to_dicts(cur.fetchall())

        by_talabat: dict[str, dict[str, Any]] = {}
        by_id: dict[str, dict[str, Any]] = {}
        by_name: dict[str, dict[str, Any]] = {}
        category_cache: dict[str, int] = {}

        for item in existing_rows:
            category_cache[item["category_name"]] = int(item["category_id"])
            by_id[str(item["id"])] = item
            by_name[item["name"].lower()] = item
            if item.get("talabat_id"):
                by_talabat[str(item["talabat_id"])] = item

        merged = list(existing_rows)

        for index, raw in enumerate(incoming):
            if not isinstance(raw, dict):
                continue
            normalized = _normalize_item(raw, index, category_cache, cur)
            if not normalized:
                continue

            talabat_key = normalized.get("talabat_id")
            existing_item = (
                by_talabat.get(str(talabat_key)) if talabat_key else None
            ) or by_id.get(str(normalized["id"])) or by_name.get(normalized["name"].lower())

            if existing_item:
                existing_item.update(normalized)
                existing_item["id"] = existing_item["id"]
                target = existing_item
            else:
                merged.append(normalized)
                target = normalized
                by_id[str(target["id"])] = target
                by_name[target["name"].lower()] = target
                if talabat_key:
                    by_talabat[str(talabat_key)] = target

        cur.execute("DELETE FROM items")
        for item in merged:
            if not str(item.get("name", "")).strip():
                continue
            cur.execute(
                """
                INSERT INTO items (
                    id, category_id, category_name, name, description,
                    price, image_url, is_available, talabat_id, source
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    int(item["id"]),
                    int(item["category_id"]),
                    item["category_name"],
                    item["name"],
                    item.get("description", ""),
                    float(item.get("price") or 0),
                    item.get("image_url", ""),
                    int(item.get("is_available", 1)),
                    item.get("talabat_id"),
                    item.get("source", "Talabat"),
                ),
            )

        return {"total": len(merged), "synced": len(incoming)}
