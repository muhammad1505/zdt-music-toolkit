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
from flask import Flask, request, render_template_string, jsonify, Response
from functools import wraps
try:
    import mutagen
    from mutagen.easyid3 import EasyID3
    from mutagen.mp4 import MP4, MP4Cover
    from mutagen.flac import FLAC, Picture
except ImportError:
    pass

PROJECT_DIR = os.path.dirname(os.path.abspath(__file__))

WEB_TASK_LOG_PATH = os.environ.get("ZDT_WEB_LOG", os.path.join(tempfile.gettempdir(), "zdt_web_task.log"))

# Clear old task logs on startup
if os.path.exists(WEB_TASK_LOG_PATH):
    try:
        os.remove(WEB_TASK_LOG_PATH)
    except:
        pass

app = Flask(__name__)
app.secret_key = secrets.token_hex(32)

# CSRF token store
_csrf_tokens = set()

def _generate_csrf_token():
    """Generate and store a CSRF token."""
    token = secrets.token_urlsafe(32)
    _csrf_tokens.add(token)
    # Keep only last 100 tokens to prevent memory leak
    if len(_csrf_tokens) > 100:
        _csrf_tokens.clear()
        _csrf_tokens.add(token)
    return token

def _validate_csrf_token(token):
    """Validate and consume a CSRF token."""
    if token in _csrf_tokens:
        _csrf_tokens.discard(token)
        return True
    return False

def requires_csrf(f):
    """Decorator for POST endpoints requiring CSRF token."""
    @wraps(f)
    def decorated(*args, **kwargs):
        token = request.headers.get("X-CSRF-Token") or (request.json or {}).get("csrf_token", "")
        if not _validate_csrf_token(token):
            return jsonify({"success": False, "message": "CSRF token invalid. Refresh halaman dan coba lagi."}), 403
        return f(*args, **kwargs)
    return decorated

# Rate limiting: max 30 requests per minute per IP
_rate_limit_store = defaultdict(list)

def _rate_limit(ip, max_requests=30, window=60):
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
    """Generate random password on first run, save to config."""
    config_file = os.path.expanduser("~/.config/zdt/config.conf")
    os.makedirs(os.path.dirname(config_file), exist_ok=True)
    
    if not os.path.exists(config_file):
        random_pass = secrets.token_urlsafe(12)
        with open(config_file, 'w') as f:
            f.write(f'ZDT_WEB_USER=admin\n')
            f.write(f'ZDT_WEB_PASS={random_pass}\n')
        try:
            os.chmod(config_file, 0o600)
        except: pass
        print(f"\n{'='*60}")
        print(f"  🔐 FIRST RUN: Web Dashboard credentials generated!")
        print(f"  Username: admin")
        print(f"  Password: {random_pass}")
        print(f"  Saved to: {config_file}")
        print(f"{'='*60}\n")

def check_auth(username, password):
    config_file = os.path.expanduser("~/.config/zdt/config.conf")
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
        'Akses Web Dashboard Ditolak!\\nSilakan login menggunakan username dan password Anda.\\nPassword dibuat otomatis saat pertama dijalankan (cek output terminal / ~/.config/zdt/config.conf).', 401,
        {'WWW-Authenticate': 'Basic realm="ZDT Enterprise Server"'})

def requires_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth = request.authorization
        if not auth or not check_auth(auth.username, auth.password):
            return authenticate()
        return f(*args, **kwargs)
    return decorated
APP_VERSION = os.environ.get("ZDT_VERSION", "4.1.7")

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

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ZDT Enterprise Dashboard</title>
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" rel="stylesheet">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        :root {
            --bg-base: #050505;
            --bg-surface: rgba(10, 10, 12, 0.85);
            --bg-card: rgba(15, 15, 20, 0.6);
            --primary: #6366f1;
            --primary-hover: #8b5cf6;
            --accent: #10b981;
            --danger: #f43f5e;
            --warning: #fbbf24;
            --text-main: #ffffff;
            --text-muted: #a1a1aa;
            --border-light: rgba(255, 255, 255, 0.05);
            --glass-shadow: 0 0 30px rgba(99, 102, 241, 0.1);
        }
        
        * { box-sizing: border-box; }
        
        body {
            margin: 0; padding: 0;
            font-family: 'Inter', -apple-system, sans-serif;
            background-color: var(--bg-base);
            color: var(--text-main);
            min-height: 100vh;
            display: flex;
            background-image: 
                radial-gradient(circle at 15% 50%, rgba(99, 102, 241, 0.08), transparent 30%),
                radial-gradient(circle at 85% 30%, rgba(139, 92, 246, 0.08), transparent 30%);
            background-attachment: fixed;
            -webkit-font-smoothing: antialiased;
        }

        /* Scrollbar */
        ::-webkit-scrollbar { width: 6px; }
        ::-webkit-scrollbar-track { background: transparent; }
        ::-webkit-scrollbar-thumb { background: var(--bg-card); border-radius: 3px; }
        ::-webkit-scrollbar-thumb:hover { background: var(--primary); }

        .sidebar {
            width: 280px;
            background: var(--bg-surface);
            backdrop-filter: blur(12px);
            -webkit-backdrop-filter: blur(12px);
            border-right: 1px solid var(--border-light);
            padding: 30px 0;
            display: flex;
            flex-direction: column;
            z-index: 100;
            box-shadow: var(--glass-shadow);
            transition: all 0.3s ease;
        }
        
        .logo {
            padding: 0 30px;
            font-size: 28px;
            font-weight: 700;
            letter-spacing: -0.5px;
            margin-bottom: 40px;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .logo i { color: var(--primary); }

        .nav-item {
            padding: 14px 30px;
            cursor: pointer;
            display: flex;
            align-items: center;
            gap: 15px;
            font-weight: 500;
            color: var(--text-muted);
            transition: all 0.2s ease;
            font-size: 14px;
            border-left: 3px solid transparent;
        }
        .nav-item:hover {
            color: var(--text-main);
            background: rgba(255, 255, 255, 0.03);
        }
        .nav-item.active {
            color: var(--primary);
            border-left: 3px solid var(--primary);
            background: linear-gradient(90deg, rgba(59, 130, 246, 0.1), transparent);
        }
        .nav-item i { width: 20px; font-size: 18px; text-align: center; }

        .main-content {
            flex: 1;
            padding: 40px 50px;
            max-width: 1200px;
            margin: 0 auto;
            width: 100%;
        }

        .header { margin-bottom: 40px; }
        .header h2 { 
            margin: 0; font-size: 28px; font-weight: 600; letter-spacing: -0.5px; 
            color: var(--text-main);
        }
        .header p { margin: 8px 0 0; color: var(--text-muted); font-size: 15px; }

        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
            gap: 20px;
            margin-bottom: 40px;
        }
        .stat-card {
            background: var(--bg-card);
            backdrop-filter: blur(10px);
            border: 1px solid var(--border-light);
            border-radius: 12px;
            padding: 24px;
            display: flex;
            align-items: center;
            gap: 18px;
            transition: transform 0.2s, box-shadow 0.2s;
        }
        .stat-card:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(0,0,0,0.2);
            border-color: rgba(59, 130, 246, 0.3);
        }
        .stat-icon {
            width: 48px; height: 48px;
            border-radius: 10px;
            background: rgba(59, 130, 246, 0.1);
            color: var(--primary);
            display: flex; justify-content: center; align-items: center;
            font-size: 20px;
        }
        .stat-info h4 { margin: 0; color: var(--text-muted); font-size: 13px; font-weight: 500; }
        .stat-info h3 { margin: 4px 0 0; font-size: 22px; font-weight: 600; }

        .panel {
            background: var(--bg-surface);
            backdrop-filter: blur(16px);
            border: 1px solid var(--border-light);
            border-radius: 16px;
            padding: 35px;
            margin-bottom: 30px;
            display: none;
            box-shadow: var(--glass-shadow);
            animation: fadeIn 0.3s ease;
        }
        .panel.active { display: block; }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }

        .panel h3 { margin-top: 0; font-size: 20px; font-weight: 600; margin-bottom: 25px; display: flex; align-items: center; gap: 10px; }
        .panel h3 i { color: var(--primary); }

        .form-group { margin-bottom: 24px; }
        label { display: block; margin-bottom: 8px; font-weight: 500; font-size: 14px; color: var(--text-muted); }
        input[type="text"], select {
            width: 100%; padding: 14px 16px;
            background: rgba(0, 0, 0, 0.2);
            border: 1px solid var(--border-light);
            color: var(--text-main);
            border-radius: 8px;
            font-family: 'Inter', sans-serif; font-size: 14px;
            transition: all 0.2s ease;
        }
        input[type="text"]:focus, select:focus { 
            outline: none; border-color: var(--primary);
            background: rgba(0, 0, 0, 0.4);
            box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
        }

        .btn {
            background: linear-gradient(135deg, var(--primary), var(--primary-hover)); color: white;
            border: none; padding: 14px 24px;
            border-radius: 8px; font-family: inherit; font-size: 14px;
            font-weight: 600; cursor: pointer; width: 100%;
            transition: all 0.3s ease;
            display: flex; justify-content: center; align-items: center; gap: 8px;
            box-shadow: 0 4px 15px rgba(99, 102, 241, 0.2);
        }
        .btn:hover { transform: translateY(-2px); box-shadow: 0 8px 25px rgba(139, 92, 246, 0.4); }
        .btn:active { transform: translateY(0); }
        .btn:disabled { opacity: 0.6; cursor: not-allowed; }
        
        .btn-spotify { background: #1DB954; color: #fff; }
        .btn-spotify:hover { background: #1ed760; box-shadow: 0 4px 12px rgba(29, 185, 84, 0.3); }
        
        .btn-danger { background: var(--danger); color: white; }
        .btn-danger:hover { background: #dc2626; box-shadow: 0 4px 12px rgba(239, 68, 68, 0.3); }

        .btn-outline { background: transparent; border: 1px solid var(--border-light); color: var(--text-main); }
        .btn-outline:hover { background: rgba(255,255,255,0.05); }

        .status-box { margin-top: 20px; padding: 16px; border-radius: 8px; font-size: 14px; font-weight: 500; display: none; animation: fadeIn 0.3s ease; }
        .status-box.success { display: block; background: rgba(16, 185, 129, 0.1); color: var(--accent); border: 1px solid rgba(16, 185, 129, 0.2); }
        .status-box.error { display: block; background: rgba(239, 68, 68, 0.1); color: var(--danger); border: 1px solid rgba(239, 68, 68, 0.2); }
        .status-box.info { display: block; background: rgba(59, 130, 246, 0.1); color: var(--primary); border: 1px solid rgba(59, 130, 246, 0.2); }

        /* Toast Notifications */
        #toastContainer {
            position: fixed; top: 20px; right: 20px; z-index: 9999;
            display: flex; flex-direction: column; gap: 10px;
        }
        .toast {
            background: var(--bg-surface); backdrop-filter: blur(12px);
            border: 1px solid var(--border-light); border-radius: 8px;
            padding: 16px 20px; color: var(--text-main); font-size: 14px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
            display: flex; align-items: center; gap: 12px;
            animation: slideInRight 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275);
            min-width: 250px;
        }
        .toast.success { border-left: 4px solid var(--accent); }
        .toast.error { border-left: 4px solid var(--danger); }
        .toast.info { border-left: 4px solid var(--primary); }
        .toast-icon { font-size: 18px; }
        .toast.success .toast-icon { color: var(--accent); }
        .toast.error .toast-icon { color: var(--danger); }
        .toast.info .toast-icon { color: var(--primary); }
        @keyframes slideInRight { from { transform: translateX(100%); opacity: 0; } to { transform: translateX(0); opacity: 1; } }
        @keyframes fadeOut { to { opacity: 0; transform: translateY(-10px); } }

        /* Live Progress Bar */
        .progress-wrapper {
            width: 100%; height: 12px; background: rgba(0,0,0,0.5);
            border-radius: 6px; overflow: hidden; margin-top: 10px;
            display: none; border: 1px solid var(--border-light);
        }
        .progress-fill {
            height: 100%; width: 0%; background: linear-gradient(90deg, var(--primary), var(--accent));
            border-radius: 6px; transition: width 0.3s ease;
            box-shadow: 0 0 10px rgba(59, 130, 246, 0.5);
        }
        .progress-text {
            font-size: 12px; color: var(--text-muted); margin-top: 5px;
            display: flex; justify-content: space-between;
        }

        .tools-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 20px; }
        .tool-card {
            background: var(--bg-card); border: 1px solid var(--border-light);
            border-radius: 12px; padding: 25px; transition: all 0.2s ease;
            display: flex; flex-direction: column;
        }
        .tool-card:hover { border-color: rgba(255,255,255,0.2); transform: translateY(-2px); }
        .tool-icon { font-size: 28px; color: var(--primary); margin-bottom: 15px; }
        .tool-title { font-size: 16px; font-weight: 600; margin-bottom: 8px; color: var(--text-main); }
        .tool-desc { font-size: 13px; color: var(--text-muted); margin-bottom: 20px; line-height: 1.5; flex: 1; }

        .log-container {
            background: rgba(0, 0, 0, 0.4); border: 1px solid var(--border-light);
            padding: 16px; margin-top: 20px; border-radius: 8px;
            font-family: "JetBrains Mono", "Courier New", monospace; font-size: 13px; color: #a3be8c;
            height: 250px; overflow-y: auto; white-space: pre-wrap;
            box-shadow: inset 0 2px 10px rgba(0,0,0,0.2);
        }

        .switch-wrapper { display: flex; align-items: center; justify-content: space-between; padding: 15px; background: rgba(0,0,0,0.2); border-radius: 8px; margin-bottom: 15px; border: 1px solid var(--border-light); }
        .switch-info h4 { margin: 0 0 5px 0; font-size: 15px; }
        .switch-info p { margin: 0; font-size: 12px; color: var(--text-muted); }
        
        .badge { padding: 4px 10px; border-radius: 20px; font-size: 11px; font-weight: 600; text-transform: uppercase; }
        .badge-active { background: rgba(16, 185, 129, 0.15); color: var(--accent); }
        .badge-inactive { background: rgba(239, 68, 68, 0.15); color: var(--danger); }
        /* ===== MOBILE BOTTOM NAV ===== */
        .mobile-header {
            display: none;
            position: fixed; top: 0; left: 0; right: 0; z-index: 200;
            background: var(--bg-surface); backdrop-filter: blur(16px);
            border-bottom: 1px solid var(--border-light);
            padding: 12px 20px; align-items: center; justify-content: space-between;
        }
        .mobile-header .logo { margin: 0; font-size: 20px; padding: 0; }

        /* More menu popup */
        .more-overlay {
            display: none; position: fixed; inset: 0; z-index: 300;
            background: rgba(0,0,0,0.5); backdrop-filter: blur(4px);
        }
        .more-overlay.show { display: block; }
        .more-sheet {
            position: fixed; bottom: 0; left: 0; right: 0; z-index: 301;
            background: var(--bg-surface); backdrop-filter: blur(20px);
            border-top: 1px solid var(--border-light);
            border-radius: 20px 20px 0 0;
            padding: 20px 16px 30px;
            transform: translateY(100%);
            transition: transform 0.3s cubic-bezier(0.16, 1, 0.3, 1);
        }
        .more-sheet.show { transform: translateY(0); }
        .more-sheet-handle {
            width: 40px; height: 4px; background: rgba(255,255,255,0.2);
            border-radius: 2px; margin: 0 auto 18px;
        }
        .more-sheet-item {
            display: flex; align-items: center; gap: 14px;
            padding: 14px 16px; border-radius: 10px; cursor: pointer;
            color: var(--text-muted); font-size: 15px; font-weight: 500;
            transition: all 0.15s;
        }
        .more-sheet-item:hover, .more-sheet-item:active {
            background: rgba(255,255,255,0.05); color: var(--text-main);
        }
        .more-sheet-item i { width: 24px; font-size: 18px; text-align: center; color: var(--primary); }
        .more-sheet-item.active { color: var(--primary); background: rgba(59,130,246,0.1); }

        /* Mobile nav: hide overflow items */
        .nav-more-trigger { display: none; }

        @media (max-width: 900px) {
            .sidebar {
                position: fixed; bottom: 0; left: 0; right: 0; z-index: 200;
                width: 100%; height: auto; border-right: none;
                border-top: 1px solid var(--border-light);
                padding: 0; flex-direction: row; justify-content: space-around;
                overflow: visible;
                scrollbar-width: none;
            }
            .sidebar::-webkit-scrollbar { display: none; }
            .sidebar .logo { display: none; }
            .sidebar .nav-item {
                flex: 1; padding: 8px 4px;
                border-left: none; border-top: 3px solid transparent;
                font-size: 10px; flex-direction: column; gap: 3px;
                text-align: center; white-space: nowrap;
            }
            .sidebar .nav-item i { width: auto; font-size: 20px; margin: 0; }
            .sidebar .nav-item.active {
                border-left: none; border-top: 3px solid var(--primary);
                background: linear-gradient(0deg, rgba(59, 130, 246, 0.08), transparent);
            }
            /* Hide these from bottom nav on mobile */
            .sidebar .nav-hide-mobile { display: none; }
            .nav-more-trigger {
                display: flex; flex: 1; padding: 8px 4px;
                flex-direction: column; gap: 3px; align-items: center;
                font-size: 10px; color: var(--text-muted); cursor: pointer;
                border-top: 3px solid transparent; transition: all 0.2s;
            }
            .nav-more-trigger i { font-size: 20px; }
            .nav-more-trigger.active { color: var(--primary); border-top-color: var(--primary); }
            
            .mobile-header { display: flex; }
            body { flex-direction: column; padding-top: 56px; padding-bottom: 66px; }
            .main-content { padding: 20px 16px; max-width: 100%; }
            .header { margin-bottom: 24px; }
            .header h2 { font-size: 22px; }
            .header p { font-size: 13px; }
            .stats-grid { grid-template-columns: repeat(2, 1fr); gap: 12px; margin-bottom: 24px; }
            .stat-card { padding: 16px; gap: 12px; }
            .stat-icon { width: 40px; height: 40px; font-size: 16px; }
            .stat-info h3 { font-size: 18px; }
            .stat-info h4 { font-size: 11px; }
            .panel { padding: 20px; margin-bottom: 20px; border-radius: 12px; }
            .panel h3 { font-size: 17px; margin-bottom: 18px; }
            .tools-grid { grid-template-columns: 1fr; gap: 14px; }
            .tool-card { padding: 18px; }
            .switch-wrapper { flex-direction: column; gap: 12px; align-items: flex-start; }
            .switch-wrapper > div:last-child { width: 100%; display: flex; gap: 10px; }
            .switch-wrapper > div:last-child .btn { flex: 1; }
            .form-group { margin-bottom: 18px; }
            input[type="text"], select { padding: 12px 14px; font-size: 16px; }
            .btn { padding: 14px 20px; font-size: 15px; }
            .log-container { height: 200px; font-size: 11px; }
        }

        @media (max-width: 480px) {
            .stats-grid { grid-template-columns: 1fr 1fr; gap: 10px; }
            .stat-card { padding: 12px 14px; }
            .stat-icon { width: 36px; height: 36px; font-size: 14px; border-radius: 8px; }
            .stat-info h3 { font-size: 15px; }
            .stat-info h4 { font-size: 10px; }
            .main-content { padding: 16px 12px; }
            .panel { padding: 16px; }
            .panel h3 { font-size: 16px; gap: 8px; }
            .header h2 { font-size: 20px; }
            .tool-card { padding: 16px; }
            .tool-title { font-size: 14px; }
            .tool-desc { font-size: 12px; margin-bottom: 14px; }
            .btn { padding: 12px 16px; font-size: 14px; }
            .log-container { height: 160px; font-size: 10px; }
            .badge { font-size: 10px; padding: 3px 8px; }
        }
    </style>
</head>
<body>
    <div id="toastContainer"></div>
    <div class="mobile-header">
        <div class="logo"><i class="fa-solid fa-layer-group"></i> ZDT</div>
        <span id="mobileVersion" style="font-size:12px; color:var(--primary);"></span>
    </div>

    <div class="sidebar">
        <div class="logo"><i class="fa-solid fa-layer-group"></i> ZDT Enterprise</div>
        <div class="nav-item active" onclick="switchTab('dashboard', this)"><i class="fa-solid fa-chart-pie"></i> Dashboard</div>
        <div class="nav-item" onclick="switchTab('statistik', this)"><i class="fa-solid fa-chart-line"></i> Statistik</div>
        <div class="nav-item" onclick="switchTab('downloader', this)"><i class="fa-solid fa-cloud-arrow-down"></i> Download</div>
        <div class="nav-item" onclick="switchTab('spotify', this)"><i class="fa-brands fa-spotify"></i> Spotify</div>
        <div class="nav-item nav-hide-mobile" onclick="switchTab('metadata', this)"><i class="fa-solid fa-tags"></i> Metadata</div>
        <div class="nav-item" onclick="switchTab('servertools', this)"><i class="fa-solid fa-toolbox"></i> Tools</div>
        <div class="nav-item nav-hide-mobile" onclick="switchTab('system', this)"><i class="fa-solid fa-server"></i> Daemons</div>
        <div class="nav-item nav-hide-mobile" onclick="switchTab('settings', this)"><i class="fa-solid fa-gear"></i> Settings</div>
        <div class="nav-more-trigger" onclick="toggleMoreMenu()"><i class="fa-solid fa-ellipsis"></i> Lainnya</div>
    </div>

    <!-- Mobile More Sheet -->
    <div class="more-overlay" id="moreOverlay" onclick="closeMoreMenu()"></div>
    <div class="more-sheet" id="moreSheet">
        <div class="more-sheet-handle"></div>
        <div class="more-sheet-item" onclick="moreNav('metadata')"><i class="fa-solid fa-tags"></i> Metadata Editor</div>
        <div class="more-sheet-item" onclick="moreNav('system')"><i class="fa-solid fa-server"></i> System Daemons</div>
        <div class="more-sheet-item" onclick="moreNav('settings')"><i class="fa-solid fa-gear"></i> Pengaturan</div>
    </div>

    <div class="main-content">
        <div class="header">
            <h2 id="pageTitle">Dashboard Overview</h2>
            <p id="pageSubtitle">Monitor your storage and system resources</p>
        </div>

        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-icon"><i class="fa-solid fa-hard-drive"></i></div>
                <div class="stat-info">
                    <h4>Free Storage</h4>
                    <h3 id="statStorage">Loading...</h3>
                </div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="color:var(--warning); background:rgba(245,158,11,0.1);"><i class="fa-solid fa-eye"></i></div>
                <div class="stat-info">
                    <h4>Watch Daemon</h4>
                    <h3 id="statWatcher">Checking...</h3>
                </div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="color:var(--accent); background:rgba(16,185,129,0.1);"><i class="fa-brands fa-telegram"></i></div>
                <div class="stat-info">
                    <h4>Telegram Bot</h4>
                    <h3 id="statTele">Checking...</h3>
                </div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="color:#a78bfa; background:rgba(167,139,250,0.1);"><i class="fa-solid fa-music"></i></div>
                <div class="stat-info">
                    <h4>Media Files</h4>
                    <h3 id="statFiles">0</h3>
                </div>
            </div>
        </div>

        <!-- Dashboard Panel -->
        <div id="dashboard" class="panel active">
            <h3><i class="fa-solid fa-home"></i> ZDT Enterprise Dashboard <span id="dashVersion" style="font-size:13px; color:var(--primary); font-weight:400;"></span></h3>
            <p style="color:var(--text-muted); line-height:1.6; font-size:15px;">
                Server lokal ZDT aktif dan siap digunakan.
                Gunakan sidebar untuk navigasi: download media, sinkronisasi Spotify, ekstrak vokal via AI, atau kelola daemon background.
            </p>
            <div style="margin-top: 30px; padding: 20px; background: rgba(0,0,0,0.2); border-radius: 8px; border: 1px solid var(--border-light);">
                <h4 style="margin:0 0 10px 0;">Current Configuration</h4>
                <div style="display:flex; gap: 20px; color: var(--text-muted); font-size:13px;">
                    <div><i class="fa-solid fa-folder"></i> Target Dir: <span id="dashTargetDir" style="color:var(--text-main);">Loading...</span></div>
                </div>
            </div>
        </div>

        <!-- Statistik Panel -->
        <div id="statistik" class="panel">
            <h3><i class="fa-solid fa-chart-line"></i> Download History & Statistik</h3>
            <div class="stats-grid">
                <div class="stat-card">
                    <div class="stat-icon" style="color:var(--primary); background:rgba(139,92,246,0.1);"><i class="fa-solid fa-music"></i></div>
                    <div class="stat-info">
                        <h4>Total Unduhan</h4>
                        <h3 id="statTotalDl">0</h3>
                    </div>
                </div>
                <div class="stat-card">
                    <div class="stat-icon" style="color:var(--success); background:rgba(16,185,129,0.1);"><i class="fa-solid fa-hard-drive"></i></div>
                    <div class="stat-info">
                        <h4>Total Ukuran</h4>
                        <h3 id="statTotalSize">0 MB</h3>
                    </div>
                </div>
                <div class="stat-card">
                    <div class="stat-icon" style="color:#1DB954; background:rgba(29,185,84,0.1);"><i class="fa-brands fa-spotify"></i></div>
                    <div class="stat-info">
                        <h4>Spotify</h4>
                        <h3 id="statSpotify">0</h3>
                    </div>
                </div>
                <div class="stat-card">
                    <div class="stat-icon" style="color:#FF0000; background:rgba(255,0,0,0.1);"><i class="fa-brands fa-youtube"></i></div>
                    <div class="stat-info">
                        <h4>YouTube</h4>
                        <h3 id="statYoutube">0</h3>
                    </div>
                </div>
            </div>
            
            <div style="display:flex; gap:20px; margin-top:20px; flex-wrap:wrap;">
                <div style="flex:1; min-width:300px; background:var(--bg-card); border-radius:8px; border:1px solid var(--border-light); padding:20px; display:flex; justify-content:center; align-items:center; box-shadow:0 4px 15px rgba(0,0,0,0.2);">
                    <canvas id="statsChart" style="max-height: 250px;"></canvas>
                </div>
                <div style="flex:2; min-width:400px; background:var(--bg-card); border-radius:8px; border:1px solid var(--border-light); overflow:hidden; box-shadow:0 4px 15px rgba(0,0,0,0.2);">
                    <h4 style="padding:15px; margin:0; border-bottom:1px solid var(--border-light);">10 Unduhan Terakhir</h4>
                    <div style="overflow-x:auto;">
                        <table style="width:100%; border-collapse:collapse; text-align:left; font-size:14px;">
                            <thead>
                                <tr style="background:rgba(255,255,255,0.05);">
                                    <th style="padding:12px 15px; border-bottom:1px solid var(--border-light);">File</th>
                                    <th style="padding:12px 15px; border-bottom:1px solid var(--border-light);">Sumber</th>
                                    <th style="padding:12px 15px; border-bottom:1px solid var(--border-light);">Ukuran</th>
                                    <th style="padding:12px 15px; border-bottom:1px solid var(--border-light);">Waktu</th>
                                </tr>
                            </thead>
                            <tbody id="recentDownloadsTbody">
                                <tr><td colspan="4" style="padding:15px; text-align:center; color:var(--text-muted);">Memuat data...</td></tr>
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
        </div>

        <!-- Downloader Panel -->
        <div id="downloader" class="panel">
            <h3><i class="fa-solid fa-cloud-arrow-down"></i> Universal Downloader</h3>
            <form id="formDownloader">
                <div class="form-group">
                    <label>Media URL (YouTube / SoundCloud / TikTok)</label>
                    <input type="text" id="dlUrl" placeholder="https://..." required>
                </div>
                <div style="display:flex; gap:15px; flex-wrap:wrap;">
                    <div class="form-group" style="flex:1; min-width:140px;">
                        <label>Format</label>
                        <select id="dlFormat" onchange="updateFormatOptions()">
                            <option value="audio">🎵 Audio Only</option>
                            <option value="video">🎬 Video</option>
                        </select>
                    </div>
                    <div class="form-group" style="flex:2;">
                        <label>Quality</label>
                        <select id="dlFormatSpec"></select>
                    </div>
                    <div class="form-group" style="flex:1; min-width:140px;" id="divBitrate" style="display:none;">
                        <label>Bitrate</label>
                        <select id="dlBitrate">
                            <option value="320">320 kbps (HQ)</option>
                            <option value="256">256 kbps</option>
                            <option value="192">192 kbps (Med)</option>
                            <option value="128">128 kbps (Low)</option>
                        </select>
                    </div>
                </div>
                <button type="submit" id="btnDl" class="btn"><i class="fa-solid fa-download"></i> Execute Download</button>
            </form>
            <div id="dlStatus" class="status-box"></div>
        </div>

        <!-- Spotify Sync Panel -->
        <div id="spotify" class="panel">
            <h3><i class="fa-brands fa-spotify"></i> Spotify Incremental Sync</h3>
            <p style="color:var(--text-muted); margin-bottom:25px; font-size:14px;">Input a Spotify Playlist URL. The system will intelligently scan your target folder and only download missing tracks.</p>
            <form id="formSpotify">
                <div class="form-group">
                    <label>Playlist URL / URI</label>
                    <input type="text" id="spUrl" placeholder="https://open.spotify.com/playlist/..." required>
                </div>
                <button type="submit" id="btnSp" class="btn btn-spotify"><i class="fa-solid fa-rotate"></i> Start Synchronization</button>
            </form>
            <div id="spStatus" class="status-box"></div>
        </div>

        <!-- Metadata Editor Panel -->
        <div id="metadata" class="panel">
            <h3><i class="fa-solid fa-tags"></i> ID3 Tag Injector</h3>
            <form id="formMeta">
                <div class="form-group">
                    <label>Select Audio File</label>
                    <select id="metaFile" required><option value="">Loading files...</option></select>
                </div>
                <div style="display:flex; gap:15px; flex-wrap:wrap;">
                    <div class="form-group" style="flex:1; min-width:140px;">
                        <label>New Title</label>
                        <input type="text" id="metaTitle" placeholder="Leave empty to keep current">
                    </div>
                    <div class="form-group" style="flex:1;">
                        <label>New Artist</label>
                        <input type="text" id="metaArtist" placeholder="Leave empty to keep current">
                    </div>
                </div>
                <button type="submit" id="btnMeta" class="btn"><i class="fa-solid fa-pen-to-square"></i> Inject Metadata</button>
            </form>
            <div id="metaStatus" class="status-box"></div>
        </div>

        <!-- Server Tools Panel -->
        <div id="servertools" class="panel">
            <h3><i class="fa-solid fa-toolbox"></i> Server Utility Tools</h3>
            <p style="color:var(--text-muted); margin-bottom:25px; font-size:14px;">Batch process and organize your media library directly on the server.</p>
            <div id="toolsStatus" class="status-box" style="margin-bottom: 20px;"></div>
            
            <div class="tools-grid">
                <!-- Clean Directory -->
                <div class="tool-card">
                    <div class="tool-icon"><i class="fa-solid fa-wand-magic-sparkles"></i></div>
                    <div class="tool-title">Clean Filenames</div>
                    <div class="tool-desc">Automatically removes trailing numbers, "(Official Video)", and weird characters from all filenames.</div>
                    <button class="btn btn-outline" onclick="runTool('clean')">Clean Library</button>
                </div>
                <!-- Make Playlist -->
                <div class="tool-card">
                    <div class="tool-icon"><i class="fa-solid fa-list-ol"></i></div>
                    <div class="tool-title">Generate Playlist</div>
                    <div class="tool-desc">Create a universal .m3u playlist file containing all tracks in the current directory.</div>
                    <button class="btn btn-outline" onclick="runTool('playlist')">Generate .m3u</button>
                </div>
                <!-- Sync Lyrics -->
                <div class="tool-card">
                    <div class="tool-icon"><i class="fa-solid fa-closed-captioning"></i></div>
                    <div class="tool-title">Auto Sync Lyrics</div>
                    <div class="tool-desc">Scan library for missing lyrics and download .lrc files automatically via syncedlyrics.</div>
                    <button class="btn btn-outline" onclick="runTool('sync_lyrics')">Sync Lyrics</button>
                </div>
                <!-- Delete All -->
                <div class="tool-card" style="border-color: rgba(239, 68, 68, 0.3);">
                    <div class="tool-icon" style="color:var(--danger);"><i class="fa-solid fa-trash-can"></i></div>
                    <div class="tool-title">Wipe Directory</div>
                    <div class="tool-desc">DANGER: Delete all media files in the current target directory permanently.</div>
                    <button class="btn btn-danger" onclick="if(confirm('Are you absolutely sure? This cannot be undone!')) runTool('delete_all')">Wipe Files</button>
                </div>
            </div>

            <h4 style="margin-top:40px; margin-bottom:20px; font-size:16px; border-bottom:1px solid var(--border-light); padding-bottom:10px;">Per-File AI & Processing</h4>
            <div class="tools-grid">
                <!-- Extract Vocals -->
                <div class="tool-card">
                    <div class="tool-title"><i class="fa-solid fa-microphone-slash"></i> Demucs AI Splitter</div>
                    <div class="tool-desc">Extract vocals and instruments into separate tracks using AI.</div>
                    <select id="toolFileDemucs" style="margin-bottom: 15px;"></select>
                    <button class="btn" style="background:#8b5cf6;" onclick="runTool('demucs')">Split Tracks</button>
                </div>
                <!-- Compress Audio -->
                <div class="tool-card">
                    <div class="tool-title"><i class="fa-solid fa-compress"></i> FFmpeg Compressor</div>
                    <div class="tool-desc">Compress large media files to save storage space without major quality loss.</div>
                    <select id="toolFileCompress" style="margin-bottom: 15px;"></select>
                    <button class="btn btn-outline" onclick="runTool('compress')">Compress File</button>
                </div>
            </div>
        </div>

        <!-- System & Daemons Panel -->
        <div id="system" class="panel">
            <h3><i class="fa-solid fa-server"></i> System Daemons</h3>
            <p style="color:var(--text-muted); margin-bottom:25px; font-size:14px;">Manage ZDT background services running on your server.</p>
            <div id="daemonStatus" class="status-box" style="margin-bottom: 20px;"></div>

            <div class="switch-wrapper">
                <div class="switch-info">
                    <h4>Watchdog Daemon <span id="badgeWatcher" class="badge badge-inactive">Offline</span></h4>
                    <p>Automatically cleans filenames and metadata whenever a new file is detected in the folder.</p>
                </div>
                <div style="display:flex; gap:10px;">
                    <button id="btnWatch" class="btn" style="width:auto; padding: 10px 15px;" onclick="toggleDaemon('watch', 'start')"><i class="fa-solid fa-play"></i> Start</button>
                </div>
            </div>

            <div class="switch-wrapper">
                <div class="switch-info">
                    <h4>Telegram Bot <span id="badgeTele" class="badge badge-inactive">Offline</span></h4>
                    <p>Control ZDT remotely via Telegram. Requires bot token to be configured.</p>
                </div>
                <div style="display:flex; gap:10px;">
                    <button id="btnTele" class="btn" style="width:auto; padding: 10px 15px;" onclick="toggleDaemon('telegram', 'start')"><i class="fa-solid fa-play"></i> Start</button>
                </div>
            </div>
        </div>

        <!-- Settings Panel -->
        <div id="settings" class="panel">
            <h3><i class="fa-solid fa-gear"></i> Global Settings</h3>
            <form id="formSettings">
                <div class="form-group">
                    <label>Target Storage Directory</label>
                    <p style="font-size:12px; color:var(--text-muted); margin-top:0;">Absolute path where files will be downloaded and processed.</p>
                    <input type="text" id="setTargetDir" placeholder="/home/user/Music" required>
                </div>
                <button type="submit" id="btnSettings" class="btn"><i class="fa-solid fa-floppy-disk"></i> Save Configuration</button>
            </form>
            <div id="settingsStatus" class="status-box"></div>
        </div>


        <div id="logSection" style="display: none;">
            <div class="header" style="margin-top: 50px; margin-bottom: 15px; display: flex; justify-content: space-between; align-items: center;">
                <h3 style="margin:0; font-size:18px;"><i class="fa-solid fa-terminal"></i> Live Task Output</h3>
                <button class="btn btn-outline" style="width:auto; padding: 5px 15px; font-size: 12px;" onclick="closeLogs()"><i class="fa-solid fa-xmark"></i> Tutup Log</button>
            </div>
            <div class="log-container" id="terminalLog">System ready. Waiting for task execution...</div>
            <div class="progress-wrapper" id="liveProgressWrapper">
                <div class="progress-fill" id="liveProgressFill"></div>
                <div class="progress-text">
                    <span id="liveProgressTask">Processing...</span>
                    <span id="liveProgressPct">0%</span>
                </div>
            </div>
        </div>
    </div>

    <script>
        function updateFormatOptions() {
            const type = document.getElementById("dlFormat").value;
            const spec = document.getElementById("dlFormatSpec");
            spec.innerHTML = "";
            if (type === "audio") {
                document.getElementById('divBitrate').style.display = 'block';
                spec.innerHTML = `
                    <option value="1">M4A (Default, Broad Compatibility)</option>
                    <option value="2">MP3 (Universal)</option>
                    <option value="3">FLAC (Lossless Studio Quality)</option>
                    <option value="4">WAV (Uncompressed)</option>
                    <option value="5">OPUS (Modern, Small Size)</option>
                    <option value="6">OGG (Open Source)</option>
                `;
            } else {
                document.getElementById('divBitrate').style.display = 'none';
                spec.innerHTML = `
                    <option value="1">MP4 (1080p / Max Res)</option>
                    <option value="2">MKV (1080p / Max Res)</option>
                    <option value="3">WebM (1080p / Max Res)</option>
                    <option value="4">MKV (Best Video + Best Audio)</option>
                `;
            }
        }
        window.addEventListener("DOMContentLoaded", () => {
            if(document.getElementById("dlFormat")) updateFormatOptions();
        });

        function switchTab(tabId, el) {
            document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
            document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
            document.getElementById(tabId).classList.add('active');
            if(el) el.classList.add('active');
            
            const titles = {
                'dashboard': ['Dashboard Overview', 'Monitor your storage and system resources'],
                'statistik': ['Statistik & Riwayat', 'Pantau aktivitas unduhan dan histori'],
                'downloader': ['Media Downloader', 'Download audio and video from various platforms'],
                'spotify': ['Spotify Synchronization', 'Keep your local library synced with Spotify'],
                'metadata': ['Metadata Editor', 'Fix missing album art and ID3 tags'],
                'servertools': ['Server Utility Tools', 'Batch process files directly on the server'],
                'system': ['System Daemons', 'Manage background automation services'],
                'settings': ['Global Settings', 'Configure ZDT core behaviors']
            };
            document.getElementById('pageTitle').innerText = titles[tabId][0];
            document.getElementById('pageSubtitle').innerText = titles[tabId][1];
            
            if(['metadata', 'servertools'].includes(tabId)) loadFiles();
            if(tabId === 'statistik') loadDbStats();
        }

        let statsChartInstance = null;

        async function loadDbStats() {
            try {
                const res = await fetch('/api/stats');
                const data = await res.json();
                if(data.success === false) return;
                
                document.getElementById('statTotalDl').innerText = data.total_count || 0;
                document.getElementById('statTotalSize').innerText = ((data.total_size_bytes || 0) / (1024*1024)).toFixed(2) + ' MB';
                const spCount = data.sources['spotify'] || 0;
                const ytCount = data.sources['youtube'] || 0;
                document.getElementById('statSpotify').innerText = spCount;
                document.getElementById('statYoutube').innerText = ytCount;
                
                const ctx = document.getElementById('statsChart');
                if(ctx) {
                    if(statsChartInstance) statsChartInstance.destroy();
                    statsChartInstance = new Chart(ctx, {
                        type: 'doughnut',
                        data: {
                            labels: ['Spotify', 'YouTube', 'Lainnya'],
                            datasets: [{
                                data: [spCount, ytCount, (data.total_count || 0) - spCount - ytCount],
                                backgroundColor: ['#1DB954', '#FF0000', '#6366f1'],
                                borderWidth: 0,
                                hoverOffset: 4
                            }]
                        },
                        options: {
                            responsive: true,
                            maintainAspectRatio: false,
                            cutout: '70%',
                            plugins: {
                                legend: { position: 'bottom', labels: { color: '#ffffff', padding: 20, font: { family: 'Inter', size: 12 } } },
                                title: { display: true, text: 'Proporsi Sumber Unduhan', color: '#a1a1aa', font: { family: 'Inter', size: 14, weight: 'normal' } }
                            }
                        }
                    });
                }
                
                const tbody = document.getElementById('recentDownloadsTbody');
                tbody.innerHTML = '';
                if(!data.recent || data.recent.length === 0) {
                    tbody.innerHTML = '<tr><td colspan="4" style="padding:15px; text-align:center; color:var(--text-muted);">Belum ada riwayat unduhan.</td></tr>';
                } else {
                    data.recent.forEach(item => {
                        const tr = document.createElement('tr');
                        const sizeMB = (item.size_bytes / (1024*1024)).toFixed(2) + ' MB';
                        let sourceIcon = '';
                        if(item.source === 'spotify') sourceIcon = '<i class="fa-brands fa-spotify" style="color:#1DB954"></i> Spotify';
                        else if(item.source === 'youtube') sourceIcon = '<i class="fa-brands fa-youtube" style="color:#FF0000"></i> YouTube';
                        else sourceIcon = item.source;
                        
                        tr.innerHTML = `
                            <td style="padding:12px 15px; border-bottom:1px solid rgba(255,255,255,0.05); max-width:200px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;" title="${item.filename}">${item.filename}</td>
                            <td style="padding:12px 15px; border-bottom:1px solid rgba(255,255,255,0.05);">${sourceIcon}</td>
                            <td style="padding:12px 15px; border-bottom:1px solid rgba(255,255,255,0.05);">${sizeMB}</td>
                            <td style="padding:12px 15px; border-bottom:1px solid rgba(255,255,255,0.05); color:var(--text-muted); font-size:12px;">${item.timestamp}</td>
                        `;
                        tbody.appendChild(tr);
                    });
                }
            } catch(e) { console.error(e); }
        }

        async function loadStatus() {
            try {
                const res = await fetch('/api/status');
                const data = await res.json();
                document.getElementById('statStorage').innerText = data.storage_free + ' Free';
                
                const wStatus = data.watcher;
                document.getElementById('statWatcher').innerText = wStatus ? 'Running' : 'Stopped';
                const bWatcher = document.getElementById('badgeWatcher');
                bWatcher.className = wStatus ? 'badge badge-active' : 'badge badge-inactive';
                bWatcher.innerText = wStatus ? 'Running' : 'Offline';
                const btnWatch = document.getElementById('btnWatch');
                if (btnWatch) {
                    btnWatch.className = wStatus ? 'btn btn-danger' : 'btn';
                    btnWatch.innerHTML = wStatus ? '<i class="fa-solid fa-stop"></i> Stop' : '<i class="fa-solid fa-play"></i> Start';
                    btnWatch.onclick = () => toggleDaemon('watch', wStatus ? 'stop' : 'start');
                }

                const tStatus = data.telegram;
                document.getElementById('statTele').innerText = tStatus ? 'Active' : 'Offline';
                const bTele = document.getElementById('badgeTele');
                bTele.className = tStatus ? 'badge badge-active' : 'badge badge-inactive';
                bTele.innerText = tStatus ? 'Active' : 'Offline';
                const btnTele = document.getElementById('btnTele');
                if (btnTele) {
                    btnTele.className = tStatus ? 'btn btn-danger' : 'btn';
                    btnTele.innerHTML = tStatus ? '<i class="fa-solid fa-stop"></i> Stop' : '<i class="fa-solid fa-play"></i> Start';
                    btnTele.onclick = () => toggleDaemon('telegram', tStatus ? 'stop' : 'start');
                }

                if(document.getElementById('dashTargetDir').innerText === 'Loading...') {
                    document.getElementById('dashTargetDir').innerText = data.target_dir;
                    document.getElementById('setTargetDir').value = data.target_dir;
                }
                document.getElementById('statFiles').innerText = (data.file_count || 0) + ' files';
                if(data.version) {
                    document.getElementById('dashVersion').innerText = 'v' + data.version;
                    document.getElementById('mobileVersion').innerText = 'v' + data.version;
                }
            } catch(e) {}
        }
        setInterval(loadStatus, 3000);
        loadStatus();

        // TOAST NOTIFICATION LOGIC
        function showToast(message, type = 'info') {
            const container = document.getElementById('toastContainer');
            const toast = document.createElement('div');
            toast.className = `toast ${type}`;
            
            let iconClass = 'fa-solid fa-circle-info';
            if (type === 'success') iconClass = 'fa-solid fa-circle-check';
            if (type === 'error') iconClass = 'fa-solid fa-circle-exclamation';
            
            toast.innerHTML = `<div class="toast-icon"><i class="${iconClass}"></i></div><div>${message}</div>`;
            container.appendChild(toast);
            
            setTimeout(() => {
                toast.style.animation = 'fadeOut 0.3s forwards';
                setTimeout(() => toast.remove(), 300);
            }, 4000);
        }

        // CSRF Token management
        let csrfToken = '';
        
        async function refreshCsrfToken() {
            try {
                const res = await fetch('/api/csrf-token');
                const data = await res.json();
                if (data.csrf_token) csrfToken = data.csrf_token;
            } catch(e) {}
        }
        
        function csrfFetch(url, options = {}) {
            if (!options.headers) options.headers = {};
            options.headers['X-CSRF-Token'] = csrfToken;
            if (!options.headers['Content-Type']) options.headers['Content-Type'] = 'application/json';
            return fetch(url, options).then(async res => {
                // Refresh CSRF token after each request
                if (res.status !== 403) refreshCsrfToken();
                return res;
            });
        }
        
        // Initial CSRF token fetch
        refreshCsrfToken();
        // Refresh token periodically
        setInterval(refreshCsrfToken, 300000); // every 5 minutes

        async function loadFiles() {
            try {
                const res = await fetch('/api/files');
                const data = await res.json();
                const selMeta = document.getElementById('metaFile');
                const selDem = document.getElementById('toolFileDemucs');
                const selComp = document.getElementById('toolFileCompress');
                selMeta.innerHTML = selDem.innerHTML = selComp.innerHTML = '<option value="">-- Select File --</option>';
                data.files.forEach(f => {
                    const opt = `<option value="${f}">${f}</option>`;
                    selMeta.innerHTML += opt; selDem.innerHTML += opt; selComp.innerHTML += opt;
                });
            } catch(e) {}
        }

        function handleFormSubmit(formId, btnId, statusId, apiEndpoint, payloadBuilder, loadingText) {
            document.getElementById(formId).addEventListener('submit', async (e) => {
                e.preventDefault();
                const btn = document.getElementById(btnId);
                const status = document.getElementById(statusId);
                const originalHtml = btn.innerHTML;
                btn.disabled = true; btn.innerHTML = `<i class="fa-solid fa-circle-notch fa-spin"></i> ${loadingText}`;
                try {
                    const res = await csrfFetch(apiEndpoint, {
                        method: 'POST', headers: {'Content-Type': 'application/json'},
                        body: JSON.stringify(payloadBuilder())
                    });
                    const data = await res.json();
                    showToast(data.message, data.success ? 'success' : 'error');
                    if(data.success && formId !== 'formSettings' && formId !== 'formMeta') e.target.reset();
                    if(formId === 'formSettings') { document.getElementById('dashTargetDir').innerText = 'Loading...'; loadStatus(); }
                } catch(err) { showToast('Connection Error!', 'error'); }
                btn.disabled = false; btn.innerHTML = originalHtml;
            });
        }

        handleFormSubmit('formDownloader', 'btnDl', 'dlStatus', '/api/download', () => ({
            url: document.getElementById('dlUrl').value,
            format: document.getElementById('dlFormat').value,
            spec: document.getElementById('dlFormatSpec').value,
            bitrate: document.getElementById('dlBitrate').value
        }), 'EXECUTING...');

        handleFormSubmit('formSpotify', 'btnSp', 'spStatus', '/api/spotify-sync', () => ({
            url: document.getElementById('spUrl').value
        }), 'SYNCING...');

        handleFormSubmit('formMeta', 'btnMeta', 'metaStatus', '/api/metadata', () => ({
            filename: document.getElementById('metaFile').value,
            title: document.getElementById('metaTitle').value,
            artist: document.getElementById('metaArtist').value
        }), 'INJECTING...');

        handleFormSubmit('formSettings', 'btnSettings', 'settingsStatus', '/api/settings/storage', () => ({
            path: document.getElementById('setTargetDir').value
        }), 'SAVING...');

        async function runTool(toolType) {
            showToast('Dispatching command to server...', 'info');
            
            let payload = { action: toolType, csrf_token: csrfToken };
            if (toolType === 'demucs') {
                payload.filename = document.getElementById('toolFileDemucs').value;
                if (!payload.filename) return alert("Please select a file first!");
            }
            if (toolType === 'compress') {
                payload.filename = document.getElementById('toolFileCompress').value;
                if (!payload.filename) return alert("Please select a file first!");
            }

            try {
                const res = await csrfFetch('/api/tools', {
                    method: 'POST', headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify(payload)
                });
                const data = await res.json();
                showToast(data.message, data.success ? 'success' : 'error');
                if(data.success) { loadFiles(); loadStatus(); }
            } catch(err) {
                showToast('Connection Error!', 'error');
            }
        }

        async function toggleDaemon(service, action) {
            showToast(`Sending ${action} command to ${service}...`, 'info');
            try {
                const res = await csrfFetch('/api/daemon', {
                    method: 'POST', headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({ service, action, csrf_token: csrfToken })
                });
                const data = await res.json();
                showToast(data.message, data.success ? 'success' : 'error');
                loadStatus();
            } catch(err) {
                showToast('Connection Error!', 'error');
            }
        }

        // More menu functions
        function toggleMoreMenu() {
            document.getElementById('moreOverlay').classList.toggle('show');
            document.getElementById('moreSheet').classList.toggle('show');
            document.querySelector('.nav-more-trigger').classList.toggle('active');
        }
        function closeMoreMenu() {
            document.getElementById('moreOverlay').classList.remove('show');
            document.getElementById('moreSheet').classList.remove('show');
            document.querySelector('.nav-more-trigger').classList.remove('active');
        }
        function moreNav(tabId) {
            closeMoreMenu();
            // Find the hidden nav-item for this tab and activate it
            document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
            document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
            document.getElementById(tabId).classList.add('active');
            // Highlight the correct sidebar item
            document.querySelectorAll('.nav-item').forEach(n => {
                if(n.getAttribute('onclick') && n.getAttribute('onclick').includes(tabId)) n.classList.add('active');
            });
            document.querySelector('.nav-more-trigger').classList.add('active');
            const titles = {
                'metadata': ['Metadata Editor', 'Fix missing album art and ID3 tags'],
                'system': ['System Daemons', 'Manage background automation services'],
                'settings': ['Global Settings', 'Configure ZDT core behaviors']
            };
            if(titles[tabId]) {
                document.getElementById('pageTitle').innerText = titles[tabId][0];
                document.getElementById('pageSubtitle').innerText = titles[tabId][1];
            }
            if(tabId === 'metadata') loadFiles();
        }

        async function closeLogs() {
            document.getElementById("logSection").style.display = "none";
            await csrfFetch('/api/logs/clear', {method: 'POST'});
        }

        setInterval(async () => {
            try {
                const res = await fetch("/api/logs");
                const data = await res.json();
                if(data.log && data.log.trim().length > 0 && data.log !== "No active tasks.") {
                    document.getElementById("logSection").style.display = "block";
                    const term = document.getElementById("terminalLog");
                    
                    if (term.textContent !== data.log) {
                        term.textContent = data.log;
                        term.scrollTop = term.scrollHeight;
                        
                        // Regex Parser for Progress Bar
                        const logLines = data.log.split('\\n');
                        let lastProgressLine = "";
                        for (let i = logLines.length - 1; i >= 0; i--) {
                            if (logLines[i].includes('%')) { lastProgressLine = logLines[i]; break; }
                        }
                        
                        const wrapper = document.getElementById("liveProgressWrapper");
                        const fill = document.getElementById("liveProgressFill");
                        const pctSpan = document.getElementById("liveProgressPct");
                        const taskSpan = document.getElementById("liveProgressTask");
                        
                        if (lastProgressLine) {
                            wrapper.style.display = "block";
                            const match = lastProgressLine.match(/(\\d+\\.?\\d*)%/);
                            if (match && match[1]) {
                                fill.style.width = match[1] + '%';
                                pctSpan.innerText = match[1] + '%';
                                
                                if (lastProgressLine.toLowerCase().includes('download')) taskSpan.innerText = "Downloading Media...";
                                else if (lastProgressLine.toLowerCase().includes('split')) taskSpan.innerText = "Splitting Stems (Demucs)...";
                                else if (lastProgressLine.toLowerCase().includes('size')) taskSpan.innerText = "Compressing Media (FFmpeg)...";
                                else taskSpan.innerText = "Processing...";
                            }
                        } else {
                            wrapper.style.display = "none";
                        }
                    }
                } else {
                    document.getElementById("logSection").style.display = "none";
                    document.getElementById("liveProgressWrapper").style.display = "none";
                }
            } catch(e) {}
        }, 1500);
    </script>
</body>
</html>

"""

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
    return render_template_string(HTML_TEMPLATE)

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
    except:
        return False

@app.route('/api/status', methods=['GET'])
@requires_auth
def get_status():
    target = get_target_dir()
    storage_free = "Unknown"
    try:
        total, used, free = shutil.disk_usage(target if os.path.exists(target) else "/")
        storage_free = f"{free // (2**30)} GB"
    except:
        pass
    
    # Count media files
    file_count = 0
    if os.path.exists(target):
        for ext in ['*.mp3','*.m4a','*.flac','*.wav','*.ogg','*.opus','*.mp4','*.mkv']:
            file_count += len(glob.glob(os.path.join(target, ext)))
    
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
    for ext in ['*.mp3', '*.m4a', '*.flac', '*.wav', '*.ogg', '*.opus', '*.mp4', '*.mkv', '*.webm']:
        for f in glob.glob(os.path.join(target, ext)):
            files.append(os.path.basename(f))
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
    def find_script(name):
        for p in [os.path.join(script_dir, name), os.path.expanduser(f"~/.local/share/zdt/{name}")]:
            if os.path.exists(p): return p
        return os.path.join(script_dir, name)
    script_map = {
        'watch': find_script('zdt-watch.py'),
        'telegram': find_script('zdt-telegram.py')
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
    if filename:
        allowed_files = []
        if os.path.exists(target):
            for ext in ['*.mp3', '*.m4a', '*.flac', '*.wav', '*.ogg', '*.opus', '*.mp4', '*.mkv', '*.webm']:
                allowed_files.extend(glob.glob(os.path.join(target, ext)))
        allowed_basenames = {os.path.basename(f) for f in allowed_files}
        if filename not in allowed_basenames:
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
            media_exts = {'.mp3', '.m4a', '.flac', '.wav', '.ogg', '.opus', '.mp4', '.mkv', '.webm', '.avi', '.mov', '.ts', '.jpg', '.jpeg', '.png', '.lrc', '.m3u', '.srt'}
            for f in os.listdir(target):
                fp = os.path.join(target, f)
                if os.path.isfile(fp) and os.path.splitext(f)[1].lower() in media_exts:
                    try:
                        os.remove(fp)
                        count += 1
                    except: pass
            return jsonify({"success": True, "message": f"Berhasil menghapus {count} file media dari Storage!"})

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

@app.route("/api/logs", methods=["GET"])
@requires_auth
def get_logs():
    log_file = WEB_TASK_LOG_PATH
    if os.path.exists(log_file):
        with open(log_file, "r") as f:
            lines = f.readlines()
            if lines: return jsonify({"log": "".join(lines[-100:])})
    return jsonify({"log": "No active tasks."})

@app.route("/api/logs/clear", methods=["POST"])
@requires_auth
@requires_csrf
def clear_logs():
    try: os.remove(WEB_TASK_LOG_PATH)
    except: pass
    return jsonify({"success": True})

if __name__ == '__main__':
    _ensure_password()
    import argparse
    parser = argparse.ArgumentParser(description='ZDT Enterprise Dashboard')
    parser.add_argument('--bind', default='127.0.0.1', help='Bind address (default: 127.0.0.1)')
    parser.add_argument('--port', type=int, default=5000, help='Port number (default: 5000)')
    args = parser.parse_args()
    print(f"Memulai ZDT Enterprise Dashboard di {args.bind}:{args.port}...")
    app.run(host=args.bind, port=args.port, debug=False)
