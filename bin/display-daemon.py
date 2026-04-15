#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json
import os
import socket
import subprocess
import time
from datetime import datetime, timedelta
from threading import Lock

from gpiozero import LED, Button
from luma.core.interface.serial import i2c
from luma.core.render import canvas
from luma.oled.device import ssd1306
from PIL import ImageFont

LED_PIN = 17
BUTTON_PIN = 27

STATE_FILE = "/opt/speedmon/run/display-state.json"

INACTIVITY_TIMEOUT_SEC = 180
SLEEP_MESSAGE_SEC = 2.0
POLL_INTERVAL_SEC = 0.5

led = LED(LED_PIN)
button = Button(BUTTON_PIN, pull_up=True, bounce_time=0.1)

serial = i2c(port=1, address=0x3C)
device = ssd1306(serial, width=128, height=64)
font = ImageFont.load_default()

state_lock = Lock()
display_awake = True
sleep_in_progress = False
last_button_ts = time.monotonic()
last_render_key = None


def safe_hide():
    try:
        device.hide()
    except Exception:
        try:
            device.clear()
        except Exception:
            pass


def safe_show():
    try:
        device.show()
    except Exception:
        pass


def parse_state():
    default = {
        "speedtest_running": False,
        "last_status": "no_data",
        "last_download_mbps": 0.0,
        "last_upload_mbps": 0.0,
        "last_ping_ms": 0.0,
        "last_jitter_ms": 0.0,
        "last_result_ts": "",
        "last_server_name": "",
        "next_run_epoch": 0,
        "speedtest_interval_min": 10,
        "awaiting_first_speedtest": True,
    }

    if not os.path.exists(STATE_FILE):
        return default

    try:
        with open(STATE_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)

        merged = default.copy()
        merged.update(data)

        merged["speedtest_running"] = bool(merged.get("speedtest_running", False))
        merged["last_download_mbps"] = float(merged.get("last_download_mbps", 0.0) or 0.0)
        merged["last_upload_mbps"] = float(merged.get("last_upload_mbps", 0.0) or 0.0)
        merged["last_ping_ms"] = float(merged.get("last_ping_ms", 0.0) or 0.0)
        merged["last_jitter_ms"] = float(merged.get("last_jitter_ms", 0.0) or 0.0)
        merged["next_run_epoch"] = int(merged.get("next_run_epoch", 0) or 0)
        merged["speedtest_interval_min"] = int(merged.get("speedtest_interval_min", 10) or 10)
        merged["awaiting_first_speedtest"] = bool(merged.get("awaiting_first_speedtest", True))

        return merged
    except Exception:
        return default


def get_lan_ip():
    try:
        out = subprocess.check_output(["hostname", "-I"], text=True).strip()
        if out:
            for ip in out.split():
                ip = ip.strip()
                if ip and not ip.startswith("127.") and ":" not in ip:
                    return ip
    except Exception:
        pass

    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        if ip and not ip.startswith("127."):
            return ip
    except Exception:
        pass

    return ""


def fmt_num(value, digits=1):
    try:
        return f"{float(value):.{digits}f}"
    except Exception:
        return "0.0"


def fmt_timestamp(iso_ts):
    if not iso_ts:
        return "--.-- --:--"
    try:
        dt = time.strptime(iso_ts, "%Y-%m-%dT%H:%M:%SZ")
        return time.strftime("%d.%m %H:%M", dt)
    except Exception:
        return iso_ts[:16]


def get_next_cron_epoch(interval_min: int) -> int:
    """
    Berechnet den nächsten echten Cron-Slot für Muster wie */N * * * *
    Beispiele:
      interval=10 -> 00,10,20,30,40,50
      interval=5  -> 00,05,10,...
      interval=60 -> volle Stunde
    """
    now = datetime.now()

    if interval_min <= 0:
        return int(time.time())

    if interval_min >= 60:
        next_dt = now.replace(minute=0, second=0, microsecond=0) + timedelta(hours=1)
        return int(next_dt.timestamp())

    next_minute = ((now.minute // interval_min) + 1) * interval_min

    if next_minute >= 60:
        next_dt = now.replace(minute=0, second=0, microsecond=0) + timedelta(hours=1)
    else:
        next_dt = now.replace(minute=next_minute, second=0, microsecond=0)

    return int(next_dt.timestamp())


def fmt_countdown(interval_min, running):
    if running:
        return "Test laeuft..."

    next_epoch = get_next_cron_epoch(interval_min)
    remaining = max(0, next_epoch - int(time.time()))

    mm, ss = divmod(remaining, 60)
    hh, mm = divmod(mm, 60)

    if hh > 0:
        return f"Next {hh:02d}:{mm:02d}:{ss:02d}"
    return f"Next {mm:02d}:{ss:02d}"


def sync_led(state):
    if state.get("speedtest_running", False):
        led.on()
    else:
        led.off()


def should_show_first_boot_screen(state):
    return bool(state.get("awaiting_first_speedtest", True))


def draw_first_run_screen(state, ip_addr):
    global last_render_key

    if not display_awake:
        return

    running = state.get("speedtest_running", False)

    if running:
        line1 = "Test laeuft..."
        line2 = "bitte warten..."
    else:
        line1 = "Warte auf"
        line2 = "ersten Speedtest"

    render_key = ("first_run", ip_addr, running, line1, line2, display_awake)
    if render_key == last_render_key:
        return

    safe_show()
    with canvas(device) as draw:
        draw.text((18, 0), "speedlens 2.0", font=font, fill="white")
        if ip_addr:
            draw.text((0, 14), f"IP: {ip_addr}", font=font, fill="white")
        else:
            draw.text((0, 14), "Warte auf IP-Adresse", font=font, fill="white")

        draw.text((20, 34), line1, font=font, fill="white")
        draw.text((4, 48), line2, font=font, fill="white")

    last_render_key = render_key


def draw_main_screen(state):
    global last_render_key

    if not display_awake:
        return

    status = str(state.get("last_status", "no_data")).upper()
    ts_text = fmt_timestamp(state.get("last_result_ts", ""))
    dl = fmt_num(state.get("last_download_mbps", 0.0), 1)
    ul = fmt_num(state.get("last_upload_mbps", 0.0), 1)
    ping = fmt_num(state.get("last_ping_ms", 0.0), 1)
    jitter = fmt_num(state.get("last_jitter_ms", 0.0), 1)
    countdown = fmt_countdown(state.get("speedtest_interval_min", 10), state.get("speedtest_running", False))

    render_key = (
        "main",
        state.get("speedtest_running", False),
        status,
        ts_text,
        dl,
        ul,
        ping,
        jitter,
        countdown,
        display_awake
    )

    if render_key == last_render_key:
        return

    safe_show()
    with canvas(device) as draw:
        draw.text((0, 0), f"{ts_text} {status}", font=font, fill="white")
        draw.text((0, 12), f"DL {dl} Mbit/s", font=font, fill="white")
        draw.text((0, 24), f"UL {ul} Mbit/s", font=font, fill="white")
        draw.text((0, 36), f"Ping {ping}  Jit {jitter}", font=font, fill="white")
        draw.text((0, 52), countdown, font=font, fill="white")

    last_render_key = render_key


def draw_sleep_message():
    safe_show()
    with canvas(device) as draw:
        draw.text((26, 24), "Display Off", font=font, fill="white")


def go_to_sleep():
    global display_awake, sleep_in_progress, last_render_key

    with state_lock:
        if not display_awake or sleep_in_progress:
            return
        sleep_in_progress = True

    draw_sleep_message()
    time.sleep(SLEEP_MESSAGE_SEC)

    with state_lock:
        display_awake = False
        sleep_in_progress = False
        last_render_key = None
        safe_hide()


def wake_display():
    global display_awake, sleep_in_progress, last_render_key

    with state_lock:
        display_awake = True
        sleep_in_progress = False
        last_render_key = None
        safe_show()


def handle_button_press():
    global last_button_ts

    last_button_ts = time.monotonic()

    with state_lock:
        currently_awake = display_awake

    if currently_awake:
        go_to_sleep()
    else:
        wake_display()


def main():
    global last_button_ts

    button.when_pressed = handle_button_press
    last_button_ts = time.monotonic()
    wake_display()

    while True:
        state = parse_state()
        sync_led(state)

        with state_lock:
            awake = display_awake
            sleeping_now = sleep_in_progress

        if awake and not sleeping_now:
            ip_addr = get_lan_ip()

            if should_show_first_boot_screen(state):
                draw_first_run_screen(state, ip_addr)
            else:
                draw_main_screen(state)

            inactive_for = time.monotonic() - last_button_ts
            if inactive_for >= INACTIVITY_TIMEOUT_SEC:
                go_to_sleep()

        time.sleep(POLL_INTERVAL_SEC)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        led.off()
        try:
            device.clear()
        except Exception:
            pass
