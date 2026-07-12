# CLAUDE.md

Guida per lavorare su questo repo. Per il contesto completo del progetto (cosa fa,
stack, architettura, setup, comandi utili) **fai riferimento sempre al [README.md](./README.md)**:
è la fonte di verità e va tenuto sincronizzato.

## Cos'è pikiosk

Kiosk su **Raspberry Pi 5**: mostra un sito in full-screen su HDMI, instrada tutto
il traffico via **ProtonVPN/WireGuard**, mostra pagine di errore se la VPN è giù o la
temperatura ≥ 80°C, ed è controllabile da remoto via **VNC**. Dettagli nel README.

## File principali

| File | Ruolo |
|---|---|
| `install.sh` | Setup automatico |
| `launch-kiosk.sh` | Loop VPN + temperatura, avvia Chromium, forza audio HDMI a 100%, preferisce l'ethernet (spegne/accende il WiFi) |
| `labwc-autostart` | Autostart della sessione labwc (VNC + kiosk) |
| `monitor.sh` | Monitor live di potenza e temperatura |
| `*-error.html` / `temp-warning.html` | Pagine di errore mostrate dal kiosk |
| `*.conf` | Config di LightDM, DRM, WireGuard |

> Nota: i path nel repo sono flat (root), mentre il README descrive una struttura a
> cartelle (`kiosk/`, `config/`, `scripts/`). Gli script deployati usano `/home/pjcau/...`.

## Convenzioni di lavoro (IMPORTANTI)

1. **Microcommit**: ogni intervento va spezzato in commit piccoli e atomici, uno per
   cambiamento logico. Niente commit "calderone". Messaggi chiari e imperativi.
2. **Documentazione sempre aggiornata**: ad ogni lavoro aggiorna la doc rilevante nello
   **stesso set di microcommit** del codice (README.md e/o questo CLAUDE.md). Un cambiamento
   di comportamento senza aggiornamento della doc è considerato incompleto.
3. **ID PipeWire/wpctl non hardcodati**: sul Pi gli ID dei nodi audio cambiano ad ogni
   riavvio. Cerca i sink **per nome** (es. `hdmi`), mai per ID numerico fisso.
4. **Segreti fuori dal git**: la config WireGuard non va mai committata (vedi `.gitignore`).

## Audio HDMI

`launch-kiosk.sh` contiene `set_hdmi_volume()`: trova il sink il cui `node.name`
contiene `hdmi`, lo porta a `1.0` (100%) e lo de-muta. Viene richiamata all'avvio e nel
loop di controllo (ogni 30s), così l'audio HDMI resta a 100% dopo ogni riavvio e anche
dopo riconnessioni o cambi di profilo. Log in `/tmp/kiosk.log`.

## Rete: preferenza ethernet

`launch-kiosk.sh` contiene `prefer_ethernet()`: se l'ethernet è connessa spegne il
WiFi (`nmcli radio wifi off`), altrimenti lo riaccende (`nmcli radio wifi on`).
Richiamata all'avvio e nel loop (ogni 30s). Il match è sul **tipo** di device
(`ethernet:connected` in `nmcli device status`), non sul nome (`eth0`/`end0`), e il
WiFi viene spento **solo** se l'ethernet è davvero connessa. Se colleghi il cavo
mentre sei su WiFi funzionante, il WiFi viene comunque staccato (ethernet ha priorità).

## Prototipo wifi-portal (in sviluppo)

`wifi-portal/` è il prototipo per configurare il WiFi quando il Pi è offline (VNC non
serve: richiede già la rete). Testabile **in locale col mock** senza toccare la rete
vera. Componenti:

| File | Ruolo |
|---|---|
| `server.py` | Backend HTTP stdlib: `/api/scan`, `/api/connect`, `/api/status`, `/api/hotspot/info`; chiama sempre `$NMCLI` |
| `wifi-setup.html` | Pagina: QR di auto-join hotspot + lista WiFi interattiva (QR nascosto sul telefono) |
| `hotspot.sh` | `up`/`down`/`status` dell'hotspot di setup `pikiosk-setup` |
| `net-prefer.sh` | Versione standalone testabile della logica ethernet→WiFi (stessa di `prefer_ethernet()`) |
| `portal.conf` | SSID/password hotspot, porta, timeout setup (60s) |
| `mock/nmcli` | `nmcli` finto: reti/connect/hotspot/ethernet simulati; comando extra `mock-eth up|down` |
| `run-local.sh` | Avvia il portal in locale col mock, sceglie una porta libera |
| `vendor/qrcode.js` | Libreria QR (Kazuhiko Arase) per il QR di auto-join |

Regola invariata: `$NMCLI` punta al mock in locale, a `nmcli` vero sul Pi — stesso
codice ovunque. Non ancora integrato nel flusso `launch-kiosk.sh` (stato `setup`).
