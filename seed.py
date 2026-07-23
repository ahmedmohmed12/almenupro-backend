"""Seed SQLite with demo driver and sample restaurant menu items."""

import logging
import sys
from typing import Any

import database as db

logging.basicConfig(level=logging.INFO, format="%(levelname)s | %(message)s")
logger = logging.getLogger(__name__)

SAMPLE_MENU_ITEMS: list[dict[str, Any]] = [
    {
        "id": 101,
        "category_id": 1,
        "category_name": "مقبلات",
        "name": "حمص بالطحينة",
        "description": "حمص طازج مع طحينة وزيت زيتون",
        "price": 18.0,
        "is_available": 1,
        "source": "seed",
    },
    {
        "id": 102,
        "category_id": 1,
        "category_name": "مقبلات",
        "name": "سلطة فتوش",
        "description": "خضار موسمية مع خبز محمص ودبس رمان",
        "price": 22.0,
        "is_available": 1,
        "source": "seed",
    },
    {
        "id": 103,
        "category_id": 1,
        "category_name": "مقبلات",
        "name": "أصابع موزاريلا",
        "description": "موزارella مقرمشة مع صوص مارينارا",
        "price": 28.0,
        "is_available": 1,
        "source": "seed",
    },
    {
        "id": 201,
        "category_id": 2,
        "category_name": "أطباق رئيسية",
        "name": "برجر لحم كلاسيك",
        "description": "200غ لحم، جبنة شيدر، خس، طماطم",
        "price": 45.0,
        "is_available": 1,
        "source": "seed",
    },
    {
        "id": 202,
        "category_id": 2,
        "category_name": "أطباق رئيسية",
        "name": "دجاج مشوي",
        "description": "نصف دجاجة مشوية مع أرز وسلطة",
        "price": 52.0,
        "is_available": 1,
        "source": "seed",
    },
    {
        "id": 203,
        "category_id": 2,
        "category_name": "أطباق رئيسية",
        "name": "باستا Alfredo",
        "description": "معكرونة fettuccine بصوص كريمة وفطر",
        "price": 48.0,
        "is_available": 1,
        "source": "seed",
    },
    {
        "id": 301,
        "category_id": 3,
        "category_name": "مشروبات",
        "name": "عصير برتقال طازج",
        "description": "350 مل",
        "price": 15.0,
        "is_available": 1,
        "source": "seed",
    },
    {
        "id": 302,
        "category_id": 3,
        "category_name": "مشروبات",
        "name": "ماء معدني",
        "description": "500 مل",
        "price": 5.0,
        "is_available": 1,
        "source": "seed",
    },
    {
        "id": 303,
        "category_id": 3,
        "category_name": "مشروبات",
        "name": "قهوة أمريكano",
        "description": "قهوة سوداء",
        "price": 12.0,
        "is_available": 1,
        "source": "seed",
    },
    {
        "id": 401,
        "category_id": 4,
        "category_name": "حلويات",
        "name": "كنافة نابلسية",
        "description": "تقدّم ساخنة مع قطر",
        "price": 25.0,
        "is_available": 1,
        "source": "seed",
    },
    {
        "id": 402,
        "category_id": 4,
        "category_name": "حلويات",
        "name": "تشيز كيك",
        "description": "قطعة تشيز كيك كلاسيكية",
        "price": 22.0,
        "is_available": 1,
        "source": "seed",
    },
]


def seed_database() -> dict[str, Any]:
    """
    Create tables, ensure demo driver, and insert sample menu items if missing.
    Safe to run multiple times (idempotent).
    """
    db.init_db()
    driver_id = db.ensure_demo_driver()
    menu_stats = db.seed_items_if_missing(SAMPLE_MENU_ITEMS)

    result = {
        "success": True,
        "message": "Database seeded successfully",
        "driver": {
            "id": driver_id,
            "phone": db.DEMO_DRIVER_PHONE,
            "password": db.DEMO_DRIVER_PASSWORD,
            "created_or_existing": bool(driver_id),
        },
        "menu": menu_stats,
    }
    logger.info(
        "Seed complete — driver_id=%s items_inserted=%s items_total=%s",
        driver_id,
        menu_stats["items_inserted"],
        menu_stats["items_total"],
    )
    return result


def main() -> None:
    result = seed_database()
    logger.info(
        "Ready — phone=%s password=%s | menu items: %s total",
        db.DEMO_DRIVER_PHONE,
        db.DEMO_DRIVER_PASSWORD,
        result["menu"]["items_total"],
    )


if __name__ == "__main__":
    main()
    sys.exit(0)
