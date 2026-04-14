# SpeedMon Client

Ein leichter Bash-basierter Monitoring-Client für unbeaufsichtigte Sonden.  
Der Client sammelt Netzwerk-, DNS-, Hardware-, Traceroute- und LibreSpeed-Messdaten lokal als CSV-Dateien und liefert sie asynchron an eine zentrale API aus.

Ziel des Projekts ist ein robuster Betrieb auf kleinen Linux-Systemen wie Raspberry Pi, Mini-PCs oder VMs, auch bei instabilen Internetanschlüssen.

---

## Funktionen

- kontinuierlicher Ping-Loop
- periodische DNS-Checks
- periodische Hardware-Metriken
- periodische LibreSpeed-Speedtests
- periodische Traceroute-Messungen
- lokaler CSV-Spool für kurzzeitige Ausfälle
- automatischer Versand zur zentralen API
- automatische Bereinigung alter Spool-Dateien
- Watchdog für einfache Selbstheilung
- Cron-basierter Betrieb ohne zusätzliche Daemons

---

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

---

## Funktionsweise

Die Collector-Skripte schreiben Messdaten zunächst lokal in CSV-Dateien nach `spool/pending/...`.

Das Versandskript `send-spool.sh` versucht diese Daten periodisch an die API zu übertragen:

- bei Erfolg wandert die Datei nach `spool/sent/...`
- bei Fehler verbleibt sie zunächst in `pending/...` und wird später erneut versucht
- alte Dateien werden automatisch nach konfigurierter Retention gelöscht

Damit puffert der Client kurze Internet- oder API-Ausfälle lokal ab.

---

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

---

## Installation

### 1. Projekt kopieren

```bash
sudo mkdir -p /opt/speedmon
sudo cp -r . /opt/speedmon
cd /opt/speedmon
```

### 2. Secret-Datei anlegen

Die API-Zugangsdaten liegen bewusst außerhalb des Projektverzeichnisses.

Datei anlegen:

```bash
sudo mkdir -p /etc/speedmon
sudo nano /etc/speedmon/secret.env
```

Beispielinhalt:

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

PENDING_RETENTION_HOURS="12"
SENT_RETENTION_HOURS="2"
FAILED_RETENTION_HOURS="12"
TMP_RETENTION_HOURS="6"

DNS_CHECK_INTERVAL_MIN="5"
HARDWARE_INTERVAL_MIN="2"
SPEEDTEST_INTERVAL_MIN="10"
TRACEROUTE_INTERVAL_MIN="60"
WATCHDOG_INTERVAL_MIN="5"
DELIVERY_INTERVAL_SEC="120"
```

### 4. Optional: Hostname setzen

Da `CLIENT_ID` standardmäßig vom kurzen Hostnamen kommt, ist ein sauber gesetzter Hostname wichtig.

Beispiel:

```bash
sudo hostnamectl set-hostname standort-berlin-01
```

Damit wird der Client später in Influx/Grafana unter diesem Namen sichtbar.

### 5. Rechte setzen

Typischerweise genügt:

```bash
chmod 755 /opt/speedmon/bin/*.sh
chmod 644 /opt/speedmon/lib/common.sh
chmod 644 /opt/speedmon/etc/config.sh
```

### 6. Cronjobs installieren

```bash
/opt/speedmon/bin/install-cron.sh
```

Die Cronjobs werden aus den Werten in `etc/config.sh` erzeugt.

Wichtig:
- `collect-ping.sh` startet per `@reboot` und läuft dauerhaft
- `collect-hardware.sh` hat ein eigenes Intervall über `HARDWARE_INTERVAL_MIN`
- `run-speedtest.sh` läuft unabhängig davon in seinem eigenen Takt

### 7. Optional: Neustart

```bash
sudo reboot
```

Das ist oft der einfachste Weg, um sicherzustellen, dass `@reboot`-Jobs und Konfigurationsänderungen sauber aktiv sind.

---

## Konfiguration im Überblick

### Identität

- `CLIENT_ID`: technische Kennung des Clients  
  Standard: kurzer Hostname
- `SITE_NAME`: lesbarer Standortname

### Netzwerk

- `NETWORK_INTERFACE`: bevorzugtes Interface
- `PING_TARGET_PRIMARY`: primäres Ping-Ziel
- `PING_TARGET_SECONDARY`: aktuell in der Config vorhanden, aber noch kein aktiver automatischer Fallback im Ping-Collector
- `DNS_TEST_HOSTS`: Hostnamen für DNS-Checks
- `DNS_SERVERS`: DNS-Server für DNS-Checks
- `TRACEROUTE_TARGET`: Ziel für Traceroute
- `PUBLIC_IP_URLS`: Dienste zur Ermittlung der Public IP

### LibreSpeed

- `LIBRESPEED_CLI_BIN`: Pfad zum LibreSpeed-CLI-Binary
- `LIBRESPEED_SERVER_JSON`: Serverliste
- `LIBRESPEED_TIMEOUT_SEC`: Timeout des Speedtests
- `LIBRESPEED_EXTRA_ARGS`: zusätzliche CLI-Parameter

### API / Versand

- `API_BASE_URL`: Basis-URL der API
- `API_CONNECT_TIMEOUT_SEC`: Timeout für Verbindungsaufbau
- `API_MAX_TIME_SEC`: maximale Request-Dauer
- `DELIVERY_BATCH_SIZE`: wie viele Dateien pro Lauf gesendet werden
- `DELIVERY_INTERVAL_SEC`: Versandintervall

### Retention / Cleanup

```bash
PENDING_RETENTION_HOURS="12"
SENT_RETENTION_HOURS="2"
FAILED_RETENTION_HOURS="12"
TMP_RETENTION_HOURS="6"

MAX_PENDING_FILES_PER_METRIC="5000"
MAX_SENT_FILES_PER_METRIC="2000"
MAX_FAILED_FILES_PER_METRIC="2000"
```

Bedeutung:

- `pending`: lokaler Kurzzeitpuffer für noch nicht gesendete Daten
- `sent`: kurzer Nachweis erfolgreich gesendeter Dateien
- `failed`: kurzzeitige Ablage fehlerhafter Dateien
- `tmp`: temporäre Dateien
- `MAX_*`: zusätzliche Sicherheitsgrenzen gegen Dateimüll

### Scheduling

```bash
PING_LOOP_INTERVAL_SEC="1"
DNS_CHECK_INTERVAL_MIN="5"
HARDWARE_INTERVAL_MIN="2"
SPEEDTEST_INTERVAL_MIN="10"
TRACEROUTE_INTERVAL_MIN="60"
WATCHDOG_INTERVAL_MIN="5"
DELIVERY_INTERVAL_SEC="120"
```

Bedeutung:

- `PING_LOOP_INTERVAL_SEC`: Ping-Messung im Dauerloop
- `DNS_CHECK_INTERVAL_MIN`: DNS-Checks per Cron
- `HARDWARE_INTERVAL_MIN`: Hardware-Metriken per Cron
- `SPEEDTEST_INTERVAL_MIN`: Speedtests per Cron
- `TRACEROUTE_INTERVAL_MIN`: Traceroute per Cron
- `WATCHDOG_INTERVAL_MIN`: Watchdog-Lauf per Cron
- `DELIVERY_INTERVAL_SEC`: Versandintervall für Spool-Daten

---

## Wichtige Skripte

### `bin/collect-ping.sh`
Dauerlaufender Ping-Collector. Startet per `@reboot`.

### `bin/collect-dns.sh`
Schreibt DNS-Messdaten als CSV in den Spool.

### `bin/collect-hardware.sh`
Schreibt Hardware-/Systemmetriken in den Spool.

### `bin/run-speedtest.sh`
Führt LibreSpeed-Speedtests aus und schreibt das Ergebnis in den Spool.

### `bin/collect-traceroute.sh`
Erzeugt periodische Traceroute-Ergebnisse.

### `bin/send-spool.sh`
Versendet CSV-Dateien aus `spool/pending` an die API und räumt alte Dateien auf.

### `bin/watchdog.sh`
Überwacht zentrale Zustände und kann Selbstheilungsmaßnahmen anstoßen.

### `bin/install-cron.sh`
Erzeugt `/etc/cron.d/speedmon` auf Basis der Konfiguration.

---

## Logs

Typische Logdateien:

```text
/opt/speedmon/log/speedmon.log
/opt/speedmon/log/ping-loop.log
/opt/speedmon/log/cron.log
/opt/speedmon/log/send-spool.log
```

Zum Beobachten:

```bash
tail -f /opt/speedmon/log/speedmon.log
tail -f /opt/speedmon/log/ping-loop.log
tail -f /opt/speedmon/log/cron.log
```

---

## Manuelle Tests

### Syntax prüfen

```bash
bash -n /opt/speedmon/bin/collect-ping.sh
bash -n /opt/speedmon/bin/collect-dns.sh
bash -n /opt/speedmon/bin/collect-hardware.sh
bash -n /opt/speedmon/bin/run-speedtest.sh
bash -n /opt/speedmon/bin/send-spool.sh
bash -n /opt/speedmon/bin/watchdog.sh
```

### Einzelne Collector manuell starten

```bash
/opt/speedmon/bin/collect-dns.sh
/opt/speedmon/bin/collect-hardware.sh
/opt/speedmon/bin/run-speedtest.sh
/opt/speedmon/bin/collect-traceroute.sh
/opt/speedmon/bin/send-spool.sh
```

### Ping-Prozess prüfen

```bash
pgrep -af collect-ping.sh
tail -n 20 /opt/speedmon/log/ping-loop.log
```

---

## Spool-Verhalten

Die Sonde ist bewusst so gebaut, dass sie kurze Störungen puffern kann.

Typischer Ablauf:

1. Collector erzeugt CSV-Datei in `spool/pending/...`
2. `send-spool.sh` versucht die Zustellung
3. bei Erfolg wird die Datei nach `spool/sent/...` verschoben
4. bei Fehler bleibt sie zunächst in `pending/...`
5. alte Dateien werden automatisch durch Retention entfernt

Dadurch ist der Client robust gegen:
- kurze API-Ausfälle
- kurze Internet-Ausfälle
- temporäre DNS-/Routing-Probleme

Nicht das Ziel ist:
- lokale Langzeitarchivierung
- vollständige Offline-Historie über viele Tage

---

## Standortwechsel / Neuaufbau

Der Client puffert Daten nur für die konfigurierten Retention-Zeiten.

Wenn eine Sonde länger als `PENDING_RETENTION_HOURS` nicht läuft oder nicht senden kann, werden alte lokale CSV-Dateien automatisch verworfen. Dadurch ist bei einem Standortwechsel nach mehr als 12 Stunden typischerweise kein zusätzlicher lokaler Eingriff nötig.

Wichtig:
- lokal alte Spool-Daten werden nach Retention verworfen
- bereits auf dem Server gespeicherte Daten bleiben erhalten, bis sie dort gelöscht werden

---

## InfluxDB: Daten löschen

### Gesamten Bucket löschen

**Achtung:** löscht alle Daten aller Clients im Bucket.

```bash
docker exec -it speedlens-influxdb influx delete   --bucket speedtests   --start '1970-01-01T00:00:00Z'   --stop "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
```

### Einen einzelnen Client löschen

Beispiel für `client_id="standort-berlin-01"`:

```bash
docker exec -it speedlens-influxdb influx delete   --bucket speedtests   --start '1970-01-01T00:00:00Z'   --stop "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"   --predicate 'client_id="standort-berlin-01"'
```

### Nur ein Measurement eines Clients löschen

```bash
docker exec -it speedlens-influxdb influx delete   --bucket speedtests   --start '1970-01-01T00:00:00Z'   --stop "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"   --predicate '_measurement="hardware_metrics" AND client_id="standort-berlin-01"'
```

---

## Mehrere Clients / mehrere Standorte

Für mehrere Standorte empfiehlt sich:

- pro Sonde ein eindeutiger Hostname
- dadurch automatisch eindeutige `CLIENT_ID`
- pro Standort ein eigenes Grafana-Dashboard
- Queries im Dashboard fest auf den jeweiligen `client_id`

Beispiel:

```flux
from(bucket: "speedtests")
  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)
  |> filter(fn: (r) => r._measurement == "hardware_metrics")
  |> filter(fn: (r) => r.client_id == "standort-berlin-01")
  |> filter(fn: (r) => r._field == "cpu_temp_c")
  |> aggregateWindow(every: v.windowPeriod, fn: mean, createEmpty: false)
```

Diese Struktur ist besonders praktisch, wenn später Benutzer nur ihr jeweiliges Standort-Dashboard sehen sollen.

---

## Bekannte Besonderheiten

- `PING_TARGET_SECONDARY` ist aktuell dokumentiert und konfigurierbar, aber noch kein automatischer Fallback im Ping-Collector
- `CLIENT_ID` ist standardmäßig der kurze Hostname
- der Client ist absichtlich Bash-basiert und simpel gehalten
- alte CSV-Dateien werden nicht archiviert, sondern nach Retention verworfen

---

## Typische Wartungsbefehle

### Alten lokalen Spool leeren

```bash
find /opt/speedmon/spool/pending -type f -delete
find /opt/speedmon/spool/failed -type f -delete
find /opt/speedmon/spool/sent -type f -delete
find /opt/speedmon/tmp -type f -delete
```

### Cron-Datei prüfen

```bash
cat /etc/cron.d/speedmon
```

### Prüfen, ob der Ping-Loop läuft

```bash
pgrep -af collect-ping.sh
```

### Hardware-Collector einmal manuell starten

```bash
/opt/speedmon/bin/collect-hardware.sh
```

---

## Zielgruppe / Einsatz

Dieses Projekt ist gedacht für:

- stationäre Mess-Sonden
- unbeaufsichtigte Clients
- WAN-/Internet-Monitoring
- kleine Linux-Systeme
- zentrale Visualisierung via InfluxDB + Grafana

Nicht gedacht ist es als:

- lokales Langzeitarchiv
- hochkomplexe Agent-Plattform
- vollautomatische Standorterkennung

---

## Lizenz / Hinweise

Projektinternes Monitoring-Werkzeug.  
Vor produktivem Rollout sollten Konfiguration, API-Zugangsdaten, Hostnamen und Cron-Takte pro Standort sauber geprüft werden.
