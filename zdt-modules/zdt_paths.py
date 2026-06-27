#!/usr/bin/env python3
"""
ZDT Path Resolution Module — Single Source of Truth for all file paths.
All Python scripts should import this instead of hardcoding paths.
Supports: local install, system-wide, Termux, and dev/repo modes.
"""
import os
import sys
import shutil


class ZdtPaths:
    """Resolves all ZDT paths dynamically across install locations."""

    # ---- Base location lists (priority order) ----

    SHARE_DIRS = [
        os.path.expanduser("~/.local/share/zdt"),
        "/usr/local/share/zdt",
        "/data/data/com.termux/files/usr/share/zdt",
    ]

    BIN_PATHS = [
        os.path.expanduser("~/.local/bin/zdt"),
        "/usr/local/bin/zdt",
        "/data/data/com.termux/files/usr/bin/zdt",
    ]

    # ---- Helpers ----

    @classmethod
    def _find_first_dir(cls, dirs):
        for d in dirs:
            e = os.path.expanduser(d)
            if os.path.isdir(e):
                return e
        return None

    @classmethod
    def _find_first_file(cls, files):
        for f in files:
            e = os.path.expanduser(f)
            if os.path.isfile(e):
                return e
        return None

    # ---- Resolved paths ----

    @classmethod
    def get_share_dir(cls):
        """Active share directory (first existing), with fallback."""
        found = cls._find_first_dir(cls.SHARE_DIRS)
        return found or cls.SHARE_DIRS[0]

    @classmethod
    def get_modules_dir(cls):
        return os.path.join(cls.get_share_dir(), "zdt-modules")

    @classmethod
    def get_templates_dir(cls):
        return os.path.join(cls.get_share_dir(), "templates")

    @classmethod
    def get_config_dir(cls):
        return os.path.expanduser("~/.config/zdt")

    @classmethod
    def get_config_file(cls):
        return os.path.join(cls.get_config_dir(), "config.env")

    @classmethod
    def get_old_config_file(cls):
        """Legacy config file for backward compatibility."""
        return os.path.expanduser("~/.config/zdt/config")

    @classmethod
    def get_db_path(cls):
        return os.path.join(cls.get_config_dir(), "zdt.db")

    @classmethod
    def get_scheduler_path(cls):
        return os.path.join(cls.get_config_dir(), "scheduler.json")

    @classmethod
    def get_bin_path(cls):
        """Find the zdt binary across all locations + PATH."""
        found = cls._find_first_file(cls.BIN_PATHS)
        if found:
            return found
        which = shutil.which("zdt")
        return which or "zdt"

    @classmethod
    def get_venv_python(cls):
        return os.path.expanduser("~/.local/share/zdt/venv/bin/python")

    @classmethod
    def get_demucs_bin(cls):
        return os.path.expanduser("~/.local/share/zdt/demucs_venv/bin/demucs")

    @classmethod
    def get_key_path(cls, name):
        """API key file path (e.g. 'gemini_key', 'openrouter_key')."""
        return os.path.join(cls.get_config_dir(), name)

    @classmethod
    def get_telegram_token_path(cls):
        return cls.get_key_path("telegram_token.txt")

    # ---- Dynamic file finding ----

    @classmethod
    def find_script(cls, name, script_dir=None):
        """Find a Python/binary script: project dir → share dir → cwd."""
        candidates = []
        if script_dir:
            candidates.append(os.path.join(script_dir, name))
        candidates.append(os.path.join(cls.get_share_dir(), name))
        candidates.append(os.path.join(os.getcwd(), name))
        return cls._find_first_file(candidates)

    @classmethod
    def find_template(cls, name, script_dir=None):
        """Find a template file: project dir → share → cwd."""
        candidates = []
        if script_dir:
            candidates.append(os.path.join(script_dir, "templates", name))
        candidates.append(os.path.join(cls.get_templates_dir(), name))
        candidates.append(os.path.join(os.getcwd(), "templates", name))
        return cls._find_first_file(candidates)

    # ---- Version resolution ----

    @classmethod
    def get_version(cls):
        """Get ZDT version dynamically — no hardcoded fallback.
        Priority: VERSION file (share dir) → ZDT_VERSION env var → parse zdt.sh → 'unknown'.
        """
        # 1. VERSION file in share dir (written by zdt.sh on startup)
        version_file = os.path.join(cls.get_share_dir(), "VERSION")
        try:
            with open(version_file) as f:
                ver = f.read().strip()
                if cls._is_valid_version(ver):
                    return ver
        except (OSError, IOError):
            pass

        # 2. Env var (set by zdt.sh: export ZDT_VERSION="$APP_VERSION")
        env_ver = os.environ.get("ZDT_VERSION")
        if env_ver and cls._is_valid_version(env_ver):
            return env_ver

        # 3. Parse zdt.sh
        for candidate in cls._get_zdt_sh_candidates():
            ver = cls._parse_zdt_sh(candidate)
            if ver:
                return ver

        return "unknown"

    @classmethod
    def _is_valid_version(cls, ver):
        """Basic validation: not empty, starts with digit."""
        return bool(ver) and ver[0].isdigit()

    @classmethod
    def _get_zdt_sh_candidates(cls):
        """Possible locations for zdt.sh."""
        project = os.environ.get("ZDT_PROJECT_DIR", "")
        cwd = os.getcwd()
        candidates = []
        if project:
            candidates.append(os.path.join(project, "zdt.sh"))
        # Use get_bin_path() which resolves the actual binary location
        bin_path = cls.get_bin_path()
        if bin_path and bin_path != "zdt":
            candidates.append(bin_path)
        candidates.append(os.path.join(cwd, "zdt.sh"))
        return candidates

    @classmethod
    def _parse_zdt_sh(cls, path):
        """Parse APP_VERSION from zdt.sh file."""
        try:
            with open(path) as f:
                for line in f:
                    # Match: readonly APP_VERSION="x.y.z" or APP_VERSION='x.y.z'
                    if 'APP_VERSION' in line and ('="' in line or "='" in line):
                        for quote in ['"', "'"]:
                            if f"={quote}" in line:
                                start = line.index(f"={quote}") + 2
                                end = line.index(quote, start)
                                ver = line[start:end]
                                if cls._is_valid_version(ver):
                                    return ver
        except (OSError, IOError, ValueError):
            pass
        return None

    @classmethod
    def find_template_candidates(cls, script_dir=None):
        """Return all candidate directories for templates (for auto-create)."""
        candidates = []
        if script_dir:
            candidates.append(os.path.join(script_dir, "templates"))
            candidates.append(os.path.join(os.path.dirname(script_dir), "templates"))
        candidates.append(cls.get_templates_dir())
        # installed system-wide
        for d in cls.SHARE_DIRS:
            candidates.append(os.path.join(d, "templates"))
        # dev mode: running from repo
        candidates.append(os.path.expanduser("~/zdt-music-toolkit/templates"))
        candidates.append(os.path.join(os.getcwd(), "templates"))
        return candidates
