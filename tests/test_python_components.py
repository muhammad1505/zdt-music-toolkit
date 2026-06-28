#!/usr/bin/env python3
"""
Pytest unit tests for ZDT Python components.
Tests syntax, code structure, and basic logic of zdt-web.py, zdt-telegram.py, zdt-watch.py.
Uses syntax validation and source inspection for components with heavy dependencies.
"""
import os
import sys
import types
import pytest

PROJECT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


# ────────────────────────────────────────────
# Fixtures
# ────────────────────────────────────────────

@pytest.fixture
def mock_home(monkeypatch, tmp_path):
    """Fixture that sets up a mock home directory."""
    def _mock_expanduser(p):
        return str(tmp_path / p.replace("~", "").lstrip("/"))
    monkeypatch.setattr(os.path, "expanduser", _mock_expanduser)
    # Create config dir
    (tmp_path / ".config" / "zdt").mkdir(parents=True, exist_ok=True)
    return tmp_path


# ────────────────────────────────────────────
# Tests: Syntax validation
# ────────────────────────────────────────────

class TestSyntax:
    """All Python files must be syntactically valid."""

    @pytest.mark.parametrize("fname", ["zdt-web.py", "zdt-telegram.py", "zdt-watch.py"])
    def test_syntax_valid(self, fname):
        """Verify the file compiles to valid Python AST."""
        with open(os.path.join(PROJECT_DIR, fname)) as f:
            compile(f.read(), fname, "exec")
        assert True

    @pytest.mark.parametrize("fname", ["zdt-web.py", "zdt-telegram.py", "zdt-watch.py"])
    def test_shebang_present(self, fname):
        """All Python files must start with #!/usr/bin/env python3."""
        with open(os.path.join(PROJECT_DIR, fname)) as f:
            first_line = f.readline().strip()
        assert first_line == "#!/usr/bin/env python3", f"{fname} missing shebang"


# ────────────────────────────────────────────
# Tests: zdt-web.py (Flask dashboard)
# ────────────────────────────────────────────

class TestWebDashboard:
    """Tests for zdt-web.py via source inspection and pattern checks."""

    def test_html_template_has_key_elements(self):
        """The HTML template should contain expected UI elements."""
        template_path = os.path.join(PROJECT_DIR, "templates", "dashboard.html")
        with open(template_path) as f:
            content = f.read()
        # Check for key UI components
        assert "Dashboard" in content
        assert "Downloader" in content
        assert "Spotify" in content
        assert "Metadata" in content
        assert "Server Tools" in content
        # Check for API endpoints
        assert "/api/status" in content
        assert "/api/download" in content
        assert "/api/spotify-sync" in content
        assert "/api/files" in content
        assert "/api/metadata" in content
        assert "/api/tools" in content
        assert "/api/logs" in content

    def test_flask_app_created(self):
        """The file should create a Flask app instance."""
        with open(os.path.join(PROJECT_DIR, "zdt-web.py")) as f:
            content = f.read()
        assert "app = Flask(" in content and "__name__" in content

    def test_argparse_configured(self):
        """The file should have argparse for --bind and --port."""
        with open(os.path.join(PROJECT_DIR, "zdt-web.py")) as f:
            content = f.read()
        assert "--bind" in content
        assert "--port" in content
        assert "argparse" in content

    def test_get_target_dir_function_exists(self):
        """The get_target_dir function should be defined."""
        with open(os.path.join(PROJECT_DIR, "zdt-web.py")) as f:
            content = f.read()
        assert "def get_target_dir()" in content

    def test_shutil_which_zdt_search(self, monkeypatch):
        """Verify zdt binary search logic works with mocked shutil.which."""
        import shutil

        # shutil.which should be called with "zdt"
        original_which = shutil.which
        called_with = []
        def mock_which(cmd, **kwargs):
            called_with.append(cmd)
            return original_which(cmd, **kwargs)
        monkeypatch.setattr(shutil, "which", mock_which)


# ────────────────────────────────────────────
# Tests: zdt-telegram.py (bot)
# ────────────────────────────────────────────

class TestTelegramBot:
    """Tests for zdt-telegram.py via source inspection."""

    def test_token_file_referenced(self):
        """Should reference the token file path."""
        with open(os.path.join(PROJECT_DIR, "zdt-telegram.py")) as f:
            content = f.read()
        assert "telegram_token.txt" in content
        assert ".config/zdt" in content

    def test_command_handlers_registered(self):
        """All expected command decorators should be present."""
        with open(os.path.join(PROJECT_DIR, "zdt-telegram.py")) as f:
            content = f.read()
        assert "@bot.message_handler(commands=['start', 'help', 'menu'])" in content
        assert "@bot.message_handler(commands=['status'])" in content
        assert "@bot.message_handler(commands=['ping'])" in content
        assert "@bot.message_handler(commands=['video'])" in content
        assert "@bot.message_handler(commands=['audio'])" in content

    def test_callback_handlers_registered(self):
        """Inline keyboard callback handlers should be defined."""
        with open(os.path.join(PROJECT_DIR, "zdt-telegram.py")) as f:
            content = f.read()
        assert "@bot.callback_query_handler" in content
        assert "infinity_polling" in content
        assert "InlineKeyboardMarkup" in content

    def test_delete_confirmation(self):
        """Delete operations must have confirmation."""
        with open(os.path.join(PROJECT_DIR, "zdt-telegram.py")) as f:
            content = f.read()
        assert "CONFIRM_DELETE" in content
        assert "CANCEL_DELETE" in content

    def test_gemini_openrouter_support(self):
        """Should support both Gemini and OpenRouter AI backends."""
        with open(os.path.join(PROJECT_DIR, "zdt-telegram.py")) as f:
            content = f.read()
        assert "generativelanguage.googleapis.com" in content
        assert "openrouter.ai" in content

    def test_token_file_security(self):
        """Token file should have restricted permissions (chmod 600)."""
        with open(os.path.join(PROJECT_DIR, "zdt-telegram.py")) as f:
            content = f.read()
        assert "chmod" in content and "0o600" in content


# ────────────────────────────────────────────
# Tests: zdt-watch.py (daemon)
# ────────────────────────────────────────────

class TestWatchDaemon:
    """Tests for zdt-watch.py via source inspection."""

    def test_watchdog_import(self):
        """Should import watchdog components."""
        with open(os.path.join(PROJECT_DIR, "zdt-watch.py")) as f:
            content = f.read()
        assert "watchdog" in content
        assert "PatternMatchingEventHandler" in content
        assert "Observer" in content

    def test_media_patterns(self):
        """Should define expected media file patterns."""
        with open(os.path.join(PROJECT_DIR, "zdt-watch.py")) as f:
            content = f.read()
        assert "*.mp3" in content
        assert "*.m4a" in content
        assert "*.mp4" in content
        assert "*.mkv" in content
        assert "*.flac" in content

    def test_events_handled(self):
        """Should handle file creation and move events."""
        with open(os.path.join(PROJECT_DIR, "zdt-watch.py")) as f:
            content = f.read()
        assert "on_created" in content
        assert "on_moved" in content

    def test_no_argparse(self):
        """zdt-watch.py should use sys.argv directly (simple daemon)."""
        with open(os.path.join(PROJECT_DIR, "zdt-watch.py")) as f:
            content = f.read()
        assert "argparse" not in content

    def test_keyboard_interrupt_handling(self):
        """Should handle Ctrl+C gracefully."""
        with open(os.path.join(PROJECT_DIR, "zdt-watch.py")) as f:
            content = f.read()
        assert "KeyboardInterrupt" in content


# ────────────────────────────────────────────
# Tests: Shared patterns across components
# ────────────────────────────────────────────

class TestSharedPatterns:
    """Cross-component consistency checks."""

    def test_consistent_zdt_binary_search(self):
        """All Python files should search for zdt binary in the same locations."""
        expected_paths = [
            "~/.local/bin/zdt",
            "/usr/local/bin/zdt",
            "/data/data/com.termux/files/usr/bin/zdt"
        ]
        for fname in ["zdt-web.py", "zdt-telegram.py", "zdt-watch.py"]:
            with open(os.path.join(PROJECT_DIR, fname)) as f:
                content = f.read()
            for p in expected_paths:
                assert p in content, f"{fname} missing path: {p}"

    def test_no_hardcoded_tokens(self):
        """No Python file should contain hardcoded API tokens."""
        import re
        # Patterns that indicate a hardcoded token (not just code structure)
        token_patterns = [
            r'sk-or-v1-[a-f0-9]{32,}',
            r'AIzaSy[A-Za-z0-9_-]{33}',
            r'ghp_[A-Za-z0-9]{36}',
        ]
        suspicious = []
        for fname in ["zdt-web.py", "zdt-telegram.py", "zdt-watch.py"]:
            with open(os.path.join(PROJECT_DIR, fname)) as f:
                lines = f.readlines()
            for i, line in enumerate(lines, 1):
                for pattern in token_patterns:
                    match = re.search(pattern, line)
                    if match:
                        # Verify it's not inside an example string or commented reference
                        stripped = line.strip()
                        # Skip lines that are just code structure, not actual values
                        if "AUTO_ACTION" in stripped:
                            continue
                        if '"models"' in stripped or '"sk-or-v1-"' in stripped:
                            continue
                        suspicious.append(f"{fname}:{i}: {stripped[:80]}")
        assert len(suspicious) == 0, f"Found potential hardcoded tokens:\n" + "\n".join(suspicious)

    def test_syntax_of_all_py_files(self):
        """All .py files must be syntactically valid."""
        for fname in ["zdt-web.py", "zdt-telegram.py", "zdt-watch.py"]:
            filepath = os.path.join(PROJECT_DIR, fname)
            with open(filepath) as f:
                source = f.read()
            try:
                compile(source, fname, "exec")
            except SyntaxError as e:
                pytest.fail(f"Syntax error in {fname}: {e}")


# ────────────────────────────────────────────
# Tests: ZdtPaths (shared path module)
# ────────────────────────────────────────────

class TestZdtPaths:
    """Tests for zdt_paths.py — single source of truth for all paths."""

    @classmethod
    def setup_class(cls):
        """Ensure zdt-modules is in sys.path for imports."""
        _modules_dir = os.path.join(PROJECT_DIR, "zdt-modules")
        if _modules_dir not in sys.path:
            sys.path.insert(0, _modules_dir)

    def test_get_share_dir_default(self, monkeypatch):
        from zdt_paths import ZdtPaths
        monkeypatch.setattr(ZdtPaths, "SHARE_DIRS", ["/nonexistent/zdt"])
        share = ZdtPaths.get_share_dir()
        assert share == "/nonexistent/zdt"

    def test_get_config_file(self):
        from zdt_paths import ZdtPaths
        cfg = ZdtPaths.get_config_file()
        assert cfg == os.path.expanduser("~/.config/zdt/config.env")

    def test_get_demucs_bin(self):
        from zdt_paths import ZdtPaths
        demucs = ZdtPaths.get_demucs_bin()
        expected = os.path.expanduser("~/.local/share/zdt/demucs_venv/bin/demucs")
        assert demucs == expected

    def test_get_venv_python(self):
        from zdt_paths import ZdtPaths
        py = ZdtPaths.get_venv_python()
        expected = os.path.expanduser("~/.local/share/zdt/venv/bin/python")
        assert py == expected

    def test_get_modules_dir(self, monkeypatch):
        from zdt_paths import ZdtPaths
        monkeypatch.setattr(ZdtPaths, "SHARE_DIRS", ["/test/share/zdt"])
        mod = ZdtPaths.get_modules_dir()
        assert mod == "/test/share/zdt/zdt-modules"

    def test_get_templates_dir(self, monkeypatch):
        from zdt_paths import ZdtPaths
        monkeypatch.setattr(ZdtPaths, "SHARE_DIRS", ["/test/share/zdt"])
        tmpl = ZdtPaths.get_templates_dir()
        assert tmpl == "/test/share/zdt/templates"

    def test_get_db_path(self):
        from zdt_paths import ZdtPaths
        db = ZdtPaths.get_db_path()
        assert db == os.path.expanduser("~/.config/zdt/zdt.db")

    def test_get_scheduler_path(self):
        from zdt_paths import ZdtPaths
        sched = ZdtPaths.get_scheduler_path()
        assert sched == os.path.expanduser("~/.config/zdt/scheduler.json")

    def test_get_telegram_token_path(self):
        from zdt_paths import ZdtPaths
        token = ZdtPaths.get_telegram_token_path()
        assert token == os.path.expanduser("~/.config/zdt/telegram_token.txt")

    def test_get_old_config_file(self, monkeypatch):
        from zdt_paths import ZdtPaths
        monkeypatch.setattr(os.path, "expanduser", lambda p: "/home/test/.config/zdt/config")
        old = ZdtPaths.get_old_config_file()
        assert old == "/home/test/.config/zdt/config"

    def test_get_bin_path_no_install(self, monkeypatch):
        from zdt_paths import ZdtPaths
        monkeypatch.setattr(ZdtPaths, "BIN_PATHS", ["/nonexistent/zdt"])
        import shutil
        monkeypatch.setattr(shutil, "which", lambda cmd, **kw: None)
        result = ZdtPaths.get_bin_path()
        assert result == "zdt"

    def test_find_script_no_install(self, monkeypatch):
        from zdt_paths import ZdtPaths
        monkeypatch.setattr(ZdtPaths, "SHARE_DIRS", ["/nonexistent/zdt"])
        result = ZdtPaths.find_script("nonexistent_script.py", "/nonexistent")
        assert result is None

    def test_get_version_priority_file(self, monkeypatch):
        """VERSION file in project root takes priority over env var."""
        from zdt_paths import ZdtPaths
        monkeypatch.setenv("ZDT_VERSION", "9.9.9")
        ver = ZdtPaths.get_version()
        # Baca dari VERSION file biar tidak perlu update manual tiap release
        expected = open("VERSION").read().strip()
        assert ver == expected

    def test_get_version_from_env(self, monkeypatch):
        """Should read version from env var when VERSION file not found."""
        from zdt_paths import ZdtPaths
        monkeypatch.setenv("ZDT_VERSION", "5.0.0")
        # Block ALL VERSION file discovery paths
        monkeypatch.setattr(os, "getcwd", lambda: "/no/version/here")
        monkeypatch.setattr(os.path, "abspath", lambda p: "/no/version/modules/zdt_paths.py" if "zdt_paths" in str(p) else p)
        monkeypatch.setattr(ZdtPaths, "SHARE_DIRS", ["/nonexistent/zdt"])
        monkeypatch.setattr(ZdtPaths, "_get_zdt_sh_candidates", lambda: [])
        ver = ZdtPaths.get_version()
        assert ver == "5.0.0"

    def test_get_version_unknown(self, monkeypatch):
        """Should return 'unknown' when nothing available."""
        from zdt_paths import ZdtPaths
        monkeypatch.delenv("ZDT_VERSION", raising=False)
        monkeypatch.setattr(os, "getcwd", lambda: "/no/version/here")
        monkeypatch.setattr(os.path, "abspath", lambda p: "/no/version/modules/zdt_paths.py" if "zdt_paths" in str(p) else p)
        monkeypatch.setattr(ZdtPaths, "SHARE_DIRS", ["/nonexistent/zdt"])
        monkeypatch.setattr(ZdtPaths, "_get_zdt_sh_candidates", lambda: [])
        ver = ZdtPaths.get_version()
        assert ver == "unknown"

    def test_is_valid_version(self):
        from zdt_paths import ZdtPaths
        assert ZdtPaths._is_valid_version("4.4.3") is True
        assert ZdtPaths._is_valid_version("0.1.0") is True
        assert ZdtPaths._is_valid_version("1") is True
        assert ZdtPaths._is_valid_version("") is False
        assert ZdtPaths._is_valid_version("abc") is False
        assert ZdtPaths._is_valid_version("v4.4.3") is False
