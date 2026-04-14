# Speedtest Client mit Display

Ein Raspberry-Pi-basierter LibreSpeed-Client mit OLED-Display, Status-LED und Taster.

Der Client führt automatisch Speedtests aus, sammelt weitere Messdaten und legt die Ergebnisse lokal im Spool ab, damit sie anschließend an einen Server übertragen werden können.

Zusätzlich zeigt ein OLED-Display den letzten Speedtest, den Countdown bis zum nächsten Test und den Status beim Systemstart an.

---

## Funktionen

- automatischer LibreSpeed-Speedtest per Bash
- Fallback auf mehrere Speedtest-Server
- OLED-Anzeige für:
  - letzten Speedtest
  - Download
  - Upload
  - Ping
  - Jitter
  - Countdown bis zum nächsten Test
  - Startanzeige bis zum ersten Test nach dem Boot
- Status-LED:
  - leuchtet während eines laufenden Speedtests
- Tastersteuerung:
  - Display ein/aus
  - automatischer Darkmode nach Inaktivität
- zusätzliche Messungen:
  - Ping
  - DNS
  - Hardware
  - Traceroute
- lokaler Spool für Pending-, Sent- und Failed-Daten
- Versand der Messdaten über separaten Senderprozess

---

## Projektaufbau

```text
/opt/speedmon
├── bin/        # ausführbare Skripte
├── etc/        # Projektkonfiguration
├── lib/        # gemeinsame Shell-Funktionen
├── log/        # Logdateien zur Laufzeit
├── run/        # Laufzeitstatus / State-Dateien
├── tmp/        # temporäre Dateien
├── spool/      # Messdaten-Spool
│   ├── pending/
│   ├── sent/
│   └── failed/
```

### Wichtige Skripte

- `bin/run-speedtest.sh`  
  Führt einen Speedtest aus und schreibt das Ergebnis in den Spool.

- `bin/run-speedtest-after-boot.sh`  
  Führt den ersten Speedtest nach dem Boot aus.

- `bin/update-display-state.sh`  
  Schreibt den aktuellen Display-Status in eine JSON-Datei.

- `bin/display-daemon.py`  
  Steuert OLED, LED und Taster.

- `bin/install-deps.sh`  
  Installiert benötigte Pakete und Python-Abhängigkeiten.

- `bin/install-cron.sh`  
  Erstellt den Cronjob für die regelmäßigen Messungen.

- `bin/install-display-service.sh`  
  Installiert und aktiviert den Display-Dienst.

- `bin/install.sh`  
  Erzeugt die Projektstruktur und richtet die Basisinstallation ein.

---

## Architektur

Das Projekt ist bewusst getrennt aufgebaut:

### Bash
Bash übernimmt:
- Speedtest
- Datenerfassung
- Spool-Verwaltung
- Versand
- Cronjobs
- Installationslogik

### Python
Python wird nur für die Display-Hardware verwendet:
- OLED-Ausgabe
- LED
- Taster
- Schlaf-/Wake-Logik des Displays

Die Übergabe zwischen Bash und Python erfolgt über:

```text
/opt/speedmon/run/display-state.json
```

Bash aktualisiert diese Datei, Python liest sie zyklisch ein und zeigt den aktuellen Zustand an.

---

## Hardware

Ausgelegt für einen Raspberry Pi mit:

- SSD1306 OLED per I2C
- LED an GPIO 17
- Taster an GPIO 27

### GPIO-Belegung

- `LED_PIN = 17`
- `BUTTON_PIN = 27`

### Display

Verwendet wird ein SSD1306-Display mit:

- I2C-Adresse: `0x3C`
- Größe: `128x64`

---

## Anzeigeverhalten

### Im normalen Betrieb
Das Display zeigt:

- Zeit des letzten Speedtests
- Status
- Download
- Upload
- Ping
- Jitter
- Countdown bis zum nächsten Test

### Nach dem Boot
Nach dem Start zeigt das Display zunächst:

- Projekttitel
- IP-Adresse bzw. Wartehinweis
- Countdown bis zum ersten Speedtest nach dem Boot

Erst nach dem ersten neuen Speedtest werden wieder echte Messwerte angezeigt.

### Darkmode
Wenn der Taster längere Zeit nicht betätigt wird, schaltet das Display in den Darkmode.

Ein Tastendruck:
- weckt das Display wieder auf
- oder schaltet es wieder aus

---

## Installation

### 1. Projekt nach `/opt/speedmon` kopieren

Das Projekt muss nach diesem Pfad liegen:

```bash
/opt/speedmon
```

### 2. Abhängigkeiten installieren

```bash
cd /opt/speedmon
sudo /opt/speedmon/bin/install-deps.sh
```

### 3. Grundstruktur und Dienste einrichten

```bash
sudo /opt/speedmon/bin/install.sh
```

### 4. System neu starten

```bash
sudo reboot
```

---

## Voraussetzungen

- Raspberry Pi OS / Debian-basiertes System
- aktiviertes I2C
- funktionierendes Netzwerk
- eingerichtete LibreSpeed-Serverliste
- vorhandene Server-API bzw. Zielsystem für den Datenversand

### I2C aktivieren

Falls I2C noch nicht aktiv ist:

```bash
sudo raspi-config
```

Dann:

- `Interface Options`
- `I2C`
- `Enable`

---

## Konfiguration

Die Projektkonfiguration liegt in:

```bash
/opt/speedmon/etc/config.sh
```

Dort werden unter anderem folgende Werte gesetzt:

- Messintervalle
- Versandintervalle
- Client-ID
- Standortname
- Serverpfade
- LibreSpeed-Konfiguration
- Zeitpunkt des ersten Speedtests nach dem Boot

### Wichtige Werte

#### Speedtest-Intervall

```bash
SPEEDTEST_INTERVAL_MIN="10"
```

Legt fest, in welchem Abstand normale Speedtests ausgeführt werden.

#### Erster Speedtest nach dem Boot

```bash
FIRST_SPEEDTEST_DELAY_SEC="30"
```

Legt fest, welcher Countdown auf dem Display bis zum ersten Test nach dem Boot angezeigt wird.

#### Serverliste

Die LibreSpeed-Serverliste liegt in:

```bash
/opt/speedmon/etc/librespeed-servers.json
```

Dort können mehrere Server mit IDs eingetragen werden.

Die Reihenfolge ist wichtig:
- zuerst bevorzugte interne/private Server
- danach öffentliche Fallback-Server

---

## Verhalten bei mehreren Speedtest-Servern

`run-speedtest.sh` arbeitet die in der Serverliste eingetragenen Server nacheinander ab.

Wenn ein Server kein brauchbares Ergebnis liefert, wird automatisch der nächste verwendet.

Dadurch kann ein interner Server bevorzugt werden, während ein öffentlicher Server als Fallback dient.

---

## Cronjobs

Die regelmäßigen Jobs werden über folgende Datei eingerichtet:

```bash
/etc/cron.d/speedmon
```

Diese Datei wird durch das Skript

```bash
/opt/speedmon/bin/install-cron.sh
```

erstellt.

Dort werden unter anderem ausgeführt:

- Ping-Sammlung
- DNS-Checks
- Hardware-Messung
- Speedtests
- Traceroute
- Datenversand
- Boot-Speedtest

---

## Display-Dienst

Der Display-Dienst wird über systemd gestartet.

Installiert wird er mit:

```bash
/opt/speedmon/bin/install-display-service.sh
```

Dabei wird der Dienst:

- angelegt
- aktiviert
- direkt gestartet

Vor dem Start des Python-Daemons wird der Display-State initialisiert.

---

## Was `install.sh` macht

`install.sh` erzeugt die benötigte Projektstruktur unter `/opt/speedmon` und richtet die Grundrechte ein.

Zusätzlich ruft es die Installationsskripte für:

- Cronjobs
- Display-Dienst

auf.

---

## Was `install-deps.sh` macht

`install-deps.sh` installiert die benötigten Systempakete und Python-Abhängigkeiten, zum Beispiel:

- `jq`
- `curl`
- `cron`
- `python3`
- `python3-pip`
- `python3-gpiozero`
- `python3-pil`
- `i2c-tools`
- `luma.oled`

Außerdem wird dort der `librespeed-cli` installiert.

---

## Was man typischerweise anpasst

### 1. `etc/config.sh`
Für:
- Intervalle
- Client-Name
- Standortname
- Versandziele
- erstes Boot-Delay

### 2. `etc/librespeed-servers.json`
Für:
- interne Server
- öffentliche Fallback-Server
- Reihenfolge der Server

### 3. `bin/display-daemon.py`
Für:
- Displaylayout
- Texte
- GPIO-Pins
- Timeout für den Darkmode

### 4. `bin/install-cron.sh`
Für:
- Cron-Zeiten
- Boot-Speedtest-Delay vor dem ersten Start

---

## Manuelle Tests

### Speedtest manuell starten

```bash
/opt/speedmon/bin/run-speedtest.sh
```

### Boot-Speedtest-Skript manuell starten

```bash
/opt/speedmon/bin/run-speedtest-after-boot.sh
```

### Display-Dienst prüfen

```bash
systemctl status speedmon-display.service --no-pager
```

### Cron-Datei prüfen

```bash
cat /etc/cron.d/speedmon
```

---

## Ziel des Projekts

Das Projekt soll einen eigenständig laufenden Speedtest-Client bereitstellen, der:

- zuverlässig misst
- lokal puffert
- mit mehreren Servern umgehen kann
- direkt am Gerät den aktuellen Status anzeigt
- auf einem Raspberry Pi ohne zusätzliche Bedienoberfläche läuft
