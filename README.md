# pikiosk

Raspberry Pi 5 kiosk setup with VPN and remote VNC control.

## What it does

- Displays a target website in full-screen kiosk mode on HDMI
- Routes all traffic through **ProtonVPN WireGuard**
- Shows an error page if the VPN is down or temperature exceeds 80°C
- Recovers automatically when conditions are restored
- Remote control via **VNC** (TigerVNC on PC, VNC Viewer on iOS)
- SSH always available for management

## Stack

| Component | Role |
|---|---|
| Raspberry Pi OS Lite 64-bit (Trixie) | OS |
| LightDM | Display manager / autologin |
| labwc | Wayland compositor |
| wayvnc | VNC server (Wayland native) |
| Chromium | Kiosk browser |
| WireGuard / ProtonVPN | VPN |

## Architecture

```mermaid
graph TB
    subgraph hw["HARDWARE"]
        pi["🔴 Raspberry Pi 5<br/>64-bit"]
        hdmi["📺 HDMI Output"]
        sensor["🌡️ Temp Sensor"]
        eth["🔌 Ethernet"]
        wifi_hw["📶 Wi-Fi"]
    end
    
    subgraph os["OPERATING SYSTEM"]
        rpi_os["Raspberry Pi OS Lite<br/>Trixie 64-bit"]
    end
    
    subgraph display_stack["DISPLAY STACK"]
        drm["DRM/KMS<br/>fbdev emulation"]
        lightdm["LightDM<br/>Auto-login"]
        labwc["labwc<br/>Wayland"]
    end
    
    subgraph kiosk_layer["KIOSK APPLICATION"]
        checker["launch-kiosk.sh<br/>VPN + Temp Check"]
        chromium["Chromium<br/>Kiosk Mode"]
    end
    
    subgraph content["CONTENT DISPLAY"]
        site["✅ Target Site"]
        vpn_err["❌ VPN Error"]
        temp_err["🔥 Temp Warning"]
    end
    
    subgraph network["NETWORK & VPN"]
        eth_conn["Ethernet"]
        wifi_conn["Wi-Fi"]
        vpn["🔒 WireGuard<br/>ProtonVPN<br/>System-level"]
        internet["Internet"]
    end
    
    subgraph remote["REMOTE ACCESS"]
        wayvnc["wayvnc<br/>VNC Server :5900"]
        client["VNC Client<br/>PC / iOS"]
    end
    
    %% Hardware connections
    pi --> hdmi
    pi --> sensor
    pi --> eth
    pi --> wifi_hw
    
    %% Boot sequence
    rpi_os --> drm
    drm --> hdmi
    rpi_os --> lightdm
    lightdm --> labwc
    labwc --> chromium
    
    %% Kiosk logic
    sensor --> checker
    vpn --> checker
    checker --> chromium
    chromium --> site
    chromium --> vpn_err
    chromium --> temp_err
    
    %% Network flow - BOTH connections go through VPN
    eth --> eth_conn
    wifi_hw --> wifi_conn
    eth_conn --> vpn
    wifi_conn --> vpn
    vpn --> internet
    chromium --> internet
    
    %% VNC access
    labwc --> wayvnc
    wayvnc --> client
    
    %% Styling
    style hw fill:#ffebee,stroke:#c62828,stroke-width:2px
    style os fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px
    style display_stack fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    style kiosk_layer fill:#fff3e0,stroke:#e65100,stroke-width:2px
    style content fill:#fce4ec,stroke:#c2185b,stroke-width:2px
    style network fill:#e0f2f1,stroke:#00695c,stroke-width:2px
    style remote fill:#ede7f6,stroke:#512da8,stroke-width:2px
    
    style pi fill:#ffcdd2
    style chromium fill:#ffe0b2
    style vpn fill:#a5d6a7,stroke:#1b5e20,stroke-width:3px
    style eth_conn fill:#b2dfdb
    style wifi_conn fill:#b2dfdb
    style wayvnc fill:#e1bee7
```

## Folder structure

```
pikiosk/
├── README.md
├── .gitignore
├── install.sh              # Automated setup script
├── kiosk/
│   ├── launch-kiosk.sh     # VPN + temp check, launches Chromium
│   ├── vpn-error.html      # Shown when VPN is down
│   └── temp-warning.html   # Shown when temperature >= 80°C
├── config/
│   ├── labwc-autostart     # ~/.config/labwc/autostart
│   ├── lightdm-autologin.conf  # /etc/lightdm/lightdm.conf.d/
│   ├── drm.conf            # /etc/modprobe.d/drm.conf
│   └── wireguard-template.conf  # Template for /etc/wireguard/protonvpn.conf
└── scripts/
    └── monitor.sh          # Live power and temperature monitor
```

## Quick setup

1. Flash **Raspberry Pi OS Lite 64-bit** to microSD via Raspberry Pi Imager (enable SSH, set Wi-Fi).
2. SSH into the Pi and clone this repo:
   ```bash
   sudo apt install -y git
   git clone https://github.com/YOUR_USERNAME/pikiosk.git
   cd pikiosk
   ```
3. Copy your ProtonVPN WireGuard config:
   ```bash
   cp /path/to/protonvpn-uk.conf config/wireguard.conf
   ```
4. Run the installer:
   ```bash
   chmod +x install.sh
   ./install.sh
   ```
5. Reboot:
   ```bash
   sudo reboot
   ```

## Changing the target site

Edit `kiosk/launch-kiosk.sh` and update the `URL_SITE` variable at the top.

## VNC access

Connect with **TigerVNC** (PC) or **VNC Viewer** (iOS) to:
```
PI_IP:5900
```
Find the IP with `hostname -I`.

## Useful commands

```bash
# Check VPN status
sudo wg show

# Check external IP (should match VPN server)
curl ifconfig.me

# Monitor power and temperature
./scripts/monitor.sh 60

# Check temperature only
vcgencmd measure_temp

# View kiosk log
tail -f /tmp/kiosk.log

# View VNC log
tail -f /tmp/wayvnc.log

# Restart everything without reboot
pkill chromium; pkill wayvnc; pkill labwc

# Safe shutdown
sudo poweroff
```

## Temperature thresholds

| Range | Status |
|---|---|
| < 60°C | Idle / light load |
| 60–70°C | Normal under load |
| 70–80°C | Heavy load, monitor |
| ≥ 80°C | Warning page shown, content paused |

## Ethernet setup (recommended)

Using Ethernet instead of WiFi gives a more stable and secure connection.

**Find the Ethernet MAC address:**
```bash
ip link show eth0 | grep ether
```

**Assign a fixed IP in your router** (e.g. Fritz!Box):
1. Open `http://fritz.box`
2. Go to **Home Network → Network**
3. Find `pikiosk` by MAC address
4. Enable **"Always assign this network device the same IPv4 address"**
5. Save

**Disable WiFi permanently** (persists across reboots):
```bash
sudo nmcli radio wifi off
```

**Re-enable WiFi if needed:**
```bash
sudo nmcli radio wifi on
```

**Check radio status:**
```bash
nmcli radio
```

## Notes

- The WireGuard config file (`config/wireguard.conf`) is excluded from git via `.gitignore` — never commit VPN credentials.
- If the VPN IP gets blocked, download a different server config from ProtonVPN and replace `/etc/wireguard/protonvpn.conf`.
- WiFi credentials with special characters (e.g. `!`) must be passed with single quotes in `nmcli`.
