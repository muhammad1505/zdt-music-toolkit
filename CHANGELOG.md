# ZDT Music Toolkit - Changelog

Semua perubahan yang mencolok pada project ini akan didokumentasikan di file ini.

## v4.1.83 (True OR→Gemini Fallback)
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



## v4.1.79 (Zaki AI UX Redesign — Conversational Flow)
- **Refactor(AI)**: **Alur Percakapan Berkelanjutan** - Zaki AI tidak lagi `clear` layar & menggambar ulang menu tiap giliran. Header hanya tampil sekali; percakapan kini mengalir turn-demi-turn layaknya chat sungguhan (bukan menu).
- **Refactor(AI)**: **Hapus `_pause` Pemutus Alur** - Menghilangkan prompt "Tekan tombol apa aja untuk kembali ke menu" setelah tiap jawaban/aksi/greeting/error. User bisa langsung lanjut mengetik.
- **Fix(AI)**: **Pertanyaan Kapabilitas ke AI** - Menghapus intercept regex (`bisa apa aja`, `kemampuan`, dst.) yang membajak pertanyaan natural ke menu statis. Kini AI yang menjawab kontekstual (daftar fitur tetap akurat via system prompt).

## v4.1.78 (Security & Hardening)
- **Fix(Security)**: **Pengaman `rm -rf`** - Menambahkan guard `${target:?}` pada `hapus_semua` (`daemon.sh`) untuk mencegah ekspansi tak terduga ke `/*` jika variabel target kosong (SC2115).
- **Fix(Security)**: **Temp File Aman** - Mengganti nama temp file yang dapat ditebak (`/tmp/...$$`) dengan `mktemp` acak pada AI assistant (`assistant.sh`) dan OTA updater (`daemon.sh`) untuk mencegah serangan symlink.
- **Fix(Web)**: **Pesan Login** - Menghapus pesan menyesatkan `Default: admin / admin` pada layar 401 karena kredensial default kini sudah ditolak; diganti petunjuk lokasi password yang di-generate otomatis.

## v4.1.69 (Latest Enterprise Update)
- **Feat(Core)**: **Smart Duplicate Detector** - Mencegah unduhan ganda lewat pengecekan SQLite `check_duplicate`.
- **Feat(Core)**: **Auto-Retry & Resume Queue** - Menangani kegagalan unduhan dengan sistem rehat dan coba ulang cerdas (Max 3 retries).
- **Feat(Core)**: **Global Archive** - File arsip `yt-dlp` diletakkan di `$TARGET_DIR` agar tersinkronisasi.
- **Feat(Web)**: **HTTP Basic Auth** - Mengamankan Dashboard dengan layar Login (Default: `admin:admin` atau via `ZDT_WEB_USER` & `ZDT_WEB_PASS`).
- **Feat(Web)**: **OLED Ultra Dark Mode** - Desain UI yang jauh lebih premium dengan efek *neon glow* dan latar hitam legam.
- **Feat(Web)**: **Statistik Tab** - Panel Riwayat Unduhan & Metrik Ukuran terintegrasi penuh ke SQLite.
- **Feat(DB)**: **Unit Test & DevEx** - Tabel `downloads`, command `add_download`, `get_stats` & standardisasi dependensi `requirements.txt`.
- **Feat(AI)**: Zaki-Bot AI kini lebih pintar menjabarkan fitur berkat pembaruan prompt (bypassing batasan kalimat singkat saat diminta informasi bantuan).
- **Feat(Core)**: Mekanisme **Graceful Fallback** untuk AI. Jika Gemini gagal/limit, Zaki-Bot otomatis beralih menggunakan OpenRouter API.
- **Feat(Web)**: Global Error Handler (`@app.errorhandler`) di Flask untuk menangkap Error 500 menjadi JSON agar Web UI (Dashboard) tidak menampilkan layar putih.
- **Feat(Telegram)**: UI Telegram lebih interaktif dengan *Inline Keyboard* alih-alih eksekusi buta ke seluruh file. Update progres *real-time* lewat editan pesan yang efisien.
- **Feat(Web)**: Sistem Web Dashboard menggunakan *Live Progress Bar* Regex Parser berbasis Javascript & HTML Toast Notifications.
- **Feat(DB)**: **ZDT Database (SQLite)**. Memperkenalkan file persisten untuk riwayat chat Telegram dan memori bot, membuka jalan untuk statistik masa depan.
- **Fix**: Modul *testing* dirombak (MockFlask handler) untuk menghindari *error* import saat *smoke test*.
- **Fix**: Keamanan — Evaluasi kode `eval "find ..."` yang rentan eksploitasi telah dirombak penuh ke mode *Array bash expansion* (`media.sh`).

---

### v3.8.0
- **Feat**: Modular Refactor! `zdt.sh` dipecah dari monolitik 4.786 baris menjadi arsitektur modular dengan 8 modul di `zdt-modules/` (core, helpers, download, media, playlist, daemon, setup, assistant)
- **Feat**: Pytest Unit Tests untuk komponen Python (`zdt-web.py`, `zdt-telegram.py`, `zdt-watch.py`)
- **Fix**: `_find_media_files()` sekarang menggunakan array bash yang benar untuk argumen `find` (perbaiki bug ekstensi filter)
- **Enhance**: Thin loader `zdt.sh` — hanya 143 baris, lebih cepat di-load
- **Enhance**: OTA updater sekarang juga mendownload modul dari GitHub
- **Chore**: Smoke test ditingkatkan untuk mendeteksi duplikasi fungsi antar modul

### v3.7.1
- **Fix**: Hapus positional argument `$ROOT_DIR` dari pemanggilan `zdt-web.py` yang menyebabkan error `unrecognized arguments`
- Bump versi untuk deteksi auto-updater

### v3.7.0
- **Feat**: Smoke test (`test_smoke.sh`) untuk validasi syntax, duplicate functions, dan integrity checks
- **Feat**: Konfirmasi hapus file di Telegram bot dengan inline keyboard (mencegah hapus tidak sengaja)
- **Feat**: Keamanan token Telegram (`chmod 600`)
- **Feat**: Atomic config write dengan file locking (`flock`)
- **Feat**: DRY refactor helper `_find_media_files()` untuk scan media files
- **Feat**: `--bind` dan `--port` argument untuk Web Dashboard
- **Feat**: `WEB_BIND` config variable
- **Fix**: Playlist M3U newline escape di Web Dashboard
- **Fix**: Simplifikasi batch worker pool (audio & video compression)
- **Fix**: Perbaikan exit code handling di video re-encode
