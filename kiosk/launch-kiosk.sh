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

# Force the HDMI audio sink to 100%. Node IDs change on every boot, so we look
# up the sink by name (must contain "hdmi") instead of hardcoding an ID.
set_hdmi_volume() {
  local id name
  for id in $(wpctl status 2>/dev/null | grep -oE '[0-9]+\. ' | grep -oE '[0-9]+'); do
    name=$(wpctl inspect "$id" 2>/dev/null | grep -m1 'node.name' | grep -oiE 'alsa_output[^"]*')
    if echo "$name" | grep -qi hdmi; then
      wpctl set-volume "$id" 1.0 2>/dev/null
      wpctl set-mute "$id" 0 2>/dev/null
      echo "$(date): HDMI sink $id ($name) set to 100%"
      return 0
    fi
  done
  echo "$(date): no HDMI sink found (display connected?)"
  return 1
}

temp_high() {
  local temp
  temp=$(vcgencmd measure_temp | grep -oE '[0-9]+' | head -1)
  [ "$temp" -ge "$TEMP_THRESHOLD" ]
}

# Prefer Ethernet over WiFi. If Ethernet is connected, turn WiFi off (more stable,
# less interference); if Ethernet is down/absent, turn WiFi back on so the Pi can
# rejoin a known network (or later enter WiFi setup). We match NetworkManager's
# device TYPE, not a fixed name (eth0/end0), and only ever disable WiFi when
# Ethernet is truly connected — so we never cut off a WiFi-only connection.
prefer_ethernet() {
  if nmcli -t -f TYPE,STATE device status 2>/dev/null | grep -q '^ethernet:connected'; then
    if [ "$(nmcli radio wifi 2>/dev/null)" = "enabled" ]; then
      nmcli radio wifi off 2>/dev/null && echo "$(date): Ethernet connected → WiFi off"
    fi
  else
    if [ "$(nmcli radio wifi 2>/dev/null)" != "enabled" ]; then
      nmcli radio wifi on 2>/dev/null && echo "$(date): Ethernet absent → WiFi on"
    fi
  fi
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

# Force HDMI audio to 100% at startup
set_hdmi_volume

# Prefer Ethernet: disable WiFi if the cable is in, enable it otherwise
prefer_ethernet

# Initial launch
CURRENT_STATE=$(get_state)
apply_state "$CURRENT_STATE"

# Monitoring loop — recheck every 30 seconds
while true; do
  sleep 30
  # Keep HDMI audio pinned at 100% (survives reconnects / profile changes)
  set_hdmi_volume
  # Re-evaluate Ethernet vs WiFi: if the cable was just plugged in, drop WiFi;
  # if it was unplugged, bring WiFi back so the Pi can reconnect.
  prefer_ethernet
  NEW_STATE=$(get_state)
  if [ "$NEW_STATE" != "$CURRENT_STATE" ]; then
    CURRENT_STATE="$NEW_STATE"
    apply_state "$CURRENT_STATE"
  fi
done
