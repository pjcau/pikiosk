#!/usr/bin/env bash
# launch-kiosk.sh — Kiosk controller: VPN, temperature, network and WiFi setup.
#
# State machine (priority high→low):
#   temp   — temperature >= threshold        → temperature warning page
#   setup  — no physical uplink / manual flag → WiFi setup portal (+ hotspot)
#   vpn    — uplink present but VPN down       → VPN error page
#   ok     — VPN up, temperature OK            → target site
# Rechecks every 30s and switches automatically. Also forces HDMI audio to 100%
# and prefers Ethernet over WiFi.
#
# Run-in-place: this script lives in the cloned repo (pikiosk/kiosk/) and finds
# its sibling files relative to its own location — no hardcoded home paths.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../pikiosk/kiosk
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"                     # .../pikiosk
PORTAL_DIR="$REPO_DIR/wifi-portal"

# Portal settings (hotspot SSID/pass, port, timeout, flag, cache). Exported so the
# portal server (started below) inherits them.
# shellcheck disable=SC1091
[ -f "$PORTAL_DIR/portal.conf" ] && source "$PORTAL_DIR/portal.conf"
export HOTSPOT_SSID HOTSPOT_PASS HOTSPOT_GW PORTAL_PORT PORTAL_HOST SCAN_CACHE SETUP_FLAG
PORTAL_PORT="${PORTAL_PORT:-8080}"
SETUP_TIMEOUT="${SETUP_TIMEOUT:-60}"
SETUP_FLAG="${SETUP_FLAG:-/tmp/kiosk-wifi-setup}"

URL_SITE="https://www.bbc.co.uk/iplayer/live/bbcone"
URL_VPN_ERROR="file://$SCRIPT_DIR/vpn-error.html"
URL_TEMP_ERROR="file://$SCRIPT_DIR/temp-warning.html"
URL_RECON="file://$SCRIPT_DIR/reconnecting.html"
URL_SETUP="http://127.0.0.1:${PORTAL_PORT}"
TEMP_THRESHOLD=80
LOOP_INTERVAL=30
# Consecutive no-uplink loops before auto-entering setup (debounce).
NEED=$(( (SETUP_TIMEOUT + LOOP_INTERVAL - 1) / LOOP_INTERVAL ))
# Loops the VPN may stay down (with a stable uplink) before we call it a real
# failure. Until then we show the neutral "reconnecting" page instead of the VPN
# error — this covers the brief Ethernet→WiFi handover gap.
VPN_GRACE=2
CURRENT_STATE=""
NO_NET_COUNT=0
VPN_DOWN_COUNT=0

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
# NOTE: not called while in setup mode, so it never tears down the hotspot.
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

# Our setup hotspot is up (WiFi radio is in AP mode, not a real uplink).
hotspot_active() {
  nmcli -t -f NAME connection show --active 2>/dev/null | grep -qi hotspot
}

# A real physical uplink exists: Ethernet connected, or WiFi associated to a real
# network (NOT our own setup hotspot). Independent of VPN/internet reachability.
have_network() {
  nmcli -t -f TYPE,STATE device status 2>/dev/null | grep -q '^ethernet:connected' && return 0
  if ! hotspot_active && nmcli -t -f TYPE,STATE device status 2>/dev/null | grep -q '^wifi:connected'; then
    return 0
  fi
  return 1
}

portal_running() { pgrep -f "$PORTAL_DIR/server.py" >/dev/null 2>&1; }

start_portal() {
  portal_running && return 0
  ( cd "$PORTAL_DIR" && nohup python3 server.py >> /tmp/kiosk-portal.log 2>&1 & )
  echo "$(date): portal started on $URL_SETUP"
}

stop_portal() { pkill -f "$PORTAL_DIR/server.py" 2>/dev/null || true; }

enter_setup() {
  echo "$(date): entering WiFi setup mode"
  nmcli radio wifi on 2>/dev/null || true
  start_portal
  sleep 1
  # Single-radio: warm the scan cache while the radio is still free, BEFORE the
  # AP goes up (once the hotspot is active, live scans return nothing).
  curl -s "http://127.0.0.1:${PORTAL_PORT}/api/scan" >/dev/null 2>&1 || true
  "$PORTAL_DIR/hotspot.sh" up || true
  launch_chromium "$URL_SETUP"
}

leave_setup() {
  echo "$(date): leaving WiFi setup mode"
  "$PORTAL_DIR/hotspot.sh" down || true
  stop_portal
  rm -f "$SETUP_FLAG"
}

# Decide the current state. Uses globals CURRENT_STATE and NO_NET_COUNT.
compute_state() {
  if temp_high; then echo "temp"; return; fi
  # Manual override forces setup — but only while there is NO real uplink. If
  # Ethernet (or a real WiFi station) is present, setup makes no sense: keeping
  # the hotspot up next to a working uplink is the "three states at once" mess
  # (ethernet + hotspot + VPN). So a genuine uplink wins and clears the stale flag.
  if [ -f "$SETUP_FLAG" ]; then
    if have_network; then
      rm -f "$SETUP_FLAG"; echo "$(date): real uplink present → dropping stale setup flag" >&2
    else
      echo "setup"; return
    fi
  fi
  if [ "$CURRENT_STATE" = "setup" ]; then
    # Stay in setup until a real uplink returns.
    have_network || { echo "setup"; return; }
  else
    # Auto-trigger: no uplink for long enough (debounce).
    if ! have_network && [ "$NO_NET_COUNT" -ge "$NEED" ]; then echo "setup"; return; fi
  fi
  # No uplink but within the setup debounce → transient, show "reconnecting".
  if ! have_network; then echo "recon"; return; fi
  if ! vpn_up; then
    # Uplink present but VPN down: brief → reconnecting, persistent → real error.
    [ "$VPN_DOWN_COUNT" -lt "$VPN_GRACE" ] && { echo "recon"; return; }
    echo "vpn"; return
  fi
  echo "ok"
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
    setup)
      echo "$(date): no network → WiFi setup portal"
      enter_setup
      ;;
    recon)
      echo "$(date): network/VPN in transition → showing reconnecting page"
      launch_chromium "$URL_RECON"
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

# Update the uplink / VPN-down counters used by compute_state's debounce & grace.
update_counters() {
  if have_network; then
    NO_NET_COUNT=0
    if vpn_up; then VPN_DOWN_COUNT=0; else VPN_DOWN_COUNT=$((VPN_DOWN_COUNT + 1)); fi
  else
    NO_NET_COUNT=$((NO_NET_COUNT + 1))
    VPN_DOWN_COUNT=0   # no uplink → not a "VPN persistently down" case
  fi
}

# ── Startup ───────────────────────────────────────────────────────────────────
set_hdmi_volume
prefer_ethernet
update_counters
CURRENT_STATE=$(compute_state)
apply_state "$CURRENT_STATE"

# ── Monitoring loop ───────────────────────────────────────────────────────────
while true; do
  sleep "$LOOP_INTERVAL"
  # Keep HDMI audio pinned at 100% (survives reconnects / profile changes).
  set_hdmi_volume

  # Track uplink presence and VPN state for the debounce / reconnect grace.
  update_counters

  # Ethernet/WiFi preference — but never while in setup (would kill the hotspot).
  [ "$CURRENT_STATE" != "setup" ] && prefer_ethernet

  NEW_STATE=$(compute_state)
  if [ "$NEW_STATE" != "$CURRENT_STATE" ]; then
    [ "$CURRENT_STATE" = "setup" ] && leave_setup
    CURRENT_STATE="$NEW_STATE"
    apply_state "$CURRENT_STATE"
  fi
done
