import os
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent
load_dotenv(BASE_DIR / ".env")

# Key: set in .env (recommended) or replace the fallback below
OPENAI_API_KEY = (
    os.getenv("OPENAI_API_KEY", "").strip() or "sk-proj-your_actual_key_here"
)

# Vercel: use /tmp (writable, ephemeral). Local: project folder.
_on_vercel = bool(os.getenv("VERCEL"))
_default_db = "/tmp/database.db" if _on_vercel else str(BASE_DIR / "database.db")
_default_upload = "/tmp/uploads" if _on_vercel else str(BASE_DIR / "uploads")
DATABASE_PATH = os.getenv("DATABASE_PATH", _default_db)
UPLOAD_DIR = Path(os.getenv("UPLOAD_DIR", _default_upload))
FLASK_SECRET_KEY = os.getenv("FLASK_SECRET_KEY", "dev-change-in-production")
MAX_CONTENT_LENGTH = 16 * 1024 * 1024  # 16 MB
ALLOWED_EXTENSIONS = {"png", "jpg", "jpeg", "webp", "gif"}
