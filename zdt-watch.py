#!/usr/bin/env python3
import sys
import os
import time
import subprocess
from collections import OrderedDict
from watchdog.observers import Observer
from watchdog.events import PatternMatchingEventHandler

# Load shared path module
_MODULES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "zdt-modules")
if not os.path.isdir(_MODULES_DIR):
    for _d in [os.path.expanduser("~/.local/share/zdt/zdt-modules"), "/usr/local/share/zdt/zdt-modules"]:
        if os.path.isdir(_d):
            _MODULES_DIR = _d
            break
if _MODULES_DIR not in sys.path:
    sys.path.insert(0, _MODULES_DIR)
from zdt_paths import ZdtPaths

class ZDTFileHandler(PatternMatchingEventHandler):
    def __init__(self):
        super().__init__(patterns=["*.mp3", "*.m4a", "*.mp4", "*.mkv", "*.webm", "*.flac"],
                         ignore_directories=True, case_sensitive=False)
        # Proper LRU: OrderedDict for predictable O(1) eviction of oldest entries
        self.processed_files = OrderedDict()
        self._max_processed = 1000

    def process(self, filepath):
        if filepath in self.processed_files:
            return
        self.processed_files[filepath] = True
        # Evict oldest entry when over limit (predictable O(1) popitem)
        if len(self.processed_files) > self._max_processed:
            self.processed_files.popitem(last=False)
        
        print(f"[{time.strftime('%H:%M:%S')}] File baru terdeteksi: {os.path.basename(filepath)}")
        
        # Wait for file to be fully written: check size stability
        try:
            prev_size = -1
            stable_count = 0
            while stable_count < 3:
                time.sleep(1)
                curr_size = os.path.getsize(filepath)
                if curr_size == prev_size and curr_size > 0:
                    stable_count += 1
                else:
                    stable_count = 0
                prev_size = curr_size
        except OSError:
            # File disappeared or can't be read
            time.sleep(2)
        
        import shutil
        zdt_bin = shutil.which("zdt") or ZdtPaths.get_bin_path()
            
        print(f"[{time.strftime('%H:%M:%S')}] Memulai auto-clean ZDT untuk file tersebut...")
        subprocess.run([zdt_bin, "--clean-file", filepath])
        print(f"[{time.strftime('%H:%M:%S')}] Selesai diproses.")

    def on_created(self, event):
        self.process(event.src_path)

    def on_moved(self, event):
        self.process(event.dest_path)

if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "."
    if not os.path.exists(path):
        print(f"Direktori {path} tidak ditemukan!")
        sys.exit(1)
        
    print(f"Memulai ZDT Auto-Watch Daemon di {path}")
    print("Menunggu file media baru masuk...")
    
    event_handler = ZDTFileHandler()
    observer = Observer()
    observer.schedule(event_handler, path, recursive=True)
    observer.start()
    
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
        print("Daemon dimatikan.")
    
    observer.join()
