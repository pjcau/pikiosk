#!/usr/bin/env bash
# run-local.sh — Avvia il wifi-portal in LOCALE usando il mock di nmcli.
#
# Non tocca la rete vera: $NMCLI punta a mock/nmcli, che simula scan/connect/hotspot
# su un file di stato temporaneo. Utile per iterare su backend e UI dal PC.
#
# Sceglie da solo una porta LIBERA (parte da 8088) per non scontrarsi con altri
# server locali (es. Apache sulla 8080). Stampa l'URL e apre il browser.
#
# Uso:
#   ./run-local.sh            # porta automatica + apre il browser
#   PORT=9000 ./run-local.sh  # forza una porta specifica
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
[ -f "$HERE/portal.conf" ] && source "$HERE/portal.conf"
export HOTSPOT_SSID HOTSPOT_PASS
export NMCLI="$HERE/mock/nmcli"
export NMCLI_STATE="${NMCLI_STATE:-/tmp/mock-nmcli-state}"
export HOST="${HOST:-127.0.0.1}"

port_busy() {
  # true (0) se la porta e' gia' in ascolto
  (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && { exec 3>&- 3<&-; return 0; }
  return 1
}

# Se PORT non e' forzato, trova la prima porta libera da 8088 in su.
if [ -z "${PORT:-}" ]; then
  PORT=8088
  while port_busy "$PORT"; do
    echo "porta $PORT occupata, provo la successiva…"
    PORT=$((PORT + 1))
    [ "$PORT" -gt 8110 ] && { echo "nessuna porta libera 8088-8110"; exit 1; }
  done
elif port_busy "$PORT"; then
  echo "ATTENZIONE: la porta $PORT che hai scelto e' gia' occupata. Liberala o usane un'altra." >&2
  exit 1
fi
export PORT

chmod +x "$NMCLI"
rm -f "$NMCLI_STATE"   # parti sempre da "non connesso"

URL="http://$HOST:$PORT"
echo
echo "=================================================="
echo "  wifi-portal LOCALE (mock nmcli) — ATTIVO"
echo "  APRI NEL BROWSER:   $URL"
echo "=================================================="
echo "  Reti finte: HomeWiFi(password123) CoffeeShop(latte)"
echo "              OpenGuest(aperta) Neighbor_5G(secret)"
echo "  QR hotspot: $HOTSPOT_SSID / $HOTSPOT_PASS"
echo "  Ferma con Ctrl-C."
echo

command -v xdg-open >/dev/null && (sleep 1; xdg-open "$URL" >/dev/null 2>&1 || true) &
exec python3 "$HERE/server.py"
