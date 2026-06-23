---
name: zdt-music-toolkit-dev
description: Develop, debug, test, and release features for the ZDT Music Toolkit (zdt-music-toolkit) repo — a modular Bash + Python CLI for downloading and managing music/video from Spotify, YouTube, TikTok. Use when adding features, editing the zdt.sh loader or zdt-modules, working on the Flask web dashboard, Telegram bot, or watch daemon, fixing bugs, writing tests, running the smoke test, or cutting a release.
icon: music
color: Purple
---

# ZDT Music Toolkit — Development Guide

ZDT (Zaki Downloader Tools) is an all-in-one terminal toolkit for downloading,
compressing, renaming/tagging, and organizing audio & video from Spotify,
YouTube, TikTok, etc. It is a **modular Bash application** with three **Python
companion components** and an AI assistant (Gemini-based "Zaki AI").

Repo: https://github.com/muhammad1505/zdt-music-toolkit

## Project Layout

```
zdt.sh                 # Thin loader/entrypoint (~143 lines). Holds APP_VERSION, sources modules, main()
zdt-modules/           # 8 Bash modules — sourced in a FIXED ORDER by zdt.sh
  core.sh              #   constants, config, colors, logging, portability, lockfile, signal traps
  helpers.sh           #   shared utils: dependency checks, folder selection, file cleaning, media scan
  download.sh          #   Spotify (spotdl), YouTube/yt-dlp, video downloads
  media.sh             #   compression (multiprocessing), Demucs vocal removal, metadata/cover editor
  playlist.sh          #   lyrics sync (syncedlyrics), Spotify incremental sync, M3U generator
  daemon.sh            #   background services: watch daemon, telegram bot, web dashboard, OTA update
  setup.sh             #   dependency mgmt (VENV), system info, docs, storage setup, CLI args parsing
  assistant.sh         #   Zaki AI assistant (Gemini), conversation history, intent recognition
zdt-web.py             # Flask local web dashboard (zdt --web), supports --bind / --port
zdt-telegram.py        # Telegram remote-control bot (zdt --telegram)
zdt-watch.py           # watchdog-based auto-watch daemon (zdt --watch)
tests/                 # pytest suite + conftest.py (mocks optional deps)
test_smoke.sh          # Bash+Python syntax, duplicate-function, integrity, security checks
install.sh / Makefile  # installers (script-based and make install)
release.sh             # version bump + commit + push (patch|minor|major)
.github/workflows/ci.yml  # CI: shellcheck, smoke test, pytest+coverage on py3.10/3.11/3.12
```

## Architecture Rules (READ BEFORE EDITING)

1. **`zdt.sh` is a thin loader.** Do NOT add feature logic here. It only:
   defines `APP_VERSION`, locates `zdt-modules/` (local → installed share dirs →
   GitHub fallback), sources modules in order, parses args, and dispatches `main()`.

2. **Module source order is fixed and matters:**
   `core → helpers → download → media → playlist → daemon → setup → assistant`.
   A module may call functions defined in any earlier module. `core.sh` must load
   first (it defines colors, logging, config, constants like `APP_NAME`,
   `ZDT_VENV_DIR`, `ZDT_CONFIG_FILE`). If you add a new module, register it in the
   loader loop in `zdt.sh` **and** in the GitHub-fallback download loop, the
   Makefile install step, and the OTA updater in `daemon.sh`.

3. **No duplicate function names across files.** The smoke test fails the build if
   the same `funcname()` is defined in more than one `.sh` file. Pick the right
   module for a function; never copy-paste a helper into two modules.

4. **Naming conventions:** internal/private helpers are prefixed with `_`
   (e.g. `_check_dependency`, `_ensure_python_tool`, `_find_media_files`,
   `_load_config`). User-facing feature entrypoints are unprefixed
   (e.g. `download_spotdl`, `kompres_media`, `hapus_vokal`, `bikin_playlist`).

5. **UI strings are in Indonesian.** Keep user-facing text Indonesian to match the
   existing tone. Code comments are mixed ID/EN — follow the surrounding file.

6. **Python isolation (PEP 668).** Python tools (yt-dlp, spotdl, syncedlyrics,
   mutagen, demucs, flask, telebot, watchdog) run inside a VENV at
   `$HOME/.local/share/zdt/venv`. Use `_ensure_python_tool <bin> <DisplayName> <required>`
   from `setup.sh` to guarantee a tool exists before using it. Never assume a
   global pip install.

7. **Config** lives at `~/.config/zdt/config.env`, written atomically with `flock`.
   Constants: `ZDT_VENV_DIR`, `ZDT_CONFIG_FILE` in `core.sh`. Use `_load_config` /
   the existing config helpers; don't hardcode paths.

8. **Bash safety:** every module assumes `set -uo pipefail` (set in `zdt.sh`).
   Quote variables, use arrays for command args (the `_find_media_files()` bug was
   caused by an unquoted/string `find` arg — use bash arrays). Target Bash 4+.

## Common Development Tasks

### Add a feature to the CLI
1. Decide the owning module (download/media/playlist/etc.).
2. Add the user-facing function (unprefixed) + any `_`-prefixed helpers in that module.
3. Wire it into the interactive menu (see `media.sh` / `download.sh` `_print_menu_box` patterns) and, if it deserves a flag, into `_parse_args` in `setup.sh` plus the `case "$MAIN_MODE"` dispatch in `zdt.sh`'s `main()`.
4. Gate any Python dep behind `_ensure_python_tool`.
5. Run the smoke test and shellcheck (below).

### Edit a Python component
- `zdt-web.py` (Flask), `zdt-telegram.py` (pyTelegramBotAPI/telebot), `zdt-watch.py` (watchdog).
- These import heavy/optional deps; `tests/conftest.py` mocks them so tests run without installs. Keep functions importable/testable (avoid top-level side effects that need real deps; guard with `if __name__ == "__main__":`).
- `zdt-web.py` is the only Python file under coverage (`.coveragerc`). New web logic should have pytest coverage in `tests/`.
- Do NOT pass positional args that the Python CLIs don't accept (a past bug: stray `$ROOT_DIR` passed to `zdt-web.py` caused "unrecognized arguments").

### Run tests locally (always before commit)
```bash
cd zdt-music-toolkit
bash test_smoke.sh                                   # syntax + duplicate-fn + integrity
shellcheck -S error -s bash *.sh zdt-modules/*.sh    # only errors are fatal in CI
python -m pytest tests/ -v --cov=zdt-web.py          # python unit tests + coverage
```
CI (`.github/workflows/ci.yml`) runs exactly these on py3.10/3.11/3.12. Match it.

### Cut a release
```bash
./release.sh patch      # or: minor | major
```
`release.sh` reads `readonly APP_VERSION="x.y.z"` from `zdt.sh`, bumps it (patch
rolls over at .9 → next minor), rewrites the version in `zdt.sh` and the README
install line, syncs a local install if present, then `git commit` + `git push`.
The OTA auto-updater detects the new version on GitHub, so always bump via this
script — do not hand-edit `APP_VERSION` and forget the README/commit.

## Pre-commit checklist
- [ ] `bash test_smoke.sh` passes (0 failures)
- [ ] No duplicate function names across `.sh` files
- [ ] `shellcheck -S error` clean on changed scripts
- [ ] New module registered in loader, GitHub fallback, Makefile, OTA updater
- [ ] Python deps gated behind `_ensure_python_tool` / VENV
- [ ] `pytest tests/` passes; new `zdt-web.py` logic covered
- [ ] User-facing strings in Indonesian
- [ ] Version bumped via `./release.sh`, not manually

## References
- `references/architecture.md` — module responsibilities, load order, data flow, key globals
- `references/testing-and-ci.md` — smoke test internals, pytest patterns, conftest mocking, coverage, CI matrix
- `references/workflows.md` — step-by-step recipes (new module, new CLI flag, web route, release, OTA)
