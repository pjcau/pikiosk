#!/usr/bin/env bash
# apply-remote.sh — Applica le modifiche al telecomando IR senza rilanciare install.sh
# né riavviare il Pi.
#
# Uso: ./apply-remote.sh            → applica keymap, tasti labwc e bordo di focus
#      ./apply-remote.sh --no-kiosk → come sopra ma senza riavviare il kiosk
#
# Cosa applica (dopo aver modificato i file nel clone o fatto git pull):
#   config/ir-keymap.toml   → scancode → tasti     (restart del service pikiosk-ir)
#   config/labwc-rc.xml     → azioni dei tasti     (es. Back → Alt+Sinistra; reload labwc)
#   kiosk/focus-ring/       → bordo di focus       (riavvio del kiosk)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../pikiosk/scripts
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"                     # .../pikiosk
LABWC_RC="$HOME/.config/labwc/rc.xml"

# 1. wtype serve al keybind Back → Alt+Sinistra
if ! command -v wtype >/dev/null; then
  echo "[1/4] Installo wtype..."
  sudo apt install -y wtype
else
  echo "[1/4] wtype già presente."
fi

# 2. Keymap del telecomando (scancode → KEY_*)
echo "[2/4] Ricarico la keymap IR (pikiosk-ir)..."
if systemctl list-unit-files pikiosk-ir.service >/dev/null 2>&1 \
   && systemctl is-enabled pikiosk-ir.service >/dev/null 2>&1; then
  sudo systemctl restart pikiosk-ir.service
  tail -n 1 /tmp/kiosk-ir.log 2>/dev/null | sed 's/^/  /'
else
  echo "  service pikiosk-ir non installato: lancia prima ./install.sh"
fi

# 3. Azioni dei tasti in labwc (rc.xml), con backup se diverso
echo "[3/4] Aggiorno le azioni dei tasti in labwc..."
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

# 4. Bordo di focus (estensione Chromium): serve riavviare il kiosk
if [ "$1" = "--no-kiosk" ]; then
  echo "[4/4] Kiosk non riavviato (--no-kiosk)."
else
  echo "[4/4] Riavvio il kiosk..."
  "$SCRIPT_DIR/kiosk.sh" restart
fi

echo "Fatto. Test tasti: sudo libinput debug-events | grep -i key"
