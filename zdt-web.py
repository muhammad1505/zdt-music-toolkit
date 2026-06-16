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


# Clear old task logs on startup
if os.path.exists("/tmp/zdt_web_task.log"):
    try:
        os.remove("/tmp/zdt_web_task.log")
    except:
        pass

app = Flask(__name__)

# Config Directory
CONFIG_FILE = os.path.expanduser("~/.config/zdt/config.env")

def get_target_dir():
    target_dir = os.path.expanduser("~/Music/ZDT_Downloads")
    
    # 1. Cek config lama
    old_conf = os.path.expanduser("~/.config/zdt/config")
    if os.path.exists(old_conf):
        with open(old_conf, "r") as f:
            for line in f:
                if line.startswith("storage_dir="):
                    val = line.strip().split("=", 1)[1].strip("\"").strip("'")
                    if val: target_dir = os.path.expanduser(val)
                    
    # 2. Cek config env baru
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, "r") as f:
            for line in f:
                if line.startswith("TARGET_DIR="):
                    val = line.strip().split("=", 1)[1].strip("\"").strip("'")
                    if val and val != ".":
                        target_dir = os.path.expanduser(val)
                        
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
            --bg-dark: #050510;
            --panel-bg: rgba(10, 10, 25, 0.85);
            --primary: #0ff;
            --primary-glow: rgba(0, 255, 255, 0.6);
            --secondary: #f0f;
            --secondary-glow: rgba(255, 0, 255, 0.6);
            --accent: #ff003c;
            --text: #e0e0ff;
            --text-dim: #707090;
            --glass-border: rgba(0, 255, 255, 0.3);
            --glass-highlight: rgba(255, 0, 255, 0.3);
        }
        
        body {
            margin: 0; padding: 0;
            font-family: 'Outfit', -apple-system, sans-serif;
            background-color: var(--bg-dark); color: var(--text);
            min-height: 100vh; display: flex;
            background-image: 
                linear-gradient(rgba(0, 255, 255, 0.05) 1px, transparent 1px),
                linear-gradient(90deg, rgba(0, 255, 255, 0.05) 1px, transparent 1px);
            background-size: 30px 30px;
            background-attachment: fixed; overflow-x: hidden;
            -webkit-font-smoothing: antialiased;
        }

        /* Cyberpunk Glitch Effect on Logo */
        @keyframes glitch {
            0% { transform: translate(0) }
            20% { transform: translate(-2px, 2px) }
            40% { transform: translate(-2px, -2px) }
            60% { transform: translate(2px, 2px) }
            80% { transform: translate(2px, -2px) }
            100% { transform: translate(0) }
        }

        /* Scrollbar styling */
        ::-webkit-scrollbar { width: 8px; }
        ::-webkit-scrollbar-track { background: var(--bg-dark); }
        ::-webkit-scrollbar-thumb { background: rgba(0, 255, 255, 0.4); border-radius: 4px; border: 1px solid var(--primary); }
        ::-webkit-scrollbar-thumb:hover { background: var(--primary); }

        .mobile-header {
            display: none;
            width: 100%;
            background: rgba(5, 5, 16, 0.95);
            border-bottom: 2px solid var(--primary);
            padding: 15px 20px;
            box-sizing: border-box;
            justify-content: space-between;
            align-items: center;
            position: sticky;
            top: 0;
            z-index: 200;
            box-shadow: 0 0 15px var(--primary-glow);
        }
        .mobile-logo { font-size: 24px; font-weight: 800; color: white; text-shadow: 0 0 10px var(--primary); }
        .mobile-logo span { color: var(--secondary); }
        .hamburger {
            font-size: 24px; color: var(--primary); cursor: pointer;
            text-shadow: 0 0 5px var(--primary);
        }

        .sidebar {
            width: 280px; background: rgba(10, 10, 20, 0.9);
            border-right: 2px solid var(--primary);
            padding: 40px 0; display: flex; flex-direction: column; z-index: 100;
            box-shadow: 5px 0 30px rgba(0,255,255,0.1);
            transition: all 0.4s cubic-bezier(0.16, 1, 0.3, 1);
        }
        
        .logo {
            text-align: center; font-size: 34px; font-weight: 800; color: white;
            margin-bottom: 50px; letter-spacing: 2px; 
            text-shadow: 2px 2px 0px var(--secondary), -2px -2px 0px var(--primary);
            animation: glitch 3s infinite;
        }
        .logo span { color: var(--primary); }

        .nav-item {
            padding: 16px 35px; cursor: pointer; display: flex; align-items: center; gap: 18px;
            font-weight: 600; color: var(--text-dim); transition: all 0.3s ease; 
            border-left: 4px solid transparent; font-size: 15px;
            position: relative; overflow: hidden; text-transform: uppercase; letter-spacing: 1px;
        }
        .nav-item::before {
            content: ''; position: absolute; left: 0; top: 0; height: 100%; width: 0%;
            background: linear-gradient(90deg, rgba(255, 0, 255, 0.2), transparent);
            transition: width 0.3s ease; z-index: -1;
        }
        .nav-item:hover { color: white; text-shadow: 0 0 8px var(--primary); }
        .nav-item:hover::before { width: 100%; }
        .nav-item.active {
            color: white; border-left: 4px solid var(--secondary);
            text-shadow: 0 0 10px var(--secondary);
            background: linear-gradient(90deg, rgba(255, 0, 255, 0.15), transparent);
        }
        .nav-item i { width: 22px; font-size: 20px; color: var(--text-dim); transition: all 0.3s ease; text-align: center; }
        .nav-item.active i, .nav-item:hover i { color: var(--primary); transform: scale(1.1); filter: drop-shadow(0 0 8px var(--primary)); }

        .main-content { flex: 1; padding: 50px; position: relative; max-width: 1400px; margin: 0 auto; width: 100%; box-sizing: border-box; }
        .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 45px; }
        .header h2 { margin: 0; font-size: 32px; font-weight: 800; letter-spacing: 1px; text-transform: uppercase; text-shadow: 0 0 10px var(--primary); border-bottom: 2px solid var(--secondary); display: inline-block; padding-bottom: 5px; }

        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 24px; margin-bottom: 45px; }
        .stat-card {
            background: rgba(0,0,0,0.7);
            border: 1px solid var(--primary); border-radius: 0px; padding: 24px;
            display: flex; align-items: center; gap: 20px; box-shadow: 0 0 15px rgba(0,255,255,0.1);
            transition: all 0.3s ease; position: relative; overflow: hidden;
            border-left: 4px solid var(--secondary);
        }
        .stat-card::after {
            content: ''; position: absolute; top: 0; left: -100%; width: 50%; height: 100%;
            background: linear-gradient(90deg, transparent, rgba(0,255,255,0.1), transparent);
            transition: left 0.5s ease;
        }
        .stat-card:hover { transform: translateY(-5px); border-color: var(--secondary); box-shadow: 0 0 25px rgba(255,0,255,0.3); }
        .stat-card:hover::after { left: 200%; }
        
        .stat-icon {
            width: 56px; height: 56px; border-radius: 0px;
            background: rgba(255, 0, 255, 0.1); 
            color: var(--primary); border: 1px solid var(--primary);
            display: flex; justify-content: center; align-items: center; font-size: 24px;
            box-shadow: inset 0 0 15px var(--primary-glow);
        }
        .stat-info h4 { margin: 0; color: var(--text-dim); font-size: 13px; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; }
        .stat-info h3 { margin: 8px 0 0; font-size: 26px; font-weight: 700; color: white; text-shadow: 0 0 5px var(--primary); }

        .panel {
            background: rgba(5, 5, 10, 0.8);
            border: 1px solid var(--glass-border); border-radius: 0px; padding: 40px;
            margin-bottom: 30px; display: none; animation: slideUp 0.5s cubic-bezier(0.16, 1, 0.3, 1) forwards;
            box-shadow: 0 0 20px rgba(0,255,255,0.1);
            border-top: 3px solid var(--primary);
        }
        .panel.active { display: block; }
        @keyframes slideUp { from { opacity: 0; transform: translateY(20px); } to { opacity: 1; transform: translateY(0); } }

        .form-group { margin-bottom: 28px; }
        label { display: block; margin-bottom: 12px; font-weight: 600; font-size: 14px; color: var(--primary); letter-spacing: 1px; text-transform: uppercase; }
        input[type="text"], select {
            width: 100%; padding: 18px 20px; background: rgba(0,0,0,0.8); 
            border: 1px solid var(--secondary); color: white; border-radius: 0px; 
            font-family: 'Outfit', sans-serif; font-size: 15px; box-sizing: border-box;
            transition: all 0.3s ease; box-shadow: inset 0 0 10px rgba(255,0,255,0.1);
        }
        input[type="text"]:focus, select:focus { 
            outline: none; border-color: var(--primary); 
            box-shadow: inset 0 0 15px rgba(0,255,255,0.2), 0 0 10px rgba(0,255,255,0.5); 
            background: rgba(0,0,0,0.9); 
        }

        .btn {
            background: rgba(0,0,0,0.6); color: var(--primary);
            border: 1px solid var(--primary); padding: 18px 30px; border-radius: 0px; font-family: inherit; font-size: 16px;
            font-weight: 700; cursor: pointer; width: 100%; transition: all 0.3s ease; 
            letter-spacing: 2px; text-transform: uppercase;
            position: relative; overflow: hidden; display: flex; justify-content: center; align-items: center; gap: 10px;
            box-shadow: 0 0 10px rgba(0,255,255,0.2);
        }
        .btn::before {
            content: ''; position: absolute; top: 0; left: -100%; width: 100%; height: 100%;
            background: linear-gradient(90deg, transparent, rgba(0,255,255,0.4), transparent); transition: left 0.4s;
        }
        .btn:hover { background: var(--primary); color: black; box-shadow: 0 0 20px var(--primary); text-shadow: none; }
        .btn:hover::before { left: 100%; }
        .btn:active { transform: scale(0.98); }
        .btn:disabled { opacity: 0.5; border-color: var(--text-dim); color: var(--text-dim); pointer-events: none; }
        
        .btn-spotify { border-color: #1DB954; color: #1DB954; box-shadow: 0 0 10px rgba(29, 185, 84, 0.2); }
        .btn-spotify:hover { background: #1DB954; color: black; box-shadow: 0 0 20px #1DB954; }
        
        .btn-danger { border-color: var(--accent); color: var(--accent); box-shadow: 0 0 10px rgba(255, 42, 95, 0.2); }
        .btn-danger:hover { background: var(--accent); color: white; box-shadow: 0 0 20px var(--accent); }

        .status-box { margin-top: 25px; padding: 18px 20px; border-radius: 0px; text-align: center; display: none; font-weight: 600; font-size: 15px; animation: slideUp 0.3s ease; text-transform: uppercase; letter-spacing: 1px; }
        .status-box.success { display: block; background: rgba(0, 255, 255, 0.1); color: var(--primary); border: 1px solid var(--primary); box-shadow: 0 0 10px rgba(0,255,255,0.2); }
        .status-box.error { display: block; background: rgba(255, 0, 60, 0.1); color: var(--accent); border: 1px solid var(--accent); box-shadow: 0 0 10px rgba(255,0,60,0.2); }
        .status-box.info { display: block; background: rgba(255, 0, 255, 0.1); color: var(--secondary); border: 1px solid var(--secondary); box-shadow: 0 0 10px rgba(255,0,255,0.2); }

        /* Tools Grid */
        .tools-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 24px; }
        .tool-card {
            background: rgba(0,0,0,0.6); border: 1px solid var(--secondary);
            border-radius: 0px; padding: 35px 25px; text-align: center; transition: all 0.3s ease;
            position: relative; overflow: hidden;
        }
        .tool-card:hover { border-color: var(--primary); box-shadow: 0 0 20px rgba(0, 255, 255, 0.3); transform: translateY(-4px); }
        .tool-icon { font-size: 42px; color: var(--secondary); margin-bottom: 20px; text-shadow: 0 0 10px var(--secondary); transition: 0.3s; }
        .tool-card:hover .tool-icon { color: var(--primary); text-shadow: 0 0 15px var(--primary); }
        .tool-title { font-size: 20px; font-weight: 800; margin-bottom: 12px; color: white; text-transform: uppercase; letter-spacing: 1px; }
        .tool-desc { font-size: 14px; color: var(--text-dim); margin-bottom: 25px; line-height: 1.6; }

        @media (max-width: 900px) {
            body { flex-direction: column; }
            .mobile-header { display: flex; }
            .sidebar {
                position: fixed;
                top: 0; left: -100%;
                height: 100vh;
                width: 280px;
                border-right: 2px solid var(--primary);
                background: rgba(5, 5, 16, 0.98);
                padding-top: 80px;
                box-shadow: 10px 0 30px rgba(0,0,0,0.8);
                transition: left 0.4s cubic-bezier(0.16, 1, 0.3, 1);
            }
            .sidebar.open { left: 0; }
            .logo { display: none; } /* Hide logo inside sidebar on mobile since it's in header */
            .nav-item { padding: 20px 30px; font-size: 16px; border-left: 4px solid transparent; flex-direction: row; justify-content: flex-start; border-bottom: none; }
            .main-content { padding: 20px 15px; }
            .header { flex-direction: column; align-items: flex-start; gap: 10px; margin-bottom: 25px; }
            .header h2 { font-size: 24px; }
            .stats-grid { grid-template-columns: 1fr; margin-bottom: 25px; }
            .stat-card { padding: 20px; }
            .tools-grid { grid-template-columns: 1fr; }
            .btn { font-size: 14px; padding: 15px 20px; }
            input[type="text"], select { padding: 15px; font-size: 14px; }
            .panel { padding: 20px 15px; }
            
            /* Overlay for mobile sidebar */
            .sidebar-overlay {
                position: fixed; top: 0; left: 0; right: 0; bottom: 0;
                background: rgba(0,0,0,0.7); z-index: 90;
                display: none; opacity: 0; transition: opacity 0.3s;
            }
            .sidebar-overlay.show { display: block; opacity: 1; }
        }

    
        .log-container {
            background: #000; border: 1px solid var(--primary);
            padding: 15px; margin-top: 25px; border-radius: 4px;
            font-family: "Courier New", monospace; font-size: 13px; color: #0f0;
            height: 250px; overflow-y: auto; white-space: pre-wrap;
            box-shadow: inset 0 0 10px rgba(0,255,255,0.1);
        }
</style>
</head>
<body>
    <div class="sidebar-overlay" id="sidebarOverlay" onclick="toggleMobileMenu()"></div>
    
    <div class="mobile-header">
        <div class="mobile-logo">ZDT<span>.</span></div>
        <div class="hamburger" onclick="toggleMobileMenu()"><i class="fa-solid fa-bars"></i></div>
    </div>

    <div class="sidebar" id="sidebar">
        <div class="logo">ZDT<span>.</span></div>
        <div class="nav-item active" onclick="switchTab('dashboard')"><i class="fa-solid fa-chart-pie"></i> Dashboard</div>
        <div class="nav-item" onclick="switchTab('downloader')"><i class="fa-solid fa-cloud-arrow-down"></i> Downloader</div>
        <div class="nav-item" onclick="switchTab('spotify')"><i class="fa-brands fa-spotify"></i> Spotify Sync</div>
        <div class="nav-item" onclick="switchTab('metadata')"><i class="fa-solid fa-tags"></i> Metadata Editor</div>
        <div class="nav-item" onclick="switchTab('servertools')"><i class="fa-solid fa-toolbox"></i> Server Tools</div>
    </div>

    <div class="main-content">
        <div class="header">
            <h2><span id="pageTitle">Dashboard</span></h2>
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
                merapikan metadata file, hingga melakukan optimasi direktori secara langsung dari peramban Anda.
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
                    <label>Tipe Media</label>
                    <select id="dlFormat" onchange="updateFormatOptions()">
                        <option value="audio">🎵 Audio</option>
                        <option value="video">🎬 Video</option>
                    </select>
                </div>
                <div class="form-group">
                    <label>Format / Kualitas Output</label>
                    <select id="dlFormatSpec">
                        <!-- Populated by JS -->
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

        <!-- Server Tools Panel -->
        <div id="servertools" class="panel">
            <h3 style="margin-top:0; color:var(--primary);">Server Utility Tools</h3>
            <p style="color:var(--text-dim); margin-bottom:25px;">Akses penuh ke fitur utama ZDT untuk merapikan dan memproses file lokal.</p>
            <div id="toolsStatus" class="status-box" style="margin-bottom: 20px;"></div>
            
            <div class="tools-grid">
                <!-- Clean Directory -->
                <div class="tool-card">
                    <div class="tool-icon"><i class="fa-solid fa-broom"></i></div>
                    <div class="tool-title">Clean Directory</div>
                    <div class="tool-desc">Otomatis membersihkan angka, teks 'Official Video', dan merapikan nama semua file di direktori Anda.</div>
                    <button class="btn" onclick="runTool('clean')">Clean Now</button>
                </div>
                
                <!-- Make Playlist -->
                <div class="tool-card">
                    <div class="tool-icon"><i class="fa-solid fa-list-ol"></i></div>
                    <div class="tool-title">Make Playlist</div>
                    <div class="tool-desc">Buat file .m3u instan yang memuat semua lagu di direktori untuk diputar di music player.</div>
                    <button class="btn" onclick="runTool('playlist')">Generate .m3u</button>
                </div>
                
                <!-- Extract Vocals -->
                <div class="tool-card">
                    <div class="tool-icon"><i class="fa-solid fa-microphone-slash"></i></div>
                    <div class="tool-title">Extract Vocals</div>
                    <div class="tool-desc">Gunakan AI Demucs untuk memisahkan Vokal dan Instrumen dari file audio (Pilih di bawah).</div>
                    <select id="toolFileDemucs" style="margin-bottom: 10px; font-size: 13px; padding: 10px;"></select>
                    <button class="btn btn-danger" onclick="runTool('demucs')">Split AI</button>
                </div>
                
                <!-- Compress Audio -->
                <div class="tool-card">
                    <div class="tool-icon"><i class="fa-solid fa-compress"></i></div>
                    <div class="tool-title">Compress File</div>
                    <div class="tool-desc">Kompres file media untuk memperkecil ukurannya dengan FFmpeg (Pilih di bawah).</div>
                    <select id="toolFileCompress" style="margin-bottom: 10px; font-size: 13px; padding: 10px;"></select>
                    <button class="btn btn-danger" onclick="runTool('compress')">Compress</button>
                </div>
            </div>
        </div>


        <div id="logSection" style="display: none;">
            <div class="header" style="margin-top: 40px; margin-bottom: 20px;">
                <h2><i class="fa-solid fa-terminal"></i> Realtime Logs</h2>
            </div>
            <div class="log-container" id="terminalLog">System ready. Waiting for task execution...</div>
        </div>
    </div>

    <script>
        function updateFormatOptions() {
            const type = document.getElementById("dlFormat").value;
            const spec = document.getElementById("dlFormatSpec");
            spec.innerHTML = "";
            if (type === "audio") {
                spec.innerHTML = `
                    <option value="1">M4A (Default, Paling Kompatibel)</option>
                    <option value="2">MP3 (Universal)</option>
                    <option value="3">FLAC (Lossless, Kualitas Tertinggi)</option>
                    <option value="4">WAV (Uncompressed Studio)</option>
                    <option value="5">OPUS (Modern, Ukuran Kecil)</option>
                    <option value="6">OGG (Open Source)</option>
                `;
            } else {
                spec.innerHTML = `
                    <option value="1">MP4 (1080p / Max Res)</option>
                    <option value="2">MKV (1080p / Max Res)</option>
                    <option value="3">WebM (1080p / Max Res)</option>
                    <option value="4">MKV (Best Video + Best Audio)</option>
                `;
            }
        }
        // Initialize options on load
        window.addEventListener("DOMContentLoaded", () => {
            if(document.getElementById("dlFormat")) {
                updateFormatOptions();
            }
        });
        function toggleMobileMenu() {
            const sidebar = document.getElementById("sidebar");
            const overlay = document.getElementById("sidebarOverlay");
            sidebar.classList.toggle("open");
            overlay.classList.toggle("show");
        }

        
        setInterval(async () => {
            try {
                const res = await fetch("/api/logs");
                const data = await res.json();
                if(data.log && data.log.trim().length > 0) {
                    document.getElementById("logSection").style.display = "block";
                    const term = document.getElementById("terminalLog");
                    // only update if changed
                    if (term.textContent !== data.log) {
                        term.textContent = data.log;
                        term.scrollTop = term.scrollHeight;
                    }
                } else {
                    document.getElementById("logSection").style.display = "none";
                }
            } catch(e) {}
        }, 1500);
function switchTab(tabId) {
            if(window.innerWidth <= 900) {
                document.getElementById("sidebar").classList.remove("open");
                document.getElementById("sidebarOverlay").classList.remove("show");
            }

            document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
            document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
            document.getElementById(tabId).classList.add('active');
            event.currentTarget.classList.add('active');
            
            const titles = {
                'dashboard': 'Dashboard Overview',
                'downloader': 'Media Downloader',
                'spotify': 'Spotify Synchronization',
                'metadata': 'Metadata Editor',
                'servertools': 'Server Utility Tools'
            };
            document.getElementById('pageTitle').innerText = titles[tabId];
            
            if(tabId === 'metadata' || tabId === 'servertools') loadFiles();
        }

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

        async function loadFiles() {
            try {
                const res = await fetch('/api/files');
                const data = await res.json();
                
                // Metadata Select
                const selMeta = document.getElementById('metaFile');
                selMeta.innerHTML = '<option value="">-- Pilih File --</option>';
                data.files.forEach(f => { selMeta.innerHTML += `<option value="${f}">${f}</option>`; });
                
                // Demucs & Compress Select
                const selDem = document.getElementById('toolFileDemucs');
                const selComp = document.getElementById('toolFileCompress');
                selDem.innerHTML = '<option value="">-- Pilih File --</option>';
                selComp.innerHTML = '<option value="">-- Pilih File --</option>';
                data.files.forEach(f => {
                    selDem.innerHTML += `<option value="${f}">${f}</option>`;
                    selComp.innerHTML += `<option value="${f}">${f}</option>`;
                });
            } catch(e) {}
        }

        document.getElementById('formDownloader').addEventListener('submit', async (e) => {
            e.preventDefault();
            const url = document.getElementById('dlUrl').value;
            const format = document.getElementById('dlFormat').value;
            const spec = document.getElementById('dlFormatSpec').value;
            const btn = document.getElementById('btnDl');
            const status = document.getElementById('dlStatus');
            btn.disabled = true; btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> EXECUTING...';
            try {
                const res = await fetch('/api/download', {
                    method: 'POST', headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({url, format, spec})
                });
                const data = await res.json();
                if(data.success) {
                    status.className = 'status-box success'; status.innerText = '✅ Proses download dikirim ke server background!';
                    document.getElementById('dlUrl').value = '';
                } else {
                    status.className = 'status-box error'; status.innerText = '❌ ' + data.message;
                }
            } catch(err) { status.className = 'status-box error'; status.innerText = 'Connection Error!'; }
            btn.disabled = false; btn.innerHTML = '<i class="fa-solid fa-bolt"></i> Execute Download';
        });

        document.getElementById('formSpotify').addEventListener('submit', async (e) => {
            e.preventDefault();
            const url = document.getElementById('spUrl').value;
            const btn = document.getElementById('btnSp');
            const status = document.getElementById('spStatus');
            btn.disabled = true; btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> SYNCING...';
            try {
                const res = await fetch('/api/spotify-sync', {
                    method: 'POST', headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({url})
                });
                const data = await res.json();
                if(data.success) {
                    status.className = 'status-box success'; status.innerText = '✅ Proses sinkronisasi dimulai di server!';
                    document.getElementById('spUrl').value = '';
                } else {
                    status.className = 'status-box error'; status.innerText = '❌ ' + data.message;
                }
            } catch(err) { status.className = 'status-box error'; status.innerText = 'Connection Error!'; }
            btn.disabled = false; btn.innerHTML = '<i class="fa-solid fa-sync"></i> Start Sync Process';
        });

        document.getElementById('formMeta').addEventListener('submit', async (e) => {
            e.preventDefault();
            const filename = document.getElementById('metaFile').value;
            const title = document.getElementById('metaTitle').value;
            const artist = document.getElementById('metaArtist').value;
            const btn = document.getElementById('btnMeta');
            const status = document.getElementById('metaStatus');
            btn.disabled = true; btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> INJECTING...';
            try {
                const res = await fetch('/api/metadata', {
                    method: 'POST', headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({filename, title, artist})
                });
                const data = await res.json();
                if(data.success) {
                    status.className = 'status-box success'; status.innerText = '✅ Metadata berhasil disimpan!';
                } else {
                    status.className = 'status-box error'; status.innerText = '❌ ' + data.message;
                }
            } catch(err) { status.className = 'status-box error'; status.innerText = 'Connection Error!'; }
            btn.disabled = false; btn.innerHTML = '<i class="fa-solid fa-pen-nib"></i> Inject Metadata';
        });

        async function runTool(toolType) {
            const status = document.getElementById('toolsStatus');
            status.className = 'status-box info';
            status.innerText = '⏳ Mengirim perintah ke server...';
            
            let payload = { action: toolType };
            if (toolType === 'demucs') {
                payload.filename = document.getElementById('toolFileDemucs').value;
                if (!payload.filename) return alert("Pilih file dulu!");
            }
            if (toolType === 'compress') {
                payload.filename = document.getElementById('toolFileCompress').value;
                if (!payload.filename) return alert("Pilih file dulu!");
            }

            try {
                const res = await fetch('/api/tools', {
                    method: 'POST', headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify(payload)
                });
                const data = await res.json();
                if (data.success) {
                    status.className = 'status-box success';
                    status.innerText = '✅ ' + data.message;
                } else {
                    status.className = 'status-box error';
                    status.innerText = '❌ Error: ' + data.message;
                }
            } catch(err) {
                status.className = 'status-box error';
                status.innerText = '❌ Connection Error!';
            }
        }
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
    # Cek direktori utama jika target belum dibuat
    if not os.path.exists(target):
        target = os.path.expanduser("~")
        
    if os.path.exists(target):
        total, used, free = shutil.disk_usage(target)
        free_space = f"{free // (2**30)} GB"
    
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
    spec = data.get('spec', '1')
    if not url: return jsonify({"success": False, "message": "URL kosong"})
    import shutil
    zdt_bin = shutil.which("zdt")
    if not zdt_bin:
        for path in [os.path.expanduser("~/.local/bin/zdt"), "/usr/local/bin/zdt", "/data/data/com.termux/files/usr/bin/zdt"]:
            if os.path.exists(path): zdt_bin = path; break
    if not zdt_bin: zdt_bin = "zdt"
    cmd = [zdt_bin, "--download-audio" if fmt == 'audio' else "--download-video", url]
    try:
        with open(os.devnull, 'w') as devnull:
            target = get_target_dir()
            env = os.environ.copy()
            if fmt == "audio":
                env["CONF_AUDIO_CODEC"] = str(spec)
            else:
                env["CONF_VIDEO_FMT"] = str(spec)
            subprocess.Popen(cmd, stdout=open("/tmp/zdt_web_task.log", "w"), stderr=subprocess.STDOUT, start_new_session=True, cwd=target, env=env)
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"success": False, "message": str(e)})

@app.route('/api/spotify-sync', methods=['POST'])
def spotify_sync():
    url = request.json.get('url', '')
    if not url: return jsonify({"success": False, "message": "URL kosong"})
    import shutil
    zdt_bin = shutil.which("zdt")
    if not zdt_bin:
        for path in [os.path.expanduser("~/.local/bin/zdt"), "/usr/local/bin/zdt", "/data/data/com.termux/files/usr/bin/zdt"]:
            if os.path.exists(path): zdt_bin = path; break
    if not zdt_bin: zdt_bin = "zdt"
    cmd = [zdt_bin, "--no-color", "--no-unicode", "--spotify-sync", url]
    try:
        with open(os.devnull, 'w') as devnull:
            target = get_target_dir()
            subprocess.Popen(cmd, stdout=open("/tmp/zdt_web_task.log", "w"), stderr=subprocess.STDOUT, start_new_session=True, cwd=target)
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"success": False, "message": str(e)})

@app.route('/api/files', methods=['GET'])
def list_files():
    target = get_target_dir()
    files = []
    if os.path.exists(target):
        for ext in ['*.mp3', '*.m4a', '*.flac', '*.mp4', '*.mkv', '*.webm']:
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
    if not os.path.exists(filepath): return jsonify({"success": False, "message": "File tidak ditemukan di server"})
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

@app.route('/api/tools', methods=['POST'])
def server_tools():
    data = request.json
    action = data.get('action')
    filename = data.get('filename')
    target = get_target_dir()
    import shutil
    zdt_bin = shutil.which("zdt")
    if not zdt_bin:
        for path in [os.path.expanduser("~/.local/bin/zdt"), "/usr/local/bin/zdt", "/data/data/com.termux/files/usr/bin/zdt"]:
            if os.path.exists(path): zdt_bin = path; break
    if not zdt_bin: zdt_bin = "zdt"

    try:
        if action == 'clean':
            # Cari seluruh file dan jalankan zdt --clean-file di background
            if not os.path.exists(target): return jsonify({"success": False, "message": "Direktori kosong/tidak valid."})
            count = 0
            for ext in ['*.mp3', '*.m4a', '*.flac', '*.mp4']:
                for f in glob.glob(os.path.join(target, ext)):
                    subprocess.Popen([zdt_bin, "--clean-file", f], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    count += 1
            return jsonify({"success": True, "message": f"Proses pembersihan {count} file sedang berjalan di background!"})

        elif action == 'playlist':
            if not os.path.exists(target): return jsonify({"success": False, "message": "Direktori kosong."})
            m3u_path = os.path.join(target, "ZDT_Playlist.m3u")
            with open(m3u_path, 'w') as f:
                f.write("#EXTM3U\\n")
                for ext in ['*.mp3', '*.m4a', '*.flac']:
                    for track in glob.glob(os.path.join(target, ext)):
                        f.write(f"{os.path.basename(track)}\\n")
            return jsonify({"success": True, "message": "File ZDT_Playlist.m3u berhasil dibuat di folder."})

        elif action == 'demucs':
            if not filename: return jsonify({"success": False, "message": "Pilih file."})
            filepath = os.path.join(target, filename)
            # Jalankan demucs manual asinkron
            with open(os.devnull, 'w') as devnull:
                subprocess.Popen(["demucs", "--two-stems=vocals", "-o", target, filepath], stdout=open("/tmp/zdt_web_task.log", "w"), stderr=subprocess.STDOUT, start_new_session=True, cwd=target)
            return jsonify({"success": True, "message": "Demucs AI mulai memisahkan vokal di background!"})

        elif action == 'compress':
            if not filename: return jsonify({"success": False, "message": "Pilih file."})
            filepath = os.path.join(target, filename)
            outpath = os.path.join(target, "COMPRESSED_" + filename)
            
            ext = filepath.lower()
            if ext.endswith('.mp4') or ext.endswith('.mkv'):
                cmd = ["ffmpeg", "-y", "-i", filepath, "-vcodec", "libx264", "-crf", "28", outpath]
            else:
                cmd = ["ffmpeg", "-y", "-i", filepath, "-b:a", "128k", outpath]
                
            with open(os.devnull, 'w') as devnull:
                target = get_target_dir()
            env = os.environ.copy()
            if fmt == "audio":
                env["CONF_AUDIO_CODEC"] = str(spec)
            else:
                env["CONF_VIDEO_FMT"] = str(spec)
            subprocess.Popen(cmd, stdout=open("/tmp/zdt_web_task.log", "w"), stderr=subprocess.STDOUT, start_new_session=True, cwd=target, env=env)
            return jsonify({"success": True, "message": "Proses kompresi FFmpeg berjalan di background!"})

        return jsonify({"success": False, "message": "Aksi tidak dikenal."})
    except Exception as e:
        return jsonify({"success": False, "message": str(e)})

@app.route("/api/logs", methods=["GET"])
def get_logs():
    log_file = "/tmp/zdt_web_task.log"
    if os.path.exists(log_file):
        with open(log_file, "r") as f:
            lines = f.readlines()
            # return last 100 lines to avoid massive payloads
            return jsonify({"log": "".join(lines[-100:])})
    return jsonify({"log": "No active tasks."})

if __name__ == '__main__':
    print("Memulai ZDT Web Dashboard V2 di port 5000...")
    app.run(host='0.0.0.0', port=5000)



