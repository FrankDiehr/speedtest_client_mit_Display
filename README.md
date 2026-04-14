# Speedtest Client mit Display

Ein robuster Speedtest- und Monitoring-Client für Raspberry Pi und andere kleine Linux-Systeme.

Der Client sammelt Netzwerk-, DNS-, Hardware-, Traceroute- und LibreSpeed-Messdaten lokal als CSV-Dateien und sendet sie asynchron an eine zentrale API. Zusätzlich steuert ein Python-Display-Daemon ein SSD1306-OLED, eine Status-LED und einen Taster.

## Funktionen

- kontinuierlicher Ping-Loop
- periodische DNS-Checks
- periodische Hardware-Metriken
- periodische LibreSpeed-Speedtests mit Server-Fallback
- periodische Traceroute-Messungen
- lokaler CSV-Spool für kurzzeitige Ausfälle
- automatischer Versand zur zentralen API
- automatische Bereinigung alter Spool-Dateien
- Watchdog für einfache Selbstheilung
- OLED-Display mit letztem Speedtest und Countdown bis zum nächsten Test
- LED leuchtet während eines laufenden Speedtests
- Taster zum Ein- und Ausschalten des Displays
- automatischer Darkmode des Displays nach Inaktivität
- erster Speedtest nach Boot mit eigenem Countdown
- Cron-basierter Betrieb, Display nur für die Hardwarelogik in Python

## Display-Funktionen

Das OLED zeigt im Normalbetrieb:

- Zeitstempel des letzten Speedtests
- Download in Mbit/s
- Upload in Mbit/s
- Ping und Jitter
- Countdown bis zum nächsten Test

Zusätzlich gilt:

- nach dem Boot wird zunächst der Startbildschirm für den ersten Test angezeigt
- solange nach dem Boot noch kein neuer Speedtest gelaufen ist, wird der Countdown bis zum ersten Speedtest angezeigt
- während eines laufenden Speedtests leuchtet die LED
- nach 3 Minuten ohne Tastendruck wird das Display ausgeschaltet
- beim Ausschalten erscheint kurz `Enter darkmode`
- per Taster kann das Display jederzeit wieder eingeschaltet werden

## Projektstruktur

```text
/opt/speedmon/
├── bin/                  # ausführbare Skripte
├── etc/                  # Konfiguration
├── lib/                  # gemeinsame Hilfsfunktionen
├── spool/
│   ├── pending/          # noch nicht gesendete CSV-Dateien
│   ├── sent/             # erfolgreich gesendete CSV-Dateien
│   └── failed/           # fehlgeschlagene/abgelegte CSV-Dateien
├── log/                  # Logs
├── run/                  # Lock- und State-Dateien
└── tmp/                  # temporäre Dateien
```

## Messarten

### Ping

`collect-ping.sh` läuft als Dauerprozess und schreibt fortlaufend Ping-Ergebnisse in minutenweise CSV-Dateien.

Typische Felder:

- Status
- Latenz in Millisekunden
- Paketverlust in Prozent
- Public IP
- LAN-IP(s)
- Default Interface

### DNS

`collect-dns.sh` testet konfigurierte DNS-Server und Hostnamen.

Typische Felder:

- DNS-Server
- Query-Name
- Status
- Query-Zeit in Millisekunden
- Antwort-IP(s)

### Hardware

`collect-hardware.sh` sammelt Systemmetriken.

Typische Felder:

- Load Average
- CPU-Auslastung
- CPU-Temperatur
- RAM-Nutzung
- Root-Dateisystem
- Uptime
- Interface-Statistiken
- Prozessanzahl
- TCP-Verbindungen

### Speedtest

`run-speedtest.sh` führt periodisch LibreSpeed-Tests gegen definierte Server aus.

Typische Felder:

- Download
- Upload
- Ping
- Jitter
- gewählter Testserver
- Raw JSON des Ergebnisses

### Traceroute

`collect-traceroute.sh` führt Traceroute-Messungen zum konfigurierten Ziel durch.

## Voraussetzungen

- Raspberry Pi oder anderes Linux-System
- Bash
- Cron
- jq
- curl
- Python 3
- I2C aktiviert, wenn das OLED genutzt wird
- SSD1306 OLED an I2C
- LED und Taster gemäß eigener Verdrahtung

## Download

### Repository klonen

```bash
git clone https://github.com/FrankDiehr/speedtest_client_mit_Display.git /opt/speedmon
cd /opt/speedmon
```

### Alternativ als ZIP herunterladen

- Auf GitHub das Repository öffnen
- `Code` anklicken
- `Download ZIP` wählen
- nach `/opt/speedmon` entpacken

## Installation

### 1. Abhängigkeiten installieren

```bash
cd /opt/speedmon
sudo /opt/speedmon/bin/install-deps.sh
```

Das Skript installiert unter anderem:

- Git-Basiswerkzeuge und Netzwerktools
- Python 3 und benötigte Python-Pakete
- `librespeed-cli`
- I2C-Hilfstools

### 2. Secret-Datei anlegen

Die API-Zugangsdaten liegen bewusst außerhalb des Projektverzeichnisses.

```bash
sudo mkdir -p /etc/speedmon
sudo nano /etc/speedmon/secret.env
```

Beispiel:

```bash
API_TOKEN="dein_api_token"
```

### 3. Konfiguration anpassen

Die Hauptkonfiguration liegt in:

```bash
/opt/speedmon/etc/config.sh
```

Wichtige Werte:

```bash
CLIENT_ID="${CLIENT_ID:-$(hostname -s 2>/dev/null || echo speedmon-unknown)}"
SITE_NAME="speedlens"

NETWORK_INTERFACE="eth0"
PING_TARGET_PRIMARY="1.1.1.1"
PING_TARGET_SECONDARY="8.8.8.8"

API_BASE_URL="https://dein-server.example/api/v1"

DNS_CHECK_INTERVAL_MIN="5"
HARDWARE_INTERVAL_MIN="2"
SPEEDTEST_INTERVAL_MIN="10"
TRACEROUTE_INTERVAL_MIN="60"
WATCHDOG_INTERVAL_MIN="5"
DELIVERY_INTERVAL_SEC="120"

FIRST_SPEEDTEST_DELAY_SEC="40"
```

Hinweis:

- `SPEEDTEST_INTERVAL_MIN` ist der normale Dauertakt
- `FIRST_SPEEDTEST_DELAY_SEC` steuert nur den Countdown bis zum ersten Test nach dem Boot
- der eigentliche Reboot-Speedtest wird zusätzlich über Cron mit einem kurzen `sleep` gestartet

### 4. Hostname optional setzen

Da `CLIENT_ID` standardmäßig vom kurzen Hostnamen kommt, ist ein sauber gesetzter Hostname sinnvoll.

```bash
sudo hostnamectl set-hostname standort-berlin-01
```

### 5. Projekt installieren

```bash
sudo /opt/speedmon/bin/install.sh
```

Das Skript:

- legt die Laufzeitstruktur unter `/opt/speedmon` an
- setzt die nötigen Rechte
- installiert die Cronjobs
- installiert und aktiviert den Display-Service

### 6. Reboot

```bash
sudo reboot
```

## Cron und Boot-Verhalten

Die Datei `/etc/cron.d/speedmon` wird von `bin/install-cron.sh` erzeugt.

Wichtige Punkte:

- `collect-ping.sh` startet per `@reboot` und läuft dauerhaft
- beim Boot werden zuerst alte CSV-Dateien in `spool/pending` gelöscht, damit keine beschädigten Altlasten gesendet werden
- der erste Speedtest nach dem Boot startet mit kurzem Puffer per `sleep`, damit Display und restliches System sauber oben sind
- der normale periodische Speedtest läuft zusätzlich nach `SPEEDTEST_INTERVAL_MIN`

## Display-Service

Der Display-Daemon läuft als systemd-Service:

- Service-Datei: `/etc/systemd/system/speedmon-display.service`
- Hauptskript: `/opt/speedmon/bin/display-daemon.py`

Nützliche Befehle:

```bash
systemctl status speedmon-display.service --no-pager
systemctl restart speedmon-display.service
journalctl -u speedmon-display.service -n 50 --no-pager
```

## Manuelle Tests

### Display-State initialisieren

```bash
/opt/speedmon/bin/update-display-state.sh init
```

### Speedtest manuell starten

```bash
/opt/speedmon/bin/run-speedtest.sh
```

### Boot-Speedtest-Wrapper manuell testen

```bash
/opt/speedmon/bin/run-speedtest-after-boot.sh
```

## Git

Laufzeitdaten wie `spool/`, `tmp/`, `run/` und `log/` sind nicht für Git gedacht und sollten per `.gitignore` ausgeschlossen bleiben.

Typischer Ablauf:

```bash
git add .
git commit -m "Update speedtest client with display"
git push
```

## Bekannte Hinweise

- Git speichert keine leeren Ordner. Das ist hier unkritisch, weil `install.sh` die benötigten Ordner automatisch anlegt.
- Das OLED-Layout ist auf ein SSD1306 mit 128x64 Pixeln ausgelegt.
- Die Server-Fallback-Logik arbeitet nur dann sauber, wenn `librespeed-cli` selbst korrekt installiert ist.
- Wenn der erste Speedtest nach dem Boot zu früh oder zu spät wirkt, kann der Reboot-`sleep` in `install-cron.sh` angepasst werden.

## Lizenz

Der Projektstand ist aktuell für den Eigengebrauch dokumentiert. Eine explizite Lizenzdatei ist derzeit nicht enthalten.
