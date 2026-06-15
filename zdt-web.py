#!/usr/bin/env python3
import os
import sys
import subprocess
import shutil
import glob
from flask import Flask, request, render_template_string, jsonify
try:
    import mutagen
    from mutagen.easyid3 import EasyID3
    from mutagen.mp4 import MP4, MP4Cover
    from mutagen.flac import FLAC, Picture
except ImportError:
    pass

app = Flask(__name__)

# Config Directory
CONFIG_FILE = os.path.expanduser("~/.config/zdt/config.env")
def get_target_dir():
    target_dir = os.path.expanduser("~/Music/ZDT_Downloads")
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, 'r') as f:
            for line in f:
                if line.startswith("TARGET_DIR="):
                    target_dir = line.strip().split('=', 1)[1].strip('"').strip("'")
    return target_dir

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ZDT Web Dashboard V2</title>
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" rel="stylesheet">
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;800&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg-dark: #09090e;
            --panel-bg: rgba(20, 20, 30, 0.6);
            --primary: #00f0ff;
            --primary-glow: rgba(0, 240, 255, 0.4);
            --secondary: #7000ff;
            --accent: #ff003c;
            --text: #e2e2e2;
            --text-dim: #888899;
            --glass-border: rgba(255, 255, 255, 0.05);
        }
        
        body {
            margin: 0;
            padding: 0;
            font-family: 'Outfit', sans-serif;
            background-color: var(--bg-dark);
            color: var(--text);
            min-height: 100vh;
            display: flex;
            background-image: 
                radial-gradient(circle at 15% 50%, rgba(112, 0, 255, 0.15), transparent 25%),
                radial-gradient(circle at 85% 30%, rgba(0, 240, 255, 0.15), transparent 25%);
            background-attachment: fixed;
            overflow-x: hidden;
        }

        /* Sidebar */
        .sidebar {
            width: 260px;
            background: var(--panel-bg);
            backdrop-filter: blur(20px);
            border-right: 1px solid var(--glass-border);
            padding: 30px 0;
            display: flex;
            flex-direction: column;
            z-index: 10;
        }
        
        .logo {
            text-align: center;
            font-size: 32px;
            font-weight: 800;
            color: white;
            margin-bottom: 40px;
            letter-spacing: 2px;
            text-shadow: 0 0 15px var(--primary-glow);
        }
        .logo span { color: var(--primary); }

        .nav-item {
            padding: 15px 30px;
            cursor: pointer;
            display: flex;
            align-items: center;
            gap: 15px;
            font-weight: 600;
            color: var(--text-dim);
            transition: all 0.3s;
            border-left: 3px solid transparent;
        }
        
        .nav-item:hover, .nav-item.active {
            color: white;
            background: rgba(255,255,255,0.03);
            border-left: 3px solid var(--primary);
            text-shadow: 0 0 10px rgba(255,255,255,0.3);
        }
        
        .nav-item i { width: 20px; font-size: 18px; color: var(--primary); }

        /* Main Content */
        .main-content {
            flex: 1;
            padding: 40px;
            position: relative;
        }
        
        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 40px;
        }
        
        .header h2 {
            margin: 0;
            font-size: 28px;
            font-weight: 800;
        }

        /* Stats Cards */
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 40px;
        }
        
        .stat-card {
            background: var(--panel-bg);
            backdrop-filter: blur(15px);
            border: 1px solid var(--glass-border);
            border-radius: 15px;
            padding: 20px;
            display: flex;
            align-items: center;
            gap: 20px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            transition: transform 0.3s;
        }
        .stat-card:hover { transform: translateY(-5px); }
        .stat-icon {
            width: 50px; height: 50px;
            border-radius: 12px;
            background: rgba(0, 240, 255, 0.1);
            color: var(--primary);
            display: flex; justify-content: center; align-items: center;
            font-size: 24px;
        }
        .stat-info h4 { margin: 0; color: var(--text-dim); font-size: 14px; font-weight: 400; }
        .stat-info h3 { margin: 5px 0 0; font-size: 22px; font-weight: 600; }

        /* Panels */
        .panel {
            background: var(--panel-bg);
            backdrop-filter: blur(15px);
            border: 1px solid var(--glass-border);
            border-radius: 15px;
            padding: 30px;
            margin-bottom: 30px;
            display: none;
            animation: fadeIn 0.4s ease forwards;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
        }
        .panel.active { display: block; }
        
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(10px); }
            to { opacity: 1; transform: translateY(0); }
        }

        .form-group { margin-bottom: 25px; }
        label { display: block; margin-bottom: 10px; font-weight: 600; font-size: 14px; color: var(--primary); }
        
        input[type="text"], select {
            width: 100%;
            padding: 15px;
            background: rgba(0,0,0,0.3);
            border: 1px solid rgba(255,255,255,0.1);
            color: white;
            border-radius: 8px;
            font-family: 'Outfit', sans-serif;
            font-size: 16px;
            box-sizing: border-box;
            transition: all 0.3s;
        }
        input[type="text"]:focus, select:focus {
            outline: none;
            border-color: var(--primary);
            box-shadow: 0 0 15px var(--primary-glow);
            background: rgba(0,0,0,0.5);
        }

        .btn {
            background: linear-gradient(45deg, var(--secondary), var(--primary));
            color: white;
            border: none;
            padding: 15px 30px;
            border-radius: 8px;
            font-family: inherit;
            font-size: 16px;
            font-weight: 800;
            cursor: pointer;
            width: 100%;
            transition: all 0.3s;
            text-transform: uppercase;
            letter-spacing: 1px;
            box-shadow: 0 5px 15px rgba(0, 240, 255, 0.2);
        }
        .btn:hover {
            transform: scale(1.02);
            box-shadow: 0 8px 25px rgba(0, 240, 255, 0.4);
        }
        .btn:disabled { opacity: 0.6; cursor: not-allowed; transform: none; }
        
        .btn-spotify { background: linear-gradient(45deg, #1DB954, #1ed760); box-shadow: 0 5px 15px rgba(29, 185, 84, 0.3); }
        .btn-spotify:hover { box-shadow: 0 8px 25px rgba(29, 185, 84, 0.5); }

        .status-box {
            margin-top: 20px;
            padding: 15px;
            border-radius: 8px;
            text-align: center;
            display: none;
            font-weight: 600;
            animation: fadeIn 0.3s ease;
        }
        .status-box.success { display: block; background: rgba(0, 255, 0, 0.1); color: #00ff00; border: 1px solid rgba(0,255,0,0.2); }
        .status-box.error { display: block; background: rgba(255, 0, 60, 0.1); color: var(--accent); border: 1px solid rgba(255,0,60,0.2); }

    </style>
</head>
<body>

    <div class="sidebar">
        <div class="logo">ZDT<span>.</span></div>
        <div class="nav-item active" onclick="switchTab('dashboard')"><i class="fa-solid fa-chart-pie"></i> Dashboard</div>
        <div class="nav-item" onclick="switchTab('downloader')"><i class="fa-solid fa-cloud-arrow-down"></i> Downloader</div>
        <div class="nav-item" onclick="switchTab('spotify')"><i class="fa-brands fa-spotify"></i> Spotify Sync</div>
        <div class="nav-item" onclick="switchTab('metadata')"><i class="fa-solid fa-tags"></i> Metadata Editor</div>
    </div>

    <div class="main-content">
        <div class="header">
            <h2><span id="pageTitle">Dashboard</span> Overview</h2>
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
                <div class="stat-icon"><i class="fa-solid fa-eye"></i></div>
                <div class="stat-info">
                    <h4>Watch Daemon</h4>
                    <h3 id="statWatcher">Checking...</h3>
                </div>
            </div>
            <div class="stat-card">
                <div class="stat-icon"><i class="fa-brands fa-telegram"></i></div>
                <div class="stat-info">
                    <h4>Telegram Bot</h4>
                    <h3 id="statTele">Checking...</h3>
                </div>
            </div>
        </div>

        <!-- Dashboard Panel -->
        <div id="dashboard" class="panel active">
            <h3 style="margin-top:0; color:var(--primary);">Welcome to ZDT Premium Dashboard</h3>
            <p style="color:var(--text-dim); line-height:1.6;">
                Anda terhubung ke server lokal Zaki Downloader Tools. 
                Gunakan menu di sidebar untuk mendownload media, melakukan sinkronisasi otomatis playlist Spotify, 
                atau merapikan metadata file langsung dari peramban Anda.
            </p>
        </div>

        <!-- Downloader Panel -->
        <div id="downloader" class="panel">
            <h3 style="margin-top:0; color:var(--primary);">Universal Media Downloader</h3>
            <form id="formDownloader">
                <div class="form-group">
                    <label>Media URL (YouTube/Soundcloud/TikTok)</label>
                    <input type="text" id="dlUrl" placeholder="https://youtube.com/watch?v=..." required>
                </div>
                <div class="form-group">
                    <label>Format</label>
                    <select id="dlFormat">
                        <option value="audio">🎵 Audio MP3 (High Quality)</option>
                        <option value="video">🎬 Video MP4 (Max Resolution)</option>
                    </select>
                </div>
                <button type="submit" id="btnDl" class="btn"><i class="fa-solid fa-bolt"></i> Execute Download</button>
            </form>
            <div id="dlStatus" class="status-box"></div>
        </div>

        <!-- Spotify Sync Panel -->
        <div id="spotify" class="panel">
            <h3 style="margin-top:0; color:#1DB954;">Spotify Incremental Sync</h3>
            <p style="color:var(--text-dim); margin-bottom:25px;">Masukkan link Playlist Spotify Anda. Sistem akan mencari dan hanya mengunduh lagu-lagu baru yang belum Anda miliki.</p>
            <form id="formSpotify">
                <div class="form-group">
                    <label style="color:#1DB954;">Playlist URL / URI</label>
                    <input type="text" id="spUrl" placeholder="https://open.spotify.com/playlist/..." required>
                </div>
                <button type="submit" id="btnSp" class="btn btn-spotify"><i class="fa-solid fa-sync"></i> Start Sync Process</button>
            </form>
            <div id="spStatus" class="status-box"></div>
        </div>

        <!-- Metadata Editor Panel -->
        <div id="metadata" class="panel">
            <h3 style="margin-top:0; color:var(--primary);">ID3 Tag Injector</h3>
            <form id="formMeta">
                <div class="form-group">
                    <label>Pilih File Audio di Server</label>
                    <select id="metaFile" required>
                        <option value="">Loading files...</option>
                    </select>
                </div>
                <div class="form-group">
                    <label>Judul Baru</label>
                    <input type="text" id="metaTitle" placeholder="Kosongkan jika tidak diubah">
                </div>
                <div class="form-group">
                    <label>Nama Artis Baru</label>
                    <input type="text" id="metaArtist" placeholder="Kosongkan jika tidak diubah">
                </div>
                <button type="submit" id="btnMeta" class="btn"><i class="fa-solid fa-pen-nib"></i> Inject Metadata</button>
            </form>
            <div id="metaStatus" class="status-box"></div>
        </div>

    </div>

    <script>
        // Tab Switcher
        function switchTab(tabId) {
            document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
            document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
            document.getElementById(tabId).classList.add('active');
            event.currentTarget.classList.add('active');
            
            const titles = {
                'dashboard': 'Dashboard',
                'downloader': 'Media Downloader',
                'spotify': 'Spotify Synchronization',
                'metadata': 'Metadata Editor'
            };
            document.getElementById('pageTitle').innerText = titles[tabId];
            
            if(tabId === 'metadata') loadFiles();
        }

        // Fetch System Status
        async function loadStatus() {
            try {
                const res = await fetch('/api/status');
                const data = await res.json();
                document.getElementById('statStorage').innerText = data.storage_free + ' Free';
                document.getElementById('statWatcher').innerText = data.watcher ? '🟢 Running' : '🔴 Stopped';
                document.getElementById('statWatcher').style.color = data.watcher ? '#00ff00' : '#ff003c';
                document.getElementById('statTele').innerText = data.telegram ? '🟢 Active' : '🔴 Offline';
                document.getElementById('statTele').style.color = data.telegram ? '#00ff00' : '#ff003c';
            } catch(e) {}
        }
        setInterval(loadStatus, 5000);
        loadStatus();

        // Load Audio Files for Metadata
        async function loadFiles() {
            try {
                const res = await fetch('/api/files');
                const data = await res.json();
                const sel = document.getElementById('metaFile');
                sel.innerHTML = '<option value="">-- Pilih File --</option>';
                data.files.forEach(f => {
                    sel.innerHTML += `<option value="${f}">${f}</option>`;
                });
            } catch(e) {}
        }

        // Handle Downloader Form
        document.getElementById('formDownloader').addEventListener('submit', async (e) => {
            e.preventDefault();
            const url = document.getElementById('dlUrl').value;
            const format = document.getElementById('dlFormat').value;
            const btn = document.getElementById('btnDl');
            const status = document.getElementById('dlStatus');
            
            btn.disabled = true; btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> EXECUTING...';
            status.className = 'status-box';
            
            try {
                const res = await fetch('/api/download', {
                    method: 'POST', headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({url, format})
                });
                const data = await res.json();
                if(data.success) {
                    status.className = 'status-box success';
                    status.innerText = '✅ Proses download dikirim ke server background!';
                    document.getElementById('dlUrl').value = '';
                } else {
                    status.className = 'status-box error';
                    status.innerText = '❌ ' + data.message;
                }
            } catch(err) {
                status.className = 'status-box error'; status.innerText = 'Connection Error!';
            }
            btn.disabled = false; btn.innerHTML = '<i class="fa-solid fa-bolt"></i> Execute Download';
        });

        // Handle Spotify Sync
        document.getElementById('formSpotify').addEventListener('submit', async (e) => {
            e.preventDefault();
            const url = document.getElementById('spUrl').value;
            const btn = document.getElementById('btnSp');
            const status = document.getElementById('spStatus');
            
            btn.disabled = true; btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> SYNCING...';
            status.className = 'status-box';
            
            try {
                const res = await fetch('/api/spotify-sync', {
                    method: 'POST', headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({url})
                });
                const data = await res.json();
                if(data.success) {
                    status.className = 'status-box success';
                    status.innerText = '✅ Proses sinkronisasi dimulai di server!';
                    document.getElementById('spUrl').value = '';
                } else {
                    status.className = 'status-box error';
                    status.innerText = '❌ ' + data.message;
                }
            } catch(err) {
                status.className = 'status-box error'; status.innerText = 'Connection Error!';
            }
            btn.disabled = false; btn.innerHTML = '<i class="fa-solid fa-sync"></i> Start Sync Process';
        });

        // Handle Metadata
        document.getElementById('formMeta').addEventListener('submit', async (e) => {
            e.preventDefault();
            const filename = document.getElementById('metaFile').value;
            const title = document.getElementById('metaTitle').value;
            const artist = document.getElementById('metaArtist').value;
            const btn = document.getElementById('btnMeta');
            const status = document.getElementById('metaStatus');
            
            btn.disabled = true; btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> INJECTING...';
            status.className = 'status-box';
            
            try {
                const res = await fetch('/api/metadata', {
                    method: 'POST', headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({filename, title, artist})
                });
                const data = await res.json();
                if(data.success) {
                    status.className = 'status-box success';
                    status.innerText = '✅ Metadata berhasil disimpan!';
                } else {
                    status.className = 'status-box error';
                    status.innerText = '❌ ' + data.message;
                }
            } catch(err) {
                status.className = 'status-box error'; status.innerText = 'Connection Error!';
            }
            btn.disabled = false; btn.innerHTML = '<i class="fa-solid fa-pen-nib"></i> Inject Metadata';
        });
    </script>
</body>
</html>
"""

@app.route('/')
def index():
    return render_template_string(HTML_TEMPLATE)

@app.route('/api/status', methods=['GET'])
def system_status():
    target = get_target_dir()
    free_space = "Unknown"
    if os.path.exists(target):
        total, used, free = shutil.disk_usage(target)
        free_space = f"{free // (2**30)} GB"
    
    # Check processes
    try:
        ps = subprocess.check_output(['ps', 'aux']).decode('utf-8')
        watcher = 'zdt-watch.py' in ps
        tele = 'zdt-telegram.py' in ps
    except:
        watcher = False
        tele = False
        
    return jsonify({
        "storage_free": free_space,
        "watcher": watcher,
        "telegram": tele
    })

@app.route('/api/download', methods=['POST'])
def download():
    data = request.json
    url = data.get('url', '')
    fmt = data.get('format', 'audio')
    
    if not url: return jsonify({"success": False, "message": "URL kosong"})
        
    zdt_bin = "/home/zaki/.local/bin/zdt" if os.path.exists("/home/zaki/.local/bin/zdt") else "/home/zaki/zdt.sh"
    cmd = [zdt_bin, "--download-audio" if fmt == 'audio' else "--download-video", url]
        
    try:
        with open(os.devnull, 'w') as devnull:
            subprocess.Popen(cmd, stdout=devnull, stderr=devnull, start_new_session=True)
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"success": False, "message": str(e)})

@app.route('/api/spotify-sync', methods=['POST'])
def spotify_sync():
    url = request.json.get('url', '')
    if not url: return jsonify({"success": False, "message": "URL kosong"})
    
    zdt_bin = "/home/zaki/.local/bin/zdt" if os.path.exists("/home/zaki/.local/bin/zdt") else "/home/zaki/zdt.sh"
    cmd = [zdt_bin, "--spotify-sync", url]
    
    try:
        with open(os.devnull, 'w') as devnull:
            subprocess.Popen(cmd, stdout=devnull, stderr=devnull, start_new_session=True)
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"success": False, "message": str(e)})

@app.route('/api/files', methods=['GET'])
def list_files():
    target = get_target_dir()
    files = []
    if os.path.exists(target):
        for ext in ['*.mp3', '*.m4a', '*.flac']:
            for f in glob.glob(os.path.join(target, ext)):
                files.append(os.path.basename(f))
    return jsonify({"files": files})

@app.route('/api/metadata', methods=['POST'])
def edit_metadata():
    data = request.json
    filename = data.get('filename')
    title = data.get('title')
    artist = data.get('artist')
    
    if not filename: return jsonify({"success": False, "message": "Pilih file terlebih dahulu"})
    
    filepath = os.path.join(get_target_dir(), filename)
    if not os.path.exists(filepath):
        return jsonify({"success": False, "message": "File tidak ditemukan di server"})
        
    try:
        ext = filepath.lower()
        if ext.endswith('.mp3'):
            import mutagen.id3
            try: audio = mutagen.id3.ID3(filepath)
            except: 
                audio = mutagen.id3.ID3()
                audio.save(filepath)
            if title: audio.add(mutagen.id3.TIT2(encoding=3, text=title))
            if artist: audio.add(mutagen.id3.TPE1(encoding=3, text=artist))
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
            
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"success": False, "message": f"Gagal memproses file: {str(e)}"})

if __name__ == '__main__':
    print("Memulai ZDT Web Dashboard V2 di port 5000...")
    app.run(host='0.0.0.0', port=5000)
