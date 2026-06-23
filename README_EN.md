# Zaki Downloader Tools (ZDT) 🎵🎬

ZDT Music Toolkit is an all-in-one CLI assistant designed to simplify downloading, compressing, cleaning filenames, and organizing multimedia files (Audio & Video) from various platforms like YouTube, Spotify, and TikTok. Comes with **Zaki AI Assistant**, vocal removal, and auto lyric sync!

## Key Features ✨

- **Spotify HQ Downloader**: Download Spotify songs/playlists with lyrics and metadata (album art).
- **Universal Downloader**: Grab Audio/Video from YouTube, TikTok, etc. in best resolution/quality.
- **Auto Sync Lyrics**: Search and download synced `.lrc` files automatically.
- **Smart Renamer & Auto-Tagger**: Clean dirty filenames like `[Official Music Video]`, then **automatically inject ID3 metadata** (Title & Artist) permanently into your audio files using `mutagen`!
- **Vocal Removal (Demucs)**: Separate instruments and vocals from songs using AI.
- **Media Compression (Multi-Processing)**: Shrink audio/video files in bulk. With the **multi-processing** engine, ZDT can compress 4 songs or 2 videos in parallel for blazing speed!
- **Playlist Generator**: Create `.m3u` files instantly from your music directory.
- **Auto-Watch Daemon**: Run `zdt --watch` to monitor a folder. Raw files dropped in are automatically renamed, ID3 tagged, and lyrics fetched.
- **Telegram Remote Downloader**: Run `zdt --telegram` and control ZDT remotely via Telegram Bot from your phone.
- **Web Dashboard (Local UI)**: Run `zdt --web` to start a local server and download songs directly from your phone's browser. Supports `--bind` and `--port` for address configuration.
- **Spotify Incremental Sync**: Register your Spotify Playlists and ZDT only downloads new songs not yet in the folder.
- **Metadata & Cover Art Editor**: Manually edit Title, Artist, and inject cover art images via terminal interface.
- **Over-The-Air (OTA) Updater**: Update ZDT directly from GitHub with a single button inside the app!
- **Configuration File**: Save your preferred video resolution and audio quality so you're not asked repeatedly (stored in `~/.config/zdt/config.env`).
- **Zaki AI Assistant (Pro)**: Smart assistant powered by Gemini AI. Just chat in everyday language ("Bro, remove vocals from the last song please"), and the AI executes the command!
- **Smoke Test**: Run `bash test_smoke.sh` to validate syntax, integrity, and security of all script files before commit/deploy.

## Changelog

See [**CHANGELOG.md**](CHANGELOG.md) for release details of **v4.1.74** and previous versions.

## Installation 🚀

ZDT (v3.1.1+) is designed to run on various Linux environments (Ubuntu/Debian, Arch, Fedora, Termux, WSL) using safe **Python Virtual Environment (VENV)** isolation compliant with PEP 668.

### Method 1: Script Installation (Recommended)

```bash
git clone https://github.com/muhammad1505/zdt-music-toolkit.git
cd zdt-music-toolkit
./install.sh
# Or: ./zdt.sh --install
```

### Method 2: Makefile Installation

```bash
git clone https://github.com/muhammad1505/zdt-music-toolkit.git
cd zdt-music-toolkit
sudo make install
```

### Method 3: Portable (Direct Execution)

```bash
chmod +x zdt.sh
./zdt.sh
```

## Getting Started 💡

Once installed globally, simply run:

```bash
zdt
```

### CLI Arguments

- `zdt update` (or `zdt --update`): Download and install the latest ZDT version from GitHub (OTA Update).
- `zdt --web`: Launch Web Dashboard at `http://localhost:5000` with auto-open browser.
- `zdt --web-bind 0.0.0.0`: Launch Web Dashboard open to all network interfaces.
- `zdt --help`: Display the full list of available command-line arguments.

**Important!** On first run, go to `[A] Auto Install Tools`. This will automatically set up the VENV system, download core Python packages (yt-dlp, spotdl, etc.), and check system dependencies like ffmpeg so your app is 100% battle-ready.

*Developed For Efficiency & Quality 🚀*
