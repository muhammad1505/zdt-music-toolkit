# Zaki Downloader Tools (ZDT) 🎵🎬

ZDT Music Toolkit adalah asisten terminal (CLI) all-in-one yang dirancang untuk memudahkan Anda mengunduh, mengompres, membersihkan nama, serta mengatur file multimedia (Audio dan Video) dari berbagai platform seperti YouTube, Spotify, dan TikTok. Dilengkapi dengan **Zaki AI Assistant**, memisahkan vokal, dan auto-sync lirik!

## Fitur Utama ✨
- **Spotify HQ Downloader**: Download lagu/playlist Spotify lengkap dengan lirik dan metadata (album art).
- **Universal Downloader**: Sedot Audio/Video dari YouTube, TikTok, dll dalam resolusi/kualitas terbaik.
- **Auto Sync Lirik**: Cari dan download file `.lrc` yang sinkron dengan ketukan lagu secara otomatis.
- **Smart Renamer & Auto-Tagger**: Bersihkan nama file yang kotor seperti `[Official Music Video]`, lalu **otomatis menyuntikkan metadata ID3** (Title & Artist) secara permanen ke dalam file audio Anda menggunakan `mutagen`!
- **Hapus Vokal (Demucs)**: Pisahkan instrumen dan vokal lagu menggunakan AI.
- **Kompres Media (Multi-Processing)**: Perkecil ukuran file audio/video secara massal. Berkat mesin *multi-processing*, ZDT mampu mengompres 4 lagu atau 2 video secara paralel sehingga proses menjadi jauh lebih ngebut!
- **Playlist Generator**: Buat file `.m3u` secara instan dari direktori musik Anda.
- **Auto-Watch Daemon**: Jalankan `zdt --watch` untuk memantau folder secara otomatis. Jika ada file mentah dimasukkan, ZDT otomatis merapikan nama, menyuntik Tag ID3, dan mencari lirik.
- **Telegram Remote Downloader**: Jalankan `zdt --telegram` dan kontrol ZDT dari jarak jauh menggunakan Bot Telegram di HP Anda untuk mendownload musik ke PC/Server rumah.
- **Web Dashboard (Local UI)**: Jalankan `zdt --web` untuk menyalakan server lokal dan mendownload lagu langsung dari browser di HP Anda. Mendukung `--bind` dan `--port` untuk konfigurasi address.
- **Spotify Incremental Sync**: Daftarkan Playlist Spotify Anda dan ZDT hanya akan mendownload lagu baru yang belum ada di dalam folder.
- **Metadata & Cover Art Editor**: Ubah Judul, Artis, dan injeksi gambar sebagai Cover Art lagu secara manual melalui antarmuka terminal.
- **Over-The-Air (OTA) Updater**: Perbarui versi skrip ZDT Anda langsung dari GitHub ke sistem Anda cukup dengan satu tombol dari dalam aplikasi!
- **File Konfigurasi**: Simpan preferensi resolusi video dan kualitas audio favorit Anda sehingga Anda tidak perlu ditanya berulang-ulang saat mengunduh (*tersimpan di `~/.config/zdt/config.env`*).
- **Zaki AI Assistant (Pro)**: Asisten cerdas berbasis Gemini AI & OpenRouter. Cukup *chat* pakai bahasa sehari-hari ("Bro tolong pisahin dong vokal lagu terakhir", dll), paham variasi bahasa ("download"/"sedot"/"unduh" = download). Dilengkapi **keyword fallback** — kalo AI gagal deteksi intent, keyword matching otomatis ambil alih biar perintah tetep dieksekusi!
- **Telegram Bot Cerdas**: Kontrol ZDT dari HP via Telegram dengan bahasa santai. Sama kayak AI Assistant, paham variasi bahasa dan punya **keyword fallback** biar ga ada perintah yang kelewat.
- **Smart Web Dashboard (ZDT Console)**: Tampilan modern ala audio mixing console dengan mode gelap/terang, grafik Chart.js, log real-time, dan notifikasi. Bisa di-restart otomatis (kill + start ulang) biar selalu pake kode terbaru.
- **Over-The-Air (OTA) Updater**: Perbarui versi ZDT langsung dari GitHub. Backup otomatis sebelum update, tinggal rollback kalo ada masalah.
- **Auto GitHub Release**: Setiap tag `v*` otomatis bikin GitHub Release.
- **Smoke Test**: Jalankan `bash test_smoke.sh` untuk memvalidasi syntax, integritas, dan keamanan semua file script sebelum commit/deploy.

## Changelog

Riwayat versi dan pembaruan ZDT sekarang tersedia di file terpisah. 
Silakan lihat: [**CHANGELOG.md**](CHANGELOG.md) untuk detail rilis **v4.4.6** dan versi-versi sebelumnya.

## Instalasi 🚀

ZDT (v3.1.1+) dirancang untuk berjalan di berbagai lingkungan berbasis Linux (Ubuntu/Debian, Arch, Fedora, Termux, WSL) menggunakan isolasi **Python Virtual Environment (VENV)** yang aman dan mematuhi PEP 668.

### Metode 1: Instalasi Melalui Skrip (Direkomendasikan)
```bash
git clone https://github.com/muhammad1505/zdt-music-toolkit.git
cd zdt-music-toolkit
./install.sh
# Atau bisa juga dengan: ./zdt.sh --install
```

### Metode 2: Instalasi Menggunakan Makefile
```bash
git clone https://github.com/muhammad1505/zdt-music-toolkit.git
cd zdt-music-toolkit
sudo make install
```

### Metode 3: Portable (Eksekusi Langsung)
Anda juga bebas menjalankan skrip ini secara portabel tanpa instalasi:
```bash
chmod +x zdt.sh
./zdt.sh
```

## Mulai Menggunakan (Getting Started) 💡

Setelah terinstal secara global, Anda cukup memanggil aplikasinya dari manapun dengan perintah:
```bash
zdt
```

### CLI Arguments (Pintasan Eksekusi Cepat)
Anda juga bisa menggunakan argumen saat memanggil aplikasi lewat terminal:
- `zdt update` *(atau `zdt --update`)* : Mengunduh dan memasang versi terbaru ZDT secara instan dari GitHub (Over-The-Air Update) tanpa perlu membuka menu aplikasi.
- `zdt --web` : Menjalankan Web Dashboard di `http://localhost:5000` dengan auto-open browser.
- `zdt --web-bind 0.0.0.0` : Menjalankan Web Dashboard terbuka untuk semua network interface.
- `zdt --help` : Menampilkan daftar lengkap *command-line arguments* yang tersedia.

**(Penting!)** Pada saat **pertama kali** dijalankan, masuklah ke menu **[A] Auto Install Tools**. Fitur ini akan otomatis merakit sistem VENV, mendownload paket Python utama (`yt-dlp`, `spotdl`, dll), serta mengecek dependensi sistem seperti `ffmpeg` agar aplikasi Anda siap tempur 100%.

---
**Dikembangkan Khusus Untuk Efisiensi & Kualitas** 🚀
