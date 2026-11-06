"""hajimi connection monitor.

Shows every client that has connected to the hajimi server: IP address,
approximate location (from Vercel geo headers), and device model.

Data source (first match wins):
  1. DATABASE_URL environment variable (Postgres, e.g. the Neon database used on Vercel)
  2. DATABASE_URL in ../server/.env.local (written by `vercel env pull`)
  3. The local development SQLite file ../server/data/hajimi.sqlite
"""

import hmac
import os
import sqlite3
from datetime import datetime, timedelta, timezone
from pathlib import Path

from flask import Flask, Response, jsonify, render_template, request

ROOT = Path(__file__).resolve().parent.parent
SERVER_ENV = ROOT / "server" / ".env.local"
SQLITE_PATH = ROOT / "server" / "data" / "hajimi.sqlite"
ONLINE_WINDOW = timedelta(minutes=5)

COLUMNS = [
    "client_id", "ip", "city", "region", "country", "latitude", "longitude",
    "device_model", "os_version", "app_version", "user_agent", "last_path",
    "request_count", "first_seen", "last_seen",
]
QUERY = f"SELECT {', '.join(COLUMNS)} FROM client_connections ORDER BY last_seen DESC LIMIT 1000"

# Apple hardware identifiers -> marketing names (common recent devices).
DEVICE_NAMES = {
    "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max",
    "iPhone12,8": "iPhone SE (2nd gen)",
    "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12", "iPhone13,3": "iPhone 12 Pro",
    "iPhone13,4": "iPhone 12 Pro Max",
    "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13", "iPhone14,2": "iPhone 13 Pro",
    "iPhone14,3": "iPhone 13 Pro Max", "iPhone14,6": "iPhone SE (3rd gen)",
    "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus", "iPhone15,2": "iPhone 14 Pro",
    "iPhone15,3": "iPhone 14 Pro Max",
    "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus", "iPhone16,1": "iPhone 15 Pro",
    "iPhone16,2": "iPhone 15 Pro Max",
    "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus", "iPhone17,1": "iPhone 16 Pro",
    "iPhone17,2": "iPhone 16 Pro Max", "iPhone17,5": "iPhone 16e",
    "iPhone18,3": "iPhone 17", "iPhone18,1": "iPhone 17 Pro", "iPhone18,2": "iPhone 17 Pro Max",
    "iPhone18,4": "iPhone Air",
    "arm64": "Mac / Simulator", "x86_64": "Simulator (Intel)",
}

app = Flask(__name__)


@app.before_request
def require_password():
    """HTTP Basic Auth. MONITOR_PASSWORD is required when deployed (fail closed)."""
    password = os.environ.get("MONITOR_PASSWORD")
    if not password:
        if os.environ.get("VERCEL"):
            return Response("MONITOR_PASSWORD is not configured", 503)
        return None  # local development on 127.0.0.1
    auth = request.authorization
    user_ok = auth and hmac.compare_digest(auth.username or "", os.environ.get("MONITOR_USER", "admin"))
    pass_ok = auth and hmac.compare_digest(auth.password or "", password)
    if user_ok and pass_ok:
        return None
    return Response("Login required", 401, {"WWW-Authenticate": 'Basic realm="hajimi monitor"'})


def database_url():
    url = os.environ.get("DATABASE_URL") or os.environ.get("POSTGRES_URL")
    if url:
        return url
    if SERVER_ENV.exists():
        for line in SERVER_ENV.read_text().splitlines():
            key, sep, value = line.partition("=")
            if sep and key.strip() in ("DATABASE_URL", "POSTGRES_URL"):
                return value.strip().strip('"').strip("'")
    return None


def fetch_rows():
    url = database_url()
    if url and url.startswith(("postgres://", "postgresql://")):
        import psycopg2

        conn = psycopg2.connect(url, connect_timeout=10)
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT to_regclass('client_connections')")
                if cur.fetchone()[0] is None:
                    return [], "Postgres (table not created yet)"
                cur.execute(QUERY)
                return [dict(zip(COLUMNS, row)) for row in cur.fetchall()], "Postgres"
        finally:
            conn.close()

    if not SQLITE_PATH.exists():
        return [], "no database found"
    conn = sqlite3.connect(SQLITE_PATH)
    try:
        rows = conn.execute(QUERY).fetchall()
    except sqlite3.OperationalError as exc:
        if "no such table" not in str(exc):
            raise
        rows = []  # table not created yet: the server has not been started with the new code
    finally:
        conn.close()
    return [dict(zip(COLUMNS, row)) for row in rows], "SQLite"


def as_datetime(value):
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if isinstance(value, str):
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    return None


def present(row, now):
    last_seen = as_datetime(row["last_seen"])
    first_seen = as_datetime(row["first_seen"])
    place = ", ".join(p for p in (row["city"], row["region"], row["country"]) if p)
    model = row["device_model"]
    device = None
    if model:
        base, simulator = model, model.endswith(" (Simulator)")
        if simulator:
            base = model[: -len(" (Simulator)")]
        name = DEVICE_NAMES.get(base)
        device = f"{name} ({model})" if name else model
    return {
        **row,
        "location": place or "Unknown",
        "device": device or "Unknown (not the iOS app)",
        "online": bool(last_seen and now - last_seen <= ONLINE_WINDOW),
        "first_seen": first_seen.isoformat() if first_seen else None,
        "last_seen": last_seen.isoformat() if last_seen else None,
        "last_seen_text": last_seen.astimezone().strftime("%Y-%m-%d %H:%M:%S") if last_seen else "",
    }


def load():
    rows, source = fetch_rows()
    now = datetime.now(timezone.utc)
    return [present(r, now) for r in rows], source


@app.route("/")
def index():
    error = None
    try:
        clients, source = load()
    except Exception as exc:  # show database problems on the page instead of a 500
        clients, source, error = [], "error", str(exc)
    online = sum(1 for c in clients if c["online"])
    return render_template(
        "index.html", clients=clients, source=source, error=error,
        online=online, total=len(clients),
    )


@app.route("/api/connections")
def api_connections():
    clients, source = load()
    return jsonify({"source": source, "clients": clients})


if __name__ == "__main__":
    # Bound to localhost: this page lists users' IPs and locations, keep it private.
    app.run(host="127.0.0.1", port=int(os.environ.get("PORT", 5050)), debug=False)
