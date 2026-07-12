#!/usr/bin/env python3
"""wifi-portal backend — piccolo server HTTP (solo stdlib) per il setup WiFi.

Serve la pagina wifi-setup.html ed espone poche API che pilotano nmcli:
  GET  /                 -> pagina interattiva (lista + password + connetti)
  GET  /api/status       -> {connectivity, active_ssid, hotspot}
  GET  /api/scan         -> [{ssid, signal, security, in_use}]
  POST /api/connect      -> {ssid, password}  =>  {ok, message}

Astrazione chiave: TUTTI i comandi passano da self.nmcli(...), che esegue il
binario indicato dall'env NMCLI (default: "nmcli"). In locale lo puntiamo al mock
(wifi-portal/mock/nmcli); sul Pi resta il vero nmcli. Stesso codice ovunque.

Bind di default su 0.0.0.0 cosi' la STESSA istanza serve sia lo schermo del Pi
(via 127.0.0.1) sia il telefono connesso all'hotspot (via IP dell'AP).
"""
import json
import os
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NMCLI = os.environ.get("NMCLI", "nmcli")
HERE = os.path.dirname(os.path.abspath(__file__))
PORT = int(os.environ.get("PORT", os.environ.get("PORTAL_PORT", "8080")))
HOST = os.environ.get("HOST", os.environ.get("PORTAL_HOST", "0.0.0.0"))
# Credenziali dell'hotspot di setup: servono alla pagina per costruire il QR di
# auto-join. Non sono la password di una WiFi reale (vedi portal.conf).
HOTSPOT_SSID = os.environ.get("HOTSPOT_SSID", "pikiosk-setup")
HOTSPOT_PASS = os.environ.get("HOTSPOT_PASS", "pikiosk1234")


def nmcli(*args, timeout=25):
    """Esegue nmcli (o il mock). Ritorna (rc, stdout, stderr)."""
    try:
        p = subprocess.run([NMCLI, *args], capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout.strip(), p.stderr.strip()
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"
    except FileNotFoundError:
        return 127, "", f"nmcli non trovato: {NMCLI}"


def connectivity():
    rc, out, _ = nmcli("networking", "connectivity")
    return out or "unknown"


def scan():
    # -t = tabellare (campi separati da ':'), -f = campi scelti
    rc, out, err = nmcli("-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list")
    nets, seen = [], set()
    for line in out.splitlines():
        # NB: gli SSID possono contenere ':' -> splittiamo max 3 volte da sinistra
        parts = line.split(":", 3)
        if len(parts) != 4:
            continue
        inuse, ssid, signal, sec = parts
        if not ssid or ssid in seen:
            continue
        seen.add(ssid)
        nets.append({
            "ssid": ssid,
            "signal": int(signal) if signal.isdigit() else 0,
            "security": sec or "OPEN",
            "in_use": inuse.strip() == "*",
        })
    nets.sort(key=lambda n: n["signal"], reverse=True)
    return nets


def active_ssid():
    for n in scan():
        if n["in_use"]:
            return n["ssid"]
    return None


def connect(ssid, password):
    args = ["dev", "wifi", "connect", ssid]
    if password:
        args += ["password", password]
    rc, out, err = nmcli(*args, timeout=45)
    return rc == 0, (out or err or "").strip()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass  # silenzioso; il logging lo fa launch-kiosk.sh

    def _send(self, code, body, ctype="application/json"):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _json(self, code, obj):
        self._send(code, json.dumps(obj), "application/json")

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path in ("/", "/index.html", "/generate_204", "/hotspot-detect.html"):
            # gli ultimi due: URL che i telefoni chiamano per rilevare il captive portal
            try:
                with open(os.path.join(HERE, "wifi-setup.html"), "rb") as f:
                    self._send(200, f.read(), "text/html; charset=utf-8")
            except FileNotFoundError:
                self._send(404, "wifi-setup.html mancante", "text/plain")
        elif path == "/qrcode.js":
            try:
                with open(os.path.join(HERE, "vendor", "qrcode.js"), "rb") as f:
                    self._send(200, f.read(), "application/javascript")
            except FileNotFoundError:
                self._send(404, "qrcode.js mancante", "text/plain")
        elif path == "/api/status":
            self._json(200, {
                "connectivity": connectivity(),
                "active_ssid": active_ssid(),
            })
        elif path == "/api/hotspot/info":
            # La pagina usa questi dati per generare il QR di auto-join (WIFI:...).
            self._json(200, {"ssid": HOTSPOT_SSID, "password": HOTSPOT_PASS})
        elif path == "/api/scan":
            self._json(200, {"networks": scan()})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        if self.path.split("?", 1)[0] != "/api/connect":
            return self._json(404, {"error": "not found"})
        length = int(self.headers.get("Content-Length", "0") or 0)
        try:
            payload = json.loads(self.rfile.read(length) or "{}")
        except json.JSONDecodeError:
            return self._json(400, {"ok": False, "message": "JSON non valido"})
        ssid = (payload.get("ssid") or "").strip()
        password = payload.get("password") or ""
        if not ssid:
            return self._json(400, {"ok": False, "message": "SSID mancante"})
        ok, msg = connect(ssid, password)
        self._json(200 if ok else 502, {"ok": ok, "message": msg})


def main():
    print(f"wifi-portal: http://{HOST}:{PORT}  (NMCLI={NMCLI})", flush=True)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
