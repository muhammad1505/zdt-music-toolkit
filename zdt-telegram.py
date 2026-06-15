#!/usr/bin/env python3
import sys
import os
import time
import subprocess
try:
    import telebot
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

@bot.message_handler(commands=['start', 'help'])
def send_welcome(message):
    msg = (
        "🤖 **ZDT Remote Downloader Aktif!**\n\n"
        "Kirimkan link YouTube / Spotify / SoundCloud ke chat ini, "
        "dan saya akan mendownload audionya langsung ke komputer Anda!\n\n"
        "_Untuk mendownload video, ketik /video diikuti link._"
    )
    bot.reply_to(message, msg, parse_mode="Markdown")

@bot.message_handler(commands=['video'])
def download_video(message):
    text = message.text.replace('/video', '').strip()
    if "http" not in text:
        bot.reply_to(message, "Link tidak valid!")
        return
        
    url = [word for word in text.split() if "http" in word][0]
    bot.reply_to(message, f"Sedang mendownload Video dari {url} di komputer server...")
    
    try:
        with open(os.devnull, 'w') as devnull:
            subprocess.Popen([zdt_bin, "--download-video", url], stdout=devnull, stderr=devnull, start_new_session=True)
    except Exception as e:
        bot.reply_to(message, f"Terjadi kesalahan: {str(e)}")

@bot.message_handler(func=lambda message: True)
def download_audio(message):
    text = message.text
    if "http" not in text:
        bot.reply_to(message, "Saya hanya mengerti link media. Coba kirimkan link YouTube atau Spotify!")
        return
        
    url = [word for word in text.split() if "http" in word][0]
    bot.reply_to(message, f"Menerima link! Sedang mendownload Audio dari {url} di komputer server...")
    
    try:
        with open(os.devnull, 'w') as devnull:
            subprocess.Popen([zdt_bin, "--download-audio", url], stdout=devnull, stderr=devnull, start_new_session=True)
    except Exception as e:
        bot.reply_to(message, f"Terjadi kesalahan: {str(e)}")

print("Telegram Bot ZDT berjalan. Menunggu pesan masuk...")
bot.infinity_polling()
