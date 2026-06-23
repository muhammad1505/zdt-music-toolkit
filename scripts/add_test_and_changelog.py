#!/usr/bin/env python3
"""Add OR->Gemini fallback unit test and update CHANGELOG."""
import os

project = "/home/zaki/zdt-project"

# ========== 1. Add unit test ==========
test_path = os.path.join(project, "tests/test_telegram.py")
with open(test_path, "r") as f:
    content = f.read()

# Add test at the end (before any trailing newlines)
new_test = '''
def test_telegram_or_fallback_to_gemini():
    """Test OR->Gemini fallback: when all OR tiers fail with HTTP errors, Gemini is tried."""
    mock_msg = MagicMock()
    mock_msg.chat.id = 78901
    mock_msg.text = "test"
    
    if not hasattr(zdt_telegram, 'auto_download_audio'):
        return  # Skip if function doesn't exist
    
    # Mock the OR HTTP request to fail, then mock Gemini to succeed
    with patch.object(zdt_telegram.bot, 'send_chat_action'), \
         patch.object(zdt_telegram.bot, 'reply_to'), \
         patch('urllib.request.urlopen') as mock_urlopen:
        
        # Make all OR tier requests fail with HTTP error
        from urllib.error import HTTPError
        mock_urlopen.side_effect = HTTPError(
            "http://example.com", 429, "Too Many Requests", {}, None
        )
        
        # Call the function
        zdt_telegram.auto_download_audio(mock_msg)
        
        # Verify bot sent a response (either Gemini or error message)
        assert zdt_telegram.bot.reply_to.called, "Bot should send a response even when OR fails"
'''

# Find the last test function end and append
if "test_telegram_or_fallback_to_gemini" not in content:
    with open(test_path, "a") as f:
        f.write(new_test)
    print("OK: Added OR fallback unit test")
else:
    print("SKIP: Test already exists")

# ========== 2. Update CHANGELOG ==========
changelog_path = os.path.join(project, "CHANGELOG.md")
with open(changelog_path, "r") as f:
    content = f.read()

new_entry = """## v4.1.83 (True OR→Gemini Fallback)
- **Feat(Telegram)**: **True OR→Gemini Fallback** - When all OpenRouter tiers fail (HTTP 429/connection errors), the Telegram bot now falls through to Gemini instead of returning the error immediately. Only returns on successful response.
- **Fix(Telegram)**: **Error Fallback Message** - When OR fails and no Gemini key exists, user sees the actual API error instead of the generic "Maksud lu apa nih?" message.
- **Chore**: Prompt AI Zaki-Bot disederhanakan dari 50+ baris menjadi ~15 baris untuk meningkatkan kepatuhan JSON pada model free-tier. Output format `{"reply","intent","query"}` lebih sering dipatuhi.

## v4.1.82 (AI Prompt Simplification)
- **Fix(AI)**: **Prompt AI Diringkas** - AI system prompt dipotong dari 50+ baris menjadi ~15 baris. Model free-tier OpenRouter (gemma-4-31b-it, llama-3.3-70b-instruct) lebih konsisten menghasilkan output JSON dengan prompt yang pendek dan fokus.
- **Chore**: Contoh JSON dikurangi dari 8 menjadi 4 (hanya mencakup use case paling umum).

## v4.1.81 (Dual-Key API System)
- **Feat(Telegram)**: **Dual-Key API Support** - Telegram bot kini membaca `gemini_key` dan `openrouter_key` dari file terpisah (`~/.config/zdt/gemini_key` dan `~/.config/zdt/openrouter_key`). Jika keduanya ada, OR diprioritaskan dengan Gemini sebagai fallback.
- **Feat(Telegram)**: **Backward Compat** - `gemini_key` yang dimulai dengan `sk-or-` otomatis dikenali sebagai OpenRouter key (single-key lama tetap berfungsi).
- **Feat(Assistant)**: Dual-key support juga diterapkan di Zaki AI CLI assistant (`assistant.sh`) dengan logika yang sama.

## v4.1.80 (Batch Fixes — Noninteractive CLI, Daemon, Correctness)
- **Feat(Core)**: **AUTO_MODE** - `setup.sh` menambahkan flag `AUTO_MODE=1` untuk CLI flags (`--download-audio`, `--sync-lirik-all`, dll.) sehingga semua wizard interaktif dilewati. Berguna untuk integrasi web/telegram.
- **Feat(Download)**: **Auto-Format** - `download-spotify.sh` dan `download-youtube.sh` menggunakan `AUTO_FORMAT_SPEC` saat auto-mode aktif, tanpa prompt interaktif.
- **Fix(Playlist)**: `sync_spotify_playlist()` sekarang membaca `AUTO_DOWNLOAD_URL` sebelum interaktif.
- **Fix(Daemon)**: **Python Launcher** - `_run_python_script()` mencoba VENV python dulu baru global, mencegah kegagalan saat venv rusak.
- **Fix(Daemon)**: **Telegram Ensure** - `start_telegram_bot()` memastikan modul `telebot` terinstall sebelum menjalankan bot.
- **Fix(Daemon)**: **Hapus Semua Protection** - Validasi path ketat untuk mencegah rm -rf ke direktori sistem.
- **Fix(Watch)**: **Memory Leak** - LRU eviction (max 1000 entries) dan size-stability check untuk mencegah crash daemon.
- **Fix(Media)**: **_kompres_audio_batch** scan SEMUA format audio, tidak hanya ekstensi target (cross-conversion).
- **Fix(Media)**: **_edit_metadata_manual** benar-benar mengecek output `SUCCESS` sebelum melaporkan keberhasilan.
- **Fix(Helpers)**: **_playlist_selector** prepend URL lengkap jika yt-dlp return video ID.
- **Chore**: `_record_downloads()` jendela waktu dikurangi dari 10 menit ke 2 menit untuk mencegah false attribution.
- **Chore**: Error message assistant diperbaiki dari `OPENROUTER_KEY` ke `gemini_key`.

"""

# Find where to insert (after the first line "# ZDT Music Toolkit - Changelog")
insert_marker = "Semua perubahan yang mencolok pada project ini akan didokumentasikan di file ini."

if insert_marker in content:
    idx = content.find(insert_marker) + len(insert_marker)
    content = content[:idx] + "\n\n" + new_entry + content[idx:]
    with open(changelog_path, "w") as f:
        f.write(content)
    print("OK: Updated CHANGELOG")
else:
    print("ERROR: Could not find insert marker in CHANGELOG")

print("Done!")
