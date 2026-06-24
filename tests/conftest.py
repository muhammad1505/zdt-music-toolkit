#!/usr/bin/env python3
"""
Pytest conftest for ZDT tests.
Provides shared mock infrastructure, fixtures, and import helpers for testing Python components.
"""
import json
import os
import sys
import types
import importlib.util
import pytest

PROJECT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


# ════════════════════════════════════════════
# Shared Mock Classes for zdt-web.py testing
# ════════════════════════════════════════════

class MockTestResponse:
    """Mock Flask Response object."""
    def __init__(self, data, status_code=200, headers=None):
        self.data = data.encode() if isinstance(data, str) else data
        self.status_code = status_code
        self.headers = headers or {}

    def get_json(self):
        try:
            return json.loads(self.data)
        except Exception:
            return {"raw": self.data.decode()}


class MockHeaders(dict):
    """Mock request.headers supporting .get() like Flask."""
    def get(self, key, default=None):
        return super().get(key, default)


class MockAuth:
    username = "admin"
    password = "admin"


class MockPopenResult:
    returncode = 0
    stdout = ""
    stderr = ""


class MockPopen:
    def __init__(self, *args, **kwargs):
        pass
    def __enter__(self):
        return self
    def __exit__(self, *args):
        pass
    def communicate(self):
        return ("", "")
    def wait(self):
        return 0


class MockFlask:
    """Mock Flask application class."""
    def __init__(self, name, **kwargs):
        self.name = name
        self._routes = {}

    def route(self, rule, **options):
        methods = options.get("methods", ["GET"])
        def decorator(f):
            for m in methods:
                self._routes.setdefault(rule, {})[m] = f
            return f
        return decorator

    def before_request(self, f):
        return f

    def errorhandler(self, code_or_exception):
        def decorator(f):
            return f
        return decorator

    def test_client(self):
        return MockTestClient(self)

    def run(self, **kwargs):
        pass


class MockTestClient:
    """Simple mock Flask test client for business logic tests."""
    def __init__(self, app_ref):
        self.app = app_ref

    def __enter__(self):
        return self

    def __exit__(self, *args):
        pass

    def get(self, path):
        route = self.app._routes.get(path, {})
        handler = route.get("GET")
        if handler is None:
            return MockTestResponse("Not Found", 404)
        try:
            self.app._request.method = "GET"
            result = handler()
            status = 200
            if isinstance(result, tuple):
                result, status = result[0], result[1]
            if isinstance(result, MockTestResponse):
                return result
            if isinstance(result, (dict, list)):
                return MockTestResponse(json.dumps(result), status)
            return MockTestResponse(result or "OK", status)
        except Exception as e:
            return MockTestResponse(f"500: {type(e).__name__}: {e}", 500)

    def post(self, path, json_data=None):
        route = self.app._routes.get(path, {})
        handler = route.get("POST")
        if handler is None:
            return MockTestResponse("Not Found", 404)
        try:
            if hasattr(self.app, '_request'):
                self.app._request.method = "POST"
                self.app._request.json = json_data or {}
            result = handler()
            status = 200
            if isinstance(result, tuple):
                result, status = result[0], result[1]
            if isinstance(result, MockTestResponse):
                return result
            if isinstance(result, (dict, list)):
                return MockTestResponse(json.dumps(result), status)
            return MockTestResponse(result or "OK", status)
        except Exception as e:
            import traceback
            tb = traceback.format_exc()
            return MockTestResponse(f"500: {type(e).__name__}: {e}\n{tb}", 500)


class MockRequest:
    """Mock Flask request object."""
    def __init__(self, headers_dict=None):
        self.json = {}
        self.method = "GET"
        self.authorization = MockAuth()
        self.remote_addr = "127.0.0.1"
        self.headers = MockHeaders(headers_dict or {})


def _mock_missing_deps():
    """Mock optional dependencies that may not be installed."""
    deps = {
        "flask": ["flask"],
        "telebot": ["telebot", "telebot.types"],
        "watchdog": ["watchdog", "watchdog.observers", "watchdog.events"],
        "mutagen": ["mutagen", "mutagen.easyid3", "mutagen.mp4", "mutagen.flac", "mutagen.id3"],
    }
    for mod_name, submodules in deps.items():
        try:
            __import__(mod_name)
        except ImportError:
            mock_mod = types.ModuleType(mod_name)
            mock_mod.__path__ = []
            sys.modules[mod_name] = mock_mod
            for sub in submodules:
                try:
                    __import__(sub)
                except ImportError:
                    sub_parts = sub.split(".")
                    parent = sys.modules.get(sub_parts[0], mock_mod)
                    for i in range(1, len(sub_parts)):
                        sub_mod = types.ModuleType(".".join(sub_parts[:i+1]))
                        setattr(parent, sub_parts[i], sub_mod)
                        sys.modules[".".join(sub_parts[:i+1])] = sub_mod


def import_module_from_file(name, filepath):
    """Import a .py file as a module by path with dependency mocking."""
    _mock_missing_deps()
    spec = importlib.util.spec_from_file_location(name, filepath)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


# ════════════════════════════════════════════
# Shared helper: Create mock Flask module
# ════════════════════════════════════════════

def _create_mock_flask_module(headers_dict=None):
    """
    Create a mock 'flask' module with all needed classes.
    Returns (flask_mod, request_obj) where flask_mod can be placed in sys.modules.
    """
    flask_mod = types.ModuleType("flask")
    flask_mod.Flask = MockFlask
    flask_mod.request = MockRequest(headers_dict or {})
    flask_mod.render_template_string = lambda s, **kw: s
    flask_mod.render_template = lambda s, **kw: s
    flask_mod.jsonify = lambda *args, **kw: args[0] if args else kw
    flask_mod.Response = MockTestResponse
    return flask_mod


class WebTestEnv:
    """
    Context manager for zdt-web.py test environment.
    Sets up all mocks and restores originals on exit.
    """
    def __init__(self, module_name="zdt_web_test", argv=None, headers_dict=None):
        self.module_name = module_name
        self.argv = argv or ["zdt-web.py", "--bind", "127.0.0.1", "--port", "5000"]
        self.headers_dict = headers_dict
        self._originals = {}
        self._tmp_home = None

    def __enter__(self):
        import shutil
        import subprocess
        import glob as glob_mod
        import tempfile

        self._originals = {
            "argv": sys.argv.copy(),
            "expanduser": os.path.expanduser,
            "disk_usage": shutil.disk_usage,
            "which": shutil.which,
            "popen": subprocess.Popen,
            "run": subprocess.run,
            "glob": glob_mod.glob,
        }

        sys.argv = self.argv

        # 1) Mock home directory
        self._tmp_home = tempfile.mkdtemp()
        os.path.expanduser = lambda p: str(self._tmp_home + p.replace("~", "").lstrip("/"))
        _music_dir = os.path.join(self._tmp_home, "Music", "ZDT_Downloads")
        os.makedirs(_music_dir, exist_ok=True)

        # 2) Mock shutil
        shutil.disk_usage = lambda p: (500 * 2**30, 200 * 2**30, 300 * 2**30)
        shutil.which = lambda cmd, **kw: "/usr/local/bin/zdt" if cmd == "zdt" else self._originals["which"](cmd, **kw)

        # 3) Mock subprocess
        subprocess.Popen = MockPopen
        subprocess.run = lambda *a, **kw: MockPopenResult()

        # 4) Mock glob
        glob_mod.glob = lambda p: []

        # 5) Mock mutagen
        sys.modules["mutagen"] = types.ModuleType("mutagen")
        sys.modules["mutagen.easyid3"] = types.ModuleType("mutagen.easyid3")
        sys.modules["mutagen.mp4"] = types.ModuleType("mutagen.mp4")
        sys.modules["mutagen.flac"] = types.ModuleType("mutagen.flac")
        sys.modules["mutagen.id3"] = types.ModuleType("mutagen.id3")

        # 6) Mock Flask module
        self.flask_mod = _create_mock_flask_module(self.headers_dict)
        sys.modules["flask"] = self.flask_mod

        # 7) Import zdt-web.py
        spec = importlib.util.spec_from_file_location(
            self.module_name,
            os.path.join(PROJECT_DIR, "zdt-web.py")
        )
        self.mod = importlib.util.module_from_spec(spec)
        sys.modules[self.module_name] = self.mod
        spec.loader.exec_module(self.mod)
        # Save original check_auth before override (needed by test_web_config.py)
        self.mod._original_check_auth = self.mod.check_auth
        self.mod.check_auth = lambda u, p: True
        self.mod.app._request = self.flask_mod.request

        return self

    def __exit__(self, *args):
        import shutil
        import subprocess
        import glob as glob_mod

        sys.argv = self._originals["argv"]
        os.path.expanduser = self._originals["expanduser"]
        shutil.disk_usage = self._originals["disk_usage"]
        shutil.which = self._originals["which"]
        subprocess.Popen = self._originals["popen"]
        subprocess.run = self._originals["run"]
        glob_mod.glob = self._originals["glob"]


# ════════════════════════════════════════════
# Pytest fixtures
# ════════════════════════════════════════════

@pytest.fixture
def mock_home(tmp_path):
    """Fixture that sets up a mock home directory."""
    import os
    original_expanduser = os.path.expanduser
    def _mock_expanduser(p):
        return str(tmp_path / p.replace("~", "").lstrip("/"))
    os.path.expanduser = _mock_expanduser
    yield tmp_path
    os.path.expanduser = original_expanduser


@pytest.fixture
def mock_disk_usage(monkeypatch):
    """Fixture that mocks shutil.disk_usage."""
    import shutil
    monkeypatch.setattr(shutil, "disk_usage", lambda p: (100 * 2**30, 50 * 2**30, 50 * 2**30))
