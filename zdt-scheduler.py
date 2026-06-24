#!/usr/bin/env python3
"""
ZDT Scheduler Daemon — Periodically sync Spotify playlists.
Reads schedule from ~/.config/zdt/scheduler.json
"""

import os
import sys
import json
import time
import subprocess
import shutil
from datetime import datetime, timezone

SCHEDULER_FILE = os.path.expanduser("~/.config/zdt/scheduler.json")
CHECK_INTERVAL = 3600  # Check every hour

def find_zdt_bin():
    """Find the zdt binary."""
    zdt_bin = shutil.which("zdt")
    if zdt_bin:
        return zdt_bin
    for path in [
        os.path.expanduser("~/.local/bin/zdt"),
        "/usr/local/bin/zdt",
        "/data/data/com.termux/files/usr/bin/zdt"
    ]:
        if os.path.exists(path):
            return path
    return "zdt"


def load_schedule():
    """Load schedule from JSON file."""
    if not os.path.exists(SCHEDULER_FILE):
        return {"playlists": []}
    try:
        with open(SCHEDULER_FILE, "r") as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError):
        return {"playlists": []}


def save_schedule(schedule):
    """Save schedule to JSON file."""
    config_dir = os.path.dirname(SCHEDULER_FILE)
    os.makedirs(config_dir, exist_ok=True)
    with open(SCHEDULER_FILE, "w") as f:
        json.dump(schedule, f, indent=2)


def send_telegram_notification(message):
    """Send notification via Telegram if configured."""
    config_path = os.path.expanduser("~/.config/zdt/config.env")
    token = ""
    chat_id = ""
    if os.path.exists(config_path):
        with open(config_path, "r") as f:
            for line in f:
                if line.startswith("TELEGRAM_NOTIFY_TOKEN="):
                    token = line.strip().split("=", 1)[1].strip('"').strip("'")
                elif line.startswith("TELEGRAM_NOTIFY_CHAT_ID="):
                    chat_id = line.strip().split("=", 1)[1].strip('"').strip("'")
    
    if not token or not chat_id:
        return
    
    import urllib.request
    import json as _json
    
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    payload = _json.dumps({"chat_id": chat_id, "text": message, "parse_mode": "HTML"}).encode()
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10):
            pass
    except Exception as e:
        print(f"  [Notify Error] {e}")


def sync_playlist(url):
    """Sync a Spotify playlist."""
    zdt_bin = find_zdt_bin()
    print(f"  Syncing: {url}")
    result = subprocess.run(
        [zdt_bin, "--spotify-sync", url],
        capture_output=True, text=True, timeout=1800  # 30 min timeout
    )
    output = result.stdout + result.stderr
    success = result.returncode == 0
    print(f"  {'OK' if success else 'FAILED'} (exit {result.returncode})")
    return success, output[:500]


def run_cycle():
    """Execute one scheduler cycle: check all playlists."""
    now = datetime.now(timezone.utc)
    schedule = load_schedule()
    playlists = schedule.get("playlists", [])
    
    if not playlists:
        return  # No playlists configured
    
    changed = False
    for playlist in playlists:
        url = playlist.get("url", "")
        interval_hours = playlist.get("interval_hours", 24)
        last_run_str = playlist.get("last_run", "")
        
        if not url:
            continue
        
        # Determine if it's time to run
        should_run = False
        if not last_run_str:
            should_run = True  # Never run before
        else:
            try:
                last_run = datetime.fromisoformat(last_run_str)
                elapsed = (now - last_run).total_seconds() / 3600
                if elapsed >= interval_hours:
                    should_run = True
            except (ValueError, TypeError):
                should_run = True
        
        if should_run:
            print(f"  [{now.strftime('%H:%M:%S')}] Syncing playlist: {url}")
            success, _ = sync_playlist(url)
            playlist["last_run"] = now.isoformat()
            playlist["last_status"] = "ok" if success else "failed"
            changed = True
            
            # Send notification
            if success:
                name = playlist.get("name", url)
                msg = (f"✅ <b>Auto-Sync Selesai</b>\n"
                       f"Playlist: {name}\n"
                       f"Waktu: {now.strftime('%Y-%m-%d %H:%M')}")
                send_telegram_notification(msg)
    
    if changed:
        save_schedule(schedule)


def main():
    print(f"ZDT Scheduler Daemon started")
    print(f"Config: {SCHEDULER_FILE}")
    print(f"Check interval: {CHECK_INTERVAL}s ({CHECK_INTERVAL//3600}h)")
    print("Press Ctrl+C to stop.\n")
    
    # Initial run immediately
    run_cycle()
    
    while True:
        time.sleep(CHECK_INTERVAL)
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Checking schedules...")
        run_cycle()


if __name__ == "__main__":
    main()
