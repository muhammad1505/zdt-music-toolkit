#!/usr/bin/env python3
"""
Pytest conftest for ZDT tests.
Provides fixtures and import helpers for testing Python components.
"""
import os
import sys
import types
import pytest
import importlib.util

PROJECT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def _mock_missing_deps():
    """Mock optional dependencies that may not be installed."""
    deps = {
        "flask": ["Flask"],
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
