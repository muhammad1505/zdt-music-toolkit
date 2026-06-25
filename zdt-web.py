#!/usr/bin/env python3
import os
import sys
import subprocess
import shutil
import glob
import tempfile
import secrets
import time
from collections import defaultdict
from flask import Flask, request, render_template, render_template_string, jsonify, Response
from functools import wraps
try:
    import mutagen
    from mutagen.easyid3 import EasyID3
    from mutagen.mp4 import MP4, MP4Cover
    from mutagen.flac import FLAC, Picture
except ImportError:
    pass

PROJECT_DIR = os.path.dirname(os.path.abspath(__file__))

def _find_templates_dir():
    """Find templates directory across multiple possible install locations.
    If not found, auto-create and copy from known sources."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    cwd = os.getcwd()
    candidates = [
        os.path.join(script_dir, 'templates'),
        os.path.join(os.path.dirname(script_dir), 'templates'),
        os.path.expanduser('~/.local/share/zdt/templates'),
        '/usr/local/share/zdt/templates',
        os.path.expanduser('~/zdt-music-toolkit/templates'),
        os.path.join(cwd, 'templates'),  # dev mode: running from project dir
    ]
    for candidate in candidates:
        if os.path.isdir(candidate):
            return candidate
    # Auto-create templates dir at the installed location
    target_dir = os.path.expanduser('~/.local/share/zdt/templates')
    target_file = os.path.join(target_dir, 'dashboard.html')
    # Search for source template in various locations
    source_candidates = [
        os.path.join(script_dir, 'templates', 'dashboard.html'),
        os.path.join(os.path.dirname(script_dir), 'templates', 'dashboard.html'),
        os.path.expanduser('~/zdt-music-toolkit/templates/dashboard.html'),
        os.path.join(PROJECT_DIR, 'templates', 'dashboard.html'),
        os.path.join(cwd, 'templates', 'dashboard.html'),  # dev mode
    ]
    for src in source_candidates:
        if os.path.exists(src):
            os.makedirs(target_dir, exist_ok=True)
            shutil.copy2(src, target_file)
            print(f"  📋 Template dashboard copied to {target_file}")
            return target_dir
    return candidates[0]

WEB_TASK_LOG_PATH = os.environ.get("ZDT_WEB_LOG", os.path.join(tempfile.gettempdir(), "zdt_web_task.log"))

# Clear old task logs on startup
if os.path.exists(WEB_TASK_LOG_PATH):
    try:
        os.remove(WEB_TASK_LOG_PATH)
    except OSError:
        pass

app = Flask(__name__, template_folder=_find_templates_dir())
app.secret_key = secrets.token_hex(32)

# CSRF token store: dict[token, expiry_time]
_csrf_tokens = {}
_CSRF_TOKEN_TTL = 3600  # 1 hour

def _generate_csrf_token():
    """Generate and store a CSRF token with expiry."""
    _expire_old_csrf_tokens()
    token = secrets.token_urlsafe(32)
    _csrf_tokens[token] = time.time() + _CSRF_TOKEN_TTL
    return token

def _expire_old_csrf_tokens():
    """Remove expired tokens to prevent memory leak."""
    now = time.time()
    expired = [t for t, exp in _csrf_tokens.items() if now > exp]
    for t in expired:
        _csrf_tokens.pop(t, None)

def _validate_csrf_token(token):
    """Validate and consume a CSRF token."""
    if token in _csrf_tokens:
        expiry = _csrf_tokens.pop(token, 0)
        if time.time() <= expiry:
            return True
    return False

def requires_csrf(f):
    """Decorator for endpoints requiring CSRF token.
    Skips validation for safe HTTP methods (GET, HEAD, OPTIONS).
    """
    @wraps(f)
    def decorated(*args, **kwargs):
        if request.method in ('GET', 'HEAD', 'OPTIONS'):
            return f(*args, **kwargs)
        token = request.headers.get("X-CSRF-Token") or (request.json or {}).get("csrf_token", "")
        if not _validate_csrf_token(token):
            return jsonify({"success": False, "message": "CSRF token invalid. Refresh halaman dan coba lagi."}), 403
        return f(*args, **kwargs)
    return decorated

# Rate limiting: max 120 requests per minute per IP
# (dashboard has 3 polling loops: status 3s, logs 3s, scheduler 10s = ~46 req/min)
_rate_limit_store = defaultdict(list)

def _rate_limit(ip, max_requests=120, window=60):
    """Return True if rate limited."""
    now = time.time()
    _rate_limit_store[ip] = [t for t in _rate_limit_store[ip] if now - t < window]
    if len(_rate_limit_store[ip]) >= max_requests:
        return True
    _rate_limit_store[ip].append(now)
    return False

@app.before_request
def check_rate_limit():
    ip = request.remote_addr
    if _rate_limit(ip):
        return jsonify({"error": "Too many requests. Slow down!"}), 429

def _ensure_password():
    """Generate random password on first run, save to config.env."""
    config_file = CONFIG_FILE
    os.makedirs(os.path.dirname(config_file), exist_ok=True)
    
    # Baca dulu config yang sudah ada (untuk migrasi dari config.conf)
    old_conf = os.path.expanduser("~/.config/zdt/config.conf")
    existing_user = ""
    existing_pass = ""
    lines = []
    
    if os.path.exists(config_file):
        with open(config_file, 'r') as f:
            lines = f.readlines()
    
    # Cek apakah kredensial sudah ada di config.env
    has_user = any(l.startswith("ZDT_WEB_USER=") for l in lines)
    has_pass = any(l.startswith("ZDT_WEB_PASS=") for l in lines)
    
    if has_user and has_pass:
        return  # Sudah ada kredensial
    
    # Coba migrasi dari config.conf (file lama)
    if not has_user and os.path.exists(old_conf):
        with open(old_conf, 'r') as f:
            for line in f:
                line = line.strip()
                if line.startswith("ZDT_WEB_USER="):
                    existing_user = line.split("=", 1)[1].strip('"\'')
                elif line.startswith("ZDT_WEB_PASS="):
                    existing_pass = line.split("=", 1)[1].strip('"\'')
    
    random_pass = existing_pass or ""
    if not has_user:
        lines = [l for l in lines if not l.startswith("ZDT_WEB_USER=")]
        lines.append(f'ZDT_WEB_USER={existing_user or "admin"}\n')
    if not has_pass:
        lines = [l for l in lines if not l.startswith("ZDT_WEB_PASS=")]
        random_pass = existing_pass or secrets.token_urlsafe(12)
        lines.append(f'ZDT_WEB_PASS={random_pass}\n')
    
    with open(config_file, 'w') as f:
        f.writelines(lines)
    try:
        os.chmod(config_file, 0o600)
    except OSError:
        pass
    
    if not existing_pass:
        print(f"\n{'='*60}")
        print(f"  🔐 Web Dashboard credentials generated!")
        print(f"  Username: {existing_user or 'admin'}")
        print(f"  Password: {random_pass}")
        print(f"  Saved to: {config_file}")
        print(f"{'='*60}\n")

def _print_credentials():
    """Print login credentials on every startup."""
    config_file = CONFIG_FILE
    conf_user, conf_pass = "", ""
    if os.path.exists(config_file):
        with open(config_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line.startswith("ZDT_WEB_USER="):
                    conf_user = line.split("=", 1)[1].strip('"\'')
                elif line.startswith("ZDT_WEB_PASS="):
                    conf_pass = line.split("=", 1)[1].strip('"\'')
    if conf_user and conf_pass:
        print(f"  🔐 Login: {conf_user} / {conf_pass}")
    else:
        print(f"  🔐 Login: admin / (lihat output terminal di atas)")

def check_auth(username, password):
    config_file = CONFIG_FILE
    conf_user, conf_pass = "", ""
    if os.path.exists(config_file):
        with open(config_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line.startswith("ZDT_WEB_USER="):
                    conf_user = line.split("=", 1)[1].strip('"\'')
                elif line.startswith("ZDT_WEB_PASS="):
                    conf_pass = line.split("=", 1)[1].strip('"\'')
    if conf_user == "admin" and conf_pass == "admin":
        return False
    return username == conf_user and password == conf_pass

def authenticate():
    return Response(
        'Akses Web Dashboard Ditolak!\\nSilakan login menggunakan username dan password Anda.\\nPassword dibuat otomatis saat pertama dijalankan (cek output terminal / ~/.config/zdt/config.env).', 401,
        {'WWW-Authenticate': 'Basic realm="ZDT Enterprise Server"'})

def requires_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth = request.authorization
        if not auth or not check_auth(auth.username, auth.password):
            return authenticate()
        return f(*args, **kwargs)
    return decorated
APP_VERSION = os.environ.get("ZDT_VERSION", "4.1.91")

CONFIG_FILE = os.path.expanduser("~/.config/zdt/config.env")

def get_target_dir():
    target_dir = os.path.expanduser("~/Music/ZDT_Downloads")
    # Baca dari config.env (single source of truth)
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, "r") as f:
            for line in f:
                if line.startswith("storage_dir=") or line.startswith("TARGET_DIR="):
                    val = line.strip().split("=", 1)[1].strip("\"").strip("'")
                    if val and val != ".":
                        target_dir = os.path.expanduser(val)
    # Fallback: old config file for backward compatibility
    old_conf = os.path.expanduser("~/.config/zdt/config")
    if target_dir == os.path.expanduser("~/Music/ZDT_Downloads") and os.path.exists(old_conf):
        with open(old_conf, "r") as f:
            for line in f:
                if line.startswith("storage_dir="):
                    val = line.strip().split("=", 1)[1].strip("\"").strip("'")
                    if val: target_dir = os.path.expanduser(val)
    return target_dir

@app.errorhandler(Exception)
def handle_exception(e):
    import traceback
    traceback.print_exc()
    return jsonify({
        "success": False,
        "message": f"Server Error: {str(e)}"
    }), 500

@app.route('/')
@requires_auth
def index():
    return render_template('dashboard.html')

@app.route('/api/stats', methods=['GET'])
@requires_auth
def get_stats():
    import json
    try:
        db_path = os.path.join(os.path.expanduser("~"), ".config", "zdt", "zdt.db")
        db_script = os.path.join(PROJECT_DIR, "zdt-modules", "zdt_db.py")
        res = subprocess.run([sys.executable, db_script, db_path, "get_stats"], capture_output=True, text=True)
        if res.returncode == 0:
            return jsonify(json.loads(res.stdout.strip()))
        return jsonify({"success": False, "message": res.stderr}), 500
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({"success": False, "message": str(e)}), 500

def is_process_running(script_name):
    try:
        output = subprocess.check_output(["ps", "aux"]).decode()
        for line in output.split("\n"):
            if script_name in line and "python" in line and not "grep" in line:
                return True
        return False
    except Exception:
        return False

@app.route('/api/status', methods=['GET'])
@requires_auth
def get_status():
    target = get_target_dir()
    storage_free = "Unknown"
    try:
        total, used, free = shutil.disk_usage(target if os.path.exists(target) else "/")
        storage_free = f"{free // (2**30)} GB"
    except Exception:
        pass
    
    # Count media files (recursive, including subdirectories)
    file_count = 0
    if os.path.exists(target):
        media_exts = {'.mp3', '.m4a', '.flac', '.wav', '.ogg', '.opus', '.mp4', '.mkv', '.webm'}
        for root, dirs, files in os.walk(target):
            for f in files:
                if os.path.splitext(f)[1].lower() in media_exts:
                    file_count += 1
    
    return jsonify({
        "target_dir": target,
        "storage_free": storage_free,
        "file_count": file_count,
        "version": APP_VERSION,
        "watcher": is_process_running("zdt-watch.py"),
        "telegram": is_process_running("zdt-telegram.py")
    })

@app.route('/api/files', methods=['GET'])
@requires_auth
def get_files():
    target = get_target_dir()
    if not os.path.exists(target): return jsonify({"files": []})
    
    files = []
    media_exts = {'.mp3', '.m4a', '.flac', '.wav', '.ogg', '.opus', '.mp4', '.mkv', '.webm'}
    for root, dirs, fnames in os.walk(target):
        for f in fnames:
            if os.path.splitext(f)[1].lower() in media_exts:
                # Include relative path to disambiguate files with same name in different dirs
                rel = os.path.relpath(os.path.join(root, f), target)
                files.append(rel)
    files.sort()
    return jsonify({"files": files})

@app.route('/api/daemon', methods=['POST'])
@requires_auth
@requires_csrf
def manage_daemon():
    data = request.json
    service = data.get('service')
    action = data.get('action')
    venv_python = os.path.expanduser("~/.local/share/zdt/venv/bin/python")
    
    # Try multiple locations for scripts
    script_dir = os.path.dirname(os.path.abspath(__file__))
    cwd = os.getcwd()
    def find_script(name):
        for p in [
            os.path.join(script_dir, name),
            os.path.expanduser(f"~/.local/share/zdt/{name}"),
            os.path.join(cwd, name),  # dev mode
        ]:
            if os.path.exists(p): return p
        return os.path.join(script_dir, name)
    script_map = {
        'watch': find_script('zdt-watch.py'),
        'telegram': find_script('zdt-telegram.py'),
        'scheduler': find_script('zdt-scheduler.py')
    }
    
    if service not in script_map:
        return jsonify({"success": False, "message": "Unknown service."})
        
    script_path = script_map[service]
    
    if action == 'start':
        if is_process_running(os.path.basename(script_path)):
            return jsonify({"success": True, "message": f"{service.capitalize()} is already running."})
        # Pass target directory to watch daemon
        watch_args = []
        if service == 'watch':
            watch_args = [get_target_dir()]
        # Use close_fds=True and stdin=DEVNULL to fully detach and prevent hanging the API request
        subprocess.Popen([venv_python, script_path] + watch_args, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True, close_fds=True)
        return jsonify({"success": True, "message": f"Started {service} daemon."})
        
    elif action == 'stop':
        try:
            output = subprocess.check_output(["ps", "aux"]).decode()
            killed = False
            for line in output.split("\n"):
                if os.path.basename(script_path) in line and "python" in line and not "grep" in line:
                    pid = int(line.split()[1])
                    import signal
                    os.kill(pid, signal.SIGTERM)
                    killed = True
            if killed:
                return jsonify({"success": True, "message": f"Stopped {service} daemon."})
            else:
                return jsonify({"success": True, "message": f"{service.capitalize()} is not running."})
        except Exception as e:
            return jsonify({"success": False, "message": f"Failed to stop: {str(e)}"})

@app.route('/api/csrf-token', methods=['GET'])
@requires_auth
def get_csrf_token():
    return jsonify({"csrf_token": _generate_csrf_token()})

@app.route('/api/settings/storage', methods=['POST'])
@requires_auth
@requires_csrf
def update_storage():
    new_path = request.json.get('path')
    if not new_path: return jsonify({"success": False, "message": "Path cannot be empty."})
    
    new_path = os.path.expanduser(new_path)
    if not os.path.exists(new_path):
        try: os.makedirs(new_path, exist_ok=True)
        except Exception as e: return jsonify({"success": False, "message": f"Cannot create directory: {str(e)}"})
        
    config_dir = os.path.dirname(CONFIG_FILE)
    if not os.path.exists(config_dir): os.makedirs(config_dir, exist_ok=True)
    
    lines = []
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, "r") as f: lines = f.readlines()
        
    found = False
    for i, line in enumerate(lines):
        if line.startswith("TARGET_DIR="):
            lines[i] = f'TARGET_DIR="{new_path}"\n'
            found = True
            break
            
    if not found: lines.append(f'TARGET_DIR="{new_path}"\n')
    
    with open(CONFIG_FILE, "w") as f: f.writelines(lines)
    
    # Sync to old config format (backward compatibility)
    old_conf = os.path.expanduser("~/.config/zdt/config")
    if os.path.exists(old_conf):
        olines = []
        with open(old_conf, "r") as f: olines = f.readlines()
        found_old = False
        for i, line in enumerate(olines):
            if line.startswith("storage_dir="):
                olines[i] = f'storage_dir="{new_path}"\n'
                found_old = True
                break
        if not found_old:
            olines.append(f'storage_dir="{new_path}"\n')
        with open(old_conf, "w") as f: f.writelines(olines)
        
    return jsonify({"success": True, "message": "Storage directory updated successfully."})

@app.route('/api/download', methods=['POST'])
@requires_auth
@requires_csrf
def trigger_download():
    data = request.json
    url = data.get('url')
    fmt = data.get('format')
    spec = data.get('spec')
    bitrate = data.get('bitrate')
    if not url: return jsonify({"success": False, "message": "URL tidak boleh kosong!"})
    
    zdt_bin = shutil.which("zdt")
    if not zdt_bin:
        for path in [os.path.expanduser("~/.local/bin/zdt"), "/usr/local/bin/zdt", "/data/data/com.termux/files/usr/bin/zdt"]:
            if os.path.exists(path): zdt_bin = path; break
    if not zdt_bin: zdt_bin = "zdt"
    
    cmd = []
    if "spotify.com" in url:
        cmd = [zdt_bin, "--download-audio", url]
    elif fmt == "audio":
        cmd = [zdt_bin, "--download-audio", url]
        if spec: cmd.extend(["--format-spec", str(spec)])
        if bitrate: cmd.extend(["--bitrate", str(bitrate)])
    else:
        cmd = [zdt_bin, "--download-video", url]
        if spec: cmd.extend(["--format-spec", str(spec)])
        
    with open(WEB_TASK_LOG_PATH, "w") as log_file:
        subprocess.Popen(cmd, stdout=log_file, stderr=subprocess.STDOUT, start_new_session=True)
        
    return jsonify({"success": True, "message": "Proses download sedang berjalan di background!"})

@app.route('/api/spotify-sync', methods=['POST'])
@requires_auth
@requires_csrf
def trigger_spotify_sync():
    url = request.json.get('url')
    if not url: return jsonify({"success": False, "message": "URL tidak boleh kosong!"})
    
    zdt_bin = shutil.which("zdt")
    if not zdt_bin:
        for path in [os.path.expanduser("~/.local/bin/zdt"), "/usr/local/bin/zdt", "/data/data/com.termux/files/usr/bin/zdt"]:
            if os.path.exists(path): zdt_bin = path; break
    if not zdt_bin: zdt_bin = "zdt"
    
    with open(WEB_TASK_LOG_PATH, "w") as log_file:
        subprocess.Popen([zdt_bin, "--spotify-sync", url], stdout=log_file, stderr=subprocess.STDOUT, start_new_session=True)
        
    return jsonify({"success": True, "message": "Sinkronisasi Spotify berjalan di background!"})

@app.route('/api/metadata', methods=['POST'])
@requires_auth
@requires_csrf
def update_metadata():
    if 'mutagen' not in sys.modules:
        return jsonify({"success": False, "message": "Mutagen belum terinstall."})
        
    data = request.json
    filename = data.get('filename')
    title = data.get('title')
    artist = data.get('artist')
    if not filename: return jsonify({"success": False, "message": "Pilih file."})
    if not title and not artist: return jsonify({"success": False, "message": "Isi minimal title atau artist."})
    
    # Path traversal protection
    target = get_target_dir()
    filepath = os.path.realpath(os.path.join(target, filename))
    if not filepath.startswith(os.path.realpath(target) + os.sep):
        return jsonify({"success": False, "message": "Akses ditolak."})
    if not os.path.exists(filepath): return jsonify({"success": False, "message": "File tidak ditemukan."})
    
    try:
        ext = filepath.lower()
        if ext.endswith('.mp3'):
            audio = EasyID3(filepath)
            if title: audio["title"] = title
            if artist: audio["artist"] = artist
            audio.save()
        elif ext.endswith('.m4a'):
            audio = MP4(filepath)
            if title: audio.tags["\xa9nam"] = title
            if artist: audio.tags["\xa9ART"] = artist
            audio.save()
        elif ext.endswith('.flac'):
            audio = FLAC(filepath)
            if title: audio["title"] = title
            if artist: audio["artist"] = artist
            audio.save()
        return jsonify({"success": True, "message": "Metadata berhasil diubah."})
    except Exception as e:
        return jsonify({"success": False, "message": f"Gagal memproses file: {str(e)}"})

@app.route('/api/tools', methods=['POST'])
@requires_auth
@requires_csrf
def server_tools():
    data = request.json
    action = data.get('action')
    filename = data.get('filename')
    target = get_target_dir()
    
    # Path traversal protection: ensure filename resolves within target directory
    # Supports both basenames (legacy) and relative paths (new /api/files recursive)
    if filename:
        allowed_files = set()
        allowed_basenames = set()
        if os.path.exists(target):
            media_exts = {'.mp3', '.m4a', '.flac', '.wav', '.ogg', '.opus', '.mp4', '.mkv', '.webm'}
            for root, dirs, fnames in os.walk(target):
                for f in fnames:
                    if os.path.splitext(f)[1].lower() in media_exts:
                        rel = os.path.relpath(os.path.join(root, f), target)
                        allowed_files.add(rel)
                        allowed_basenames.add(os.path.basename(f))
        if filename not in allowed_files and filename not in allowed_basenames:
            return jsonify({"success": False, "message": "File tidak valid atau di luar direktori yang diizinkan."})
    
    zdt_bin = shutil.which("zdt")
    if not zdt_bin:
        for path in [os.path.expanduser("~/.local/bin/zdt"), "/usr/local/bin/zdt", "/data/data/com.termux/files/usr/bin/zdt"]:
            if os.path.exists(path): zdt_bin = path; break
    if not zdt_bin: zdt_bin = "zdt"

    try:
        if action == 'clean':
            if not os.path.exists(target): return jsonify({"success": False, "message": "Direktori kosong."})
            with open(WEB_TASK_LOG_PATH, "w") as log_file:
                subprocess.Popen([zdt_bin, "--bersih-nama-all"], stdout=log_file, stderr=subprocess.STDOUT, start_new_session=True, cwd=target)
            return jsonify({"success": True, "message": "Proses pembersihan berjalan di background!"})

        elif action == 'playlist':
            if not os.path.exists(target): return jsonify({"success": False, "message": "Direktori kosong."})
            m3u_path = os.path.join(target, "ZDT_Playlist.m3u")
            with open(m3u_path, 'w') as f:
                f.write("#EXTM3U\n")
                for ext in ['*.mp3', '*.m4a', '*.flac']:
                    for track in glob.glob(os.path.join(target, ext)):
                        f.write(f"{os.path.basename(track)}\n")
            return jsonify({"success": True, "message": "File ZDT_Playlist.m3u berhasil dibuat."})
            
        elif action == 'sync_lyrics':
            if not os.path.exists(target): return jsonify({"success": False, "message": "Direktori kosong."})
            with open(WEB_TASK_LOG_PATH, "w") as log_file:
                subprocess.Popen([zdt_bin, "--sync-lirik-all"], stdout=log_file, stderr=subprocess.STDOUT, start_new_session=True, cwd=target)
            return jsonify({"success": True, "message": "Sinkronisasi lirik berjalan di background!"})
            
        elif action == 'delete_all':
            if not os.path.exists(target): return jsonify({"success": False, "message": "Direktori kosong."})
            count = 0
            dirs_removed = 0
            media_exts = {'.mp3', '.m4a', '.flac', '.wav', '.ogg', '.opus', '.mp4', '.mkv', '.webm', '.avi', '.mov', '.ts', '.jpg', '.jpeg', '.png', '.lrc', '.m3u', '.srt'}
            # Walk recursively through all subdirectories (bottom-up for safe dir removal)
            for root, dirs, files in os.walk(target, topdown=False):
                for f in files:
                    if os.path.splitext(f)[1].lower() in media_exts:
                        fp = os.path.join(root, f)
                        try:
                            os.remove(fp)
                            count += 1
                        except OSError:
                            pass
                # Remove empty directories after deleting their files
                for d in dirs:
                    dp = os.path.join(root, d)
                    try:
                        if not os.listdir(dp):  # only if empty
                            os.rmdir(dp)
                            dirs_removed += 1
                    except OSError:
                        pass
            return jsonify({"success": True, "message": f"Berhasil menghapus {count} file & {dirs_removed} folder dari Storage!"})

        elif action == 'demucs':
            if not filename: return jsonify({"success": False, "message": "Pilih file."})
            # Path traversal protection
            filepath = os.path.realpath(os.path.join(target, filename))
            if not filepath.startswith(os.path.realpath(target) + os.sep):
                return jsonify({"success": False, "message": "Akses ditolak."})
            demucs_bin = os.path.expanduser("~/.local/share/zdt/demucs_venv/bin/demucs")
            if not os.path.exists(demucs_bin): demucs_bin = shutil.which("demucs")
            if not demucs_bin: return jsonify({"success": False, "message": "Demucs AI belum terinstal."})
            
            with open(WEB_TASK_LOG_PATH, "w") as log_file:
                subprocess.Popen([demucs_bin, "--two-stems=vocals", "-o", target, filepath], stdout=log_file, stderr=subprocess.STDOUT, start_new_session=True, cwd=target)
            return jsonify({"success": True, "message": "Demucs AI mulai memisahkan vokal!"})

        elif action == 'compress':
            if not filename: return jsonify({"success": False, "message": "Pilih file."})
            # Path traversal protection
            filepath = os.path.realpath(os.path.join(target, filename))
            if not filepath.startswith(os.path.realpath(target) + os.sep):
                return jsonify({"success": False, "message": "Akses ditolak."})
            name, fext = os.path.splitext(filename)
            outpath = os.path.join(target, f"{name}_compressed{fext}")
            if fext.lower() in ('.mp4', '.mkv', '.webm', '.avi'):
                cmd = ["ffmpeg", "-y", "-i", filepath, "-vcodec", "libx264", "-crf", "28", "-acodec", "aac", outpath]
            else:
                cmd = ["ffmpeg", "-y", "-i", filepath, "-b:a", "128k", outpath]
                
            env = os.environ.copy()
            with open(WEB_TASK_LOG_PATH, "w") as log_file:
                subprocess.Popen(cmd, stdout=log_file, stderr=subprocess.STDOUT, start_new_session=True, cwd=target, env=env)
            return jsonify({"success": True, "message": "Proses kompresi FFmpeg berjalan!"})

        return jsonify({"success": False, "message": "Aksi tidak dikenal."})
    except Exception as e:
        return jsonify({"success": False, "message": str(e)})

# Track previous log state for notification detection
_last_log_state = {"active": False, "last_content": ""}

@app.route("/api/logs", methods=["GET"])
@requires_auth
def get_logs():
    global _last_log_state
    log_file = WEB_TASK_LOG_PATH
    log_content = "No active tasks."
    has_content = False
    
    if os.path.exists(log_file):
        with open(log_file, "r") as f:
            lines = f.readlines()
            if lines:
                log_content = "".join(lines[-100:])
                has_content = True
    
    # Detect task completion: was active, now idle -> send notification
    notify_sent = False
    if _last_log_state["active"] and not has_content and _last_log_state.get("notified", False) == False:
        # Task just completed — send notification if configured
        token, chat_id = _get_telegram_config()
        if token and chat_id:
            _send_telegram_message(token, chat_id, "✅ <b>ZDT Task Selesai!</b>\\nTask di web dashboard telah selesai dieksekusi.")
        _last_log_state["notified"] = True
        notify_sent = True
    
    _last_log_state["active"] = has_content
    if has_content:
        _last_log_state["last_content"] = log_content
        _last_log_state["notified"] = False
    
    return jsonify({"log": log_content, "notify_sent": notify_sent})

@app.route("/api/logs/clear", methods=["POST"])
@requires_auth
@requires_csrf
def clear_logs():
    try:
        os.remove(WEB_TASK_LOG_PATH)
    except OSError:
        pass
    return jsonify({"success": True})


# ============================================
# NOTIFICATIONS (Webhook) — Send Telegram messages
# and Scheduler Management
# ============================================

def _send_telegram_message(bot_token, chat_id, message):
    """Send a message via Telegram Bot API.
    Returns dict on success, or error string on failure."""
    import urllib.request, json as _json
    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
    # Convert numeric chat_id to int to avoid API issues with supergroups
    try:
        chat_id_val = int(chat_id)
    except (ValueError, TypeError):
        chat_id_val = chat_id
    payload = _json.dumps({"chat_id": chat_id_val, "text": message, "parse_mode": "HTML"}).encode()
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return _json.loads(resp.read())
    except urllib.request.HTTPError as e:
        body = e.read().decode(errors='replace')
        print(f"Telegram notify error: {e.code} - {body}")
        return f"Telegram API {e.code}: {body}"
    except Exception as e:
        print(f"Telegram notify error: {e}")
        return str(e)

def _get_telegram_config():
    """Get Telegram notification config from config file."""
    config_path = os.path.expanduser("~/.config/zdt/config.env")
    token = ""
    chat_id = ""
    if os.path.exists(config_path):
        with open(config_path, 'r') as f:
            for line in f:
                if line.startswith("TELEGRAM_NOTIFY_TOKEN="):
                    token = line.strip().split("=", 1)[1].strip('"').strip("'")
                elif line.startswith("TELEGRAM_NOTIFY_CHAT_ID="):
                    chat_id = line.strip().split("=", 1)[1].strip('"').strip("'")
    return token, chat_id

@app.route('/api/notify/config', methods=['GET', 'POST'])
@requires_auth
@requires_csrf
def notify_config():
    """Get or set Telegram notification config."""
    if request.method == 'GET':
        token, chat_id = _get_telegram_config()
        return jsonify({
            "configured": bool(token and chat_id),
            "chat_id": chat_id if chat_id else ""
        })
    
    data = request.json
    token = data.get('token', '')
    chat_id = data.get('chat_id', '')
    config_path = os.path.expanduser("~/.config/zdt/config.env")
    config_dir = os.path.dirname(config_path)
    os.makedirs(config_dir, exist_ok=True)
    
    lines = []
    if os.path.exists(config_path):
        with open(config_path, 'r') as f:
            lines = f.readlines()
    
    # Update or add token
    found_token = found_chat = False
    for i, line in enumerate(lines):
        if line.startswith("TELEGRAM_NOTIFY_TOKEN="):
            lines[i] = f'TELEGRAM_NOTIFY_TOKEN="{token}"\n' if token else ''
            found_token = True
        elif line.startswith("TELEGRAM_NOTIFY_CHAT_ID="):
            lines[i] = f'TELEGRAM_NOTIFY_CHAT_ID="{chat_id}"\n' if chat_id else ''
            found_chat = True
    
    if token and not found_token:
        lines.append(f'TELEGRAM_NOTIFY_TOKEN="{token}"\n')
    if chat_id and not found_chat:
        lines.append(f'TELEGRAM_NOTIFY_CHAT_ID="{chat_id}"\n')
    
    # Remove empty lines
    lines = [l for l in lines if l.strip()]
    
    with open(config_path, 'w') as f:
        f.writelines(lines)
    
    return jsonify({"success": True, "message": "Konfigurasi notifikasi disimpan!"})

@app.route('/api/notify/test', methods=['POST'])
@requires_auth
@requires_csrf
def notify_test():
    """Send a test notification."""
    token, chat_id = _get_telegram_config()
    if not token or not chat_id:
        return jsonify({"success": False, "message": "Notify belum dikonfigurasi."})
    result = _send_telegram_message(token, chat_id, "🔔 <b>ZDT Test Notification</b>\nWeb dashboard terhubung dengan notifikasi Telegram!")
    if isinstance(result, dict) and result.get('ok'):
        return jsonify({"success": True, "message": "Test notification terkirim! Cek Telegram."})
    return jsonify({"success": False, "message": f"Gagal kirim: {result}"})

@app.route('/api/scheduler/status', methods=['GET'])
@requires_auth
def scheduler_status():
    """Check if scheduler daemon is running."""
    running = is_process_running("zdt-scheduler.py")
    return jsonify({"running": running})

@app.route('/api/scheduler/playlists', methods=['GET'])
@requires_auth
def scheduler_get_playlists():
    """Get scheduled playlist config."""
    config_path = os.path.expanduser("~/.config/zdt/scheduler.json")
    if os.path.exists(config_path):
        import json as _json
        with open(config_path, 'r') as f:
            return jsonify(_json.load(f))
    return jsonify({"playlists": []})

@app.route('/api/scheduler/playlists', methods=['POST'])
@requires_auth
@requires_csrf
def scheduler_save_playlists():
    """Save playlist schedule config."""
    data = request.json
    config_path = os.path.expanduser("~/.config/zdt/scheduler.json")
    config_dir = os.path.dirname(config_path)
    os.makedirs(config_dir, exist_ok=True)
    import json as _json
    with open(config_path, 'w') as f:
        _json.dump(data, f, indent=2)
    return jsonify({"success": True, "message": "Jadwal tersimpan!"})


if __name__ == '__main__':
    _ensure_password()
    # Always print credentials on every startup
    _print_credentials()
    # Auto-start scheduler daemon in background if configured
    try:
        scheduler_config = os.path.expanduser("~/.config/zdt/scheduler.json")
        if os.path.exists(scheduler_config):
            # Search for scheduler script in multiple locations
            cwd = os.getcwd()
            scheduler_script = next(
                (p for p in [
                    os.path.join(PROJECT_DIR, "zdt-scheduler.py"),
                    os.path.expanduser("~/.local/share/zdt/zdt-scheduler.py"),
                    os.path.join(cwd, "zdt-scheduler.py"),
                ] if os.path.exists(p)),
                None
            )
            if scheduler_script and os.path.exists(scheduler_script):
                scheduler_python = os.environ.get("ZDT_VENV_PYTHON", sys.executable)
                subprocess.Popen(
                    [scheduler_python, scheduler_script],
                    stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL, start_new_session=True, close_fds=True
                )
                print("  ⏰ Scheduler daemon auto-started.")
    except Exception as e:
        print(f"  ⚠ Scheduler auto-start skipped: {e}")
    import argparse
    parser = argparse.ArgumentParser(description='ZDT Enterprise Dashboard')
    parser.add_argument('--bind', default='127.0.0.1', help='Bind address (default: 127.0.0.1)')
    parser.add_argument('--port', type=int, default=5000, help='Port number (default: 5000)')
    args = parser.parse_args()
    print(f"Memulai ZDT Enterprise Dashboard di {args.bind}:{args.port}...")
    app.run(host=args.bind, port=args.port, debug=False)
