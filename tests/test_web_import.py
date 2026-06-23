#!/usr/bin/env python3
"""
Import-based tests for zdt-web.py.
Actually imports the module with proper Flask mocking to get real coverage data.
"""
import os
import sys
import types
import json
import pytest

PROJECT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


# ────────────────────────────────────────────
# Fixture: Import zdt-web.py with mocking
# ────────────────────────────────────────────

@pytest.fixture(scope="module")
def web_app():
    """Import zdt-web.py with mocked dependencies and return the Flask app."""
    orig_argv = sys.argv.copy()
    sys.argv = ["zdt-web.py", "--bind", "127.0.0.1", "--port", "5000"]

    # ── Mock all heavy dependencies ──

    import shutil
    import subprocess
    import glob as glob_mod
    import tempfile

    # 1) Mock home directory
    _tmp_home = tempfile.mkdtemp()
    _orig_expanduser = os.path.expanduser
    os.path.expanduser = lambda p: str(_tmp_home + p.replace("~", "").lstrip("/"))

    # Create Music dir
    _music_dir = os.path.join(_tmp_home, "Music", "ZDT_Downloads")
    os.makedirs(_music_dir, exist_ok=True)

    # 2) Mock shutil
    _orig_disk_usage = shutil.disk_usage
    shutil.disk_usage = lambda p: (500 * 2**30, 200 * 2**30, 300 * 2**30)

    _orig_which = shutil.which
    shutil.which = lambda cmd, **kw: "/usr/local/bin/zdt" if cmd == "zdt" else _orig_which(cmd, **kw)

    # 3) Mock subprocess
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

    _orig_popen = subprocess.Popen
    subprocess.Popen = MockPopen
    _orig_run = subprocess.run
    subprocess.run = lambda *a, **kw: MockPopenResult()

    # 4) Mock glob
    _orig_glob = glob_mod.glob
    glob_mod.glob = lambda p: []

    # 5) Mock mutagen (optional dep)
    mutagen_mod = types.ModuleType("mutagen")
    sys.modules["mutagen"] = mutagen_mod
    sys.modules["mutagen.easyid3"] = types.ModuleType("mutagen.easyid3")
    sys.modules["mutagen.mp4"] = types.ModuleType("mutagen.mp4")
    sys.modules["mutagen.flac"] = types.ModuleType("mutagen.flac")
    sys.modules["mutagen.id3"] = types.ModuleType("mutagen.id3")

    # 6) Mock Flask
    class MockTestResponse:
        def __init__(self, data, status_code=200, headers=None):
            self.data = data.encode() if isinstance(data, str) else data
            self.status_code = status_code
            self.headers = headers or {}

        def get_json(self):
            try:
                return json.loads(self.data)
            except Exception:
                return {"raw": self.data.decode()}

    class MockTestClient:
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

    class MockFlask:
        def __init__(self, name):
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

    class MockAuth:
        username = "admin"
        password = "admin"

    class MockHeaders(dict):
        """Mock request.headers object that supports .get() like Flask."""
        def get(self, key, default=None):
            return super().get(key, default)

    class MockRequest:
        json = {}
        authorization = MockAuth()
        remote_addr = "127.0.0.1"
        headers = MockHeaders({"X-CSRF-Token": "test-csrf-token-123"})

    flask_mod = types.ModuleType("flask")
    flask_mod.Flask = MockFlask
    flask_mod.request = MockRequest()
    flask_mod.render_template_string = lambda s, **kw: s
    flask_mod.jsonify = lambda *args, **kw: args[0] if args else kw
    flask_mod.Response = MockTestResponse
    sys.modules["flask"] = flask_mod

    # ── Import zdt-web.py ──
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "zdt_web_test",
        os.path.join(PROJECT_DIR, "zdt-web.py")
    )
    mod = importlib.util.module_from_spec(spec)
    sys.modules["zdt_web_test"] = mod
    spec.loader.exec_module(mod)
    mod.check_auth = lambda u, p: True

    # Patch CSRF validation for testing (business logic tests, not CSRF mechanism tests)
    mod._validate_csrf_token = lambda token: True

    # Store request mock on the app so post() can set json
    mod.app._request = flask_mod.request

    yield mod.app

    # ── Cleanup ──
    sys.argv = orig_argv
    os.path.expanduser = _orig_expanduser
    shutil.disk_usage = _orig_disk_usage
    shutil.which = _orig_which
    subprocess.Popen = _orig_popen
    subprocess.run = _orig_run
    glob_mod.glob = _orig_glob


# ────────────────────────────────────────────
# Tests: Flask routes
# ────────────────────────────────────────────

class TestWebImportRoutes:
    """Tests that actually import zdt-web.py and exercise Flask routes."""

    def test_app_created(self, web_app):
        assert web_app is not None

    def test_index_route(self, web_app):
        with web_app.test_client() as client:
            resp = client.get("/")
            assert resp.status_code == 200, f"Got {resp.status_code}: {resp.get_json()}"

    def test_status_api(self, web_app):
        with web_app.test_client() as client:
            resp = client.get("/api/status")
            assert resp.status_code == 200, f"Got {resp.status_code}: {resp.get_json()}"
            data = resp.get_json()
            assert "storage_free" in data
            assert "watcher" in data
            assert "telegram" in data

    def test_files_api(self, web_app):
        with web_app.test_client() as client:
            resp = client.get("/api/files")
            assert resp.status_code == 200, f"Got {resp.status_code}: {resp.get_json()}"
            data = resp.get_json()
            assert "files" in data

    def test_logs_api(self, web_app):
        with web_app.test_client() as client:
            resp = client.get("/api/logs")
            assert resp.status_code == 200, f"Got {resp.status_code}: {resp.get_json()}"
            data = resp.get_json()
            assert "log" in data

    def test_download_api_empty_url(self, web_app):
        with web_app.test_client() as client:
            resp = client.post("/api/download", json_data={"url": "", "format": "audio", "spec": "1"})
            assert resp.status_code == 200, f"Got {resp.status_code}: {resp.get_json()}"
            data = resp.get_json()
            assert data.get("success") is False

    def test_download_api_with_url(self, web_app):
        with web_app.test_client() as client:
            resp = client.post("/api/download", json_data={
                "url": "https://youtube.com/watch?v=test",
                "format": "audio",
                "spec": "1"
            })
            assert resp.status_code == 200, f"Got {resp.status_code}: {resp.get_json()}"
            data = resp.get_json()
            assert data.get("success") is True

    def test_spotify_sync_empty(self, web_app):
        with web_app.test_client() as client:
            resp = client.post("/api/spotify-sync", json_data={"url": ""})
            assert resp.status_code == 200, f"Got {resp.status_code}: {resp.get_json()}"
            data = resp.get_json()
            assert data.get("success") is False

    def test_spotify_sync_with_url(self, web_app):
        with web_app.test_client() as client:
            resp = client.post("/api/spotify-sync", json_data={
                "url": "https://open.spotify.com/playlist/test"
            })
            assert resp.status_code == 200, f"Got {resp.status_code}: {resp.get_json()}"
            data = resp.get_json()
            assert data.get("success") is True

    def test_tools_clean(self, web_app):
        with web_app.test_client() as client:
            resp = client.post("/api/tools", json_data={"action": "clean"})
            assert resp.status_code == 200, f"Got {resp.status_code}: {resp.get_json()}"
            data = resp.get_json()
            assert "success" in data

    def test_tools_playlist(self, web_app):
        with web_app.test_client() as client:
            resp = client.post("/api/tools", json_data={"action": "playlist"})
            assert resp.status_code == 200, f"Got {resp.status_code}: {resp.get_json()}"
            data = resp.get_json()
            assert "success" in data

    def test_tools_invalid_action(self, web_app):
        with web_app.test_client() as client:
            resp = client.post("/api/tools", json_data={"action": "invalid_action_xyz"})
            assert resp.status_code == 200, f"Got {resp.status_code}: {resp.get_json()}"
            data = resp.get_json()
            assert data.get("success") is False

    def test_metadata_no_file(self, web_app):
        with web_app.test_client() as client:
            resp = client.post("/api/metadata", json_data={"filename": ""})
            assert resp.status_code == 200, f"Got {resp.status_code}: {resp.get_json()}"
            data = resp.get_json()
            assert data.get("success") is False
