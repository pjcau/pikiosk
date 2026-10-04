#!/usr/bin/env bash
# apply-remote.sh — Applica le modifiche al telecomando IR senza rilanciare install.sh
# né riavviare il Pi.
#
# Uso: ./apply-remote.sh            → applica keymap, rc.xml di labwc ed estensione
#      ./apply-remote.sh --no-kiosk → come sopra ma senza riavviare il kiosk
#
# Cosa applica (dopo aver modificato i file nel clone o fatto git pull):
#   config/ir-keymap.toml   → scancode → tasti     (restart del service pikiosk-ir)
#   config/labwc-rc.xml     → config labwc         (senza keybind: F9 deve arrivare a Chromium)
#   kiosk/focus-ring/       → bordo di focus + Back (F9 → history.back(); riavvio del kiosk)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../pikiosk/scripts
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"                     # .../pikiosk
LABWC_RC="$HOME/.config/labwc/rc.xml"

# 1. Keymap del telecomando (scancode → KEY_*)
echo "[1/3] Ricarico la keymap IR (pikiosk-ir)..."
if systemctl list-unit-files pikiosk-ir.service >/dev/null 2>&1 \
   && systemctl is-enabled pikiosk-ir.service >/dev/null 2>&1; then
  sudo systemctl restart pikiosk-ir.service
  tail -n 1 /tmp/kiosk-ir.log 2>/dev/null | sed 's/^/  /'
else
  echo "  service pikiosk-ir non installato: lancia prima ./install.sh"
fi

# 2. rc.xml di labwc (senza keybind), con backup se diverso
echo "[2/3] Aggiorno la config di labwc..."
mkdir -p "$(dirname "$LABWC_RC")"
if [ -f "$LABWC_RC" ] && ! cmp -s "$LABWC_RC" "$REPO_DIR/config/labwc-rc.xml"; then
  cp "$LABWC_RC" "$LABWC_RC.bak"
  echo "  backup del vecchio rc.xml in $LABWC_RC.bak"
fi
cp "$REPO_DIR/config/labwc-rc.xml" "$LABWC_RC"
# SIGHUP = labwc --reconfigure, funziona anche da SSH senza variabili Wayland.
if pkill -HUP -x labwc; then
  echo "  labwc ricaricato."
else
  echo "  labwc non in esecuzione: verrà applicato al prossimo avvio."
fi

# 3. Estensione Chromium (bordo di focus + Back): serve riavviare il kiosk
if [ "$1" = "--no-kiosk" ]; then
  echo "[3/3] Kiosk non riavviato (--no-kiosk)."
else
  echo "[3/3] Riavvio il kiosk..."
  "$SCRIPT_DIR/kiosk.sh" restart
fi

echo "Fatto. Test tasti: sudo libinput debug-events | grep -i key"
