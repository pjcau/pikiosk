#!/usr/bin/env bash
# kiosk.sh — Apre/chiude l'app kiosk (launch-kiosk.sh + Chromium) senza riavviare.
#
# Uso: ./kiosk.sh start      → avvia il kiosk sullo schermo HDMI
#      ./kiosk.sh stop       → chiude kiosk, Chromium, portal WiFi e hotspot di setup
#      ./kiosk.sh restart    → stop + start (es. dopo un git pull)
#      ./kiosk.sh status     → dice se il kiosk sta girando
#
# Funziona anche da SSH: imposta le variabili Wayland per aprire Chromium sulla
# sessione labwc. VNC (wayvnc) non viene toccato. Log in /tmp/kiosk.log.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../pikiosk/scripts
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"                     # .../pikiosk
LAUNCHER="$REPO_DIR/kiosk/launch-kiosk.sh"

is_running() { pgrep -f "$LAUNCHER" >/dev/null; }

do_stop() {
  pkill -f "$LAUNCHER" 2>/dev/null || true
  pkill -f "$REPO_DIR/wifi-portal/server.py" 2>/dev/null || true
  pkill chromium 2>/dev/null || true
  # Se eravamo nello stato setup l'hotspot è ancora su: spegnilo.
  if [ "$("$REPO_DIR/wifi-portal/hotspot.sh" status 2>/dev/null)" = "on" ]; then
    "$REPO_DIR/wifi-portal/hotspot.sh" down >/dev/null 2>&1 || true
  fi
  echo "kiosk fermato"
}

do_start() {
  if is_running; then
    echo "kiosk già in esecuzione (usa restart)"; return
  fi
  # Stesse variabili della sessione labwc (es. URL_SITE), così da SSH il kiosk
  # parte uguale all'avvio automatico. Un URL_SITE passato a mano vince sul file.
  local url_override="$URL_SITE"
  if [ -f "$HOME/.config/labwc/environment" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$HOME/.config/labwc/environment"
    set +a
  fi
  [ -n "$url_override" ] && export URL_SITE="$url_override"
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  if [ -z "$WAYLAND_DISPLAY" ]; then
    local sock
    sock=$(ls "$XDG_RUNTIME_DIR"/wayland-? 2>/dev/null | head -1)
    [ -z "$sock" ] && { echo "nessuna sessione Wayland (labwc) attiva"; exit 1; }
    export WAYLAND_DISPLAY="$(basename "$sock")"
  fi
  nohup "$LAUNCHER" >> /tmp/kiosk.log 2>&1 &
  echo "kiosk avviato (log: tail -f /tmp/kiosk.log)"
}

case "${1:-}" in
  start)   do_start ;;
  stop)    do_stop ;;
  restart) do_stop; sleep 2; do_start ;;
  status)  is_running && echo "kiosk in esecuzione" || echo "kiosk fermo" ;;
  *)       echo "Uso: $0 start|stop|restart|status"; exit 1 ;;
esac
