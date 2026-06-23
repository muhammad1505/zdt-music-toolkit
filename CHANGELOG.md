# ZDT Music Toolkit - Changelog

Semua perubahan yang mencolok pada project ini akan didokumentasikan di file ini.

## v4.1.63 (Latest)
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
