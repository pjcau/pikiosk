#!/usr/bin/env bash
# launch-kiosk.sh — Launches Chromium with VPN and temperature checks.
# - If temperature >= 80°C: shows temperature warning page.
# - If VPN is down: shows VPN error page.
# - If all OK: shows the target site.
# Rechecks every 30 seconds and switches pages automatically.

URL_SITE="https://www.bbc.co.uk/iplayer/live/bbcone"
URL_VPN_ERROR="file:///home/pjcau/vpn-error.html"
URL_TEMP_ERROR="file:///home/pjcau/temp-warning.html"
TEMP_THRESHOLD=80
CURRENT_STATE=""

vpn_up() {
  ip link show protonvpn 2>/dev/null | grep -q "UP"
}

temp_high() {
  local temp
  temp=$(vcgencmd measure_temp | grep -oE '[0-9]+' | head -1)
  [ "$temp" -ge "$TEMP_THRESHOLD" ]
}

get_state() {
  if temp_high; then
    echo "temp"
  elif ! vpn_up; then
    echo "vpn"
  else
    echo "ok"
  fi
}

launch_chromium() {
  local url=$1
  pkill chromium 2>/dev/null
  sleep 1
  chromium \
    --ozone-platform=wayland \
    --kiosk \
    --noerrdialogs \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --disable-features=Translate \
    --check-for-update-interval=31536000 \
    --autoplay-policy=no-user-gesture-required \
    "$url" &
}

apply_state() {
  local state=$1
  case "$state" in
    ok)
      echo "$(date): VPN active, temperature OK → launching site"
      launch_chromium "$URL_SITE"
      ;;
    vpn)
      echo "$(date): VPN not active → showing VPN error page"
      launch_chromium "$URL_VPN_ERROR"
      ;;
    temp)
      echo "$(date): Temperature too high → showing temperature warning"
      launch_chromium "$URL_TEMP_ERROR"
      ;;
  esac
}

# Initial launch
CURRENT_STATE=$(get_state)
apply_state "$CURRENT_STATE"

# Monitoring loop — recheck every 30 seconds
while true; do
  sleep 30
  NEW_STATE=$(get_state)
  if [ "$NEW_STATE" != "$CURRENT_STATE" ]; then
    CURRENT_STATE="$NEW_STATE"
    apply_state "$CURRENT_STATE"
  fi
done
