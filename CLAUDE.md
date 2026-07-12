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
| `install.sh` | Setup (run-in-place): installa solo i file `/etc` e aggancia l'autostart al clone |
| `kiosk/launch-kiosk.sh` | Macchina a stati (`temp`>`setup`>`recon`>`vpn`>`ok`): VPN, temperatura, audio HDMI 100%, preferenza ethernet, avvio portal WiFi |
| `kiosk/*-error.html` / `temp-warning.html` | Pagine di errore mostrate dal kiosk |
| `config/labwc-autostart` | Autostart labwc (VNC + kiosk); `__REPO_DIR__` sostituito da install.sh |
| `config/*.conf` | Config di LightDM, DRM, WireGuard |
| `scripts/monitor.sh` | Monitor live di potenza e temperatura |
| `wifi-portal/` | Setup WiFi offline (hotspot + pagina) — vedi sezione dedicata |

> **Struttura a cartelle** (`kiosk/ config/ scripts/ wifi-portal/`): repo, README e
> install.sh combaciano. **Run-in-place**: gli script girano direttamente dal clone,
> `git pull` aggiorna tutto (niente copie in `/home/...`). `launch-kiosk.sh` è
> auto-locante (`SCRIPT_DIR`/`REPO_DIR`), niente path hardcoded.

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

## Stato `recon` (riconnessione) vs `vpn` (errore reale)

Durante un cambio rete (es. stacchi il cavo e il WiFi si sta associando) la VPN
cade per pochi secondi. Per non mostrare l'errore VPN rosso in quel buco, c'è lo
stato **`recon`** (`kiosk/reconnecting.html`, pagina neutra "Riconnessione in
corso"): si mostra quando manca l'uplink entro il debounce **oppure** quando la VPN
è giù da poco (contatore `VPN_DOWN_COUNT < VPN_GRACE`, ~fino a 60s con rete stabile).
Solo se la VPN resta giù **con uplink stabile** oltre la grace si passa a `vpn`
(errore reale, es. IP ProtonVPN bloccato). `update_counters()` mantiene i contatori.

## Setup WiFi offline (`wifi-portal/` + stato `setup`)

`wifi-portal/` configura il WiFi quando il Pi è offline (VNC non serve: richiede già
la rete). **Integrato** in `launch-kiosk.sh` come stato `setup`. Testabile **in locale
col mock** senza toccare la rete vera. Componenti:

| File | Ruolo |
|---|---|
| `server.py` | Backend HTTP stdlib: `/api/scan`, `/api/connect`, `/api/status`, `/api/hotspot/info`; chiama sempre `$NMCLI`; cache scansione + consuma `SETUP_FLAG` al connect |
| `wifi-setup.html` | Pagina: QR di join hotspot + QR "apri pagina" + lista WiFi interattiva (QR nascosti sul telefono) |
| `hotspot.sh` | `up`/`down`/`status` dell'hotspot di setup `pikiosk-setup` |
| `net-prefer.sh` | Versione standalone testabile della logica ethernet→WiFi (stessa di `prefer_ethernet()`) |
| `portal.conf` | SSID/password hotspot, gateway, porta, timeout (60s), `SETUP_FLAG`, cache |
| `mock/nmcli` | `nmcli` finto: reti/connect/hotspot/ethernet/radio simulati; comando extra `mock-eth up|down` |
| `run-local.sh` | Avvia il portal in locale col mock, sceglie una porta libera |
| `vendor/qrcode.js` | Libreria QR (Kazuhiko Arase) per i QR |

Regola invariata: `$NMCLI` punta al mock in locale, a `nmcli` vero sul Pi — stesso
codice ovunque.

**Flusso stato `setup`** (in `launch-kiosk.sh`): si entra quando manca l'uplink
fisico per ~60s (`have_network` = ethernet o WiFi *station*, non l'hotspot) **oppure**
con `touch $SETUP_FLAG`. `enter_setup()` accende il WiFi, avvia il portal, **scansiona
prima di alzare l'AP** (single-radio: la radio si occupa e la scan live torna vuota →
si serve la cache), poi `hotspot.sh up` e Chromium sulla pagina. Si esce quando torna
un uplink reale (o al connect riuscito, che rimuove `$SETUP_FLAG`) → `leave_setup()`
spegne l'hotspot. `prefer_ethernet()` **non** viene chiamata in `setup` (romperebbe l'AP).

Da fare: captive-portal **auto-open** (DNS-hijack + bind porta 80) per aprire la pagina
sul telefono senza il secondo QR.
