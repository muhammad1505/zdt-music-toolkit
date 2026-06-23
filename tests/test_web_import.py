#!/usr/bin/env python3
"""
Import-based tests for zdt-web.py.
Actually imports the module with proper Flask mocking to get real coverage data.
Uses shared WebTestEnv from conftest.py to avoid duplicating mock setup.
"""
import pytest

from conftest import WebTestEnv


# ────────────────────────────────────────────
# Fixture: Import zdt-web.py with mocking
# ────────────────────────────────────────────

@pytest.fixture(scope="module")
def web_app():
    """Import zdt-web.py with mocked dependencies using shared WebTestEnv."""
    with WebTestEnv(module_name="zdt_web_test") as env:
        # Patch CSRF validation for testing (business logic, not CSRF mechanism)
        env.mod._validate_csrf_token = lambda token: True
        yield env.mod.app


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
