#!/usr/bin/env python3
import sys
import os
import time
import subprocess
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

# Monkey-patch send_message to log all outgoing responses (including reply_to)
original_send_message = bot.send_message
def logging_send_message(chat_id, text, **kwargs):
    logging.info(f"Bot mengirim pesan ke {chat_id}: {text}")
    return original_send_message(chat_id, text, **kwargs)
bot.send_message = logging_send_message

def listener(messages):
    for m in messages:
        if m.content_type == 'text':
            user = m.from_user.first_name if m.from_user else "Unknown"
            logging.info(f"Pesan masuk dari {user} (ID: {m.chat.id}): {m.text}")

bot.set_update_listener(listener)

zdt_bin = "/home/zaki/.local/bin/zdt"
if not os.path.exists(zdt_bin):
    zdt_bin = "/home/zaki/zdt.sh"

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

                    prompt = f'Peranmu Zaki-Bot, asisten gaul pada ZDT Music Toolkit Telegram Bot. Jawab santai max 3 kalimat. Info penting: Lokasi penyimpanan saat ini ada di "{abs_path}" dengan isi file: {dir_contents}.'
                    
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
                            payload = {"models": models, "messages": messages, "max_tokens": 100}
                            data = json.dumps(payload).encode("utf-8")
                            req = urllib.request.Request(url, data=data, headers=headers)
                            try:
                                with urllib.request.urlopen(req, timeout=10) as response:
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
                                if e.code == 429:
                                    continue
                                break
                            except Exception as e:
                                reply_text = f'Aduh otak AI gua lagi pusing bro wkwk. Error: {str(e)}'
                                break
                        bot.reply_to(message, reply_text)
                        return
                    else:
                        url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={gemini_key}"
                        headers = {"Content-Type": "application/json"}
                        payload = {"system_instruction": {"parts": [{"text": prompt}]}, "contents": [{"role": "user", "parts": [{"text": text}]}], "generationConfig": {"maxOutputTokens": 100}}
                        data = json.dumps(payload).encode("utf-8")
                        req = urllib.request.Request(url, data=data, headers=headers)
                        with urllib.request.urlopen(req, timeout=10) as response:
                            res = json.loads(response.read().decode())
                            if "error" in res:
                                reply_text = f"API Error: {res['error'].get('message', 'Unknown')}"
                            else:
                                content = res.get("candidates", [{}])[0].get("content", {}).get("parts", [{}])[0].get("text")
                                reply_text = f"API Error (Kosong): {json.dumps(res)}" if content is None else content.strip().replace("\n", " ")
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

print("Telegram Bot ZDT berjalan. Menunggu pesan masuk...")
bot.infinity_polling()
