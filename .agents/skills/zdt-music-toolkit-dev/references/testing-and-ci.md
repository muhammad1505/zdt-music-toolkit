# ZDT Testing & CI Reference

## `test_smoke.sh` (Bash smoke test)
Run: `bash test_smoke.sh` (must finish with 0 failures before commit).
Checks performed:
1. **Bash syntax** — `bash -n` on every `*.sh` and `zdt-modules/*.sh`.
2. **Python syntax** — `python3 -m py_compile` on every `*.py`.
3. **Duplicate function definitions** — collects `^funcname()` across all `.sh`
   files; fails if any function name appears in more than one file. This is the
   guardrail for the modular refactor — keep each function in exactly one module.
4. Additional integrity/security checks (e.g. file presence, dangerous patterns).
`pass()`/`fail()` increment counters; exit status reflects failures.

## pytest suite (`tests/`)
- `tests/conftest.py`:
  - `_mock_missing_deps()` — injects fake modules for `flask`, `telebot`,
    `watchdog`, `mutagen` (and submodules) so importing the Python components
    never fails on a machine without those installed.
  - `import_module_from_file(name, filepath)` — imports a `.py` by path *after*
    mocking deps. Use this to test functions inside `zdt-web.py` etc.
  - Fixtures: `mock_home` (patches `os.path.expanduser` to a tmp dir + creates
    `~/.config/zdt`), `mock_disk_usage` (patches `shutil.disk_usage`).
- `tests/test_python_components.py` — `TestSyntax` parametrizes over
  `zdt-web.py`, `zdt-telegram.py`, `zdt-watch.py` and asserts each compiles to a
  valid AST; plus structure/logic tests using source inspection.
- `tests/test_web_import.py` — import-level tests for the Flask app.

### Writing new tests
- For Python with heavy deps: mock at import time (use conftest helpers) and test
  pure logic / source structure rather than running a live server/bot.
- Keep `zdt-web.py` logic in importable functions so it can be unit-tested; it is
  the only file under coverage (`.coveragerc` `include = zdt-web.py, tests/*`).
- Run: `python -m pytest tests/ -v --cov=zdt-web.py --cov-report=term`.

## Coverage (`.coveragerc`)
- `source = .`, `include = zdt-web.py, tests/*`.
- `exclude_lines`: `pragma: no cover`, `if __name__ == .__main__.:`,
  `except ImportError:`, `except Exception:`, `def main`.
- `show_missing`, `skip_covered`, `skip_empty` are on.

## CI (`.github/workflows/ci.yml`)
Triggers: push to `main`/`master`/`develop` (ignores `**.md`), PRs to `main`/`master`.
Matrix: Python `3.10`, `3.11`, `3.12` on `ubuntu-latest`.
Steps (reproduce locally to match CI):
1. apt: `ffmpeg shellcheck bash`.
2. pip: `pytest pytest-cov flask`.
3. **shellcheck** `-S error -s bash` on `*.sh` and `zdt-modules/*.sh` — only
   `error`-level findings are fatal; info/warnings are tolerated (non-fatal echo).
4. `bash test_smoke.sh`.
5. `python -m pytest tests/ -v --cov=tests --cov=zdt-web.py --cov-report=term --cov-report=xml`.
6. Upload coverage to Codecov (py3.12 only, `fail_ci_if_error: false`).

## Local one-liner to mirror CI
```bash
shellcheck -S error -s bash *.sh zdt-modules/*.sh; \
bash test_smoke.sh; \
python -m pytest tests/ -v --cov=zdt-web.py --cov-report=term
```
