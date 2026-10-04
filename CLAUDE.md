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
| `URL_SITE` (env) | Sito mostrato dal kiosk; default BBC One iPlayer. Permanente in `~/.config/labwc/environment` (letto anche da `kiosk.sh start`); una tantum `URL_SITE=... ./scripts/kiosk.sh restart` |
| `kiosk/*-error.html` / `temp-warning.html` | Pagine di errore mostrate dal kiosk |
| `kiosk/focus-ring/` | Estensione Chromium locale: bordo di focus grande e visibile per il telecomando (`focus.css`) |
| `config/labwc-rc.xml` | Keybind labwc: Back del telecomando (`XF86Back`) → Alt+Sinistra = indietro in Chromium (via `wtype`) |
| `kiosk/ir-remote.sh` | Carica la keymap IR sul ricevitore gpio-ir (trova il device per driver, non per `rcN` fisso); girato al boot dal service `pikiosk-ir` |
| `config/ir-keymap.toml` | Scancode del telecomando (NEC) → tasti standard (`KEY_UP/…/ENTER/BACK`) |
| `config/pikiosk-ir.service` | Unit systemd che lancia `ir-remote.sh` al boot (`__REPO_DIR__` sostituito da install.sh) |
| `config/labwc-autostart` | Autostart labwc (VNC + kiosk); `__REPO_DIR__` sostituito da install.sh |
| `config/*.conf` | Config di LightDM, DRM, WireGuard |
| `scripts/monitor.sh` | Monitor live di potenza e temperatura |
| `scripts/clean-browser.sh` | Pulisce cache/cookie di Chromium (`--all` = profilo intero) e riavvia la sessione (`lightdm`) |
| `scripts/apply-remote.sh` | Applica le modifiche al telecomando senza reboot: `wtype`, restart `pikiosk-ir` (keymap), copia `labwc-rc.xml` + `pkill -HUP labwc`, riavvio kiosk (`--no-kiosk` per saltarlo) |
| `scripts/kiosk.sh` | `start/stop/restart/status` dell'app kiosk senza reboot (anche da SSH: setta le variabili Wayland); lo `stop` spegne anche portal e hotspot |
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

## Telecomando IR

> **Opt-in, disattivato di default**: `install.sh` **non** configura l'IR a meno di
> lanciarlo con `ENABLE_IR=1 ./install.sh`. Senza il flag non viene aggiunto l'overlay
> né installato il service `pikiosk-ir`. Per spegnerlo su un Pi già configurato vedi
> la sezione *Disabling the IR remote* nel README (disable del service + commento
> dell'overlay + reboot).

Il kiosk è pilotabile con un **telecomando TV a infrarossi** tramite un modulo
ricevitore IR cablato su **GPIO18** (pin fisico 12; VCC su 3.3V — **non 5V** — GND su
pin 6), **se abilitato** (`ENABLE_IR=1`). Catena, tutta **in-kernel, senza demoni**:

1. Overlay **`gpio-ir`** (`dtoverlay=gpio-ir,gpio_pin=18` in `/boot/firmware/config.txt`,
   aggiunto da `install.sh`, attivo dopo reboot) → il kernel decodifica l'IR.
2. `ir-remote.sh` (al boot, via service `pikiosk-ir`, da root) trova il device
   `gpio_ir_recv` **per nome driver** (l'indice `rcN` cambia ad ogni boot) e carica
   `config/ir-keymap.toml` con `ir-keytable -s <dev> -c -w`. Il `.toml` abilita **solo
   NEC**, così spariscono le decodifiche spurie (`imon 0x7fffffff`). Log su
   `/tmp/kiosk-ir.log`.
3. Da lì il kernel emette **eventi tasto standard** (`KEY_UP/DOWN/LEFT/RIGHT/ENTER/BACK`)
   sul device input IR; labwc li legge via libinput e li passa a Chromium.
4. Chromium è lanciato con **`--enable-spatial-navigation`**: le frecce spostano il
   focus tra link/pulsanti per posizione a schermo, OK (`ENTER`) attiva, Back
   (`KEY_BACK` → `XF86Back`) torna indietro nella cronologia (vedi punto 6).
5. Chromium carica anche l'estensione locale **`kiosk/focus-ring/`** (`--load-extension`):
   CSS iniettato in ogni pagina che rende il bordo di focus **spesso e giallo con alone
   scuro** (quello di default è troppo fine per vedere dove si è col telecomando).
   Spessore/colore in `focus.css`; si applica con `./scripts/kiosk.sh restart`.
6. **Back**: Chromium su Wayland ignora `KEY_BACK` (`XF86Back`) come "indietro", e un
   content script non lo riceve. Quindi lo gestisce **labwc**: `config/labwc-rc.xml`
   (installato **sempre** da `install.sh`, anche senza `ENABLE_IR`, in `~/.config/labwc/rc.xml`, backup
   dell'esistente in `.bak`) lega `XF86Back` a `wtype -M alt -k Left -m alt`, cioè
   **Alt+Sinistra** = indietro di Chromium. Si applica con `labwc --reconfigure`.

**Keymap specifica del telecomando**: gli scancode in `ir-keymap.toml` sono di *quel*
telecomando. Per un altro telecomando: `sudo ir-keytable -s <rcN> -c -p all -t`, premi
i tasti, annota gli scancode, aggiorna il `.toml`, poi `sudo systemctl restart pikiosk-ir`.
Il `git pull` aggiorna keymap e script (run-in-place); `./scripts/apply-remote.sh` ri-applica
keymap, azioni labwc e bordo di focus in un colpo solo.

**Diagnosi**: `pinctrl get 18` deve dare `hi` a riposo (sensore alimentato e DAT
connesso); `lo` = modulo non alimentato o DAT non cablato (spesso VCC↔DAT invertiti).
Verifica che il telecomando sia davvero IR (LED che lampeggia visto dalla fotocamera
del telefono): molti telecomandi smart-TV sono Bluetooth, non IR.

## Setup WiFi offline (`wifi-portal/` + stato `setup`)

`wifi-portal/` configura il WiFi quando il Pi è offline (VNC non serve: richiede già
la rete). **Integrato** in `launch-kiosk.sh` come stato `setup`. Testabile **in locale
col mock** senza toccare la rete vera. Componenti:

| File | Ruolo |
|---|---|
| `server.py` | Backend HTTP stdlib: `/api/scan`, `/api/connect`, `/api/status`, `/api/hotspot/info`; chiama sempre `$NMCLI`; cache scansione, **connect single-radio** (spegne l'hotspot → si connette → lo riaccende se fallisce), **logga ogni passo** su `/tmp/kiosk-portal.log`, consuma `SETUP_FLAG` al connect |
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
con `touch $SETUP_FLAG`. **Un uplink reale vince sul flag**: se c'è ethernet (o WiFi
station) `compute_state` scarta il `SETUP_FLAG` stantìo e non entra/resta in setup,
così non tieni l'hotspot acceso sopra un uplink funzionante (il caos "tre stati
insieme": ethernet + hotspot + VPN). `enter_setup()` accende il WiFi, avvia il portal, **scansiona
prima di alzare l'AP** (single-radio: la radio si occupa e la scan live torna vuota →
si serve la cache), poi `hotspot.sh up` e Chromium sulla pagina. Si esce quando torna
un uplink reale (o al connect riuscito, che rimuove `$SETUP_FLAG`) → `leave_setup()`
spegne l'hotspot. `prefer_ethernet()` **non** viene chiamata in `setup` (romperebbe l'AP).

**Connect single-radio** (in `server.py`): con una sola antenna non si può fare AP e
client insieme. Al `/api/connect` il backend **spegne l'hotspot** (`hotspot.sh down`),
riaccende la radio, `rescan`, poi si connette. Per le reti **protette** costruisce
**sempre un profilo WPA-PSK esplicito**: cancella un eventuale profilo salvato con lo
stesso nome e lo ricrea con `connection add ... wifi-sec.key-mgmt wpa-psk wifi-sec.psk`.
Perché: `nmcli dev wifi connect ... password` **riattiva un profilo preesistente**
(es. una vecchia connessione alla stessa rete) ignorando la password digitata; se
quel profilo ha un PSK vecchio/assente, NetworkManager **chiede il segreto a un
agente GUI** → è il dialog password che compare e sparisce sullo schermo del kiosk.
Ricreando il profilo con la PSK, NM non deve chiedere nulla (via anche l'errore
`key-mgmt is missing`). Se il connect fallisce **riaccende l'hotspot** per far
riprovare. Le reti **aperte** usano `dev wifi connect` senza password. Ogni passo è
loggato su `/tmp/kiosk-portal.log`. Nota: se configuri dal telefono, alla conferma
l'hotspot cade e il telefono si scollega — l'esito si vede sullo schermo HDMI del kiosk.

Da fare: captive-portal **auto-open** (DNS-hijack + bind porta 80) per aprire la pagina
sul telefono senza il secondo QR.
