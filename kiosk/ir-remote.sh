#!/usr/bin/env bash
# ir-remote.sh — load the pikiosk IR keymap onto the gpio-ir receiver.
#
# The gpio-ir receiver shows up as an rc device (/sys/class/rc/rcN), but the N
# index changes across boots, so we find it by driver name (gpio_ir_recv) instead
# of hardcoding rc2. Once our keymap is loaded, the kernel translates incoming NEC
# scancodes into standard key events (KEY_UP/DOWN/LEFT/RIGHT/ENTER/BACK) on the IR
# input device — labwc reads them via libinput and forwards them to Chromium. No
# daemon needed: rc-core does the translation in-kernel after the keymap is set.
#
# Run at boot by the pikiosk-ir systemd service (needs root for ir-keytable).
# Run-in-place: lives in the clone, reads the keymap from the sibling config/.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../pikiosk/kiosk
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"                     # .../pikiosk
KEYMAP="$REPO_DIR/config/ir-keymap.toml"
LOG=/tmp/kiosk-ir.log

log() { echo "$(date): $*" >> "$LOG"; }

# Find the rc device backed by the gpio-ir driver (index varies across boots).
find_dev() {
  ir-keytable 2>/dev/null | awk '
    /Found/                       { match($0, /rc[0-9]+/); dev=substr($0,RSTART,RLENGTH) }
    /gpio_ir_recv|gpio-ir-recv/   { print dev; exit }'
}

# The rc device appears early in boot, but retry a bit in case we start first.
DEV=""
for _ in $(seq 1 10); do
  DEV="$(find_dev)"
  [ -n "$DEV" ] && break
  sleep 1
done

if [ -z "$DEV" ]; then
  log "gpio-ir device not found — is 'dtoverlay=gpio-ir' in /boot/firmware/config.txt? (needs reboot)"
  exit 1
fi

# -c clears any stale keytable; -w writes ours (its [[protocols]] block also
# enables only NEC, so the spurious imon/other decodes go away).
if ir-keytable -s "$DEV" -c -w "$KEYMAP" >> "$LOG" 2>&1; then
  log "loaded keymap $KEYMAP onto $DEV"
else
  log "FAILED to load keymap $KEYMAP onto $DEV"
  exit 1
fi

# Record the resulting protocol/keytable for debugging.
ir-keytable -s "$DEV" >> "$LOG" 2>&1
