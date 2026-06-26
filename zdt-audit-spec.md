# ZDT Music Toolkit — Comprehensive Audit Spec
**Generated:** June 27, 2026
**Audience:** Developer (Original author)
**Scope:** Bugs, potential bugs, missing features, security issues, and architectural improvements

---

## 1. EXECUTIVE SUMMARY

ZDT (Zaki Downloader Tools) adalah toolkit modular Bash + Python untuk download, kompres, dan manage musik/video. Secara keseluruhan arsitektur sudah baik (modular, VENV isolation, Python companion components), tapi ada beberapa area kritis yang perlu perbaikan:

- **Critical:** Zombie background processes, race condition pada config writer, dan proses zombie network monitor
- **High:** Duplikasi kode besar antara download-spotify.sh dan download-youtube.sh, restart aplikasi penuh saat Ctrl+C, UI flicker di terminal rendah
- **Medium:** Bare excepts di Python, log rotation tidak ada, test coverage terbatas, documentasi inkonsisten
- **Low:** Minor UI/UX polish, platform discovery untuk users

---

## 2. BUGS (Confirmed)

### 2.1 Proses Zombie — Network Monitor (`zdt.sh` lines 96-100)

**Severity: CRITICAL**
**File:** `zdt.sh`

**Problem:** Background process network monitor menggunakan loop `while true` dengan `ping` setiap 3 detik. Proses ini dijalankan dengan `&` dan `disown`, tapi:
- Jika user exit melalui menu [0] (shutdown), kill dilakukan: `kill -9 "$NET_PID"` — OK.
- Jika user exit melalui Ctrl+C di sub-menu (bukan di main loop), `_trap_ctrlc` dipanggil — OK, kill dilakukan.
- **Jika user panggil `--download-audio` dari CLI (AUTO_MODE)**, `main()` langsung `exit 0` tanpa sempat kill NET_PID/NET_TMP. Proses `ping` jadi zombie.
- Jika user exit melalui `_trap_exit` (SIGTERM, shell mati mendadak), kill dilakukan — OK.

**Root Cause:** Main function memiliki `exit 0` setelah case dispatch (line 80) yang TIDAK melewati cleanup `_trap_exit` karena `exit` tidak trigger `EXIT` trap di beberapa shell.

**Reproduction:**
```bash
zdt --download-audio https://youtube.com/watch?v=test
# Exit code 0
# Tapi background ping process masih jalan
ps aux | grep ping
```

**Fix:** Pindahkan cleanup ke trap EXIT yang lebih awal, atau gunakan `trap '' EXIT` sebelum exit.

### 2.2 `_trap_ctrlc` Restart Aplikasi Penuh (`core.sh` lines 110-122)

**Severity: HIGH**
**File:** `zdt-modules/core.sh`

**Problem:** Trap Ctrl+C di sub-process (misal saat download) memanggil:
```bash
exec bash "$SCRIPT_PATH" "${ORIGINAL_ARGS[@]}"
```
Ini melakukan rekursi penuh — restart seluruh aplikasi. Efek:
- Jika user pencet Ctrl+C saat konfirmasi "Lanjutkan kompres? (y/n)", aplikasi restart dari awal (clear screen, main menu).
- State variables seperti `TARGET_DIR`, `STORAGE_DIR` hilang.
- Lebih boros resource daripada kembali ke menu.

**Expected behavior:** Ctrl+C seharusnya:
1. Kill proses anak (yt-dlp, ffmpeg, dll)
2. Bersihkan temp files
3. Kembali ke menu utama (bukan restart penuh)

**Fix:** Ganti `exec bash "$SCRIPT_PATH"...` dengan `return 0` (kembali ke main loop) + reset state.

### 2.3 Race Condition di Config Writer (`core.sh`)

**Severity: MEDIUM**
**File:** `zdt-modules/core.sh` — `_config_set()`

**Problem:** Operasi read-modify-write:
```bash
# Lock acquired (flock)
grep -v "^${key}=" "$config_file" > "$tmp_file"  # READ
echo "${key}=${value}" >> "$tmp_file"             # MODIFY
mv -- "$tmp_file" "$config_file"                 # WRITE (atomic)
```
Ada jendela antara:
1. `flock` lock diperoleh
2. `grep` membaca file lama
3. `mv` menulis file baru

Jika 2 proses ZDT berjalan dan menulis config bersamaan:
- Proses A: lock → read config → add key1 → write
- Proses B: lock → read config (belum lihat key1) → add key2 → write (key1 hilang!)

**Fix:** Baca file di dalam lock scope dan gunakan temporary file yang digenerate dengan `mktemp` untuk atomic write.

### 2.4 `AUTO_DOWNLOAD_URL` Reset Prematur (`download-youtube.sh`)

**Severity: MEDIUM**
**File:** `zdt-modules/download-youtube.sh`

**Problem:** Di `download_ytdlp()`:
```bash
if [ -n "$AUTO_DOWNLOAD_URL" ] || [ -n "$AUTO_MODE" ]; then
    links=("$AUTO_DOWNLOAD_URL")
    AUTO_DOWNLOAD_URL=""  # <-- Reset di sini
    # ... kode auto-detect playlist menggunakan $links ...
fi
# Kode auto-detect playlist ada DI LUAR blok if
# Tapi sudah me-refer $links
```

Setelah `AUTO_DOWNLOAD_URL` di-reset, ada kode:
```bash
pilih_playlist="n"
for l in "${links[@]}"; do
    if [[ "$l" == *"list="* ]]; then
        pilih_playlist="y"
        break
    fi
done
if [ -z "$links" ] || [ -z "${links[*]}" ]; then  # <-- crash jika $links belum di-set di AUTO_MODE
    echo "URL kosong!"
    return 0
fi
```

**Potential bug:** Jika `AUTO_DOWNLOAD_URL` kosong tapi `AUTO_MODE=1`, array `links` tetap kosong, lalu error "URL kosong!" muncul. Ini seharusnya dicegah di `_parse_args`.

### 2.5 `set -u` Safety Issue (`zdt.sh` line 96)

**Severity: LOW**
**File:** `zdt.sh`

**Problem:** Di dalam loop while true background process:
```bash
NET_TMP=$(mktemp ...)
( while true; do
    ...
    echo "1" > "$NET_TMP"
    ...
done ) &
```

Jika `mktemp` gagal (misal /tmp penuh), fallback ke `echo "/tmp/.zdt_net_$$"` — ini STRING, bukan file. Loop `while true` akan mencoba write ke string literal, yang bisa gagal silent.

**Fix:** Validasi NET_TMP setelah assignment; fallback yang benar harus create file.

---

## 3. POTENTIAL BUGS (Not Yet Confirmed)

### 3.1 Duplikasi Kode — Download Modules

**Severity: HIGH**
**File:** `zdt-modules/download-spotify.sh` & `zdt-modules/download-youtube.sh`

**Problem:** Kedua modul memiliki ~80% kode identik:
- Input link flow (sama persis)
- Manajemen folder output (identik)
- Format output selector (identik, hanya nama variabel berbeda)
- Archive system (identik)
- Post-process (auto clean, auto kompres — identik)

**Impact:** Jika ada bug fix di satu modul, pengembang harus ingat untuk fix juga di modul lainnya. Sudah terjadi: `download-youtube.sh` punya fitur `--split-chapters` yang tidak ada di `download-spotify.sh`.

**Suggestion:** Refactor ke fungsi shared di `helpers.sh` dengan parameter:
```bash
_download_media() {
    local type="$1"    # "spotify" | "youtube" | "video"
    local links=("${@:2}")
    # common flow here
}
```

### 3.2 Inkonsistensi Nama Modul

**Severity: MEDIUM**
**File:** Multiple files

**Problem:**
| Location | Module Name | Actual File |
|----------|------------|-------------|
| `zdt.sh` loader loop | `download-spotify`, `download-youtube` | ✅ Correct |
| `daemon.sh` OTA updater | `download-spotify`, `download-youtube` | ✅ Correct |
| `daemon.sh` OTA cleanup comment | `download.sh` | ❌ **Wrong** — references file that doesn't exist |
| Skill documentation (zdt-music-toolkit-dev) | `download.sh` | ❌ **Wrong** |
| GitHub fallback download loop (zdt.sh) | `download-spotify`, `download-youtube` | ✅ Correct |

**Fix:** Update `daemon.sh` cleanup comment dan skill documentation.

### 3.3 Memory Leak — Chat History DB (`zdt_db.py`)

**Severity: LOW**
**File:** `zdt-modules/zdt_db.py`

**Problem:** Chat history dibatasi 20 messages via `DELETE ... NOT IN (SELECT ... LIMIT 20)`. Tapi tabel `downloads` tidak ada batasan — bisa grow indefinitely. Jika user sering download, DB bisa membesar tanpa batas.

**Potential Impact:** File zdt.db bisa mencapai GB dalam jangka panjang.

### 3.4 Directory Traversal di Web API (`zdt-web.py`)

**Severity: HIGH** (but mitigated)

**File:** `zdt-web.py` — `/api/metadata`, `/api/tools`

**Problem:** Ada path traversal protection:
```python
filepath = os.path.realpath(os.path.join(target, filename))
if not filepath.startswith(os.path.realpath(target) + os.sep):
    return jsonify({"success": False, "message": "Akses ditolak."})
```
Ini **sudah OK**. Tapi di `/api/tools` untuk action 'demucs' dan 'compress', menggunakan `shutil.which("zdt")` yang bisa dimanipulasi jika attacker control PATH environment variable. **Risiko rendah karena dashboard hanya di localhost.**

### 3.5 Bare Excepts di Python

**Severity: MEDIUM**
**File:** `zdt-telegram.py`, `zdt-web.py`

**Locations:**
- `zdt-telegram.py` line 389: `except:` (bare except) — menangkap KeyboardInterrupt, SystemExit
- `zdt-web.py` lines 726-731: `except Exception` dan `except HTTPError` — terlalu luas

**Impact:** KeyboardInterrupt tidak bisa membatalkan proses di Telegram bot; SystemExit tertelan.

---

## 4. MISSING FEATURES

### 4.1 Download Queue / Batch Manager (Requested)

**Priority: HIGH**

Saat ini setiap download berjalan **sequential dan blocking**. Tidak ada mekanisme:
- Antrian download (queue)
- Prioritas download
- Cancel task spesifik (hanya Ctrl+C yang hard-kill semua)
- Resume interrupted downloads (hanya via archive system yt-dlp)
- Progress tracking real-time di CLI (hanya ada di Web Dashboard)

**Suggestion:** Implementasi simple job queue dengan state file di `/tmp/zdt_queue/`:
```json
{
  "jobs": [
    {"id": 1, "url": "...", "status": "downloading", "progress": "45%"},
    {"id": 2, "url": "...", "status": "queued"}
  ]
}
```

### 4.2 Konfigurasi Notifikasi Email / Webhook

**Priority: MEDIUM**

Saat ini notifikasi hanya via Telegram. Fitur notifikasi untuk:
- Email (SMTP)
- Webhook (HTTP POST ke endpoint custom)
- Desktop notification (via `notify-send`)

Akan berguna untuk monitoring server.

### 4.3 Log Rotation yang Proper

**Priority: MEDIUM**

Saat ini log rotation (`core.sh`):
```bash
if [ "$size" -gt "$MAX_LOG_SIZE" ]; then
    mv "$LOG_FILE" "${LOG_FILE}.old"
fi
```

Masalah:
- Hanya menyimpan 1 file backup (.old)
- Tidak ada kompresi (gzip)
- Tidak ada max file retention policy
- Tidak ada rotasi berbasis waktu (hanya size-based)

**Suggestion:** Implementasi logrotate-style:
- Simpan 5 backup (`.1.gz`, `.2.gz`, ...)
- Kompres dengan gzip
- Rotasi setiap 5MB

### 4.4 Unified AI Prompt System

**Priority: MEDIUM**  
**Note:** Pengembang setuju dengan saran untuk unification

Saat ini ada **dua sistem prompt AI terpisah**:
1. `assistant.sh` — Bash/Zaki AI CLI — ~50 lines system prompt
2. `zdt-telegram.py` — Python/Telegram — ~40 lines system prompt

Keduanya memiliki redundansi besar dan bisa inkonsisten.

**Suggestion:** Buat satu file `zdt-ai-config.json` atau `prompts/` folder yang berisi shared prompts:
```json
{
  "system_prompt": "Kamu Zaki-Bot...",
  "capabilities": ["download", "kompres", "vokal", ...]
}
```

### 4.5 Web Dashboard — Dark Mode Toggle & User Preferences

**Priority: LOW**

Dashboard saat ini selalu dark mode (ultra dark). Fitur:
- Toggle dark/light mode
- Simpan preferensi ke localStorage
- Pilihan bahasa (ID/EN)

### 4.6 ARM64 / Termux Optimization

**Priority: MEDIUM**

Beberapa masalah spesifik Termux/ARM:
- UI dashboard penuh (clear + re-render) lambat di layar kecil
- Background ping process boros batre
- Demucs (PyTorch) mungkin tidak optimal di ARM64
- ffmpeg threading: `nproc` di Termux mungkin return 8 tapi CPU terbatas

---

## 5. ARCHITECTURAL CONCERNS

### 5.1 UI Performance di Terminal Rendah

**Problem:** Main loop di `zdt.sh` melakukan:
```bash
clear
# Render full ASCII art dashboard dengan box-drawing characters
# 40+ lines of formatted output
```

Setiap iterasi loop (setiap selesai satu task):
1. `clear` — full screen clear
2. Render header (6 lines)
3. Render stats row
4. Render left panel (menu) + right panel (info) — memanggil `command -v` untuk 6+ tools setiap render
5. Prompt user

Di **Termux/SSH dengan latency tinggi**, ini sangat lambat karena:
- Setiap `echo -e` mengirim data ke terminal
- Setiap `command -v` memanggil filesystem
- Ada 30+ `echo` calls per render

**Suggestion:** 
- Cache hasil `command -v` untuk tools (tidak perlu ngecek tiap render)
- Cache `df`, `free`, `/proc/stat` — update setiap 5 detik, bukan tiap render
- Kurangi jumlah `echo` dengan menggabungkan string

### 5.2 Variable Naming Convention

**Problem:** Campuran snake_case dan lowercase tanpa prefix yang jelas:
- `TARGET_DIR`, `STORAGE_DIR` — global config (UPPER)
- `target_dir`, `auto_folder_name` — local variables (lower)
- `_config_set`, `_load_config` — internal functions (underscore prefix)

Tapi ada inkonsistensi:
```bash
# Di core.sh:
ROOT_DIR=""       # Upper — global
TARGET_DIR="."    # Upper — global  
RUNTIME_ENV=""    # Mixed case — seharusnya RUNTIME_ENV
```

**Saran:** Tetapkan konvensi:
- `ZDT_*` — exported environment variables
- `UPPER_CASE` — global/state variables
- `_lower_case` — internal functions
- `lower_case` — local variables

### 5.3 Single-threaded Python Services

**Problem:** `zdt-web.py`, `zdt-telegram.py`, `zdt-watch.py`, `zdt-scheduler.py` semuanya single-process. Flask menggunakan development server (bukan production WSGI). Jika ada task berat (Demucs AI), HTTP request lain akan blocked.

**Suggestion untuk masa depan:**
- Gunakan `gunicorn` + `gevent` untuk web
- Telegram bot sudah pakai `ThreadPoolExecutor` (max_workers=10) — ini sudah OK
- Watch daemon single-threaded — OK untuk use case sederhana

---

## 6. SECURITY CONCERNS

### 6.1 Credential di Output Terminal

**Severity: MEDIUM**

Saat `zdt-web.py` pertama dijalankan, password di-print ke terminal:
```python
print(f"Password: {random_pass}")
```
Juga di `_print_credentials()`:
```python
print(f"  🔐 Login: {conf_user} / {conf_pass}")
```

Jika terminal logging aktif (script, tmux, screen), password bisa tercatat di history/log file.

**Fix:** Tampilkan hanya sekali (saat generate) dan arahkan user ke file config.

### 6.2 `shutil.which("zdt")` Path Injection

**Severity: LOW** (dashboard hanya di localhost)

**File:** `zdt-web.py`, `zdt-telegram.py`, `zdt-watch.py`

**Problem:** `shutil.which("zdt")` mencari di PATH. Jika attacker berhasil memodifikasi PATH (misal via environment variable di dashboard), bisa menjalankan binary berbahaya.

**Fix:** Selalu gunakan path absolut yang diverifikasi:
```python
ZDT_BIN = "/usr/local/bin/zdt"  # atau hasil instalasi known path
```

### 6.3 Config File Permission

**Status: SUDAH BAIK** ✅

`chmod 600` diterapkan di beberapa tempat (token Telegram, config.env). Tapi tidak konsisten:
- `zdt-web.py` `_ensure_password()`: ✅ `os.chmod(config_file, 0o600)`
- `setup_telegram_bot()`: ✅ `chmod 600 .../telegram_token.txt`
- `_config_set()`: ❌ Tidak ada permission setting

---

## 7. TESTING GAPS

### 7.1 Coverage Blind Spots

Berdasarkan `.coveragerc`:
```ini
[run]
include =
    zdt-web.py
    tests/*
```

Tidak termasuk:
- `zdt-telegram.py` ❌
- `zdt-watch.py` ❌
- `zdt-scheduler.py` ❌
- `zdt-modules/zdt_db.py` ❌
- Semua Bash modules ❌
- **Integration tests** (Bash→Python interaction) ❌

### 7.2 Missing Test Scenarios

| Area | Ada Test? | Notes |
|------|-----------|-------|
| Web auth & CSRF | ✅ | `test_web_config.py`, `test_csrf.py` — baik |
| Telegram AI fallback | ✅ | `test_telegram.py` — baik |
| Watch daemon processing | ✅ | `test_watch.py` — baik |
| zdt_db.py (SQLite) | ✅ | `test_db.py` — baik |
| Bash argument parsing | ✅ | `test_bash_runtime.sh` — baik |
| **Config migration** (old→new) | ❌ | Tidak ada test untuk migrasi config.conf → config.env |
| **OTA Update** (daemon.sh) | ❌ | Tidak ada test untuk update mechanism |
| **Demucs pipeline** | ❌ | Tidak ada test untuk vocal removal flow |
| **Race condition config** | ❌ | Tidak ada concurrent write test |
| **Network ping zombie** | ❌ | Tidak ada test untuk cleanup process |

---

## 8. UI/UX ISSUES

### 8.1 Web Dashboard — Responsive Issues

**Problem:** Dashboard sudah responsif (media queries untuk <900px dan <480px), tapi:
- Tables (Recent Downloads, Scheduled Playlists) tidak horizontal scroll di mobile — overflow
- Select elements di tool cards tidak responsif di layar kecil
- Bottom navigation menyembunyikan item di "Lainnya" — OK tapi transisi kurang smooth

### 8.2 CLI — Multi-line Input Handling

**Problem:** Di Zaki AI (`assistant.sh`), input multi-line menggunakan:
```bash
while true; do
    read -r current_input
    if [[ "$current_input" != *"\\" ]]; then
        break
    fi
    bot_prompt="${bot_prompt%\\}"
done
```
Jika user copy-paste teks dengan backslash (`\`) di akhir baris (common di non-English text), input akan terus meminta baris baru. Ini confusing.

### 8.3 Bahasa Campuran

**Problem:** UI strings campuran Indonesia dan Inggris. User-facing strings harusnya konsisten bahasa Indonesia (sesuai skill guide), tapi ada beberapa string Inggris yang tidak sengaja tertinggal:
- Dashboard Web: 80% Inggris (titles, descriptions, buttons)
- CLI menu: 100% Indonesia ✅
- Telegram bot: 80% Indonesia ✅
- Log messages: Campuran

---

## 9. PERFORMANCE CONCERNS

### 9.1 FPS Rendering di CLI

**Problem:** Main loop render + deteksi environment setiap iterasi:
```bash
RUNTIME_ENV=$(_detect_environment)
...
local ram_pct=$(_get_ram_percent)
local uptime_val=$(_get_uptime)
local storage_pct=$(_get_storage_percent)
local os_name=$(_get_os_name)
```

Setiap fungsi ini memanggil `command -v`, `awk`, `grep`, atau read `/proc`. Di Termux, ini semua relatif lambat (subprocess overhead). Total ~100ms+ per render.

**Suggestion:**
- Cache system stats (update setiap 5 detik)
- Cache tool availability (update setiap 30 detik)
- Background refresh thread

### 9.2 Background Ping Loop

**Problem:** `ping -c 1 -W 2 8.8.8.8` setiap 3 detik:
- Network call setiap 3 detik — boros data di mobile
- Di Termux bisa mencegah Android Doze mode (baterai boros)
- Write ke file setiap 3 detik — wear on storage

**Suggestion:**
- Kurangi interval ke 30 detik
- Gunakan `curl --connect-timeout 2 -s http://google.com >/dev/null` sebagai alternatif yang lebih ringan
- Non-aktifkan di Termux (atau perpanjang interval ke 60 detik)

---

## 10. IMPROVEMENT SUGGESTIONS (Quick Wins)

### 10.1 Critical (Fix ASAP)
1. ✅ Zombie network monitor process — cleanup sebelum `exit 0`
2. ✅ Race condition di `_config_set()` — atomic write dengan mktemp
3. ✅ `_trap_ctrlc` restart penuh — ganti dengan `return 0`

### 10.2 High Priority (Next Release)
4. Refactor duplikasi download-spotify.sh & download-youtube.sh → shared helpers
5. Perbaiki log rotation (multiple backups, gzip)
6. Fix bare excepts di Python
7. Tambah download queue system

### 10.3 Medium Priority
8. Unify AI prompt system (single source of truth)
9. Add integration tests for Bash↔Python interaction
10. Optimize UI for Termux/SSH (cache system stats, nonaktifkan ping loop di mobile)
11. Migrasi total from old config.conf → config.env

### 10.4 Low Priority
12. Language consistency (Indonesia for all UI, or bilingual support)
13. Config file permission consistency (chmod 600 everywhere)
14. Persistent user preferences in web dashboard

---

## 11. FILE-BY-FILE AUDIT SUMMARY

| File | Lines | Issues Found | Severity |
|------|-------|-------------|----------|
| `zdt.sh` | ~150 | Zombie ping process, UI render perf, variable safety | CRITICAL |
| `core.sh` | ~300 | Race condition config, trap restart, log rotation | CRITICAL |
| `helpers.sh` | ~250 | ✅ Solid — no major issues | SAFE |
| `download-spotify.sh` | ~350 | Duplicate code with download-youtube.sh | HIGH |
| `download-youtube.sh` | ~450 | Duplicate code, variable scope issue in AUTO_MODE | HIGH |
| `media.sh` | ~420 | ✅ Solid — well structured | SAFE |
| `playlist.sh` | ~180 | ✅ Solid | SAFE |
| `daemon.sh` | ~300 | Stale module reference `download.sh` | LOW |
| `setup.sh` | ~280 | ✅ Solid — good argparse | SAFE |
| `assistant.sh` | ~500 | Duplicate prompt system, multi-line input UX | MEDIUM |
| `zdt-web.py` | ~875 | Bare excepts, credentials in stdout, dev server | MEDIUM |
| `zdt-telegram.py` | ~777 | Bare except (`except:`), duplikasi prompt | MEDIUM |
| `zdt-watch.py` | ~88 | ✅ Solid — simple and clean | SAFE |
| `zdt-scheduler.py` | ~157 | ✅ Solid | SAFE |
| `zdt_db.py` | ~118 | No downloads size limit | LOW |
| `templates/dashboard.html` | ~700 | Missing mobile horizontal scroll, mixed language | LOW |
| `test_smoke.sh` | ~100 | ✅ Well structured | SAFE |

---

## 12. DECISIONS MADE WITH STAKEHOLDER (From Interview)

1. **Prioritas:** Analisis komprehensif (semua aspek: bug, fitur, keamanan) ✅
2. **Target platform:** Semua (Termux, Linux, Web, Docker) ✅
3. **Module names:** `download-spotify` dan `download-youtube` adalah 2 modul terpisah — dokumentasi yang bilang `download.sh` adalah bug ✅
4. **AI prompts:** Stakeholder setuju untuk unification (single source of truth) ✅
5. **Config legacy:** Migrasi total ke config.env (buang dukungan config.conf) ✅
6. **Test coverage:** Perluas ke zdt-telegram.py, zdt-watch.py, dan integration tests ✅
7. **Download queue:** Diinginkan oleh stakeholder ✅
8. **Bare excepts:** Identifikasi dan perbaiki ✅
9. **Log rotation:** Perbaiki ✅
10. **Race condition:** Dijelaskan di spec ini ✅
11. **UI low-perf Termux/SSH:** Diakui — Termux proot-distro, ada flicker ✅
