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
                    prompt = "Peranmu Zaki-Bot, asisten gaul pada ZDT Music Toolkit Telegram Bot. Jawab santai max 3 kalimat."
                    
                    if gemini_key.startswith("sk-or-"):
                        url = "https://openrouter.ai/api/v1/chat/completions"
                        headers = {"Authorization": f"Bearer {gemini_key}", "Content-Type": "application/json"}
                        payload = {"model": "google/gemma-2-9b-it:free", "messages": [{"role": "system", "content": prompt}, {"role": "user", "content": text}], "max_tokens": 100}
                    else:
                        url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={gemini_key}"
                        headers = {"Content-Type": "application/json"}
                        payload = {"system_instruction": {"parts": [{"text": prompt}]}, "contents": [{"role": "user", "parts": [{"text": text}]}], "generationConfig": {"maxOutputTokens": 100}}
                    
                    data = json.dumps(payload).encode("utf-8")
                    req = urllib.request.Request(url, data=data, headers=headers)
                    with urllib.request.urlopen(req, timeout=10) as response:
                        res = json.loads(response.read().decode())
                        if gemini_key.startswith("sk-or-"):
                            content = res.get("choices", [{}])[0].get("message", {}).get("content", "Error bro.")
                        else:
                            content = res.get("candidates", [{}])[0].get("content", {}).get("parts", [{}])[0].get("text", "Error bro.")
                        bot.reply_to(message, content.strip())
                        return
            except Exception as e:
                bot.reply_to(message, f"Aduh otak AI gua lagi pusing bro wkwk. Error: {str(e)}")
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
