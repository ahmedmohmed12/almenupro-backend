"""Create the demo driver manually (same credentials as app startup)."""

import logging
import sys

import database as db

logging.basicConfig(level=logging.INFO, format="%(levelname)s | %(message)s")
logger = logging.getLogger(__name__)


def main() -> None:
    db.init_db()
    driver_id = db.ensure_demo_driver()
    if driver_id:
        logger.info(
            "Ready — phone=%s password=%s",
            db.DEMO_DRIVER_PHONE,
            db.DEMO_DRIVER_PASSWORD,
        )


if __name__ == "__main__":
    main()
    sys.exit(0)
