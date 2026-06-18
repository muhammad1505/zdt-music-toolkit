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
APP_VERSION = "4.1.3"

CONFIG_FILE = os.path.expanduser("~/.config/zdt/config.env")

def get_target_dir():
    target_dir = os.path.expanduser("~/Music/ZDT_Downloads")
    old_conf = os.path.expanduser("~/.config/zdt/config")
    if os.path.exists(old_conf):
        with open(old_conf, "r") as f:
            for line in f:
                if line.startswith("storage_dir="):
                    val = line.strip().split("=", 1)[1].strip("\"").strip("'")
                    if val: target_dir = os.path.expanduser(val)
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
    <title>ZDT Enterprise Dashboard</title>
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" rel="stylesheet">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg-base: #0b0f19;
            --bg-surface: rgba(17, 24, 39, 0.7);
            --bg-card: rgba(31, 41, 55, 0.5);
            --primary: #3b82f6;
            --primary-hover: #2563eb;
            --accent: #10b981;
            --danger: #ef4444;
            --warning: #f59e0b;
            --text-main: #f9fafb;
            --text-muted: #9ca3af;
            --border-light: rgba(255, 255, 255, 0.08);
            --glass-shadow: 0 8px 32px 0 rgba(0, 0, 0, 0.3);
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
                radial-gradient(circle at 15% 50%, rgba(59, 130, 246, 0.12), transparent 25%),
                radial-gradient(circle at 85% 30%, rgba(16, 185, 129, 0.08), transparent 25%);
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
            background: var(--primary); color: white;
            border: none; padding: 14px 24px;
            border-radius: 8px; font-family: inherit; font-size: 14px;
            font-weight: 500; cursor: pointer; width: 100%;
            transition: all 0.2s ease;
            display: flex; justify-content: center; align-items: center; gap: 8px;
        }
        .btn:hover { background: var(--primary-hover); transform: translateY(-1px); box-shadow: 0 4px 12px rgba(59, 130, 246, 0.3); }
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

        @media (max-width: 900px) {
            body { flex-direction: column; }
            .sidebar { width: 100%; border-right: none; border-bottom: 1px solid var(--border-light); padding: 20px; flex-direction: row; overflow-x: auto; white-space: nowrap; }
            .logo { display: none; }
            .nav-item { padding: 10px 20px; border-left: none; border-bottom: 3px solid transparent; }
            .nav-item.active { border-left: none; border-bottom: 3px solid var(--primary); background: transparent; }
            .main-content { padding: 20px; }
            .stats-grid { grid-template-columns: 1fr; }
            .tools-grid { grid-template-columns: 1fr; }
            .switch-wrapper { flex-direction: column; gap: 15px; }
        }
        @media (max-width: 600px) {
            body { flex-direction: column; }
            .sidebar { width: 100%; overflow-x: auto; padding: 10px 0; border-right: none; border-bottom: 1px solid var(--border-light); }
            .sidebar .logo { padding: 5px 15px; font-size: 16px; margin-bottom: 5px; }
            .sidebar .nav-item { padding: 8px 12px; font-size: 12px; white-space: nowrap; }
            .sidebar .nav-item i { margin-right: 4px; }
            .main-content { padding: 15px; min-height: auto; }
            .header h2 { font-size: 20px; }
            .header p { font-size: 12px; }
            .stat-card { padding: 15px; }
            .panel { padding: 20px; }
            .tool-card { padding: 20px; }
        }
    </style>
</head>
<body>
    <div class="sidebar">
        <div class="logo"><i class="fa-solid fa-layer-group"></i> ZDT Enterprise</div>
        <div class="nav-item active" onclick="switchTab('dashboard', this)"><i class="fa-solid fa-chart-pie"></i> Dashboard</div>
        <div class="nav-item" onclick="switchTab('downloader', this)"><i class="fa-solid fa-cloud-arrow-down"></i> Downloader</div>
        <div class="nav-item" onclick="switchTab('spotify', this)"><i class="fa-brands fa-spotify"></i> Spotify Sync</div>
        <div class="nav-item" onclick="switchTab('metadata', this)"><i class="fa-solid fa-tags"></i> Metadata</div>
        <div class="nav-item" onclick="switchTab('servertools', this)"><i class="fa-solid fa-toolbox"></i> Server Tools</div>
        <div class="nav-item" onclick="switchTab('system', this)"><i class="fa-solid fa-server"></i> Daemons</div>
        <div class="nav-item" onclick="switchTab('settings', this)"><i class="fa-solid fa-gear"></i> Settings</div>
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

        <!-- Downloader Panel -->
        <div id="downloader" class="panel">
            <h3><i class="fa-solid fa-cloud-arrow-down"></i> Universal Downloader</h3>
            <form id="formDownloader">
                <div class="form-group">
                    <label>Media URL (YouTube / SoundCloud / TikTok)</label>
                    <input type="text" id="dlUrl" placeholder="https://..." required>
                </div>
                <div style="display:flex; gap:15px;">
                    <div class="form-group" style="flex:1;">
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
                <div style="display:flex; gap:15px;">
                    <div class="form-group" style="flex:1;">
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
                    <button class="btn" style="width:auto; padding: 10px 15px;" onclick="toggleDaemon('watch', 'start')"><i class="fa-solid fa-play"></i> Start</button>
                    <button class="btn btn-danger" style="width:auto; padding: 10px 15px;" onclick="toggleDaemon('watch', 'stop')"><i class="fa-solid fa-stop"></i> Stop</button>
                </div>
            </div>

            <div class="switch-wrapper">
                <div class="switch-info">
                    <h4>Telegram Bot <span id="badgeTele" class="badge badge-inactive">Offline</span></h4>
                    <p>Control ZDT remotely via Telegram. Requires bot token to be configured.</p>
                </div>
                <div style="display:flex; gap:10px;">
                    <button class="btn" style="width:auto; padding: 10px 15px;" onclick="toggleDaemon('telegram', 'start')"><i class="fa-solid fa-play"></i> Start</button>
                    <button class="btn btn-danger" style="width:auto; padding: 10px 15px;" onclick="toggleDaemon('telegram', 'stop')"><i class="fa-solid fa-stop"></i> Stop</button>
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
        </div>
    </div>

    <script>
        function updateFormatOptions() {
            const type = document.getElementById("dlFormat").value;
            const spec = document.getElementById("dlFormatSpec");
            spec.innerHTML = "";
            if (type === "audio") {
                spec.innerHTML = `
                    <option value="1">M4A (Default, Broad Compatibility)</option>
                    <option value="2">MP3 (Universal)</option>
                    <option value="3">FLAC (Lossless Studio Quality)</option>
                    <option value="4">WAV (Uncompressed)</option>
                    <option value="5">OPUS (Modern, Small Size)</option>
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

                const tStatus = data.telegram;
                document.getElementById('statTele').innerText = tStatus ? 'Active' : 'Offline';
                const bTele = document.getElementById('badgeTele');
                bTele.className = tStatus ? 'badge badge-active' : 'badge badge-inactive';
                bTele.innerText = tStatus ? 'Active' : 'Offline';

                if(document.getElementById('dashTargetDir').innerText === 'Loading...') {
                    document.getElementById('dashTargetDir').innerText = data.target_dir;
                    document.getElementById('setTargetDir').value = data.target_dir;
                }
                document.getElementById('statFiles').innerText = (data.file_count || 0) + ' files';
                if(data.version) document.getElementById('dashVersion').innerText = 'v' + data.version;
            } catch(e) {}
        }
        setInterval(loadStatus, 3000);
        loadStatus();

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
                    const res = await fetch(apiEndpoint, {
                        method: 'POST', headers: {'Content-Type': 'application/json'},
                        body: JSON.stringify(payloadBuilder())
                    });
                    const data = await res.json();
                    status.className = 'status-box ' + (data.success ? 'success' : 'error');
                    status.innerText = (data.success ? '✅ ' : '❌ ') + data.message;
                    if(data.success && formId !== 'formSettings' && formId !== 'formMeta') e.target.reset();
                    if(formId === 'formSettings') { document.getElementById('dashTargetDir').innerText = 'Loading...'; loadStatus(); }
                } catch(err) { status.className = 'status-box error'; status.innerText = '❌ Connection Error!'; }
                btn.disabled = false; btn.innerHTML = originalHtml;
            });
        }

        handleFormSubmit('formDownloader', 'btnDl', 'dlStatus', '/api/download', () => ({
            url: document.getElementById('dlUrl').value,
            format: document.getElementById('dlFormat').value,
            spec: document.getElementById('dlFormatSpec').value
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
            const status = document.getElementById('toolsStatus');
            status.className = 'status-box info';
            status.innerText = '⏳ Dispatching command to server...';
            
            let payload = { action: toolType };
            if (toolType === 'demucs') {
                payload.filename = document.getElementById('toolFileDemucs').value;
                if (!payload.filename) return alert("Please select a file first!");
            }
            if (toolType === 'compress') {
                payload.filename = document.getElementById('toolFileCompress').value;
                if (!payload.filename) return alert("Please select a file first!");
            }

            try {
                const res = await fetch('/api/tools', {
                    method: 'POST', headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify(payload)
                });
                const data = await res.json();
                status.className = 'status-box ' + (data.success ? 'success' : 'error');
                status.innerText = (data.success ? '✅ ' : '❌ ') + data.message;
                if(data.success) { loadFiles(); loadStatus(); }
            } catch(err) {
                status.className = 'status-box error'; status.innerText = '❌ Connection Error!';
            }
        }

        async function toggleDaemon(service, action) {
            const status = document.getElementById('daemonStatus');
            status.className = 'status-box info';
            status.innerText = `⏳ Sending ${action} command to ${service}...`;
            try {
                const res = await fetch('/api/daemon', {
                    method: 'POST', headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({ service, action })
                });
                const data = await res.json();
                status.className = 'status-box ' + (data.success ? 'success' : 'error');
                status.innerText = (data.success ? '✅ ' : '❌ ') + data.message;
                loadStatus();
            } catch(err) {
                status.className = 'status-box error'; status.innerText = '❌ Connection Error!';
            }
        }

        function closeLogs() {
            document.getElementById("logSection").style.display = "none";
            fetch('/api/logs/clear', {method: 'POST'});
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
                    }
                } else {
                    document.getElementById("logSection").style.display = "none";
                }
            } catch(e) {}
        }, 1500);
    </script>
</body>
</html>

"""

@app.route('/')
def index():
    return render_template_string(HTML_TEMPLATE)

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
        subprocess.Popen([venv_python, script_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return jsonify({"success": True, "message": f"Started {service} daemon."})
        
    elif action == 'stop':
        try:
            output = subprocess.check_output(["ps", "aux"]).decode()
            for line in output.split("\n"):
                if os.path.basename(script_path) in line and "python" in line and not "grep" in line:
                    pid = int(line.split()[1])
                    os.kill(pid, 9)
            return jsonify({"success": True, "message": f"Stopped {service} daemon."})
        except Exception as e:
            return jsonify({"success": False, "message": f"Failed to stop: {str(e)}"})

@app.route('/api/settings/storage', methods=['POST'])
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
    
    # Update old config as fallback
    old_conf = os.path.expanduser("~/.config/zdt/config")
    if os.path.exists(old_conf):
        olines = []
        with open(old_conf, "r") as f: olines = f.readlines()
        for i, line in enumerate(olines):
            if line.startswith("storage_dir="):
                olines[i] = f'storage_dir="{new_path}"\n'
        with open(old_conf, "w") as f: f.writelines(olines)
        
    return jsonify({"success": True, "message": "Storage directory updated successfully."})

@app.route('/api/download', methods=['POST'])
def trigger_download():
    data = request.json
    url = data.get('url')
    fmt = data.get('format')
    spec = data.get('spec')
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
        cmd = [zdt_bin, "--download-audio", url, "--format-spec", str(spec)] if spec else [zdt_bin, "--download-audio", url]
    else:
        cmd = [zdt_bin, "--download-video", url, "--format-spec", str(spec)] if spec else [zdt_bin, "--download-video", url]
        
    with open("/tmp/zdt_web_task.log", "w") as log_file:
        subprocess.Popen(cmd, stdout=log_file, stderr=subprocess.STDOUT, start_new_session=True)
        
    return jsonify({"success": True, "message": "Proses download sedang berjalan di background!"})

@app.route('/api/spotify-sync', methods=['POST'])
def trigger_spotify_sync():
    url = request.json.get('url')
    if not url: return jsonify({"success": False, "message": "URL tidak boleh kosong!"})
    
    zdt_bin = shutil.which("zdt")
    if not zdt_bin:
        for path in [os.path.expanduser("~/.local/bin/zdt"), "/usr/local/bin/zdt", "/data/data/com.termux/files/usr/bin/zdt"]:
            if os.path.exists(path): zdt_bin = path; break
    if not zdt_bin: zdt_bin = "zdt"
    
    with open("/tmp/zdt_web_task.log", "w") as log_file:
        subprocess.Popen([zdt_bin, "--spotify-sync", url], stdout=log_file, stderr=subprocess.STDOUT, start_new_session=True)
        
    return jsonify({"success": True, "message": "Sinkronisasi Spotify berjalan di background!"})

@app.route('/api/metadata', methods=['POST'])
def update_metadata():
    if 'mutagen' not in sys.modules:
        return jsonify({"success": False, "message": "Mutagen belum terinstall."})
        
    data = request.json
    filename = data.get('filename')
    title = data.get('title')
    artist = data.get('artist')
    if not filename: return jsonify({"success": False, "message": "Pilih file."})
    if not title and not artist: return jsonify({"success": False, "message": "Isi minimal title atau artist."})
    
    filepath = os.path.join(get_target_dir(), filename)
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
def server_tools():
    data = request.json
    action = data.get('action')
    filename = data.get('filename')
    target = get_target_dir()
    
    zdt_bin = shutil.which("zdt")
    if not zdt_bin:
        for path in [os.path.expanduser("~/.local/bin/zdt"), "/usr/local/bin/zdt", "/data/data/com.termux/files/usr/bin/zdt"]:
            if os.path.exists(path): zdt_bin = path; break
    if not zdt_bin: zdt_bin = "zdt"

    try:
        if action == 'clean':
            if not os.path.exists(target): return jsonify({"success": False, "message": "Direktori kosong."})
            with open("/tmp/zdt_web_task.log", "w") as log_file:
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
            with open("/tmp/zdt_web_task.log", "w") as log_file:
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
            filepath = os.path.join(target, filename)
            demucs_bin = os.path.expanduser("~/.local/share/zdt/demucs_venv/bin/demucs")
            if not os.path.exists(demucs_bin): demucs_bin = shutil.which("demucs")
            if not demucs_bin: return jsonify({"success": False, "message": "Demucs AI belum terinstal."})
            
            with open("/tmp/zdt_web_task.log", "w") as log_file:
                subprocess.Popen([demucs_bin, "--two-stems=vocals", "-o", target, filepath], stdout=log_file, stderr=subprocess.STDOUT, start_new_session=True, cwd=target)
            return jsonify({"success": True, "message": "Demucs AI mulai memisahkan vokal!"})

        elif action == 'compress':
            if not filename: return jsonify({"success": False, "message": "Pilih file."})
            filepath = os.path.join(target, filename)
            name, fext = os.path.splitext(filename)
            outpath = os.path.join(target, f"{name}_compressed{fext}")
            if fext.lower() in ('.mp4', '.mkv', '.webm', '.avi'):
                cmd = ["ffmpeg", "-y", "-i", filepath, "-vcodec", "libx264", "-crf", "28", "-acodec", "aac", outpath]
            else:
                cmd = ["ffmpeg", "-y", "-i", filepath, "-b:a", "128k", outpath]
                
            env = os.environ.copy()
            with open("/tmp/zdt_web_task.log", "w") as log_file:
                subprocess.Popen(cmd, stdout=log_file, stderr=subprocess.STDOUT, start_new_session=True, cwd=target, env=env)
            return jsonify({"success": True, "message": "Proses kompresi FFmpeg berjalan!"})

        return jsonify({"success": False, "message": "Aksi tidak dikenal."})
    except Exception as e:
        return jsonify({"success": False, "message": str(e)})

@app.route("/api/logs", methods=["GET"])
def get_logs():
    log_file = "/tmp/zdt_web_task.log"
    if os.path.exists(log_file):
        with open(log_file, "r") as f:
            lines = f.readlines()
            if lines: return jsonify({"log": "".join(lines[-100:])})
    return jsonify({"log": "No active tasks."})

@app.route("/api/logs/clear", methods=["POST"])
def clear_logs():
    try: os.remove("/tmp/zdt_web_task.log")
    except: pass
    return jsonify({"success": True})

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='ZDT Enterprise Dashboard')
    parser.add_argument('--bind', default='127.0.0.1', help='Bind address (default: 127.0.0.1)')
    parser.add_argument('--port', type=int, default=5000, help='Port number (default: 5000)')
    args = parser.parse_args()
    print(f"Memulai ZDT Enterprise Dashboard di {args.bind}:{args.port}...")
    app.run(host=args.bind, port=args.port, debug=False)
