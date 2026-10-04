#!/usr/bin/env bash
# clean-browser.sh — Pulisce cache e cookie di Chromium del kiosk e lo riavvia.
# Utile quando il sito tratta il kiosk come un bot (sessione/cookie corrotti).
#
# Uso: ./clean-browser.sh          → cancella cache + cookie (dovrai rifare il login)
#      ./clean-browser.sh --all    → cancella l'intero profilo Chromium (reset totale)
#
# Il kiosk usa il profilo di default (~/.config/chromium) e nessuna estensione.

set -e

PROFILE_DIR="$HOME/.config/chromium"
CACHE_DIR="$HOME/.cache/chromium"

echo "Stop kiosk e Chromium..."
pkill -f launch-kiosk.sh 2>/dev/null || true
pkill chromium 2>/dev/null || true
sleep 2

echo "Cancello cache: $CACHE_DIR"
rm -rf "$CACHE_DIR"

if [ "$1" = "--all" ]; then
  echo "Cancello profilo completo: $PROFILE_DIR"
  rm -rf "$PROFILE_DIR"
else
  echo "Cancello cookie, storage e sessione da: $PROFILE_DIR/Default"
  rm -rf "$PROFILE_DIR"/Default/{Cookies,Cookies-journal,"Network/Cookies","Network/Cookies-journal"} \
         "$PROFILE_DIR"/Default/{"Local Storage","Session Storage",Sessions,IndexedDB,"Service Worker","Code Cache","GPUCache"}
fi

echo "Riavvio la sessione grafica (labwc + VNC + kiosk)..."
sudo systemctl restart lightdm
