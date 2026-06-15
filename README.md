# Zaki Downloader Tools (ZDT) 🎵🎬

ZDT Music Toolkit adalah asisten terminal (CLI) all-in-one yang dirancang untuk memudahkan Anda mengunduh, mengompres, membersihkan nama, serta mengatur file multimedia (Audio dan Video) dari berbagai platform seperti YouTube, Spotify, dan TikTok. Dilengkapi dengan **Zaki AI Assistant**, memisahkan vokal, dan auto-sync lirik!

## Fitur Utama ✨
- **Spotify HQ Downloader**: Download lagu/playlist Spotify lengkap dengan lirik dan metadata (album art).
- **Universal Downloader**: Sedot Audio/Video dari YouTube, TikTok, dll dalam resolusi/kualitas terbaik.
- **Auto Sync Lirik**: Cari dan download file `.lrc` yang sinkron dengan ketukan lagu secara otomatis.
- **Smart Renamer**: Bersihkan nama file yang kotor seperti `[Official Music Video]`, dll.
- **Hapus Vokal (Demucs)**: Pisahkan instrumen dan vokal lagu menggunakan AI.
- **Kompres Media**: Perkecil ukuran file audio/video secara massal tanpa banyak mengurangi kualitas.
- **Playlist Generator**: Buat file `.m3u` secara instan dari direktori musik Anda.
- **Zaki AI Assistant (Pro)**: Asisten cerdas berbasis Gemini AI. Cukup *chat* pakai bahasa sehari-hari ("Bro tolong pisahin dong vokal lagu terakhir", dll), lalu AI yang akan mengeksekusi komandonya!

## Instalasi 🚀

ZDT (v3.0.0+) dirancang untuk berjalan di berbagai lingkungan berbasis Linux (Ubuntu/Debian, Arch, Fedora, Termux, WSL) menggunakan isolasi **Python Virtual Environment (VENV)** yang aman dan mematuhi PEP 668.

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
**(Penting!)** Pada saat **pertama kali** dijalankan, masuklah ke menu **[A] Auto Install Tools**. Fitur ini akan otomatis merakit sistem VENV, mendownload paket Python utama (`yt-dlp`, `spotdl`, dll), serta mengecek dependensi sistem seperti `ffmpeg` agar aplikasi Anda siap tempur 100%.

---
**Dikembangkan Khusus Untuk Efisiensi & Kualitas** 🚀
