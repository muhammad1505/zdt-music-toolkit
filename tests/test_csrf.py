#!/usr/bin/env python3
"""
CSRF integration tests for zdt-web.py.
Tests the CSRF token mechanism WITHOUT patching _validate_csrf_token,
so we can validate that the real token flow works end-to-end.
"""
import os
import sys
import types
import json
import pytest

PROJECT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


@pytest.fixture(scope="module")
def csrf_app():
    """Import zdt-web.py with mocked deps but WITHOUT patching CSRF validation."""
    orig_argv = sys.argv.copy()
    sys.argv = ["zdt-web.py", "--bind", "127.0.0.1", "--port", "5000"]

    import shutil
    import subprocess
    import glob as glob_mod
    import tempfile

    # Mock home directory
    _tmp_home = tempfile.mkdtemp()
    _orig_expanduser = os.path.expanduser
    os.path.expanduser = lambda p: str(_tmp_home + p.replace("~", "").lstrip("/"))

    _music_dir = os.path.join(_tmp_home, "Music", "ZDT_Downloads")
    os.makedirs(_music_dir, exist_ok=True)

    # Mock shutil
    _orig_disk_usage = shutil.disk_usage
    shutil.disk_usage = lambda p: (500 * 2**30, 200 * 2**30, 300 * 2**30)

    _orig_which = shutil.which
    shutil.which = lambda cmd, **kw: "/usr/local/bin/zdt" if cmd == "zdt" else _orig_which(cmd, **kw)

    # Mock subprocess
    class MockPopenResult:
        returncode = 0
        stdout = ""
        stderr = ""

    class MockPopen:
        def __init__(self, *args, **kwargs): pass
        def __enter__(self): return self
        def __exit__(self, *args): pass
        def communicate(self): return ("", "")
        def wait(self): return 0

    _orig_popen = subprocess.Popen
    subprocess.Popen = MockPopen
    _orig_run = subprocess.run
    subprocess.run = lambda *a, **kw: MockPopenResult()

    # Mock glob
    _orig_glob = glob_mod.glob
    glob_mod.glob = lambda p: []

    # Mock mutagen
    sys.modules["mutagen"] = types.ModuleType("mutagen")
    sys.modules["mutagen.easyid3"] = types.ModuleType("mutagen.easyid3")
    sys.modules["mutagen.mp4"] = types.ModuleType("mutagen.mp4")
    sys.modules["mutagen.flac"] = types.ModuleType("mutagen.flac")
    sys.modules["mutagen.id3"] = types.ModuleType("mutagen.id3")

    # Mock Flask
    class MockTestResponse:
        def __init__(self, data, status_code=200, headers=None):
            self.data = data.encode() if isinstance(data, str) else data
            self.status_code = status_code
            self.headers = headers or {}
        def get_json(self):
            try: return json.loads(self.data)
            except: return {"raw": self.data.decode()}

    class MockHeaders(dict):
        def get(self, key, default=None):
            return super().get(key, default)

    class MockRequest:
        json = {}
        authorization = type("MockAuth", (), {"username": "admin", "password": "admin"})()
        remote_addr = "127.0.0.1"
        headers = MockHeaders({})

    class MockTestClient:
        def __init__(self, app_ref, mod_ref):
            self.app = app_ref
            self.mod = mod_ref
            self._csrf_token = None

        def __enter__(self): return self
        def __exit__(self, *args): pass

        def _refresh_csrf(self):
            """Fetch a fresh CSRF token from the app."""
            route = self.app._routes.get("/api/csrf-token", {})
            handler = route.get("GET")
            if handler:
                if hasattr(self.app, '_request'):
                    self.app._request.headers = MockHeaders({})
                result = handler()
                if isinstance(result, dict) and "csrf_token" in result:
                    self._csrf_token = result["csrf_token"]

        def get(self, path):
            route = self.app._routes.get(path, {})
            handler = route.get("GET")
            if handler is None:
                return MockTestResponse("Not Found", 404)
            try:
                if hasattr(self.app, '_request'):
                    self.app._request.json = {}
                    self.app._request.headers = MockHeaders({})
                result = handler()
                if isinstance(result, tuple):
                    result, status = result[0], result[1]
                    if isinstance(result, MockTestResponse):
                        return result
                    return MockTestResponse(json.dumps(result), status)
                if isinstance(result, MockTestResponse):
                    return result
                return MockTestResponse(json.dumps(result) if isinstance(result, (dict, list)) else (result or "OK"), 200)
            except Exception as e:
                return MockTestResponse(f"500: {type(e).__name__}: {e}", 500)

        def post(self, path, json_data=None, use_csrf=True):
            route = self.app._routes.get(path, {})
            handler = route.get("POST")
            if handler is None:
                return MockTestResponse("Not Found", 404)
            try:
                req = self.app._request
                req.json = json_data or {}

                if use_csrf:
                    self._refresh_csrf()
                    token = self._csrf_token or ""
                    req.headers = MockHeaders({"X-CSRF-Token": token})
                else:
                    req.headers = MockHeaders({})

                result = handler()
                if isinstance(result, tuple):
                    result, status = result[0], result[1]
                    if isinstance(result, MockTestResponse):
                        return result
                    return MockTestResponse(json.dumps(result), status)
                if isinstance(result, MockTestResponse):
                    return result
                return MockTestResponse(json.dumps(result) if isinstance(result, (dict, list)) else (result or "OK"), 200)
            except Exception as e:
                import traceback
                return MockTestResponse(f"500: {type(e).__name__}: {e}\n{traceback.format_exc()}", 500)

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
        def before_request(self, f): return f
        def errorhandler(self, code_or_exception):
            def decorator(f): return f
            return decorator
        def test_client(self):
            return MockTestClient(self, None)
        def run(self, **kwargs): pass

    flask_mod = types.ModuleType("flask")
    flask_mod.Flask = MockFlask
    flask_mod.request = MockRequest()
    flask_mod.render_template_string = lambda s, **kw: s
    flask_mod.jsonify = lambda *args, **kw: args[0] if args else kw
    flask_mod.Response = MockTestResponse
    sys.modules["flask"] = flask_mod

    # Import zdt-web.py (NO CSRF patch!)
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "zdt_web_csrf_test",
        os.path.join(PROJECT_DIR, "zdt-web.py")
    )
    mod = importlib.util.module_from_spec(spec)
    sys.modules["zdt_web_csrf_test"] = mod
    spec.loader.exec_module(mod)
    mod.check_auth = lambda u, p: True

    # Build a proper test client that has access to the module
    class CsrfTestClient(MockTestClient):
        def __init__(self, app_ref, mod_ref):
            super().__init__(app_ref, mod_ref)
            self.mod = mod_ref

    mod.app._request = flask_mod.request
    mod.app.test_client = lambda: CsrfTestClient(mod.app, mod)

    yield mod.app, mod

    # Cleanup
    sys.argv = orig_argv
    os.path.expanduser = _orig_expanduser
    shutil.disk_usage = _orig_disk_usage
    shutil.which = _orig_which
    subprocess.Popen = _orig_popen
    subprocess.run = _orig_run
    glob_mod.glob = _orig_glob


class TestCsrfMechanism:
    """Tests the real CSRF token flow without patching."""

    def test_csrf_token_endpoint(self, csrf_app):
        """GET /api/csrf-token should return a valid token."""
        app, mod = csrf_app
        with app.test_client() as client:
            resp = client.get("/api/csrf-token")
            assert resp.status_code == 200, f"Got {resp.status_code}"
            data = resp.get_json()
            assert "csrf_token" in data
            token = data["csrf_token"]
            assert len(token) > 20
            # Token should be in the store
            assert token in mod._csrf_tokens

    def test_post_without_csrf_returns_403(self, csrf_app):
        """POST to a state-changing endpoint without CSRF token should fail."""
        app, mod = csrf_app
        with app.test_client() as client:
            resp = client.post("/api/download", json_data={"url": "https://youtube.com/test"}, use_csrf=False)
            assert resp.status_code == 403, f"Got {resp.status_code}: {resp.get_json()}"
            data = resp.get_json()
            assert data.get("success") is False
            assert "CSRF" in data.get("message", "")

    def test_post_with_valid_csrf_succeeds(self, csrf_app):
        """POST with a valid CSRF token should succeed."""
        app, mod = csrf_app
        with app.test_client() as client:
            resp = client.post("/api/download", json_data={"url": "", "format": "audio", "spec": "1"}, use_csrf=True)
            assert resp.status_code == 200, f"Got {resp.status_code}: {resp.get_json()}"
            data = resp.get_json()
            assert data.get("success") is False  # Empty URL = failure but not CSRF failure
            assert "URL" in data.get("message", "")

    def test_csrf_flow_multiple_requests(self, csrf_app):
        """Multiple sequential requests each with fresh CSRF tokens should all succeed."""
        app, mod = csrf_app
        with app.test_client() as client:
            # Make 3 sequential POST requests, each getting a fresh token
            for i in range(3):
                resp = client.post("/api/download", json_data={"url": ""}, use_csrf=True)
                assert resp.status_code == 200, f"Request {i} failed: {resp.get_json()}"
                data = resp.get_json()
                # Should not be a CSRF error
                assert "CSRF" not in data.get("message", ""), f"CSRF error on request {i}: {data}"


