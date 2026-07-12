#!/usr/bin/env bash
# hotspot.sh — Accende/spegne l'hotspot di setup del Pi.
#
# Usato da launch-kiosk.sh quando entra/esce dallo stato "setup". Tiene la logica
# nmcli fuori dal loop principale e la rende testabile in locale col mock.
#
# Uso:
#   ./hotspot.sh up      # crea l'hotspot pikiosk-setup (WPA2)
#   ./hotspot.sh down     # lo spegne / torna client WiFi
#   ./hotspot.sh status   # "on" oppure "off"
#
# Rispetta $NMCLI (mock in locale, nmcli vero sul Pi) e legge portal.conf per
# SSID/password dell'hotspot.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
[ -f "$HERE/portal.conf" ] && source "$HERE/portal.conf"
NMCLI="${NMCLI:-nmcli}"
HOTSPOT_SSID="${HOTSPOT_SSID:-pikiosk-setup}"
HOTSPOT_PASS="${HOTSPOT_PASS:-pikiosk1234}"
IFACE="${WIFI_IFACE:-wlan0}"

case "${1:-}" in
  up)
    "$NMCLI" radio wifi on >/dev/null 2>&1 || true
    "$NMCLI" dev wifi hotspot ifname "$IFACE" ssid "$HOTSPOT_SSID" password "$HOTSPOT_PASS"
    echo "hotspot '$HOTSPOT_SSID' attivo"
    ;;
  down)
    # Spegne l'AP: nmcli lo espone come connessione 'Hotspot'. Se non c'e', ignora.
    "$NMCLI" connection down Hotspot >/dev/null 2>&1 || \
    "$NMCLI" con down Hotspot >/dev/null 2>&1 || true
    echo "hotspot spento"
    ;;
  status)
    if "$NMCLI" -t -f NAME connection show --active 2>/dev/null | grep -qi hotspot; then
      echo "on"
    else
      echo "off"
    fi
    ;;
  *)
    echo "uso: $0 {up|down|status}" >&2; exit 1
    ;;
esac
