#!/usr/bin/env bash
# apply-remote.sh — Applica le modifiche al telecomando IR senza rilanciare install.sh
# né riavviare il Pi.
#
# Uso: ./apply-remote.sh               → applica tutto e riavvia la sessione grafica
#      ./apply-remote.sh --no-restart  → come sopra ma senza riavviare la sessione
#                                         (i tasti nuovi NON arrivano finché non riavvii)
#
# Cosa applica (dopo aver modificato i file nel clone o fatto git pull):
#   config/pikiosk-ir.service → service che carica la keymap prima della sessione
#   config/ir-keymap.toml     → scancode → tasti (restart del service pikiosk-ir)
#   config/labwc-rc.xml       → config labwc (senza keybind)
#
# Perché riavviare la sessione: labwc ricorda quali tasti dichiara il ricevitore IR
# quando lo apre e scarta tutti gli altri. Dopo aver cambiato la keymap deve
# riaprirlo, quindi la sessione (labwc + VNC + kiosk) va riavviata.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../pikiosk/scripts
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"                     # .../pikiosk
LABWC_RC="$HOME/.config/labwc/rc.xml"
UNIT=/etc/systemd/system/pikiosk-ir.service

# 1. Service + keymap del telecomando (scancode → KEY_*)
echo "[1/3] Aggiorno il service e ricarico la keymap IR..."
if [ -f "$UNIT" ]; then
  sed "s|__REPO_DIR__|${REPO_DIR}|g" "$REPO_DIR/config/pikiosk-ir.service" \
    | sudo tee "$UNIT" > /dev/null
  sudo systemctl daemon-reload
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

# 3. Riavvio della sessione: labwc riapre il ricevitore IR e vede i tasti nuovi
if [ "$1" = "--no-restart" ]; then
  echo "[3/3] Sessione non riavviata (--no-restart): i tasti nuovi arrivano dopo"
  echo "      'sudo systemctl restart lightdm' o un reboot."
else
  echo "[3/3] Riavvio la sessione grafica (labwc + VNC + kiosk)..."
  sudo systemctl restart lightdm
fi

echo "Fatto. Test tasti: WAYLAND_DISPLAY=wayland-0 wev"
