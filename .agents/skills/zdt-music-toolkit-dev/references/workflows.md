# ZDT Development Workflows (Recipes)

## 1. Add a new CLI feature (interactive + flag)
1. **Pick the module** that owns the domain (download/media/playlist/daemon).
2. Add the entrypoint function (unprefixed) and `_`-prefixed helpers in that file:
   ```bash
   my_new_feature() {
       print_header "JUDUL FITUR"                  # Indonesian title
       _ensure_python_tool "sometool" "SomeTool" 0 || return 1   # gate deps
       # ... logic, quote vars, use arrays for cmd args ...
   }
   ```
3. **Interactive menu:** add a menu entry where the module builds its menu
   (`_print_menu_box` pattern) and route the choice to `my_new_feature`.
4. **CLI flag (optional):** in `setup.sh` `_parse_args`, detect the flag and set
   `MAIN_MODE="my_mode"`. In `zdt.sh` `main()`, add `my_mode) my_new_feature ;;`
   to the dispatch `case`.
5. Run smoke test + shellcheck + pytest. Bump version via `./release.sh`.

## 2. Add a brand-new module `zdt-modules/foo.sh`
Register it in **all four** places or it won't load / install / update:
1. `zdt.sh` — add `foo` to the source loop list.
2. `zdt.sh` — add `foo` to the GitHub-fallback download loop list.
3. `Makefile` — module install already globs `zdt-modules/*.sh`, but confirm.
4. `daemon.sh` OTA updater — add `foo` to the modules it pulls from GitHub.
Then ensure no function name collides with existing modules (smoke test enforces).

## 3. Add/modify a web dashboard route (`zdt-web.py`)
- Keep handlers in importable functions; avoid heavy work at import time.
- Respect `--bind` / `--port` / `WEB_BIND`. Do not add positional args the CLI
  doesn't parse (past bug: stray `$ROOT_DIR` → "unrecognized arguments").
- Add pytest coverage in `tests/` (this file is the coverage target).
- Escape newlines correctly when emitting M3U playlists (past bug).

## 4. Telegram bot change (`zdt-telegram.py`)
- Token file must stay `chmod 600`.
- Destructive actions (delete) require an inline-keyboard confirmation.

## 5. Watch daemon change (`zdt-watch.py`)
- Pipeline on new file: clean name → inject ID3 (mutagen) → fetch lyrics.
- Launched by `start_watch_daemon` in `daemon.sh`, which finds the script in the
  installed share dirs.

## 6. Cut a release
```bash
./release.sh patch        # patch rolls .9 -> next minor
./release.sh minor
./release.sh major
```
Effects: bumps `APP_VERSION` in `zdt.sh`, updates README install line, syncs a
local install if present, commits "Release: Version x.y.z", pushes. OTA updater
then sees the new version on GitHub `main`.

## 7. Manual local install / portable run
```bash
./install.sh          # or: ./zdt.sh --install
sudo make install     # Makefile method -> /usr/local/bin/zdt + share dirs
./zdt.sh              # portable, no install
```

## Gotchas
- `set -uo pipefail` is global — unset vars abort. Default with `${VAR:-}`.
- Use bash arrays for command arguments (especially `find`), never space-joined strings.
- Python tools are VENV-only (PEP 668); always go through `_ensure_python_tool`.
- Keep one function = one module (smoke test fails on duplicates).
- User-facing text in Indonesian.
- Never hand-edit the version; use `release.sh` so README + commit stay in sync.
