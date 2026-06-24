#!/usr/bin/env python3
"""
CSRF integration tests for zdt-web.py.
Tests the CSRF token mechanism WITHOUT patching _validate_csrf_token,
so we can validate that the real token flow works end-to-end.
Uses shared WebTestEnv from conftest.py.
"""
import json
import pytest

from conftest import WebTestEnv, MockTestResponse, MockHeaders, MockTestClient


class CsrfTestClient(MockTestClient):
    """Mock test client with CSRF token support for integration tests."""

    def __init__(self, app_ref, mod_ref):
        super().__init__(app_ref)
        self.mod = mod_ref
        self._csrf_token = None

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
                self.app._request.method = "GET"
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
            req.method = "POST"
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


# ────────────────────────────────────────────
# Fixture: Import zdt-web.py without CSRF patch
# ────────────────────────────────────────────

@pytest.fixture(scope="module")
def csrf_app():
    """Import zdt-web.py with mocked deps but WITHOUT patching CSRF validation."""
    with WebTestEnv(module_name="zdt_web_csrf_test") as env:
        # Override test_client to return CsrfTestClient with module access
        env.mod.app.test_client = lambda: CsrfTestClient(env.mod.app, env.mod)
        yield env.mod.app, env.mod


# ────────────────────────────────────────────
# Tests: CSRF mechanism
# ────────────────────────────────────────────

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
            assert data.get("success") is False  # Empty URL = not a CSRF failure
            assert "URL" in data.get("message", "")

    def test_csrf_flow_multiple_requests(self, csrf_app):
        """Multiple sequential requests each with fresh CSRF tokens should all succeed."""
        app, mod = csrf_app
        with app.test_client() as client:
            for i in range(3):
                resp = client.post("/api/download", json_data={"url": ""}, use_csrf=True)
                assert resp.status_code == 200, f"Request {i} failed: {resp.get_json()}"
                data = resp.get_json()
                assert "CSRF" not in data.get("message", ""), f"CSRF error on request {i}: {data}"
