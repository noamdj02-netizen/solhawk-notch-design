"""Faux serveur pour essayer SolHawk Notch SANS le VPS. Données inventées, jeton jetable, écoute 127.0.0.1 uniquement.
Usage: python3 tools/mock_feed.py [port]   (jeton: dev-notch-mock)  — après 25 s, un nouveau token « NEWB » apparaît."""
import json, sys, time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer

TOKEN = "dev-notch-mock"
T0 = time.time()
G = {"mint": "green", "freeze": "green", "dev": "green", "volume": "green", "holders": "green"}

import math

# Cours inventés qui bougent dans le temps (réservés à ce faux serveur), pour voir vivre la simulation et les robots.
def eyes(t): return 8200 * (1 + 0.25 * math.sin(t / 50) + 0.002 * t)
def wave(t): return 6100 * (1 + 0.8 * min(t, 60) / 60 - 0.45 * max(0, min(t - 60, 60)) / 60 + 0.05 * math.sin(t / 7))
def newb(t): return 5400 * (1 + 0.012 * max(0, t - 25) + 0.08 * math.sin(t / 9))
def dump(t): return 9000 * (1 + 0.1 * math.sin(t / 5)) * (0.45 if t > 90 else 1)

def spark(fn, t, born):
    pts = [t - k * 15 for k in range(11, -1, -1) if t - k * 15 >= born]
    return [[round(x - born), round(fn(x))] for x in pts]

def items():
    t = time.time() - T0
    out = [
        {"mint": "DemoEyes11111111111111111111111111111111111", "symbol": "EYES", "name": "Pulse Eyes", "age_s": 142 + int(t), "market_cap": round(eyes(t)), "real_sol": 5.2, "risk": {"score": 12, "label": "faible"}, "lights": G, "series": spark(eyes, t, -142), "image_url": "https://tracker.example.com/eyes.png"},
        {"mint": "DemoWave11111111111111111111111111111111111", "symbol": "WAVE", "name": "Wave", "age_s": 61 + int(t), "market_cap": round(wave(t)), "real_sol": 3.4, "risk": {"score": 40, "label": "moyen"}, "lights": {**G, "holders": "orange", "dev": None}, "series": spark(wave, t, -61)},
    ]
    if t < 150:
        out.append({"mint": "DemoDump11111111111111111111111111111111111", "symbol": "DUMP", "name": "Dumpy", "age_s": 20 + int(t), "market_cap": round(dump(t)), "real_sol": 4.0, "risk": {"score": 8, "label": "faible"}, "lights": G, "series": spark(dump, t, -20)})
    if t > 25:
        out.insert(0, {"mint": "6zuDiAw3NviBwcLZfTztHJgtCmeNWfyFxYVoXtNYpump", "symbol": "NEWB", "name": "Newbie", "age_s": int(t - 25) + 9, "market_cap": round(newb(t)), "real_sol": 3.1, "risk": {"score": 10, "label": "faible"}, "lights": G, "series": spark(newb, t, 25) if t > 40 else [], "image_url": "https://images.pump.fun/coin-image/6zuDiAw3NviBwcLZfTztHJgtCmeNWfyFxYVoXtNYpump?imageSize=128x128"})
    return out

# ---- terminal (données inventées) ----
from urllib.parse import urlsplit, parse_qs
NEWB_MINT = "6zuDiAw3NviBwcLZfTztHJgtCmeNWfyFxYVoXtNYpump"
def soon1(t): return 52000 * (1 + 0.15 * math.sin(t / 30) + 0.001 * t)
def mig1(t): return 410000 * (1 + 0.08 * math.sin(t / 45))
def run1(t): return 88000 * (1 + 0.004 * t + 0.06 * math.sin(t / 6))
FNS = {NEWB_MINT: newb, "DemoEyes11111111111111111111111111111111111": eyes, "DemoWave11111111111111111111111111111111111": wave, "DemoDump11111111111111111111111111111111111": dump, "DemoSoon11111111111111111111111111111111111": soon1, "DemoMoon11111111111111111111111111111111111": mig1, "DemoRocket111111111111111111111111111111111": run1}

def col(items):
    return {"updated_at": datetime.now(timezone.utc).isoformat(), "stats": {}, "items": items, "sol_usd": 150.0}

def live():
    t = time.time() - T0
    soon = [{"mint": "DemoSoon11111111111111111111111111111111111", "symbol": "LUNA2", "name": "Luna Two", "age_s": 900 + int(t), "market_cap": round(soon1(t)), "real_sol": 62.0, "risk": {"score": 15, "label": "faible"}, "lights": G}]
    mig = [{"mint": "DemoMoon11111111111111111111111111111111111", "symbol": "MOON", "name": "Moonish", "age_s": 5400 + int(t), "market_cap": round(mig1(t)), "real_sol": 85.0, "risk": {"score": 20, "label": "faible"}, "lights": G}]
    runs = {"items": [{"mint": "DemoRocket111111111111111111111111111111111", "symbol": "ROCKET", "name": "Rocket", "gain_pct": 34.0, "sol_in": 6.2, "mc_at_detect": 80000, "mc_now": round(run1(t)), "since_detect_pct": round((run1(t) / 80000 - 1) * 100, 1), "age_s": 120 + int(t)}],
            "rule": "+20 % en 60 s · ≥ 3 SOL nets entrés", "note": "Détecté après le début du run (données de démonstration)."}
    return {"new": col(items()), "soon": col(soon), "migrated": col(mig), "runs": runs, "observe_only": True}

def screen(mint, interval):
    fn = FNS.get(mint, eyes)
    now = time.time(); t = now - T0
    candles = []
    for k in range(119, -1, -1):
        a = t - (k + 1) * interval; b = t - k * interval
        xs = [fn(a + (b - a) * j / 6) * (1 + 0.012 * math.sin((a + j) * 1.7)) for j in range(7)]
        candles.append({"t": round(now - k * interval - interval), "o": round(xs[0]), "h": round(max(xs)), "l": round(min(xs)), "c": round(xs[-1]),
                        "flow_sol": round((xs[-1] - xs[0]) / max(xs[0], 1) * 20, 3), "n": 7})
    def ema(vals, n):
        out, cur = [], None
        for i, v in enumerate(vals):
            if i + 1 < n: out.append(None); continue
            cur = sum(vals[:n]) / n if cur is None else v * 2 / (n + 1) + cur * (1 - 2 / (n + 1))
            out.append(cur)
        return out
    closes = [c["c"] for c in candles]
    return {"mint": mint, "chart": {"candles": candles, "ema9": ema(closes, 9), "ema21": ema(closes, 21), "interval_s": interval,
                                    "note": "Bougies du market cap (DONNÉES DE DÉMONSTRATION)."},
            "quote": {"market_cap": closes[-1], "source": "demo"}, "n_samples": 600, "warming": False, "observe_only": True}

def card(mint):
    return {"mint": mint, "authorities": {"mint": "renounced", "freeze": "renounced"}, "dev_pct": 3.2, "top10_pct": 21.5, "holders": 742,
            "age_s": 1800, "market_cap": None, "liquidity_usd": 54000,
            "socials": [{"kind": "twitter", "url": "https://x.com/example"}, {"kind": "telegram", "url": "https://t.me/example"}, {"kind": "website", "url": "https://example.com"}],
            "sources": ["démonstration"], "read_at": datetime.now(timezone.utc).isoformat(), "observe_only": True}

# wallets inventés (adresses factices de 44 caractères)
WALLETS = [
    {"address": "Fake1111111111111111111111111111111111111Aa", "label": "Trader Lune", "emoji": "🌙", "category": "trader", "elite": True, "influence": 3, "recent": [{"mint": "6zuDiAw3NviBwcLZfTztHJgtCmeNWfyFxYVoXtNYpump", "side": "BUY", "block_time": int(time.time()) - 60}]},
    {"address": "Fake2222222222222222222222222222222222222Bb", "label": "Dev Shiba", "emoji": "", "category": "dev", "elite": True, "influence": 2, "recent": []},
    {"address": "Fake3333333333333333333333333333333333333Cc", "label": "Baleine", "emoji": "🐋", "category": "trader", "elite": True, "influence": 2, "recent": [{"mint": "DemoEyes11111111111111111111111111111111111", "side": "RECEIVED", "block_time": int(time.time()) - 400}]},
    {"address": "Fake4444444444444444444444444444444444444Dd", "label": "BINANCE", "emoji": "", "category": "exchange", "elite": False, "influence": 0, "recent": []},
]

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send_json(self, obj):
        body = json.dumps(obj).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)

    def do_GET(self):
        if self.headers.get("X-SolHawk-Token") != TOKEN:
            self.send_response(401); self.end_headers(); return
        u = urlsplit(self.path); q = parse_qs(u.query)
        if u.path == "/api/companion/live":
            return self.send_json(live())
        if u.path == "/api/companion/screen":
            return self.send_json(screen(q.get("mint", [""])[0], int(q.get("interval", ["5"])[0])))
        if u.path.startswith("/api/companion/token/"):
            return self.send_json(card(u.path.rsplit("/", 1)[-1]))
        if self.path == "/api/companion/tracked-wallets":
            return self.send_json({"registry": {"count": len(WALLETS), "elite": 3}, "wallets": WALLETS, "observe_only": True})
        if self.path.startswith("/api/companion/tracked-wallets/"):
            return self.send_json({"activity": {"status": "OK", "tx_read": 30, "label": "2 wallet(s) suivi(s) dans les 30 dernières transactions réussies",
                                                "wallets": [{**WALLETS[0], "buys": 2, "sells": 0, "received": 0, "sent": 0, "last_block_time": int(time.time()) - 40},
                                                            {**WALLETS[2], "buys": 0, "sells": 0, "received": 1, "sent": 0, "last_block_time": int(time.time()) - 300}]}, "observe_only": True})
        if self.path != "/api/companion/feed":
            self.send_response(404); self.end_headers(); return
        body = json.dumps({"updated_at": datetime.now(timezone.utc).isoformat(), "observe_only": True,
                           "stats": {"seen": 120, "dropped": 292, "listed": len(items()), "watching": 40, "profile": "wide", "drops": {"dev_spam": 83, "no_traction": 197, "dumped": 12}, "rpc": {"ok": 120, "errors": 0, "no_rpc": 0, "last_error": None}, "ghost": {"tracked": 14, "no_price": 0}},
                           "items": items(), "sol_usd": 150.0, "note": "Score de risque = heuristique non calibrée, pas une probabilité de rug."}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)

HTTPServer(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 8799), H).serve_forever()
