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
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NMCLI = os.environ.get("NMCLI", "nmcli")
HERE = os.path.dirname(os.path.abspath(__file__))
HOTSPOT_SH = os.path.join(HERE, "hotspot.sh")
PORT = int(os.environ.get("PORT", os.environ.get("PORTAL_PORT", "8080")))
HOST = os.environ.get("HOST", os.environ.get("PORTAL_HOST", "0.0.0.0"))
# Credenziali dell'hotspot di setup: servono alla pagina per costruire il QR di
# auto-join. Non sono la password di una WiFi reale (vedi portal.conf).
HOTSPOT_SSID = os.environ.get("HOTSPOT_SSID", "pikiosk-setup")
HOTSPOT_PASS = os.environ.get("HOTSPOT_PASS", "pikiosk1234")
# IP del gateway dell'hotspot (NetworkManager shared usa 10.42.0.1 di default):
# la pagina lo usa per il QR "apri il portale" che il telefono apre dopo il join.
HOTSPOT_GW = os.environ.get("HOTSPOT_GW", "10.42.0.1")
# Cache dell'ultima scansione riuscita. Con UNA sola antenna, mentre l'hotspot e'
# attivo la radio e' occupata e "dev wifi list" torna vuoto: serviamo la cache
# scritta poco prima di accendere l'AP (single-radio pattern).
SCAN_CACHE = os.environ.get("SCAN_CACHE", "/tmp/kiosk-wifi-scan.json")
# Flag di trigger manuale: dopo una connessione riuscita lo rimuoviamo, così
# launch-kiosk.sh puo' uscire dallo stato setup (vedi portal.conf).
SETUP_FLAG = os.environ.get("SETUP_FLAG", "/tmp/kiosk-wifi-setup")


def log(msg):
    """Riga di log su stdout → finisce in /tmp/kiosk-portal.log (vedi launch-kiosk).
    Serve per capire dove casca il connect senza dover leggere il journal di NM."""
    print(f"{time.strftime('%H:%M:%S')} [portal] {msg}", flush=True)


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


def _live_scan():
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


def _read_cache():
    try:
        with open(SCAN_CACHE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return []


def _write_cache(nets):
    try:
        with open(SCAN_CACHE, "w") as f:
            json.dump(nets, f)
    except OSError:
        pass


def scan():
    """Scansione live; se vuota (hotspot attivo = radio occupata) usa la cache.
    Ogni scansione live non vuota aggiorna la cache, così quando accenderemo
    l'hotspot avremo l'ultima lista buona da servire."""
    nets = _live_scan()
    if nets:
        _write_cache(nets)
        return nets
    return _read_cache()


def active_ssid():
    for n in scan():
        if n["in_use"]:
            return n["ssid"]
    return None


def _hotspot(action):
    """up/down the setup hotspot via hotspot.sh (best effort)."""
    try:
        subprocess.run([HOTSPOT_SH, action], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        pass


def _profile_exists(ssid):
    rc, out, _ = nmcli("-t", "-f", "NAME", "connection", "show")
    return ssid in out.splitlines()


def _connect_open(ssid):
    rc, out, err = nmcli("dev", "wifi", "connect", ssid, timeout=45)
    return rc == 0, (out or err or "").strip()


def _connect_psk(ssid, password):
    """Connessione a una rete protetta creando SEMPRE un profilo WPA-PSK esplicito.

    Perche' non `dev wifi connect ... password`: se esiste gia' un profilo salvato
    con lo stesso nome (es. una vecchia connessione alla stessa rete), nmcli lo
    RIATTIVA ignorando la password digitata; se quel profilo ha un PSK vecchio o
    assente, NetworkManager chiede il segreto a un agente GUI -> spunta il dialog
    password sullo schermo del kiosk e poi sparisce. Cancellando il profilo e
    ricreandolo con la PSK esplicita, NM ha gia' il segreto e non chiede nulla."""
    if _profile_exists(ssid):
        rc, out, err = nmcli("connection", "delete", ssid)
        log(f"deleted stale profile {ssid!r} (rc={rc})")
    log(f"add explicit wpa-psk profile {ssid!r}")
    rc, out, err = nmcli(
        "connection", "add", "type", "wifi", "con-name", ssid, "ssid", ssid,
        "wifi-sec.key-mgmt", "wpa-psk", "wifi-sec.psk", password, timeout=25,
    )
    if rc != 0:
        log(f"connection add failed rc={rc}: {err or out}")
        return False, (err or out or "").strip()
    rc, out, err = nmcli("connection", "up", ssid, timeout=45)
    log(f"connection up {ssid!r} rc={rc}: {err or out}")
    return rc == 0, (out or err or "").strip()


def connect(ssid, password, security="WPA2"):
    """Connect to a WiFi network. Single-radio aware: tears down the setup hotspot
    first so the radio is free to associate as a station; on failure it brings the
    hotspot back up so the user can retry from the portal. Ogni passo e' loggato
    su /tmp/kiosk-portal.log per diagnosi."""
    secured = bool(password) and (security or "").upper() not in ("", "OPEN")
    log(f"connect ssid={ssid!r} secured={secured}")
    _hotspot("down")               # free the radio from AP mode
    log("hotspot down (radio freed)")
    nmcli("radio", "wifi", "on")
    nmcli("dev", "wifi", "rescan", timeout=20)  # refresh scan now that the radio is free
    time.sleep(4)
    if secured:
        ok, msg = _connect_psk(ssid, password)
    else:
        ok, msg = _connect_open(ssid)
    log(f"connect result ok={ok} msg={msg!r}")
    if not ok:
        _hotspot("up")             # restore the portal AP for a retry
        log("hotspot back up for retry")
    return ok, msg


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
            # La pagina usa questi dati per generare il QR di auto-join (WIFI:...)
            # e il QR/URL "apri il portale" (gateway:porta) dopo il join.
            self._json(200, {
                "ssid": HOTSPOT_SSID,
                "password": HOTSPOT_PASS,
                "portal_url": f"http://{HOTSPOT_GW}:{PORT}",
            })
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
        security = payload.get("security") or "WPA2"
        if not ssid:
            return self._json(400, {"ok": False, "message": "SSID mancante"})
        ok, msg = connect(ssid, password, security)
        if ok:
            # Connessione riuscita: consuma il flag manuale così launch-kiosk esce
            # dallo stato setup (e spegne l'hotspot) al giro successivo.
            try:
                os.remove(SETUP_FLAG)
                log(f"connect ok → removed setup flag {SETUP_FLAG}")
            except OSError:
                pass
        self._json(200 if ok else 502, {"ok": ok, "message": msg})


def main():
    print(f"wifi-portal: http://{HOST}:{PORT}  (NMCLI={NMCLI})", flush=True)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
