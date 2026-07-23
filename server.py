"""
تشغيل التطبيق: python server.py
"""

import os
import socket
import sys
import webbrowser
from pathlib import Path

from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent
DEFAULT_PORT = 5050

load_dotenv(ROOT / ".env")


def ensure_venv() -> None:
    venv_python = ROOT / ".venv" / "Scripts" / "python.exe"
    if venv_python.is_file():
        return
    print("Creating virtual environment (.venv)...")
    import subprocess

    subprocess.check_call([sys.executable, "-m", "venv", str(ROOT / ".venv")])
    subprocess.check_call(
        [str(venv_python), "-m", "pip", "install", "-q", "-r", str(ROOT / "requirements.txt")]
    )


def pick_port(preferred: int) -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        try:
            sock.bind(("127.0.0.1", preferred))
            return preferred
        except OSError:
            pass
    for port in range(preferred + 1, preferred + 20):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            try:
                sock.bind(("127.0.0.1", port))
                print("Port %s busy — using %s" % (preferred, port))
                return port
            except OSError:
                continue
    raise RuntimeError("No free port found")


def main() -> None:
    if not (ROOT / ".venv" / "Scripts" / "python.exe").is_file():
        try:
            ensure_venv()
        except Exception as exc:
            print("venv setup failed:", exc)
            sys.exit(1)

    os.chdir(ROOT)
    load_dotenv(ROOT / ".env", override=True)

    preferred = int(os.getenv("PORT", str(DEFAULT_PORT)))
    port = pick_port(preferred)
    os.environ["PORT"] = str(port)

    from app import app, bootstrap, logger  # noqa: WPS433
    from config import OPENAI_API_KEY

    print("OpenAI Key Status:", "Loaded" if OPENAI_API_KEY else "Empty")

    base = f"http://127.0.0.1:{port}"
    (ROOT / ".port").write_text(str(port), encoding="utf-8")

    print()
    print("Driver:     %s/" % base)
    print("Restaurant: %s/restaurant.html" % base)
    print("Complete:   POST %s/api/order/complete/<order_id>" % base)
    print("Login:      012345 / 123456")
    print()

    logger.info("Driver:     %s/", base)
    logger.info("Restaurant: %s/restaurant.html", base)

    if os.getenv("OPEN_BROWSER", "1") == "1":
        webbrowser.open(f"{base}/")

    bootstrap()
    app.run(host="127.0.0.1", port=port, debug=os.getenv("FLASK_DEBUG") == "1", use_reloader=os.getenv("FLASK_RELOADER") == "1")


if __name__ == "__main__":
    main()
