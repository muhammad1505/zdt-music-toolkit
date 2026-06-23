# ZDT Architecture Reference

## Entrypoint: `zdt.sh` (thin loader)
- Sets `LC_ALL=C.UTF-8`, `set -uo pipefail`.
- Declares `readonly APP_VERSION="x.y.z"` and exports `ZDT_VERSION` — **single source of truth for version**.
- Resolves `_MODULES_DIR` in this priority:
  1. `$SCRIPT_DIR/zdt-modules` (running from repo/portable)
  2. installed share dirs: `$HOME/.local/share/zdt/zdt-modules`, `/usr/local/share/zdt/zdt-modules`, Termux `.../usr/share/zdt/zdt-modules`
  3. GitHub fallback: downloads each module via `raw.githubusercontent.com/.../main/zdt-modules/<mod>.sh`
- Sources modules in fixed order: `core helpers download media playlist daemon setup assistant`.
- `main()`:
  - `_parse_args "$@"` sets `MAIN_MODE` for non-interactive CLI shortcuts.
  - If `MAIN_MODE` set → init colors/unicode/logging/config, resolve `ROOT_DIR`/`STORAGE_DIR`, dispatch via `case "$MAIN_MODE"` (download_audio, download_video, spotify_sync, kompres_media, extract_vocal, sync_lirik, bersih_nama, bikin_playlist), then exit.
  - Else → interactive mode: setup, acquire lockfile (`_acquire_lock`), set traps (`_trap_ctrlc`, `_trap_exit`, optional `_trap_err` under `ZDT_DEBUG=1`), spawn background net-check pinger, optionally auto-launch Zaki AI, show menu.

## Module responsibilities

| Module | Owns |
|---|---|
| `core.sh` | Constants (`APP_NAME`, `ZDT_VENV_DIR=$HOME/.local/share/zdt/venv`, `ZDT_CONFIG_FILE=$HOME/.config/zdt/config.env`, `CONF_*` defaults), color/unicode setup, logging (`_log`, `_init_logging`), portability/env detection, lockfile, signal traps. **Loads first.** |
| `helpers.sh` | Shared utilities: `_check_dependency`, folder selection, filename cleaning (strip `[Official Music Video]` etc.), `_find_media_files()` media scanner (uses bash arrays for `find` args). |
| `download.sh` | `download_spotdl` (Spotify via spotdl, lyrics + album art), YouTube/yt-dlp audio, `download_video`. |
| `media.sh` | `kompres_media` (audio/video compression with multiprocessing worker pool), `hapus_vokal` (Demucs vocal/instrument separation), metadata + cover-art editor, manual name cleaning. |
| `playlist.sh` | `auto_sync_lirik` (syncedlyrics `.lrc`), `sync_spotify_playlist` (incremental — only new tracks), `bikin_playlist` (M3U generator). |
| `daemon.sh` | `start_watch_daemon` (launches `zdt-watch.py`), Telegram bot launcher, web dashboard launcher, OTA updater (downloads new `zdt.sh` + modules from GitHub), clean-all. |
| `setup.sh` | `_ensure_python_tool`, `_check_dependency` flows, VENV bootstrap / Auto Install Tools, system info, docs, storage dir setup, `_parse_args` (CLI flag parsing). |
| `assistant.sh` | Zaki AI (Gemini). `ZDT_CHAT_HISTORY` array (capped at ~10 entries), `_zaki_add_history`, multi-tier model fallback, structured intent recognition → maps natural-language requests to ZDT functions. |

## Python companions
- `zdt-web.py` — Flask local dashboard. Args include `--bind` / `--port` (also `WEB_BIND` config var). Auto-opens browser on `zdt --web`. Only file tracked by `.coveragerc`.
- `zdt-telegram.py` — telebot remote control; token stored `chmod 600`; delete confirmations via inline keyboard.
- `zdt-watch.py` — watchdog observer; on new raw file: clean name → inject ID3 tags (mutagen) → fetch lyrics.

## Key globals & paths
- Version: `APP_VERSION` / `ZDT_VERSION`
- VENV: `$HOME/.local/share/zdt/venv`
- Config: `$HOME/.config/zdt/config.env` (atomic write + `flock`)
- Installed modules: `$HOME/.local/share/zdt/zdt-modules` (or `/usr/local/share/zdt/...`)
- `ROOT_DIR` / `STORAGE_DIR`: working/storage directory for downloads
- `CONF_AUDIO_CODEC`, `CONF_AUDIO_BITRATE`, `CONF_VIDEO_CODEC`, `CONF_VIDEO_QUAL`, `CONF_VIDEO_FMT`: saved preferences

## CLI flags (from README / `_parse_args`)
- `zdt update` / `zdt --update` — OTA update from GitHub
- `zdt --web` — web dashboard at http://localhost:5000 (auto-open browser)
- `zdt --web-bind 0.0.0.0` — bind to all interfaces
- `zdt --watch` — auto-watch daemon
- `zdt --telegram` — Telegram bot
- `zdt --install` — install
- `zdt --help` — list all flags
