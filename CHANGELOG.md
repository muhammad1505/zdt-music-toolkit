# ZDT Music Toolkit - Changelog

Semua perubahan yang mencolok pada project ini akan didokumentasikan di file ini.

## v4.4.0 (Web UI Evolution — Dark/Light Mode, SSE Streaming, System Logs, Pagination)
- **Feat(Web)**: **Dark/Light Mode Toggle** — Settings panel toggle + mobile More sheet. localStorage persistence + `prefers-color-scheme` auto-detection. Chart.js dynamic color update on theme switch.
- **Feat(Web)**: **SSE Real-Time Log Streaming** — Replace polling 3s dengan EventSource. New `/api/logs/stream` endpoint (1s check interval, content change detection, `json.dumps()` proper escaping). Auto-reconnect + fallback polling 10s.
- **Feat(Web)**: **Auto-Update Notification** — New `/api/update-check` endpoint cek GitHub `releases/latest`. Banner kuning "Update Tersedia!" + toast notification. Cek 5 detik setelah load, lalu setiap 30 menit.
- **Feat(Web)**: **Search/Filter File List** — Search input di Metadata Editor & Tools panel dengan client-side real-time filter via `_allFilesCache`.
- **Feat(Web)**: **System Logs Viewer** — New panel "Logs" di sidebar. Backend `/api/system/logs` dengan journalctl → syslog fallback. Table dengan sticky header, line count selector, error/warning level coloring.
- **Feat(Web)**: **Pagination Riwayat Unduhan** — DB `get_stats` support limit/offset. Pagination UI: prev/next + page number buttons (max 7 + ellipsis).
- **Feat(Core)**: **GitHub Actions Auto-Release** — New `.github/workflows/release.yml`. Trigger `v*` tag push, extract changelog entry, create GitHub Release via `softprops/action-gh-release`.
- **Feat(Core)**: **Spotify Sync Duplicate Detector** — `playlist.sh` cek DB sebelum `spotdl download`. Auto-mode skip silent, interactive tanya konfirmasi `y/N`. Record playlist URL ke DB untuk tracking antar sesi.
- **Fix(Web)**: **Version Fallback** — `zdt-web.py` APP_VERSION dari `4.1.91` → `4.4.0`.
- **Test**: +3 unit test untuk shared functions (`_resolve_scan_dir` 5 kasus, cache vars, function signatures). Total 47 tests.

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



## v4.3.0 (Current — Download Module Refactoring & Duplicate Detector)
- **Feat(Spotify)**: **Duplicate Detector** — `download-spotify.sh` sekarang punya duplicate detector seperti YouTube. Cek DB sebelum download, skip link yang sudah ada (auto-mode silent, interactive tanya konfirmasi).
- **Refactor(Download)**: **Shared Functions Extraction** — Ekstrak 4 fungsi shared ke `helpers.sh` (`_ask_folder_mode`, `_ask_format_audio`, `_post_download_audio`, `_resolve_scan_dir`). Eliminasi ~70 baris kode duplikat antara `download-spotify.sh` dan `download-youtube.sh`.
- **Feat(OTA)**: **AI Prompt Included** — OTA updater (`daemon.sh`) dan installer (`setup.sh`, `install.sh`, `Makefile`) sekarang mendownload/menyalin `zdt-ai-prompt.txt` ke direktori instalasi.

## v4.2.9 (Bug Audit & AI Prompt Unification)
- **Feat(AI)**: **Shared AI Prompt System** — Created `zdt-ai-prompt.txt` sebagai single source of truth untuk Zaki-Bot (CLI + Telegram). Kedua sistem membaca file yang sama, masing-masing menambahkan format-specific instructions (JSON untuk CLI, `AUTO_ACTION` untuk Telegram).
- **Fix(Core)**: **NET_PID Double Assignment** — Hapus `NET_PID=$!` duplikat di luar blok if-else di `zdt.sh`. PID network monitor sebelumnya di-overwrite oleh assignment kedua.
- **Fix(Core)**: **Version Comment** — Update header `zdt.sh` dari "Version: 4.1.97" menjadi "4.2.9".
- **Fix(Spotify)**: **Missing DB Recording** — `download-spotify.sh` sekarang memanggil `_record_downloads()` agar download Spotify tercatat di database statistik.
- **Fix(Media)**: **AUTO_HAPUS_VOKAL_MODE** — `hapus_vokal()` sekarang membaca dan menghormati variable ini, skip menu interaktif di auto-mode.
- **Fix(Playlist)**: **AUTO_MODE Support** — `sync_spotify_playlist()` skip `pilih_folder_target()` jika `AUTO_MODE=1`.
- **Fix(Download)**: **Indentation Fix** — Rapikan struktur if-else di `download-youtube.sh` agar playlist detection code berada di dalam blok `then` dengan indentasi benar.
- **Fix(Config)**: **File Permission** — `_config_set()` sekarang `chmod 600` setelah menulis config file.
- **Fix(DB)**: **Unbounded Growth** — Tabel `downloads` di SQLite dibatasi 1000 record terakhir, mencegah file DB membesar tanpa batas.

## v4.2.8 (Critical Bug Fixes — Batch 2)
- **Fix(Core)**: **Zombie Network Monitor** — Cleanup NET_PID/NET_TMP sebelum `exit 0` di mode CLI. Ping interval 3s→30s. Validasi `mktemp` dengan fallback file creation (bukan string literal).
- **Fix(Core)**: **Race Condition Config** — `_config_set`/`_config_unset` menggunakan `mktemp` untuk atomic write. Lock scope diperbaiki agar read-modify-write berada dalam satu lock.
- **Fix(Core)**: **Ctrl+C Restart** — `_trap_ctrlc` sekarang `return 0` bukan `exec bash "$SCRIPT_PATH"`. Mencegah restart penuh aplikasi.
- **Fix(Python)**: **Bare Excepts** — `except:` → `except Exception:` di `zdt-telegram.py`. Mencegah KeyboardInterrupt/SystemExit tertelan.
- **Fix(Log)**: **Multi-Level Rotation** — Log rotation sekarang menyimpan 5 backup (.1.gz – .5.gz) dengan kompresi gzip.
- **Fix(Daemon)**: **Stale Module Cleanup** — Hapus reference `download.sh` lama di OTA updater.

## v4.2.7 (AI Model Updates)
- **Fix(AI)**: **OpenRouter Model Refresh** — Update daftar model free-tier OpenRouter ke model yang masih berfungsi.
- **Fix(AI)**: **CLI Prompt Shortened** — System prompt Zaki AI di CLI dipotong agar lebih akurat pada model gratis.
- **Fix(AI)**: **Telegram AI Responses** — Perbaikan format respon AI di Telegram bot.

## v4.2.5 – v4.2.6 (Version Rollover Fix)
- **Fix**: Patch rollover versi di `.99` bukan `.9` (e.g. 4.1.99 → 4.2.0). Memperbaiki bug dimana 4.1.9 dianggap sebagai minor increment dari 4.1.89.
- **Fix**: Koreksi versi retroaktif: 4.1.104 → 4.2.5, 4.1.105 → 4.2.5.
- **Fix**: Inisialisasi `AUTO_MODE`/`AUTO_FORMAT_SPEC`/`AUTO_BITRATE` untuk mencegah `set -u` crash.

## v4.1.98 (Web Dashboard Stability)
- **Fix(Web)**: **Template Discovery** — `_find_templates_dir()` mencari di 5 lokasi instalasi berbeda. OTA update juga mendownload template dashboard.
- **Fix(Web)**: **CSRF Safety** — `requires_csrf` skip safe HTTP methods (GET/HEAD/OPTIONS). Perbaiki HTML `divBitrate` dan mock method attribute di test.
- **Fix(Web)**: **Timeout & Retry** — `csrfFetch` timeout 30 detik, auto-retry on 403, slow warning after 20s.
- **Fix(Web)**: **Rate Limit** — Rate limit dinaikkan 30→120 request/menit. Polling interval diperpanjang: log 3s, scheduler 10s.
- **Fix(Web)**: **Real Password** — Tampilkan password asli dari `config.env` di startup dashboard, bukan hardcoded "admin".
- **Fix(Daemon)**: **Unbound Variable** — Perbaiki `local _actual_user` tanpa inisialisasi yang menyebabkan error `set -u`.
- **Fix(CLI)**: **Web Mode Handler** — Tambah handler untuk `--web` di `main()` agar tidak langsung exit.
- **Fix(Download)**: **Playlist Auto-Detect** — `download_video` auto-detect playlist URL di auto mode.
- **Fix(Telegram)**: **Response Formatting** — Perbaiki newlines stripped, Markdown parse_mode, AI reasoning leakage.

## v4.1.91 – v4.1.97 (Incremental Fixes)
- **Fix(Web)**: **Duplicate Detector** — Skip di auto mode untuk mencegah prompt interaktif. Recursive file counting dan listing.
- **Fix(Web)**: **Delete All** — Recursive cleanup dengan empty directory handling. Auto-detect playlist di auto mode.
- **Fix(Web)**: **Template Copy** — Auto-copy dashboard template ke direktori yang benar jika tidak ditemukan.
- **Fix(Telegram)**: **AI Model Upgrade** — Upgrade ke OpenRouter model yang masih aktif. Tes Gemini-only ditambahkan.
- **Fix(Assistan)**: **JSON Injection** — Perbaiki payload JSON building pakai Python untuk mencegah injection dari special characters.
- **Fix(Assistan)**: **OpenRouter Fallback Key** — Perbaiki logika fallback key saat Gemini gagal.
- **Fix(Assistan)**: **Local Variable Scope** — Reset state variables tiap iterasi loop.
- **Fix(Batch)**: **Auto-Mode Noninteractive** — `AUTO_MODE` skip semua wizard interaktif di download-spotify dan download-youtube.
- **Fix(Batch)**: **Python Launcher** — `_run_python_script()` coba VENV python dulu baru global.
- **Fix(Batch)**: **Watch Leak** — LRU eviction (max 1000 entries) dan size-stability check di watch daemon.
- **Fix(Batch)**: **Kompres Scan** — Scan SEMUA format audio, tidak hanya ekstensi target (cross-conversion support).
- **Fix(Batch)**: **Metadata Check** — Benar-benar cek output "SUCCESS" sebelum melaporkan keberhasilan.
- **Fix(Batch)**: **Playlist URL** — Prepend URL lengkap jika yt-dlp return video ID saja.
- **Feat(AI)**: **8 New AUTO_ACTION Handlers** — Tambah handler untuk `cari playlist`, `buka web`, `setup tools`, `update tools`, `start telegram`, `start watch`, `buka scheduler`, `ubah storage`.
- **Feat(AI)**: **Knowledge Base Upgrade** — Zaki AI sekarang punya pengetahuan komprehensif tentang semua fitur ZDT.
- **Feat(Web)**: **Scheduler UI** — Panel Auto-Sync Scheduler dengan daftar playlist, interval, dan kontrol stop/start.
- **Feat(Web)**: **Notifikasi Telegram** — Panel konfigurasi token & chat ID, test notification, auto-notify task completion.
- **Feat(Web)**: **System Daemon Status** — Live status untuk Watchdog & Telegram Bot (running/offline).
- **Feat(Web)**: **Auto-Start Daemons** — Opsi untuk auto-start watch daemon dan scheduler via systemd timer.
- **Test**: **CSRF Integration** — 54 test untuk CSRF token validation, expiry, dan bypass prevention.
- **Test**: **Conftest Refactor** — Extract shared mock setup, hapus 80% fixture duplication.
- **Test**: **Telegram AI Fallback** — OR→Gemini fallback test dengan URL-based routing mock.
- **Test**: **AUTO_ACTION Handlers** — 8 unit test untuk semua handler baru.

---

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
