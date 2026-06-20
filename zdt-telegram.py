#!/usr/bin/env python3
import sys
import os
import time
import subprocess
import threading
try:
    import telebot
    from telebot.types import InlineKeyboardMarkup, InlineKeyboardButton
except ImportError:
    print("Modul pyTelegramBotAPI (telebot) belum terinstall!")
    sys.exit(1)

TOKEN_FILE = os.path.expanduser("~/.config/zdt/telegram_token.txt")
if not os.path.exists(TOKEN_FILE):
    print("Token Telegram tidak ditemukan di konfigurasi.")
    sys.exit(1)

# Pastikan token file aman (hanya bisa dibaca owner)
try:
    os.chmod(TOKEN_FILE, 0o600)
except OSError:
    pass

with open(TOKEN_FILE, 'r') as f:
    TOKEN = f.read().strip()

if not TOKEN:
    print("Token Telegram kosong!")
    sys.exit(1)

bot = telebot.TeleBot(TOKEN)

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
        chat_history[chat_id] = []
    chat_history[chat_id].append(f"Zaki-Bot: {text}")
    chat_history[chat_id] = chat_history[chat_id][-6:]
    return original_send_message(chat_id, text, **kwargs)
bot.send_message = logging_send_message


def listener(messages):
    for m in messages:
        if m.content_type == 'text':
            user = m.from_user.first_name if m.from_user else "Unknown"
            logging.info(f"Pesan masuk dari {user} (ID: {m.chat.id}): {m.text}")
            if m.chat.id not in chat_history:
                chat_history[m.chat.id] = []
            chat_history[m.chat.id].append(f"User: {m.text}")
            chat_history[m.chat.id] = chat_history[m.chat.id][-6:]

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
        if os.path.exists(gemini_key_file):
            try:
                with open(gemini_key_file, "r") as f:
                    gemini_key = f.read().strip()
                if gemini_key:
                    bot.send_chat_action(message.chat.id, 'typing')
                    import urllib.request, json
                    
                    abs_path = os.path.expanduser("~/Music/ZDT")
                    conf_file = os.path.expanduser("~/.config/zdt/config")
                    if os.path.exists(conf_file):
                        with open(conf_file, 'r') as cf:
                            for line in cf:
                                if line.startswith("storage_dir="):
                                    val = line.strip().split('=', 1)[1].strip('"').strip("'")
                                    abs_path = os.path.expanduser(val)
                                    break
                    try:
                        if os.path.exists(abs_path):
                            dir_contents = ", ".join(os.listdir(abs_path)[:50])
                        else:
                            dir_contents = "Direktori kosong/tidak ada."
                    except Exception:
                        dir_contents = "Gagal membaca direktori."

                    history_context = "\\n".join(chat_history.get(message.chat.id, []))
                    prompt = f'Peranmu Zaki-Bot, asisten gaul pada ZDT Music Toolkit Telegram Bot. Info: Lokasi file di "{abs_path}". Isi file: {dir_contents}. ATURAN SUPER PENTING: JIKA DAN HANYA JIKA user SECARA EKSPLISIT menyuruh mengeksekusi suatu aksi, WAJIB sertakan tag berikut di jawabanmu:\n1) Perintah DOWNLOAD AUDIO/LAGU: [AUTO_ACTION: gas download audio ytsearch1:judul_lagu_yang_dicari]\n2) Perintah DOWNLOAD VIDEO: [AUTO_ACTION: gas download video ytsearch1:judul_video_yang_dicari]\n3) Perintah CARI/SEARCH lagu/video biasa di YouTube: [AUTO_ACTION: cari youtube judul_yang_dicari]\n4) Perintah CARI/SEARCH PLAYLIST/ALBUM di YouTube: [AUTO_ACTION: cari playlist judul_yang_dicari]\n5) Perintah pisah vokal: [AUTO_ACTION: hapus vokal]\n6) Perintah kompres media: [AUTO_ACTION: kompres media]\n7) Perintah cari lirik: [AUTO_ACTION: sync lirik]\n8) Perintah rapikan nama file: [AUTO_ACTION: bersih nama]\n9) Perintah buat playlist: [AUTO_ACTION: bikin playlist]\n10) Perintah hapus semua file: [AUTO_ACTION: hapus semua]\n\nJIKA user hanya tanya-tanya, curhat, minta penjelasan, JANGAN GUNAKAN TAG AUTO_ACTION SAMA SEKALI! Jawab saja seperti biasa.\n\nRiwayat Chat Terbaru:\n{history_context}'

                    def process_reply(reply_text):
                        if "[AUTO_ACTION:" in reply_text:
                            import re
                            match = re.search(r"\[AUTO_ACTION:\s*(.+?)\]", reply_text)
                            if match:
                                action = match.group(1).strip()
                                
                                def run_bg_task(cmd_args, success_msg):
                                    import threading
                                    import subprocess
                                    def _task():
                                        try:
                                            res = subprocess.run([zdt_bin] + cmd_args, capture_output=True, text=True)
                                            # get last 5 lines for context
                                            log_context = "\n".join([line for line in res.stdout.split("\n") if line.strip()][-5:])
                                            if res.returncode == 0:
                                                bot.reply_to(message, f"✅ {success_msg}\n\n📄 Log:\n`{log_context}`", parse_mode="Markdown")
                                            else:
                                                err_log = "\n".join([line for line in res.stderr.split("\n") if line.strip()][-5:])
                                                bot.reply_to(message, f"❌ Terjadi kesalahan.\n\n📄 Error:\n`{err_log}`", parse_mode="Markdown")
                                        except Exception as e:
                                            bot.reply_to(message, f"❌ System Error: {e}")
                                    threading.Thread(target=_task).start()

                                if action.startswith("gas download audio"):
                                    url = action.replace("gas download audio", "").strip()
                                    bot.reply_to(message, f"⏳ *Sedang Mendownload Audio...*\n📍 `Server` memproses link.", parse_mode="Markdown")
                                    run_bg_task(["--download-audio", url], "Audio berhasil di-download!")
                                elif action.startswith("gas download video"):
                                    url = action.replace("gas download video", "").strip()
                                    bot.reply_to(message, f"⏳ *Sedang Mendownload Video...*\n📍 `Server` memproses link.", parse_mode="Markdown")
                                    run_bg_task(["--download-video", url], "Video berhasil di-download!")
                                elif action.startswith("cari youtube"):
                                    query = action.replace("cari youtube", "").strip()
                                    bot.reply_to(message, f"🔍 *Mencari di YouTube...*\nKata kunci: `{query}`", parse_mode="Markdown")
                                    
                                    def _search_task():
                                        try:
                                            res = subprocess.run(["yt-dlp", f"ytsearch5:{query}", "--print", "%(title)s\n%(webpage_url)s\n"], capture_output=True, text=True)
                                            if res.returncode == 0 and res.stdout.strip():
                                                import telebot
                                                bot.reply_to(message, f"🎯 *Hasil Pencarian:*\n\n{res.stdout.strip()}\n\n_Balas dengan link atau suruh saya download salah satunya!_", parse_mode="Markdown", link_preview_options=telebot.types.LinkPreviewOptions(is_disabled=True))
                                            else:
                                                bot.reply_to(message, "❌ Pencarian tidak menemukan hasil.")
                                        except Exception as e:
                                            bot.reply_to(message, f"❌ Error pencarian: {e}")
                                    threading.Thread(target=_search_task).start()
                                elif action.startswith("cari playlist"):
                                    query = action.replace("cari playlist", "").strip()
                                    import urllib.parse
                                    bot.reply_to(message, f"🔍 *Mencari Playlist di YouTube...*\nKata kunci: `{query}`", parse_mode="Markdown")
                                    
                                    def _search_playlist_task():
                                        try:
                                            # &sp=EgIQAw%253D%253D is YouTube's filter for Playlists
                                            search_url = f"https://www.youtube.com/results?search_query={urllib.parse.quote(query)}&sp=EgIQAw%253D%253D"
                                            res = subprocess.run(["yt-dlp", search_url, "--flat-playlist", "--print", "%(title)s\n%(webpage_url)s\n", "--playlist-end", "5"], capture_output=True, text=True)
                                            if res.returncode == 0 and res.stdout.strip():
                                                import telebot
                                                bot.reply_to(message, f"🎯 *Hasil Pencarian Playlist:*\n\n{res.stdout.strip()}\n\n_Balas dengan link playlistnya untuk mendownload semua lagu di dalamnya!_", parse_mode="Markdown", link_preview_options=telebot.types.LinkPreviewOptions(is_disabled=True))
                                            else:
                                                bot.reply_to(message, "❌ Pencarian playlist tidak menemukan hasil.")
                                        except Exception as e:
                                            bot.reply_to(message, f"❌ Error pencarian playlist: {e}")
                                    threading.Thread(target=_search_playlist_task).start()
                                elif action == "hapus vokal":
                                    bot.reply_to(message, "⏳ Memisahkan vokal di background...")
                                    run_bg_task(["--extract-vocal-all"], "Vokal berhasil dipisah!")
                                elif action == "kompres media":
                                    bot.reply_to(message, "⏳ Mengkompres media di background...")
                                    run_bg_task(["--kompres-media-all"], "Media berhasil dikompres!")
                                elif action == "sync lirik":
                                    bot.reply_to(message, "⏳ Menyinkronkan lirik di background...")
                                    run_bg_task(["--sync-lirik-all"], "Lirik berhasil disinkronisasi!")
                                elif action == "bersih nama":
                                    bot.reply_to(message, "⏳ Merapikan nama file di background...")
                                    run_bg_task(["--bersih-nama-all"], "Nama file berhasil dirapikan!")
                                elif action == "bikin playlist":
                                    bot.reply_to(message, "⏳ Membuat playlist di background...")
                                    run_bg_task(["--bikin-playlist-all"], "Playlist berhasil dibuat!")
                                elif action == "hapus semua":
                                    # Konfirmasi keamanan sebelum hapus
                                    markup = InlineKeyboardMarkup()
                                    markup.row_width = 2
                                    markup.add(
                                        InlineKeyboardButton("⚠️ YA, HAPUS SEMUA", callback_data=f"CONFIRM_DELETE:{abs_path}"),
                                        InlineKeyboardButton("❌ BATAL", callback_data="CANCEL_DELETE")
                                    )
                                    bot.reply_to(message, f"⚠️ *PERINGATAN KEAMANAN!*\n\nAnda akan menghapus SEMUA file di:\n`{abs_path}`\n\nTindakan ini TIDAK BISA dibatalkan!\n\nKlik tombol di bawah untuk konfirmasi:", parse_mode="Markdown", reply_markup=markup)
                                else:
                                    bot.reply_to(message, f"❌ Aksi {action} belum didukung di Telegram.")
                                
                                clean_reply = re.sub(r"\[AUTO_ACTION:.*?\]", "", reply_text).strip()
                                if clean_reply:
                                    bot.reply_to(message, clean_reply)
                                return
                        bot.reply_to(message, reply_text)
                    
                    if gemini_key.startswith("sk-or-"):
                        url = "https://openrouter.ai/api/v1/chat/completions"
                        headers = {"Authorization": f"Bearer {gemini_key}", "Content-Type": "application/json"}
                        messages = [{"role": "system", "content": prompt}, {"role": "user", "content": text}]
                        
                        fallback_arrays = [
                            ["meta-llama/llama-3.3-70b-instruct:free", "qwen/qwen3-next-80b-a3b-instruct:free", "google/gemma-4-31b-it:free"],
                            ["nousresearch/hermes-3-llama-3.1-405b:free", "meta-llama/llama-3.2-3b-instruct:free", "openai/gpt-oss-120b:free"],
                            ["liquid/lfm-2.5-1.2b-instruct:free", "openrouter/free"]
                        ]
                        reply_text = ""
                        import urllib.error
                        for models in fallback_arrays:
                            payload = {"models": models, "messages": messages, "max_tokens": 400}
                            data = json.dumps(payload).encode("utf-8")
                            req = urllib.request.Request(url, data=data, headers=headers)
                            try:
                                with urllib.request.urlopen(req, timeout=20) as response:
                                    res = json.loads(response.read().decode())
                                    if "error" in res:
                                        reply_text = f"API Error: {res['error'].get('message', 'Unknown')}"
                                    else:
                                        content = res.get("choices", [{}])[0].get("message", {}).get("content")
                                        reply_text = f"API Error (Kosong): {json.dumps(res)}" if content is None else content.strip().replace("\n", " ")
                                    break
                            except urllib.error.HTTPError as e:
                                err_msg = e.read().decode()
                                reply_text = f'Aduh otak AI gua lagi pusing bro wkwk. Error: {err_msg}'
                                continue
                            except Exception as e:
                                reply_text = f'Aduh otak AI gua lagi pusing bro wkwk. Error: {str(e)}'
                                continue
                        process_reply(reply_text)
                        return
                    else:
                        url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={gemini_key}"
                        headers = {"Content-Type": "application/json"}
                        payload = {"system_instruction": {"parts": [{"text": prompt}]}, "contents": [{"role": "user", "parts": [{"text": text}]}], "generationConfig": {"maxOutputTokens": 400}}
                        data = json.dumps(payload).encode("utf-8")
                        req = urllib.request.Request(url, data=data, headers=headers)
                        with urllib.request.urlopen(req, timeout=20) as response:
                            res = json.loads(response.read().decode())
                        if "error" in res:
                            reply_text = f"API Error: {res['error'].get('message', 'Unknown')}"
                        else:
                            content = res.get("candidates", [{}])[0].get("content", {}).get("parts", [{}])[0].get("text")
                            reply_text = f"API Error (Kosong): {json.dumps(res)}" if content is None else content.strip().replace("\n", " ")
                        process_reply(reply_text)
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
except Exception as e:
    pass


@bot.callback_query_handler(func=lambda call: call.data.startswith('cmd_'))
def callback_query(call):
    cmd = call.data
    action = ""
    bash_flag = ""
    
    if cmd == "cmd_kompres":
        action = "🗜️ Kompres Media"
        bash_flag = "--kompres-media-all"
    elif cmd == "cmd_vokal":
        action = "🎤 Ekstrak Vokal (Demucs AI)"
        bash_flag = "--extract-vocal-all"
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
            except Exception:
                pass
        
        bot.edit_message_text(f"✅ *Selesai!* {deleted} item berhasil dihapus dari:\n`{target_path}`", chat_id=call.message.chat.id, message_id=call.message.message_id, parse_mode="Markdown")
    except Exception as e:
        bot.edit_message_text(f"❌ Gagal menghapus: {e}", chat_id=call.message.chat.id, message_id=call.message.message_id)


@bot.callback_query_handler(func=lambda call: call.data == 'CANCEL_DELETE')
def cancel_delete_callback(call):
    """Handler untuk membatalkan hapus semua"""
    bot.edit_message_text("❌ Pembatalan hapus semua. Tidak ada file yang dihapus.", chat_id=call.message.chat.id, message_id=call.message.message_id)
    bot.answer_callback_query(call.id, "Dibatalkan.")


print("Telegram Bot ZDT berjalan. Menunggu pesan masuk...")
bot.infinity_polling()
