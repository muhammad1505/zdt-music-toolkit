#!/usr/bin/env python3
"""
Tests for zdt-web.py credential management:
- _ensure_password() credential generation & migration
- check_auth() authentication logic (via _original_check_auth from WebTestEnv)
- CSRF token expiry
"""
import os
import time
import pytest


# ────────────────────────────────────────────
# Tests: _ensure_password credential generation
# ────────────────────────────────────────────

class TestEnsurePassword:
    """Test the _ensure_password() function from zdt-web.py."""

    def test_generates_creds_when_file_missing(self, tmp_path):
        """Should generate admin user + random password in new config.env."""
        from conftest import WebTestEnv
        with WebTestEnv(module_name="zdt_web_cred_1") as env:
            cfg = env.mod.CONFIG_FILE
            if os.path.exists(cfg):
                os.remove(cfg)
            env.mod._ensure_password()
            assert os.path.exists(cfg), "config.env should be created"
            with open(cfg, "r") as f:
                content = f.read()
            assert "ZDT_WEB_USER=admin" in content, "Should have admin user"
            assert "ZDT_WEB_PASS=" in content, "Should have password"
            assert "ZDT_WEB_PASS=admin" not in content, "Password should be random"

    def test_migrates_from_old_config(self, tmp_path):
        """Should migrate credentials from old config.conf to config.env."""
        from conftest import WebTestEnv
        with WebTestEnv(module_name="zdt_web_cred_2") as env:
            cfg = env.mod.CONFIG_FILE
            if os.path.exists(cfg):
                os.remove(cfg)
            old_conf = os.path.join(os.path.dirname(cfg), "config.conf")
            os.makedirs(os.path.dirname(old_conf), exist_ok=True)
            with open(old_conf, "w") as f:
                f.write("ZDT_WEB_USER=admin\n")
                f.write("ZDT_WEB_PASS=migrated_pass_123\n")
            env.mod._ensure_password()
            assert os.path.exists(cfg)
            with open(cfg, "r") as f:
                content = f.read()
            assert "ZDT_WEB_USER=admin" in content
            assert "ZDT_WEB_PASS=migrated_pass_123" in content

    def test_preserves_existing_creds(self, tmp_path):
        """Should NOT overwrite existing credentials in config.env."""
        from conftest import WebTestEnv
        with WebTestEnv(module_name="zdt_web_cred_3") as env:
            cfg = env.mod.CONFIG_FILE
            os.makedirs(os.path.dirname(cfg), exist_ok=True)
            with open(cfg, "w") as f:
                f.write("TARGET_DIR=/music\n")
                f.write("ZDT_WEB_USER=myuser\n")
                f.write("ZDT_WEB_PASS=mypass\n")
            env.mod._ensure_password()
            with open(cfg, "r") as f:
                content = f.read()
            assert "ZDT_WEB_USER=myuser" in content
            assert "ZDT_WEB_PASS=mypass" in content

    def test_skips_if_both_creds_exist(self, tmp_path):
        """Should return early if both creds already exist."""
        from conftest import WebTestEnv
        with WebTestEnv(module_name="zdt_web_cred_4") as env:
            cfg = env.mod.CONFIG_FILE
            os.makedirs(os.path.dirname(cfg), exist_ok=True)
            with open(cfg, "w") as f:
                f.write("ZDT_WEB_USER=admin\n")
                f.write("ZDT_WEB_PASS=existing_pass\n")
            env.mod._ensure_password()
            with open(cfg, "r") as f:
                content = f.read()
            assert "ZDT_WEB_PASS=existing_pass" in content

    def test_fills_missing_user_from_old_config(self, tmp_path):
        """Should fill missing user from old config.conf when pass exists in config.env."""
        from conftest import WebTestEnv
        with WebTestEnv(module_name="zdt_web_cred_5") as env:
            cfg = env.mod.CONFIG_FILE
            os.makedirs(os.path.dirname(cfg), exist_ok=True)
            with open(cfg, "w") as f:
                f.write("ZDT_WEB_PASS=somepass\n")
            old_conf = os.path.join(os.path.dirname(cfg), "config.conf")
            with open(old_conf, "w") as f:
                f.write("ZDT_WEB_USER=admin\n")
            env.mod._ensure_password()
            with open(cfg, "r") as f:
                content = f.read()
            assert "ZDT_WEB_USER=admin" in content
            assert "ZDT_WEB_PASS=somepass" in content

    def test_chmod_600_on_new_file(self, tmp_path):
        """Should set 0o600 permissions on newly created config file."""
        from conftest import WebTestEnv
        with WebTestEnv(module_name="zdt_web_cred_6") as env:
            cfg = env.mod.CONFIG_FILE
            if os.path.exists(cfg):
                os.remove(cfg)
            env.mod._ensure_password()
            assert os.path.exists(cfg)
            mode = os.stat(cfg).st_mode & 0o777
            assert mode == 0o600, f"Expected 0o600, got {oct(mode)}"


# ────────────────────────────────────────────
# Tests: check_auth() via _original_check_auth
# ────────────────────────────────────────────

class TestCheckAuth:
    """Test check_auth() using _original_check_auth saved by WebTestEnv."""

    def _get_auth_and_config(self, module_name):
        """Import and return (original_check_auth, CONFIG_FILE)."""
        from conftest import WebTestEnv
        with WebTestEnv(module_name=module_name) as env:
            return env.mod._original_check_auth, env.mod.CONFIG_FILE

    def test_valid_credentials(self, tmp_path):
        check_auth, cfg = self._get_auth_and_config("zdt_web_chk_1")
        os.makedirs(os.path.dirname(cfg), exist_ok=True)
        with open(cfg, "w") as f:
            f.write("ZDT_WEB_USER=admin\n")
            f.write("ZDT_WEB_PASS=secret123\n")
        assert check_auth("admin", "secret123") is True

    def test_invalid_credentials(self, tmp_path):
        check_auth, cfg = self._get_auth_and_config("zdt_web_chk_2")
        os.makedirs(os.path.dirname(cfg), exist_ok=True)
        with open(cfg, "w") as f:
            f.write("ZDT_WEB_USER=admin\n")
            f.write("ZDT_WEB_PASS=secret123\n")
        assert check_auth("admin", "wrongpass") is False

    def test_rejects_admin_admin_default(self, tmp_path):
        check_auth, cfg = self._get_auth_and_config("zdt_web_chk_3")
        os.makedirs(os.path.dirname(cfg), exist_ok=True)
        with open(cfg, "w") as f:
            f.write("ZDT_WEB_USER=admin\n")
            f.write("ZDT_WEB_PASS=admin\n")
        assert check_auth("admin", "admin") is False

    def test_handles_missing_config(self, tmp_path):
        check_auth, cfg = self._get_auth_and_config("zdt_web_chk_4")
        if os.path.exists(cfg):
            os.remove(cfg)
        assert check_auth("admin", "anything") is False

    def test_handles_empty_config(self, tmp_path):
        check_auth, cfg = self._get_auth_and_config("zdt_web_chk_5")
        os.makedirs(os.path.dirname(cfg), exist_ok=True)
        with open(cfg, "w") as f:
            f.write("TARGET_DIR=/music\n")
        assert check_auth("admin", "anything") is False


# ────────────────────────────────────────────
# Tests: CSRF Token expiry
# ────────────────────────────────────────────

class TestCsrfTokenExpiry:
    """Test the CSRF token expiry logic."""

    def test_token_generation(self, tmp_path):
        from conftest import WebTestEnv
        with WebTestEnv(module_name="zdt_web_csrf_1") as env:
            mod = env.mod
            token = mod._generate_csrf_token()
            assert isinstance(token, str) and len(token) > 16

    def test_validate_new_token(self, tmp_path):
        from conftest import WebTestEnv
        with WebTestEnv(module_name="zdt_web_csrf_2") as env:
            mod = env.mod
            mod._csrf_tokens.clear()
            token = mod._generate_csrf_token()
            assert mod._validate_csrf_token(token) is True

    def test_consume_token_on_validation(self, tmp_path):
        from conftest import WebTestEnv
        with WebTestEnv(module_name="zdt_web_csrf_3") as env:
            mod = env.mod
            mod._csrf_tokens.clear()
            token = mod._generate_csrf_token()
            assert token in mod._csrf_tokens
            mod._validate_csrf_token(token)
            assert token not in mod._csrf_tokens

    def test_reject_invalid_token(self, tmp_path):
        from conftest import WebTestEnv
        with WebTestEnv(module_name="zdt_web_csrf_4") as env:
            mod = env.mod
            mod._csrf_tokens.clear()
            assert mod._validate_csrf_token("invalid_token_xyz") is False

    def test_reject_expired_token(self, tmp_path):
        from conftest import WebTestEnv
        with WebTestEnv(module_name="zdt_web_csrf_5") as env:
            mod = env.mod
            mod._csrf_tokens.clear()
            mod._csrf_tokens["expired_token"] = time.time() - 100
            assert mod._validate_csrf_token("expired_token") is False

    def test_expire_old_tokens_cleans_up(self, tmp_path):
        from conftest import WebTestEnv
        with WebTestEnv(module_name="zdt_web_csrf_6") as env:
            mod = env.mod
            mod._csrf_tokens.clear()
            mod._csrf_tokens["expired1"] = time.time() - 100
            mod._csrf_tokens["expired2"] = time.time() - 200
            mod._csrf_tokens["valid"] = time.time() + 3600
            mod._expire_old_csrf_tokens()
            assert "expired1" not in mod._csrf_tokens
            assert "expired2" not in mod._csrf_tokens
            assert "valid" in mod._csrf_tokens
