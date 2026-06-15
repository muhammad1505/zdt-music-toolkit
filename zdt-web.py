#!/usr/bin/env python3
import os
import sys
import subprocess
from flask import Flask, request, render_template_string, jsonify

app = Flask(__name__)

# Cyberpunk UI Template
HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ZDT Web Dashboard</title>
    <style>
        :root {
            --bg-dark: #0f0f13;
            --bg-panel: #1a1a24;
            --primary: #00f0ff;
            --secondary: #ff003c;
            --text: #e0e0e0;
            --border: rgba(0, 240, 255, 0.3);
        }
        body {
            font-family: 'Courier New', Courier, monospace;
            background-color: var(--bg-dark);
            color: var(--text);
            margin: 0;
            padding: 20px;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            background-image: 
                linear-gradient(rgba(0, 240, 255, 0.05) 1px, transparent 1px),
                linear-gradient(90deg, rgba(0, 240, 255, 0.05) 1px, transparent 1px);
            background-size: 20px 20px;
        }
        .container {
            background: var(--bg-panel);
            border: 1px solid var(--border);
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 0 20px rgba(0, 240, 255, 0.1);
            width: 100%;
            max-width: 500px;
        }
        h1 {
            color: var(--primary);
            text-align: center;
            text-transform: uppercase;
            letter-spacing: 2px;
            margin-top: 0;
            text-shadow: 0 0 10px rgba(0, 240, 255, 0.5);
        }
        .form-group {
            margin-bottom: 20px;
        }
        label {
            display: block;
            margin-bottom: 8px;
            color: var(--primary);
            font-weight: bold;
        }
        input[type="text"] {
            width: 100%;
            padding: 12px;
            background: rgba(0,0,0,0.5);
            border: 1px solid var(--border);
            color: white;
            border-radius: 4px;
            box-sizing: border-box;
            font-family: inherit;
        }
        input[type="text"]:focus {
            outline: none;
            border-color: var(--primary);
            box-shadow: 0 0 10px rgba(0, 240, 255, 0.2);
        }
        select {
            width: 100%;
            padding: 12px;
            background: rgba(0,0,0,0.5);
            border: 1px solid var(--border);
            color: white;
            border-radius: 4px;
            box-sizing: border-box;
            font-family: inherit;
        }
        button {
            width: 100%;
            padding: 15px;
            background: transparent;
            color: var(--primary);
            border: 1px solid var(--primary);
            border-radius: 4px;
            font-size: 16px;
            font-family: inherit;
            font-weight: bold;
            cursor: pointer;
            transition: all 0.3s ease;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        button:hover {
            background: var(--primary);
            color: var(--bg-dark);
            box-shadow: 0 0 15px var(--primary);
        }
        .status {
            margin-top: 20px;
            padding: 15px;
            border-radius: 4px;
            text-align: center;
            display: none;
            border: 1px solid;
        }
        .status.success {
            display: block;
            border-color: #00ff00;
            color: #00ff00;
            background: rgba(0, 255, 0, 0.1);
        }
        .status.error {
            display: block;
            border-color: var(--secondary);
            color: var(--secondary);
            background: rgba(255, 0, 60, 0.1);
        }
        .footer {
            margin-top: 30px;
            text-align: center;
            font-size: 12px;
            color: #666;
        }
    </style>
</head>
<body>

<div class="container">
    <h1>ZDT WEB DASHBOARD</h1>
    
    <form id="downloadForm">
        <div class="form-group">
            <label>URL Media (YouTube/Spotify/TikTok)</label>
            <input type="text" id="url" placeholder="Paste link di sini..." required>
        </div>
        <div class="form-group">
            <label>Format Media</label>
            <select id="format">
                <option value="audio">Audio (MP3/M4A)</option>
                <option value="video">Video (MP4/MKV)</option>
            </select>
        </div>
        <button type="submit" id="btnSubmit">EXECUTE DOWNLOAD</button>
    </form>
    
    <div id="statusBox" class="status"></div>
    
    <div class="footer">
        ZDT Music Toolkit v3.1.0 • Connected
    </div>
</div>

<script>
document.getElementById('downloadForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    const url = document.getElementById('url').value;
    const format = document.getElementById('format').value;
    const btn = document.getElementById('btnSubmit');
    const statusBox = document.getElementById('statusBox');
    
    btn.disabled = true;
    btn.innerText = "EXECUTING IN BACKGROUND...";
    statusBox.className = "status";
    
    try {
        const response = await fetch('/api/download', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({url, format})
        });
        
        const data = await response.json();
        
        if(data.success) {
            statusBox.className = "status success";
            statusBox.innerText = "[OK] Proses download sedang berjalan di terminal server!";
            document.getElementById('url').value = '';
        } else {
            statusBox.className = "status error";
            statusBox.innerText = "[FAIL] " + data.message;
        }
    } catch(err) {
        statusBox.className = "status error";
        statusBox.innerText = "[FAIL] Koneksi ke server terputus!";
    }
    
    btn.disabled = false;
    btn.innerText = "EXECUTE DOWNLOAD";
});
</script>

</body>
</html>
"""

@app.route('/')
def index():
    return render_template_string(HTML_TEMPLATE)

@app.route('/api/download', methods=['POST'])
def download():
    data = request.json
    url = data.get('url', '')
    fmt = data.get('format', 'audio')
    
    if not url:
        return jsonify({"success": False, "message": "URL tidak boleh kosong"})
        
    zdt_bin = "/home/zaki/.local/bin/zdt"
    if not os.path.exists(zdt_bin):
        zdt_bin = "/home/zaki/zdt.sh"
        
    if fmt == 'audio':
        cmd = [zdt_bin, "--download-audio", url]
    else:
        cmd = [zdt_bin, "--download-video", url]
        
    try:
        # Jalankan secara asinkron di background menggunakan Popen
        # dan arahkan stdout/stderr ke /dev/null agar tidak memblokir process Flask
        with open(os.devnull, 'w') as devnull:
            subprocess.Popen(cmd, stdout=devnull, stderr=devnull, start_new_session=True)
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"success": False, "message": str(e)})

if __name__ == '__main__':
    print("Memulai ZDT Web Dashboard di port 5000...")
    app.run(host='0.0.0.0', port=5000)
