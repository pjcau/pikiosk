#!/usr/bin/env bash
# install.sh — Automated pikiosk setup for Raspberry Pi 5
# Run as normal user (not root). Uses sudo where needed.

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
USER_NAME="$(whoami)"
HOME_DIR="/home/${USER_NAME}"

echo "======================================"
echo " pikiosk installer"
echo " User: ${USER_NAME}"
echo " Home: ${HOME_DIR}"
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
  git curl

# ── 3. User groups ────────────────────────────────────────────────────────────
echo "[3/8] Adding user to groups..."
sudo usermod -aG video,render,input "${USER_NAME}"

# ── 4. fbdev emulation (needed for Pi 5 KMS) ─────────────────────────────────
echo "[4/8] Configuring DRM fbdev emulation..."
sudo cp "${REPO_DIR}/config/drm.conf" /etc/modprobe.d/drm.conf

# ── 5. LightDM autologin ─────────────────────────────────────────────────────
echo "[5/8] Configuring LightDM autologin..."
sudo mkdir -p /etc/lightdm/lightdm.conf.d

# Replace placeholder with actual username
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

# ── 7. Kiosk files ───────────────────────────────────────────────────────────
echo "[7/8] Installing kiosk files..."

# Replace placeholder username in launch-kiosk.sh
sed "s|/home/pjcau|${HOME_DIR}|g" \
  "${REPO_DIR}/kiosk/launch-kiosk.sh" > "${HOME_DIR}/launch-kiosk.sh"
chmod +x "${HOME_DIR}/launch-kiosk.sh"

# Error pages
cp "${REPO_DIR}/kiosk/vpn-error.html"   "${HOME_DIR}/vpn-error.html"
cp "${REPO_DIR}/kiosk/temp-warning.html" "${HOME_DIR}/temp-warning.html"

# Monitor script
cp "${REPO_DIR}/scripts/monitor.sh" "${HOME_DIR}/monitor.sh"
chmod +x "${HOME_DIR}/monitor.sh"

# labwc autostart
mkdir -p "${HOME_DIR}/.config/labwc"
sed "s|/home/pjcau|${HOME_DIR}|g" \
  "${REPO_DIR}/config/labwc-autostart" > "${HOME_DIR}/.config/labwc/autostart"
chmod +x "${HOME_DIR}/.config/labwc/autostart"

# ── 8. Disable WiFi (use Ethernet only) ──────────────────────────────────────
echo "[8/9] Disabling WiFi (Ethernet only)..."
sudo nmcli radio wifi off
echo "  WiFi disabled. Find Ethernet MAC with: ip link show eth0 | grep ether"
echo "  Assign a fixed IP in your router using that MAC address."

# ── 9. Done ───────────────────────────────────────────────────────────────────
echo "[9/9] Done!"
echo ""
echo "======================================"
echo " Setup complete. Next steps:"
echo ""
echo " 1. Find Ethernet MAC: ip link show eth0 | grep ether"
echo " 2. Assign fixed IP in your router using that MAC"
echo " 3. Reboot: sudo reboot"
echo ""
echo " After reboot:"
echo "   sudo wg show        → VPN status"
echo "   curl ifconfig.me    → should show VPN server IP"
echo ""
echo " VNC access: PI_IP:5900"
echo "======================================"
echo ""

