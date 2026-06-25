#!/usr/bin/env python3
import sys
import os
import time
import subprocess
import threading
from concurrent.futures import ThreadPoolExecutor
try:
    import telebot
    from telebot.types import InlineKeyboardMarkup, InlineKeyboardButton
except ImportError:
    print("Modul pyTelegramBotAPI (telebot) belum terinstall!")
    sys.exit(1)

TOKEN = os.environ.get("TELEGRAM_TOKEN", "")
if not TOKEN:
    TOKEN_FILE = os.path.expanduser("~/.config/zdt/telegram_token.txt")
    if os.path.exists(TOKEN_FILE):
        # Pastikan token file aman (hanya bisa dibaca owner)
        try:
            os.chmod(TOKEN_FILE, 0o600)
        except OSError:
            pass
        with open(TOKEN_FILE, 'r') as f:
            TOKEN = f.read().strip()

if not TOKEN:
    print("Token Telegram tidak ditemukan di konfigurasi atau env var!")
    if __name__ == "__main__":
        sys.exit(1)
    else:
        TOKEN = "dummy_token_for_import"

bot = telebot.TeleBot(TOKEN)

# Thread pool untuk background tasks — batasi maks 10 thread concurrent
_bg_thread_pool = ThreadPoolExecutor(max_workers=10, thread_name_prefix="zdt_bg")

import logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(name)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
telebot.logger.setLevel(logging.INFO)

chat_history = {}

original_send_message = bot.send_message
def logging_send_message(chat_id, text, **kwargs):
    logging.info(f"Bot mengirim pesan ke {chat_id}: {text}")
    if chat_id not in chat_history:
        chat_history[chat_id] = {"messages": [], "search_results": []}
    chat_history[chat_id]["messages"].append(f"Zaki-Bot: {text}")
    chat_history[chat_id]["messages"] = chat_history[chat_id]["messages"][-6:]
    return original_send_message(chat_id, text, **kwargs)
bot.send_message = logging_send_message


def listener(messages):
    for m in messages:
        if m.content_type == 'text':
            user = m.from_user.first_name if m.from_user else "Unknown"
            logging.info(f"Pesan masuk dari {user} (ID: {m.chat.id}): {m.text}")
            if m.chat.id not in chat_history:
                chat_history[m.chat.id] = {"messages": [], "search_results": []}
            chat_history[m.chat.id]["messages"].append(f"User: {m.text}")
            chat_history[m.chat.id]["messages"] = chat_history[m.chat.id]["messages"][-6:]

bot.set_update_listener(listener)

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
    zdt_bin = "zdt"  # Fallback

@bot.message_handler(commands=['start', 'help', 'menu'])
def send_welcome(message):
    msg = (
        "🤖 *ZDT ENTERPRISE REMOTE BOT*\n"
        "━━━━━━━━━━━━━━━━━━━━━\n"
        "Selamat datang bos! Saya adalah asisten remote "
        "yang terhubung langsung ke server ZDT Anda.\n\n"
        "🚀 *DAFTAR PERINTAH:*\n"
        "🎵 `/audio <link>` - Sedot Musik (YT/Spotify)\n"
        "🎬 `/video <link>` - Sedot Video Kualitas Tinggi\n"
        "📈 `/status` - Cek Kondisi Server (RAM/Disk)\n"
        "⚡ `/ping` - Cek kecepatan respon bot\n\n"
        "Atau pilih menu otomatis di bawah ini untuk mengeksekusi fitur server:"
    )
    markup = InlineKeyboardMarkup()
    markup.row_width = 2
    markup.add(
        InlineKeyboardButton("🗜️ Kompres Media", callback_data="cmd_kompres"),
        InlineKeyboardButton("🎤 Ekstrak Vokal", callback_data="cmd_vokal"),
        InlineKeyboardButton("🧹 Bersih Nama", callback_data="cmd_bersih"),
        InlineKeyboardButton("🎵 Sync Lirik", callback_data="cmd_lirik"),
        InlineKeyboardButton("📑 Bikin Playlist", callback_data="cmd_playlist")
    )
    bot.reply_to(message, msg, parse_mode="Markdown", reply_markup=markup)

@bot.message_handler(commands=['status'])
def server_status(message):
    try:
        disk = subprocess.check_output(["df", "-h", "/"]).decode('utf-8').split('\n')[1].split()
        ram = subprocess.check_output(["free", "-m"]).decode('utf-8').split('\n')[1].split()
        uptime = subprocess.check_output(["uptime", "-p"]).decode('utf-8').strip()
        
        msg = (
            "📊 *STATUS SERVER ZDT*\n"
            "━━━━━━━━━━━━━━━━━━━━━\n"
            f"⏱️ *Uptime:* {uptime.replace('up ', '')}\n"
            f"💾 *Disk Tersisa:* {disk[3]} dari {disk[1]} ({disk[4]} Terpakai)\n"
            f"🧠 *RAM Terpakai:* {ram[2]}MB / {ram[1]}MB\n"
            "🟢 *Status:* Online & Siap Tempur!"
        )
        bot.reply_to(message, msg, parse_mode="Markdown")
    except Exception as e:
        bot.reply_to(message, f"Gagal mengambil status: {e}")

@bot.message_handler(commands=['ping'])
def ping_bot(message):
    start = time.time()
    msg = bot.reply_to(message, "🏓 Pong!")
    end = time.time()
    ms = int((end - start) * 1000)
    bot.edit_message_text(f"🏓 Pong! `{ms}ms`", chat_id=message.chat.id, message_id=msg.message_id, parse_mode="Markdown")

def get_target_dir():
    target_dir = os.path.expanduser("~/Music/ZDT_Downloads")
    conf_file = os.path.expanduser("~/.config/zdt/config.env")
    old_conf = os.path.expanduser("~/.config/zdt/config")
    for cf in [conf_file, old_conf]:
        if os.path.exists(cf):
            with open(cf, 'r') as f:
                for line in f:
                    if line.startswith("TARGET_DIR=") or line.startswith("storage_dir="):
                        val = line.strip().split('=', 1)[1].strip('"').strip("'")
                        if val and val != ".":
                            return os.path.expanduser(val)
    return target_dir

def get_config_value(key, default=""):
    """Baca satu value dari config.env (single source of truth)."""
    conf_file = os.path.expanduser("~/.config/zdt/config.env")
    old_conf = os.path.expanduser("~/.config/zdt/config")
    for cf in [conf_file, old_conf]:
        if os.path.exists(cf):
            with open(cf, 'r') as f:
                for line in f:
                    if line.startswith(f"{key}="):
                        val = line.strip().split('=', 1)[1].strip('"').strip("'")
                        if val:
                            return val
    return default

def get_recent_media_files(limit=5):
    import glob
    target = get_target_dir()
    files = []
    if os.path.exists(target):
        for ext in ['*.mp3','*.m4a','*.flac','*.wav','*.ogg','*.opus','*.mp4','*.mkv']:
            files.extend(glob.glob(os.path.join(target, ext)))
    files.sort(key=os.path.getmtime, reverse=True)
    return files[:limit]

@bot.message_handler(commands=['demucs'])
def demucs_cmd(message):
    files = get_recent_media_files(5)
    if not files:
        bot.reply_to(message, "❌ Tidak ada file media ditemukan di Storage.")
        return
    markup = InlineKeyboardMarkup()
    for f in files:
        basename = os.path.basename(f)
        markup.add(InlineKeyboardButton(f"🎤 {basename[:40]}", callback_data=f"do_demucs|{f}"))
    bot.reply_to(message, "🎶 *Pilih file yang ingin dipisah vokalnya:*", parse_mode="Markdown", reply_markup=markup)

@bot.message_handler(commands=['kompres'])
def kompres_cmd(message):
    files = get_recent_media_files(5)
    if not files:
        bot.reply_to(message, "❌ Tidak ada file media ditemukan di Storage.")
        return
    markup = InlineKeyboardMarkup()
    for f in files:
        basename = os.path.basename(f)
        markup.add(InlineKeyboardButton(f"🗜️ {basename[:40]}", callback_data=f"do_kompres|{f}"))
    bot.reply_to(message, "🗜️ *Pilih file yang ingin dikompres:*", parse_mode="Markdown", reply_markup=markup)

@bot.message_handler(commands=['video'])
def download_video(message):
    text = message.text.replace('/video', '').strip()
    if "http" not in text:
        bot.reply_to(message, "❌ Link tidak valid! Contoh: `/video https://youtube.com/...`", parse_mode="Markdown")
        return
        
    url = [word for word in text.split() if "http" in word][0]
    bot.reply_to(message, f"⏳ *Sedang Mendownload Video...*\n📍 `Server` sedang memproses link Anda.", parse_mode="Markdown")
    
    try:
        with open(os.devnull, 'w') as devnull:
            subprocess.Popen([zdt_bin, "--download-video", url], stdout=devnull, stderr=devnull, start_new_session=True)
    except Exception as e:
        bot.reply_to(message, f"❌ Terjadi kesalahan: {str(e)}")

@bot.message_handler(commands=['audio'])
def download_audio_cmd(message):
    text = message.text.replace('/audio', '').strip()
    if "http" not in text:
        bot.reply_to(message, "❌ Link tidak valid! Contoh: `/audio https://spotify.com/...`", parse_mode="Markdown")
        return
        
    url = [word for word in text.split() if "http" in word][0]
    bot.reply_to(message, f"⏳ *Sedang Mendownload Audio...*\n📍 `Server` sedang menyedot musik Anda.", parse_mode="Markdown")
    
    try:
        with open(os.devnull, 'w') as devnull:
            subprocess.Popen([zdt_bin, "--download-audio", url], stdout=devnull, stderr=devnull, start_new_session=True)
    except Exception as e:
        bot.reply_to(message, f"❌ Terjadi kesalahan: {str(e)}")

@bot.message_handler(func=lambda message: True)
def auto_download_audio(message):
    text = message.text
    if "http" not in text:
        gemini_key_file = os.path.expanduser("~/.config/zdt/gemini_key")
        openrouter_key_file = os.path.expanduser("~/.config/zdt/openrouter_key")
        gemini_key = ""
        openrouter_key = ""
        if os.path.exists(gemini_key_file):
            try:
                with open(gemini_key_file, "r") as f:
                    gemini_key = f.read().strip()
            except (OSError, PermissionError):
                pass
        if os.path.exists(openrouter_key_file):
            try:
                with open(openrouter_key_file, "r") as f:
                    openrouter_key = f.read().strip()
            except (OSError, PermissionError):
                pass
        
        # Dual-key logic: jika gemini_key starts with sk-or- -> backward compat sbg OR key
        if not openrouter_key and gemini_key and gemini_key.startswith("sk-or-"):
            openrouter_key = gemini_key
            gemini_key = ""
        
        try:
            if gemini_key or openrouter_key:
                bot.send_chat_action(message.chat.id, 'typing')
                import urllib.request, json
                    
                abs_path = get_target_dir()
                try:
                    if os.path.exists(abs_path):
                        dir_contents = ", ".join(os.listdir(abs_path)[:50])
                    else:
                        dir_contents = "Direktori kosong/tidak ada."
                except (OSError, PermissionError):
                    dir_contents = "Gagal membaca direktori."

                chat_data = chat_history.get(message.chat.id, {"messages": [], "search_results": []})
                history_context = "\\n".join(chat_data["messages"])
                search_context = "\\n".join(chat_data["search_results"])
                    
                if search_context:
                    search_context = f"\\n\\nInfo Hasil Pencarian Terakhir (Ganti nomor dengan URL yang sesuai jika user memilih):\\n{search_context}"
                        
                prompt = f'''Peranmu Zaki-Bot, asisten cerdas ZDT Music Toolkit Telegram Bot.

—PENGETAHUAN APLIKASI ZDT—
ZDT adalah toolkit manajemen musik/video berbasis CLI + Web + Telegram.

*CLI MENU UTAMA (18 menu):*
1. Download YouTube — download audio/video dari YT
2. Download Spotify — download lagu/playlist/album dari Spotify
3. Kompres Audio — kompres file audio pakai FFmpeg
4. Kompres Video — kompres file video pakai FFmpeg
5. Pisah Vokal — ekstrak vokal/instrumen pakai Demucs AI
6. Sync Lirik — cari dan sync lirik otomatis
7. Bersih Nama File — rapikan nama file berantakan
8. Buat Playlist M3U — buat playlist .m3u8
9. Info Sistem — cek disk, RAM, CPU, uptime
10. Metadata Editor — edit judul, artis, album
11. Setup Tools — install dependencies
12. Watch Daemon — pantau folder, proses file baru
13. Web Dashboard — antarmuka web (port 5678)
14. Zaki AI — asisten AI pintar
15. Telegram Bot — kontrol via Telegram
16. Update ZDT — update skrip via git
17. Storage Setup — ubah folder penyimpanan
18. Keluar

*CLI ARGUMENTS:*
--help, --download-audio URL, --download-video URL
--sync-lirik-all, --bersih-nama-all, --bikin-playlist-all
--setup, --update, --watch, --web, --telegram

*WEB DASHBOARD (port 5678):*
Monitoring: Disk, RAM, CPU + uptime (Chart.js bar charts)
AI API: status Gemini/OpenRouter
Watch: start/stop/status daemon
Notifikasi: konfigurasi Telegram Bot Token + Chat ID
Scheduler: daftar playlist Spotify terjadwal
Login: admin + password dari config.env
Auto-refresh tiap 1.5 detik

*TELEGRAM BOT COMMANDS:*
/audio <url> - download audio
/video <url> - download video
/status - cek server
/ping - cek latensi
/start - menu bantuan
/demucs - pilih file pisah vokal
/kompres - pilih file kompresi
Inline buttons: Kompres, Ekstrak Vokal, Bersih Nama, Sync Lirik, Bikin Playlist

*AI BACKEND:*
OpenRouter 3-tier fallback:
- Tier 1: qwen/qwen3-coder-next:free, deepseek/deepseek-v4-flash:free, google/gemma-4-31b-it:free
- Tier 2: nvidia/nemotron-3-super:free, minimax/minimax-m2.5:free, meta-llama/llama-3.3-70b-instruct:free
- Tier 3: openrouter/free (auto-select)
Gemini: gemini-1.5-flash (secondary fallback)
History: 6 pesan terakhir per chat (SQLite)
Config keys: ~/.config/zdt/gemini_key atau ~/.config/zdt/openrouter_key

*DAEMONS:*
1. Watch Daemon (zdt-watch.py): monitor folder download, auto-proses file baru
2. Scheduler Daemon (zdt-scheduler.py): download playlist Spotify terjadwal
   Baca jadwal dari ~/.config/zdt/scheduler.json
   Kirim notif Telegram via webhook kalau selesai
   Status: start/stop dari Web Dashboard

*CONFIG FILES:*
~/.config/zdt/config.env - main config
~/.config/zdt/gemini_key - Gemini API key
~/.config/zdt/openrouter_key - OpenRouter API key
~/.config/zdt/telegram_token.txt - Telegram Bot token
~/.config/zdt/scheduler.json - scheduler config
~/.config/zdt/zdt_history.db - SQLite chat history
Storage: ~/Music/ZDT/ (default, bisa diubah)

*SYSTEMD SERVICE:*
zdt-scheduler.service + zdt-scheduler.timer (auto-start on boot via systemd)

*AUTO_ACTION TAGS (18 jenis):*
Download Audio/Lagu: [AUTO_ACTION: gas download audio ytsearch1:judul atau URL]
Download Video: [AUTO_ACTION: gas download video ytsearch1:judul atau URL]
Cari YouTube: [AUTO_ACTION: cari youtube kata_kunci]
Cari Playlist: [AUTO_ACTION: cari playlist kata_kunci]
Pisah Vokal: [AUTO_ACTION: hapus vokal]
Kompres Media: [AUTO_ACTION: kompres media]
Cari Lirik: [AUTO_ACTION: sync lirik]
Rapi Nama File: [AUTO_ACTION: bersih nama]
Buat Playlist: [AUTO_ACTION: bikin playlist]
Hapus Semua File: [AUTO_ACTION: hapus semua]
Cek Status Server: [AUTO_ACTION: cek status]
Buka Web Dashboard: [AUTO_ACTION: buka web]
Setup Tools: [AUTO_ACTION: setup tools]
Update Tools: [AUTO_ACTION: update tools]
Start Telegram Bot: [AUTO_ACTION: start telegram]
Start Watch Daemon: [AUTO_ACTION: start watch]
Buka Scheduler: [AUTO_ACTION: buka scheduler]
Ubah Storage: [AUTO_ACTION: ubah storage]

Info: Lokasi file di "{abs_path}". Isi file: {dir_contents}.

ATURAN FORMAT RESPON:
- HANYA tulis jawaban langsung. JANGAN pernah tulis arahan, instruksi, atau penjelasan tentang apa yang harus kamu lakukan.
- JANGAN tulis ulang perintah atau komentari tugasmu. Langsung jawab aja.
- Pakai *bold* untuk teks tebal (bukan **bold**)
- JANGAN pakai ### / ## / # heading
- Pake • atau - untuk bullet list
- Pisah paragraf dengan baris kosong
- Jangan double space
- Awali dan akhiri dengan gaya santai anak muda Indonesia

ATURAN: JIKA user menyuruh EKSEKUSI aksi, WAJIB sertakan tag [AUTO_ACTION: ...]!
JIKA user hanya tanya/curhat/minta penjelasan, JANGAN pakai AUTO_ACTION!
BALAS LANGSUNG tanpa menjelaskan aturan atau proses berpikirmu.

Contoh:
User: download lagu tulus
Bot: Gas download Tulus! 🎵 [AUTO_ACTION: gas download audio ytsearch1:Tulus]

User: cek status server
Bot: Cek status bentar! 📊 [AUTO_ACTION: cek status]

User: apa itu zdt
Bot: ZDT adalah toolkit manajemen musik/video... (jelaskan fitur lengkap)

User: cara setup telegram
Bot: 1) Bikin bot di @BotFather, 2) Simpan token di ~/.config/zdt/telegram_token.txt

User: daemon apa aja yang jalan
Bot: Ada 2 daemon: Watch Daemon (pantau folder) dan Scheduler Daemon (download terjadwal). Status di Web Dashboard.

User: gimana cara pake scheduler
Bot: Buka Web Dashboard -> panel Scheduler. Tambah URL playlist Spotify, atur interval, start daemon.

User: lagu yang tadi gak jadi
Bot: Oke, gak jadi! Ada yang lain bisa dibantu?

{search_context}

Riwayat Chat Terbaru:
{history_context}'''

                def process_reply(reply_text):
                    if "[AUTO_ACTION:" in reply_text:
                        import re
                        match = re.search(r"\[AUTO_ACTION:\s*(.+?)\]", reply_text)
                        if match:
                            action = match.group(1).strip()
                                
                            def run_bg_task(cmd_args, success_msg, progress_msg=None):
                                import threading
                                import subprocess
                                import time
                                import re
                                def _task():
                                    try:
                                        # Using unbuffered output trick via stdbuf or directly reading
                                        process = subprocess.Popen([zdt_bin] + cmd_args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
                                            
                                        last_update = time.time()
                                        log_buffer = []
                                        ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
                                            
                                        for line in iter(process.stdout.readline, ''):
                                            if not line:
                                                break
                                            clean_line = ansi_escape.sub('', line).strip()
                                                
                                            if clean_line:
                                                # yt-dlp outputs progress on lines starting with [download], update it without creating new array items if it's progress
                                                if log_buffer and clean_line.startswith("[download]") and log_buffer[-1].startswith("[download]"):
                                                    log_buffer[-1] = clean_line
                                                else:
                                                    log_buffer.append(clean_line)
                                                    
                                                log_buffer = log_buffer[-6:] # keep last 6 lines
                                                
                                            # Update telegram message every 3 seconds
                                            if progress_msg and time.time() - last_update > 3.0:
                                                context = "\n".join(log_buffer)
                                                import html
                                                try:
                                                    bot.edit_message_text(f"⏳ <b>Proses Berjalan...</b>\n<pre>{html.escape(context)}</pre>", chat_id=progress_msg.chat.id, message_id=progress_msg.message_id, parse_mode="HTML")
                                                except Exception:
                                                    pass # ignore rate limits or unchanged errors
                                                last_update = time.time()
                                            
                                        process.wait()
                                        final_context = "\n".join(log_buffer)
                                        import html
                                            
                                        if process.returncode == 0:
                                            if progress_msg:
                                                try:
                                                    bot.edit_message_text(f"✅ <b>{success_msg}</b>\n\n📄 <b>Log Terakhir:</b>\n<pre>{html.escape(final_context)}</pre>", chat_id=progress_msg.chat.id, message_id=progress_msg.message_id, parse_mode="HTML")
                                                except:
                                                    bot.reply_to(message, f"✅ <b>{success_msg}</b>\n\n📄 <b>Log Terakhir:</b>\n<pre>{html.escape(final_context)}</pre>", parse_mode="HTML")
                                            else:
                                                bot.reply_to(message, f"✅ <b>{success_msg}</b>\n\n📄 <b>Log Terakhir:</b>\n<pre>{html.escape(final_context)}</pre>", parse_mode="HTML")
                                        else:
                                            if progress_msg:
                                                try:
                                                    bot.edit_message_text(f"❌ <b>Terjadi kesalahan.</b>\n\n📄 <b>Error:</b>\n<pre>{html.escape(final_context)}</pre>", chat_id=progress_msg.chat.id, message_id=progress_msg.message_id, parse_mode="HTML")
                                                except Exception:
                                                    bot.reply_to(message, f"❌ <b>Terjadi kesalahan.</b>\n\n📄 <b>Error:</b>\n<pre>{html.escape(final_context)}</pre>", parse_mode="HTML")
                                            else:
                                                bot.reply_to(message, f"❌ <b>Terjadi kesalahan.</b>\n\n📄 <b>Error:</b>\n<pre>{html.escape(final_context)}</pre>", parse_mode="HTML")
                                    except Exception as e:
                                        bot.reply_to(message, f"❌ System Error: {e}")
                                _bg_thread_pool.submit(_task)

                            if action.startswith("gas download audio"):
                                url = action.replace("gas download audio", "").strip()
                                sent_msg = bot.reply_to(message, f"⏳ <b>Sedang Mendownload Audio...</b>\n📍 <code>Server</code> memproses link.", parse_mode="HTML")
                                run_bg_task(["--download-audio", url], "Audio berhasil di-download!", sent_msg)
                            elif action.startswith("gas download video"):
                                url = action.replace("gas download video", "").strip()
                                sent_msg = bot.reply_to(message, f"⏳ <b>Sedang Mendownload Video...</b>\n📍 <code>Server</code> memproses link.", parse_mode="HTML")
                                run_bg_task(["--download-video", url], "Video berhasil di-download!", sent_msg)
                            elif action.startswith("cari youtube"):
                                query = action.replace("cari youtube", "").strip()
                                import html
                                bot.reply_to(message, f"🔍 <b>Mencari di YouTube...</b>\nKata kunci: <code>{html.escape(query)}</code>", parse_mode="HTML")
                                    
                                def _search_task():
                                    try:
                                        res = subprocess.run(["yt-dlp", f"ytsearch5:{query}", "--print", "%(title)s|%(webpage_url)s"], capture_output=True, text=True)
                                        if res.returncode == 0 and res.stdout.strip():
                                            import telebot
                                            import html
                                                
                                            lines = res.stdout.strip().split('\n')
                                            formatted = []
                                            urls = []
                                            for idx, line in enumerate(lines, 1):
                                                parts = line.split('|', 1)
                                                if len(parts) == 2:
                                                    title = html.escape(parts[0].strip())
                                                    url = html.escape(parts[1].strip())
                                                    formatted.append(f"{idx}. <b>{title}</b>\n{url}")
                                                    urls.append(f"{idx}) {parts[1].strip()}")
                                                
                                            if chat_history.get(message.chat.id):
                                                chat_history[message.chat.id]["search_results"] = urls
                                                
                                            out_text = "\n\n".join(formatted)
                                            bot.reply_to(message, f"🎯 <b>Hasil Pencarian:</b>\n\n{out_text}\n\n<i>Balas dengan nomor (misal: 'download nomor 1') atau linknya!</i>", parse_mode="HTML", link_preview_options=telebot.types.LinkPreviewOptions(is_disabled=True))
                                        else:
                                            bot.reply_to(message, "❌ Pencarian tidak menemukan hasil.")
                                    except Exception as e:
                                        bot.reply_to(message, f"❌ Error pencarian: {e}")
                                _bg_thread_pool.submit(_search_task)
                            elif action.startswith("cari playlist"):
                                query = action.replace("cari playlist", "").strip()
                                import urllib.parse
                                import html
                                bot.reply_to(message, f"🔍 <b>Mencari Playlist di YouTube...</b>\nKata kunci: <code>{html.escape(query)}</code>", parse_mode="HTML")
                                    
                                def _search_playlist_task():
                                    try:
                                        # &sp=EgIQAw%253D%253D is YouTube's filter for Playlists
                                        search_url = f"https://www.youtube.com/results?search_query={urllib.parse.quote(query)}&sp=EgIQAw%253D%253D"
                                        res = subprocess.run(["yt-dlp", search_url, "--flat-playlist", "--print", "%(title)s|%(webpage_url)s", "--playlist-end", "5"], capture_output=True, text=True)
                                        if res.returncode == 0 and res.stdout.strip():
                                            import telebot
                                            import html
                                                
                                            lines = res.stdout.strip().split('\n')
                                            formatted = []
                                            urls = []
                                            # Sometimes yt-dlp returns channel links on playlist searches, we should filter or just list them
                                            idx = 1
                                            for line in lines:
                                                parts = line.split('|', 1)
                                                if len(parts) == 2:
                                                    title = html.escape(parts[0].strip())
                                                    url = html.escape(parts[1].strip())
                                                    formatted.append(f"{idx}. <b>{title}</b>\n{url}")
                                                    urls.append(f"{idx}) {parts[1].strip()}")
                                                    idx += 1
                                                
                                            if chat_history.get(message.chat.id):
                                                chat_history[message.chat.id]["search_results"] = urls
                                                
                                            out_text = "\n\n".join(formatted)
                                            bot.reply_to(message, f"🎯 <b>Hasil Pencarian Playlist:</b>\n\n{out_text}\n\n<i>Balas dengan nomor (misal: 'download playlist nomor 1') atau linknya!</i>", parse_mode="HTML", link_preview_options=telebot.types.LinkPreviewOptions(is_disabled=True))
                                        else:
                                            bot.reply_to(message, "❌ Pencarian playlist tidak menemukan hasil.")
                                    except Exception as e:
                                        bot.reply_to(message, f"❌ Error pencarian playlist: {e}")
                                _bg_thread_pool.submit(_search_playlist_task)
                            elif action == "hapus vokal":
                                bot.reply_to(message, "⚙️ Mengakses panel Demucs AI...")
                                demucs_cmd(message)
                            elif action == "kompres media":
                                bot.reply_to(message, "⚙️ Mengakses panel Kompresi Media...")
                                kompres_cmd(message)
                            elif action == "sync lirik":
                                sent_msg = bot.reply_to(message, "⏳ <b>Menyelaraskan lirik di background...</b>", parse_mode="HTML")
                                run_bg_task(["--sync-lirik-all"], "Lirik berhasil di-sync!", sent_msg)
                            elif action == "bersih nama":
                                sent_msg = bot.reply_to(message, "⏳ <b>Membersihkan nama file di background...</b>", parse_mode="HTML")
                                run_bg_task(["--bersih-nama-all"], "Nama file berhasil dirapikan!", sent_msg)
                            elif action == "bikin playlist":
                                sent_msg = bot.reply_to(message, "⏳ <b>Membuat playlist di background...</b>", parse_mode="HTML")
                                run_bg_task(["--bikin-playlist-all"], "Playlist M3U8 berhasil dibuat!", sent_msg)
                            elif action == "hapus semua":
                                # Konfirmasi keamanan sebelum hapus
                                markup = InlineKeyboardMarkup()
                                markup.row_width = 2
                                markup.add(
                                    InlineKeyboardButton("⚠️ YA, HAPUS SEMUA", callback_data=f"CONFIRM_DELETE:{abs_path}"),
                                    InlineKeyboardButton("❌ BATAL", callback_data="CANCEL_DELETE")
                                )
                                bot.reply_to(message, f"⚠️ *PERINGATAN KEAMANAN!*\n\nAnda akan menghapus SEMUA file di:\n`{abs_path}`\n\nTindakan ini TIDAK BISA dibatalkan!\n\nKlik tombol di bawah untuk konfirmasi:", parse_mode="Markdown", reply_markup=markup)
                            elif action == "cek status":
                                server_status(message)
                            elif action == "buka web":
                                bot.reply_to(message, "🌐 Buka Web Dashboard di: http://localhost:5678/\n\nLogin dengan user/password dari config.env.\n\nFitur: Monitoring server, download management, scheduler, notifikasi Telegram.")
                            elif action == "setup tools":
                                bot.reply_to(message, "⚙️ Menjalankan Setup Tools...")
                                try:
                                    with open(os.devnull, 'w') as devnull:
                                        subprocess.Popen([zdt_bin, "--setup"], stdout=devnull, stderr=devnull, start_new_session=True)
                                except Exception as e:
                                    bot.reply_to(message, f"❌ Error: {e}")
                            elif action == "update tools":
                                bot.reply_to(message, "🔄 Menjalankan Update ZDT...")
                                try:
                                    with open(os.devnull, 'w') as devnull:
                                        subprocess.Popen([zdt_bin, "--update"], stdout=devnull, stderr=devnull, start_new_session=True)
                                except Exception as e:
                                    bot.reply_to(message, f"❌ Error: {e}")
                            elif action == "start telegram":
                                bot.reply_to(message, "🤖 Telegram Bot sudah berjalan! (Ini botnya sendiri)")
                            elif action == "start watch":
                                sent_msg = bot.reply_to(message, "⏳ <b>Memulai Watch Daemon...</b>", parse_mode="HTML")
                                run_bg_task(["--watch"], "Watch Daemon berjalan!")
                            elif action == "buka scheduler":
                                bot.reply_to(message, "📅 Scheduler ada di Web Dashboard -> panel Scheduler.\n\nCara pakai:\n1. Buka http://localhost:5678/\n2. Login, buka panel Scheduler\n3. Tambah URL playlist Spotify\n4. Atur interval (jam)\n5. Klik Start Daemon\n\nDownload otomatis + notif Telegram kalau selesai!")
                            elif action == "ubah storage":
                                bot.reply_to(message, "📁 Untuk mengubah folder Storage:\n1. Edit file ~/.config/zdt/config.env\n2. Set TARGET_DIR=/path/baru\n3. Restart bot\n\nAtau lewat CLI: zdt -> pilih menu Storage Setup")
                            else:
                                bot.reply_to(message, f"❌ Aksi {action} belum didukung di Telegram.")
                                
                            clean_reply = re.sub(r"\[AUTO_ACTION:.*?\]", "", reply_text).strip()
                            if clean_reply:
                                bot.reply_to(message, clean_reply, parse_mode="Markdown")
                            return
                    bot.reply_to(message, reply_text, parse_mode="Markdown")
                    
                # Dual-key routing: prefer OpenRouter if openrouter_key exists
                if openrouter_key:
                    url = "https://openrouter.ai/api/v1/chat/completions"
                    headers = {"Authorization": f"Bearer {openrouter_key}", "Content-Type": "application/json"}
                    messages = [{"role": "system", "content": prompt}, {"role": "user", "content": text}]
                        
                    fallback_arrays = [
                        ["qwen/qwen3-coder-next:free", "deepseek/deepseek-v4-flash:free", "google/gemma-4-31b-it:free"],
                        ["nvidia/nemotron-3-super:free", "minimax/minimax-m2.5:free", "meta-llama/llama-3.3-70b-instruct:free"],
                        ["openrouter/free"]
                    ]
                    reply_text = ""
                    import urllib.error
                    for models in fallback_arrays:
                        payload = {"models": models, "messages": messages, "max_tokens": 800}
                        data = json.dumps(payload).encode("utf-8")
                        req = urllib.request.Request(url, data=data, headers=headers)
                        try:
                            with urllib.request.urlopen(req, timeout=20) as response:
                                res = json.loads(response.read().decode())
                                if "error" in res:
                                    reply_text = f"API Error: {res['error'].get('message', 'Unknown')}"
                                else:
                                    content = res.get("choices", [{}])[0].get("message", {}).get("content")
                                    reply_text = f"API Error (Kosong): {json.dumps(res)}" if content is None else content.strip()
                                break
                        except urllib.error.HTTPError as e:
                            err_msg = e.read().decode()
                            reply_text = f'Aduh otak AI gua lagi pusing bro wkwk. Error: {err_msg}'
                            continue
                        except Exception as e:
                            reply_text = f'Aduh otak AI gua lagi pusing bro wkwk. Error: {str(e)}'
                            continue
                        
                    # OR succeeded? Process reply and return.
                    # If all OR tiers failed ("Aduh otak" = conn/auth error), fall through to Gemini
                    if not reply_text.startswith("Aduh otak"):
                        process_reply(reply_text)
                        return
                    # OR failed silently — try Gemini below
                    
                if gemini_key:
                    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={gemini_key}"
                    headers = {"Content-Type": "application/json"}
                    payload = {"system_instruction": {"parts": [{"text": prompt}]}, "contents": [{"role": "user", "parts": [{"text": text}]}], "generationConfig": {"maxOutputTokens": 800}}
                    data = json.dumps(payload).encode("utf-8")
                    req = urllib.request.Request(url, data=data, headers=headers)
                    with urllib.request.urlopen(req, timeout=20) as response:
                        res = json.loads(response.read().decode())
                    if "error" in res:
                        reply_text = f"API Error: {res['error'].get('message', 'Unknown')}"
                    else:
                        content = res.get("candidates", [{}])[0].get("content", {}).get("parts", [{}])[0].get("text")
                        reply_text = f"API Error (Kosong): {json.dumps(res)}" if content is None else content.strip()
                    process_reply(reply_text)
                    return
                    
                # OR failed and no Gemini fallback — show the actual error
                if openrouter_key and reply_text:
                    bot.reply_to(message, reply_text)
                    return
        except Exception as e:
                import urllib.error
                err_msg = e.read().decode() if isinstance(e, urllib.error.HTTPError) else str(e)
                bot.reply_to(message, f"Aduh otak AI gua lagi pusing bro wkwk. Error: {err_msg}")
                return
        
        bot.reply_to(message, "🤔 Maksud lu apa nih? Kirim link media aja langsung buat disedot, atau ketik /start untuk lihat fitur!")
        return
        
    url = [word for word in text.split() if "http" in word][0]
    bot.reply_to(message, f"🎧 *Link Terdeteksi!*\nOtomatis mendownload sebagai Audio (MP3/M4A).", parse_mode="Markdown")
    
    try:
        with open(os.devnull, 'w') as devnull:
            subprocess.Popen([zdt_bin, "--download-audio", url], stdout=devnull, stderr=devnull, start_new_session=True)
    except Exception as e:
        bot.reply_to(message, f"❌ Terjadi kesalahan: {str(e)}")

try:
    bot.remove_webhook()
    time.sleep(1)
except Exception:
    pass


@bot.callback_query_handler(func=lambda call: call.data.startswith('cmd_'))
def callback_query(call):
    cmd = call.data
    action = ""
    bash_flag = ""
    
    if cmd == "cmd_kompres":
        kompres_cmd(call.message)
        return
    elif cmd == "cmd_vokal":
        demucs_cmd(call.message)
        return
    elif cmd == "cmd_bersih":
        action = "🧹 Pembersih Nama File"
        bash_flag = "--bersih-nama-all"
    elif cmd == "cmd_lirik":
        action = "🎵 Auto-Sync Lirik"
        bash_flag = "--sync-lirik-all"
    elif cmd == "cmd_playlist":
        action = "📑 Generator Playlist"
        bash_flag = "--bikin-playlist-all"

    bot.answer_callback_query(call.id, f"Mengeksekusi: {action}")
    bot.send_message(call.message.chat.id, f"⏳ *Memulai Task:* `{action}`\n📍 _Proses berjalan di background server._", parse_mode="Markdown")
    
    try:
        with open(os.devnull, 'w') as devnull:
            subprocess.Popen([zdt_bin, bash_flag], stdout=devnull, stderr=devnull, start_new_session=True)
    except Exception as e:
        bot.send_message(call.message.chat.id, f"❌ Terjadi kesalahan: {str(e)}")

@bot.callback_query_handler(func=lambda call: call.data.startswith('do_demucs|') or call.data.startswith('do_kompres|'))
def process_specific_file(call):
    cmd_type, filepath = call.data.split('|', 1)
    if not os.path.exists(filepath):
        bot.answer_callback_query(call.id, "File sudah tidak ada di server!")
        return
    
    bot.answer_callback_query(call.id, "Memulai proses background...")
    msg = bot.send_message(call.message.chat.id, f"⏳ *Mempersiapkan tugas...*\n📍 `{os.path.basename(filepath)}`", parse_mode="Markdown")
    
    import subprocess, time, re, shutil
    
    def _task():
        try:
            cmd_args = []
            target_dir = os.path.dirname(filepath)
            
            if cmd_type == "do_demucs":
                demucs_bin = os.path.expanduser("~/.local/share/zdt/demucs_venv/bin/demucs")
                if not os.path.exists(demucs_bin): demucs_bin = shutil.which("demucs")
                if not demucs_bin:
                    bot.edit_message_text("❌ Demucs AI belum terinstal.", chat_id=msg.chat.id, message_id=msg.message_id)
                    return
                cmd_args = [demucs_bin, "--two-stems=vocals", "-o", target_dir, filepath]
                task_name = "Memisahkan Vokal"
                
            elif cmd_type == "do_kompres":
                base, ext = os.path.splitext(filepath)
                out_path = f"{base}_compressed{ext}"
                if ext.lower() in ['.mp4', '.mkv']:
                    cmd_args = ["ffmpeg", "-y", "-i", filepath, "-vcodec", "libx264", "-crf", "28", "-preset", "fast", out_path]
                else:
                    cmd_args = ["ffmpeg", "-y", "-i", filepath, "-b:a", "128k", out_path]
                task_name = "Kompresi Media"

            process = subprocess.Popen(cmd_args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
            last_update = time.time()
            log_buffer = []
            last_pct = "0%"
            
            for line in iter(process.stdout.readline, ''):
                if not line: break
                clean_line = line.strip()
                if not clean_line: continue
                
                log_buffer.append(clean_line)
                log_buffer = log_buffer[-5:]
                
                if cmd_type == "do_demucs":
                    match = re.search(r'(\d+\.?\d*)%', clean_line)
                    if match: last_pct = match.group(1) + "%"
                elif cmd_type == "do_kompres":
                    if "time=" in clean_line:
                        match = re.search(r'time=(\S+)', clean_line)
                        if match: last_pct = match.group(1)

                if time.time() - last_update > 3.0:
                    import html
                    context = "\\n".join(log_buffer)
                    text = f"⏳ <b>{task_name}</b> [{last_pct}]\\n<pre>{html.escape(context)}</pre>"
                    try:
                        bot.edit_message_text(text, chat_id=msg.chat.id, message_id=msg.message_id, parse_mode="HTML")
                    except Exception:
                        pass
                    last_update = time.time()
            
            process.wait()
            if process.returncode == 0:
                bot.edit_message_text(f"✅ *{task_name} Selesai!*\n📍 `{os.path.basename(filepath)}`", chat_id=msg.chat.id, message_id=msg.message_id, parse_mode="Markdown")
            else:
                bot.edit_message_text(f"❌ *{task_name} Gagal!*", chat_id=msg.chat.id, message_id=msg.message_id, parse_mode="Markdown")
                
        except Exception as e:
            bot.edit_message_text(f"❌ Error: {str(e)}", chat_id=msg.chat.id, message_id=msg.message_id)

    _bg_thread_pool.submit(_task)

@bot.callback_query_handler(func=lambda call: call.data.startswith('CONFIRM_DELETE:'))
def confirm_delete_callback(call):
    """Handler untuk konfirmasi hapus semua file"""
    bot.answer_callback_query(call.id, "Menghapus semua file...")
    try:
        target_path = call.data.split(':', 1)[1]
        if not os.path.exists(target_path):
            bot.edit_message_text("❌ Direktori tidak ditemukan!", chat_id=call.message.chat.id, message_id=call.message.message_id)
            return
        
        bot.edit_message_text("🗑️ *Menghapus semua file...*\nMohon tunggu.", chat_id=call.message.chat.id, message_id=call.message.message_id, parse_mode="Markdown")
        
        deleted = 0
        for filename in os.listdir(target_path):
            file_path = os.path.join(target_path, filename)
            try:
                if os.path.isfile(file_path) or os.path.islink(file_path):
                    os.unlink(file_path)
                    deleted += 1
                elif os.path.isdir(file_path):
                    shutil.rmtree(file_path)
                    deleted += 1
            except (OSError, PermissionError):
                pass
        
        bot.edit_message_text(f"✅ *Selesai!* {deleted} item berhasil dihapus dari:\n`{target_path}`", chat_id=call.message.chat.id, message_id=call.message.message_id, parse_mode="Markdown")
    except Exception as e:
        bot.edit_message_text(f"❌ Gagal menghapus: {e}", chat_id=call.message.chat.id, message_id=call.message.message_id)


@bot.callback_query_handler(func=lambda call: call.data == 'CANCEL_DELETE')
def cancel_delete_callback(call):
    """Handler untuk membatalkan hapus semua"""
    bot.edit_message_text("❌ Pembatalan hapus semua. Tidak ada file yang dihapus.", chat_id=call.message.chat.id, message_id=call.message.message_id)
    bot.answer_callback_query(call.id, "Dibatalkan.")

if __name__ == "__main__":
    print("Telegram Bot ZDT berjalan. Menunggu pesan masuk...")
    bot.infinity_polling()
