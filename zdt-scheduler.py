#!/usr/bin/env python3
"""
ZDT Scheduler Daemon — Periodically sync Spotify playlists.
Reads schedule from scheduler.json in config dir.
"""

import os
import sys
import json
import time
import subprocess
import shutil
from datetime import datetime, timezone

# Load shared path module
_MODULES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "zdt-modules")
if not os.path.isdir(_MODULES_DIR):
    # Bootstrap: ZdtPaths belum tersedia, pake hardcoded path saja
    for _d in [os.path.expanduser("~/.local/share/zdt/zdt-modules"), "/usr/local/share/zdt/zdt-modules"]:
        if os.path.isdir(_d):
            _MODULES_DIR = _d
            break
if _MODULES_DIR not in sys.path:
    sys.path.insert(0, _MODULES_DIR)
from zdt_paths import ZdtPaths

SCHEDULER_FILE = ZdtPaths.get_scheduler_path()
CHECK_INTERVAL = 3600  # Check every hour

def _acquire_scheduler_lock():
    """Acquire a lock to prevent multiple scheduler instances."""
    lock_path = "/tmp/.zdt_scheduler_%s.lock" % os.getuid()
    try:
        # Try to create lock file atomically
        fd = os.open(lock_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
        with os.fdopen(fd, 'w') as f:
            f.write(str(os.getpid()))
        return lock_path
    except FileExistsError:
        # Lock exists — check if process is still alive
        try:
            with open(lock_path, 'r') as f:
                old_pid = int(f.read().strip())
            # Check if process exists
            os.kill(old_pid, 0)
            print(f"Scheduler already running (PID: {old_pid})")
            return None
        except (ProcessLookupError, ValueError, OSError):
            # Stale lock — remove and retry
            os.remove(lock_path)
            try:
                fd = os.open(lock_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
                with os.fdopen(fd, 'w') as f:
                    f.write(str(os.getpid()))
                return lock_path
            except FileExistsError:
                return None
    except OSError:
        return None  # Fallback: run anyway (no permission?)

def _release_scheduler_lock(lock_path):
    """Release the scheduler lock."""
    if lock_path and os.path.exists(lock_path):
        try:
            os.remove(lock_path)
        except OSError:
            pass

def find_zdt_bin():
    """Find the zdt binary."""
    return shutil.which("zdt") or ZdtPaths.get_bin_path()


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
    config_dir = ZdtPaths.get_config_dir()
    os.makedirs(config_dir, exist_ok=True)
    with open(SCHEDULER_FILE, "w") as f:
        json.dump(schedule, f, indent=2)


def send_telegram_notification(message):
    """Send notification via Telegram if configured."""
    config_path = ZdtPaths.get_config_file()
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
    lock_path = _acquire_scheduler_lock()
    if lock_path is None:
        print("Failed to acquire lock. Another instance may be running.")
        sys.exit(1)
    
    try:
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
    except KeyboardInterrupt:
        print("\nScheduler stopped by user.")
    finally:
        _release_scheduler_lock(lock_path)


if __name__ == "__main__":
    main()
