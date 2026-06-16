#!/usr/bin/env python3
import sys
import os
import time
import subprocess
from watchdog.observers import Observer
from watchdog.events import PatternMatchingEventHandler

class ZDTFileHandler(PatternMatchingEventHandler):
    def __init__(self):
        super().__init__(patterns=["*.mp3", "*.m4a", "*.mp4", "*.mkv", "*.webm", "*.flac"],
                         ignore_directories=True, case_sensitive=False)
        self.processed_files = set()

    def process(self, filepath):
        if filepath in self.processed_files:
            return
        self.processed_files.add(filepath)
        
        print(f"[{time.strftime('%H:%M:%S')}] File baru terdeteksi: {os.path.basename(filepath)}")
        
        # Tunggu sebentar untuk memastikan file selesai di-copy
        time.sleep(2)
        
        import shutil
        zdt_bin = shutil.which("zdt")
        if not zdt_bin:
            for path in [
                os.path.expanduser("~/.local/bin/zdt"),
                "/usr/local/bin/zdt",
                "/data/data/com.termux/files/usr/bin/zdt"
            ]:
                if os.path.exists(path):
                    zdt_bin = path
                    break
        if not zdt_bin:
            zdt_bin = "zdt"
            
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
    observer.schedule(event_handler, path, recursive=False)
    observer.start()
    
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
        print("Daemon dimatikan.")
    
    observer.join()
