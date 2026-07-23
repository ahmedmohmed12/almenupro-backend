import logging
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone

from werkzeug.security import check_password_hash, generate_password_hash

from config import DATABASE_PATH

logger = logging.getLogger(__name__)


def get_connection() -> sqlite3.Connection:
    conn = sqlite3.connect(DATABASE_PATH, check_same_thread=False, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn

@contextmanager
def db_cursor():
    conn = get_connection()
    cursor = conn.cursor()
    try:
        yield cursor
        conn.commit()
    except Exception as e:
        conn.rollback()
        raise e
    finally:
        cursor.close()
        conn.close()  # 👈 يضمن إغلاق الاتصال دائماً بعد كل طلب


def init_db() -> None:
    with db_cursor() as cur:
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
            "CREATE INDEX IF NOT EXISTS idx_orders_driver_id ON orders (driver_id)"
        )
        cur.execute(
            "CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders (created_at DESC)"
        )
    logger.info("Database initialized at %s", DATABASE_PATH)


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def find_driver_by_phone(phone: str) -> sqlite3.Row | None:
    with db_cursor() as cur:
        cur.execute("SELECT * FROM drivers WHERE phone = ?", (phone.strip(),))
        return cur.fetchone()


def find_driver_by_id(driver_id: int) -> sqlite3.Row | None:
    with db_cursor() as cur:
        cur.execute("SELECT id, name, phone FROM drivers WHERE id = ?", (driver_id,))
        return cur.fetchone()


def verify_driver_password(driver: sqlite3.Row, password: str) -> bool:
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
        return cur.lastrowid


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
        return cur.lastrowid


DEMO_DRIVER_NAME = "سائق تجريبي"
DEMO_DRIVER_PHONE = "012345"
DEMO_DRIVER_PASSWORD = "123456"


def ensure_demo_driver() -> int | None:
    """Create the default test driver on first run if the phone is not taken."""
    existing = find_driver_by_phone(DEMO_DRIVER_PHONE)
    if existing:
        logger.debug(
            "Demo driver already exists — phone=%s id=%s",
            DEMO_DRIVER_PHONE,
            existing["id"],
        )
        return existing["id"]
    driver_id = create_driver(DEMO_DRIVER_NAME, DEMO_DRIVER_PHONE, DEMO_DRIVER_PASSWORD)
    logger.info(
        "Demo driver created — id=%s phone=%s password=%s",
        driver_id,
        DEMO_DRIVER_PHONE,
        DEMO_DRIVER_PASSWORD,
    )
    return driver_id


def get_order_by_id(order_id: int) -> sqlite3.Row | None:
    with db_cursor() as cur:
        cur.execute("SELECT * FROM orders WHERE id = ?", (order_id,))
        return cur.fetchone()


def update_order_status(order_id: int, status: str) -> bool:
    with db_cursor() as cur:
        cur.execute(
            "UPDATE orders SET status = ? WHERE id = ?",
            (status.strip(), order_id),
        )
        return cur.rowcount > 0


def list_orders_for_driver(driver_id: int) -> list[sqlite3.Row]:
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
        return cur.fetchall()


def list_orders_with_drivers() -> list[sqlite3.Row]:
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
        return cur.fetchall()
