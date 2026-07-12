#!/usr/bin/env bash
# install.sh — pikiosk setup for Raspberry Pi 5 (run-in-place model).
#
# Clone the repo anywhere, run this once. Scripts run DIRECTLY from the clone —
# nothing is copied to the home dir — so `git pull` updates everything instantly.
# Only files that MUST live under /etc (LightDM, DRM, WireGuard) are installed;
# the labwc autostart is pointed at this clone's kiosk/launch-kiosk.sh.
#
# Run as normal user (not root). Uses sudo where needed.

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
USER_NAME="$(whoami)"
HOME_DIR="/home/${USER_NAME}"

echo "======================================"
echo " pikiosk installer (run-in-place)"
echo " User: ${USER_NAME}"
echo " Repo: ${REPO_DIR}"
echo "======================================"
echo ""

# ── 1. System update ──────────────────────────────────────────────────────────
echo "[1/8] Updating system..."
sudo apt update && sudo apt full-upgrade -y

# ── 2. Install packages ───────────────────────────────────────────────────────
echo "[2/8] Installing packages..."
sudo apt install -y \
  labwc wayvnc \
  polkitd pkexec \
  libgl1-mesa-dri mesa-utils \
  chromium \
  unclutter \
  wireguard resolvconf \
  git curl \
  python3 network-manager

# ── 3. User groups ────────────────────────────────────────────────────────────
echo "[3/8] Adding user to groups..."
sudo usermod -aG video,render,input "${USER_NAME}"

# ── 4. fbdev emulation (needed for Pi 5 KMS) ─────────────────────────────────
echo "[4/8] Configuring DRM fbdev emulation..."
sudo cp "${REPO_DIR}/config/drm.conf" /etc/modprobe.d/drm.conf

# ── 5. LightDM autologin ─────────────────────────────────────────────────────
echo "[5/8] Configuring LightDM autologin..."
sudo mkdir -p /etc/lightdm/lightdm.conf.d
sed "s/YOUR_USER/${USER_NAME}/g" \
  "${REPO_DIR}/config/lightdm-autologin.conf" \
  | sudo tee /etc/lightdm/lightdm.conf.d/01-autologin.conf > /dev/null

# ── 6. WireGuard VPN ─────────────────────────────────────────────────────────
echo "[6/8] Setting up WireGuard VPN..."
if [ -f "${REPO_DIR}/config/wireguard.conf" ]; then
  sudo cp "${REPO_DIR}/config/wireguard.conf" /etc/wireguard/protonvpn.conf
  sudo chmod 600 /etc/wireguard/protonvpn.conf
  sudo systemctl enable wg-quick@protonvpn
  echo "  VPN config installed and enabled."
else
  echo "  WARNING: config/wireguard.conf not found."
  echo "  Copy your ProtonVPN WireGuard config to config/wireguard.conf and re-run."
fi

# ── 7. Wire autostart to the clone (run-in-place) ────────────────────────────
echo "[7/8] Wiring labwc autostart to ${REPO_DIR}/kiosk/launch-kiosk.sh ..."
# Make the in-repo scripts executable (git may not preserve the bit on all setups).
chmod +x "${REPO_DIR}/kiosk/launch-kiosk.sh" \
         "${REPO_DIR}/scripts/monitor.sh" \
         "${REPO_DIR}/wifi-portal/"*.sh \
         "${REPO_DIR}/wifi-portal/mock/nmcli" 2>/dev/null || true

# Point the autostart at THIS clone (no copies in home → git pull updates all).
mkdir -p "${HOME_DIR}/.config/labwc"
sed "s|__REPO_DIR__|${REPO_DIR}|g" \
  "${REPO_DIR}/config/labwc-autostart" > "${HOME_DIR}/.config/labwc/autostart"
chmod +x "${HOME_DIR}/.config/labwc/autostart"

# ── 8. Done ───────────────────────────────────────────────────────────────────
echo "[8/8] Done!"
echo ""
echo "======================================"
echo " Setup complete."
echo ""
echo " Networking: WiFi is managed automatically — Ethernet is preferred, WiFi"
echo " is turned off when the cable is in and back on when it's out. When there's"
echo " no network, the kiosk opens a 'pikiosk-setup' hotspot for phone setup."
echo ""
echo " Next steps:"
echo "   1. (Optional) fixed IP: ip link show | grep -A1 ether"
echo "   2. Reboot: sudo reboot"
echo ""
echo " After reboot:"
echo "   sudo wg show        → VPN status"
echo "   curl ifconfig.me    → should show VPN server IP"
echo "   tail -f /tmp/kiosk.log"
echo ""
echo " Update later:  cd ${REPO_DIR} && git pull   (then reboot or restart labwc)"
echo " VNC access:    PI_IP:5900"
echo "======================================"
echo ""
