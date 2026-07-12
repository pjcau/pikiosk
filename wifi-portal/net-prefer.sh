#!/usr/bin/env bash
# net-prefer.sh — Preferisci l'ethernet.
#
# Regola: se l'ethernet e' connessa, spegni il WiFi (piu' stabile/sicuro, meno
# interferenze); se l'ethernet e' assente o giu', riaccendi il WiFi cosi' il Pi
# puo' collegarsi a una rete nota oppure entrare in modalita' setup/hotspot.
#
# Idempotente: pensato per essere chiamato ogni giro nel loop di launch-kiosk.sh.
# Non spegne mai il WiFi se l'ethernet non e' realmente connessa, quindi non ti
# taglia fuori quando sei sul WiFi.
#
# Rispetta $NMCLI (mock in locale, nmcli vero sul Pi).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
[ -f "$HERE/portal.conf" ] && source "$HERE/portal.conf"
NMCLI="${NMCLI:-nmcli}"

# Ethernet connessa secondo NetworkManager (indipendente dal nome eth0/end0).
eth_connected() {
  "$NMCLI" -t -f TYPE,STATE device status 2>/dev/null | grep -q '^ethernet:connected'
}
wifi_radio_on() {
  [ "$("$NMCLI" radio wifi 2>/dev/null)" = "enabled" ]
}

if eth_connected; then
  if wifi_radio_on; then
    "$NMCLI" radio wifi off >/dev/null 2>&1 || true
    echo "$(date): ethernet connessa → WiFi spento"
  else
    echo "$(date): ethernet connessa → WiFi gia' spento"
  fi
else
  if wifi_radio_on; then
    echo "$(date): ethernet assente → WiFi gia' acceso"
  else
    "$NMCLI" radio wifi on >/dev/null 2>&1 || true
    echo "$(date): ethernet assente → WiFi riacceso"
  fi
fi
