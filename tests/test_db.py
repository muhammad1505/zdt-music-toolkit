#!/usr/bin/env python3
import os
import subprocess
import tempfile
import json
import pytest

ZDT_DB_PATH = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "zdt-modules", "zdt_db.py"))

@pytest.fixture
def temp_db():
    fd, path = tempfile.mkstemp()
    os.close(fd)
    yield path
    os.remove(path)

def run_db(db_path, cmd, *args):
    result = subprocess.run(
        [sys.executable if 'sys' in globals() else 'python3', ZDT_DB_PATH, db_path, cmd, *args],
        capture_output=True,
        text=True
    )
    return result

import sys
def run_db_sys(db_path, cmd, *args):
    result = subprocess.run(
        [sys.executable, ZDT_DB_PATH, db_path, cmd, *args],
        capture_output=True,
        text=True
    )
    return result

def test_db_initialization_and_clear(temp_db):
    res = run_db_sys(temp_db, "get_count")
    assert res.returncode == 0, res.stderr
    assert res.stdout.strip() == "0"

def test_add_and_get_count(temp_db):
    run_db_sys(temp_db, "add", "user", "Halo bot")
    run_db_sys(temp_db, "add", "model", "Halo user")
    res = run_db_sys(temp_db, "get_count")
    assert res.returncode == 0, res.stderr
    assert res.stdout.strip() == "2"

def test_get_gemini_json(temp_db):
    run_db_sys(temp_db, "add", "user", "Test 1")
    res = run_db_sys(temp_db, "get_gemini_json")
    assert res.returncode == 0, res.stderr
    # Output should be valid JSON array if wrapped in []
    json_str = f"[{res.stdout.strip()}]"
    data = json.loads(json_str)
    assert len(data) == 1
    assert data[0]["role"] == "user"
    assert data[0]["parts"][0]["text"] == "Test 1"

def test_get_openai_json(temp_db):
    run_db_sys(temp_db, "add", "user", "Test 2")
    run_db_sys(temp_db, "add", "model", "Answer 2")
    res = run_db_sys(temp_db, "get_openai_json")
    assert res.returncode == 0, res.stderr
    json_str = f"[{res.stdout.strip()}]"
    data = json.loads(json_str)
    assert len(data) == 2
    assert data[0]["role"] == "user"
    assert data[0]["content"] == "Test 2"
    assert data[1]["role"] == "assistant"
    assert data[1]["content"] == "Answer 2"

def test_max_20_messages(temp_db):
    # Add 25 messages
    for i in range(25):
        run_db_sys(temp_db, "add", "user", f"Message {i}")
    
    res = run_db_sys(temp_db, "get_count")
    assert res.returncode == 0, res.stderr
    assert res.stdout.strip() == "20"
    
    # Check that it kept the last 20 (Message 5 to 24)
    res = run_db_sys(temp_db, "get_openai_json")
    json_str = f"[{res.stdout.strip()}]"
    data = json.loads(json_str)
    assert len(data) == 20
    assert data[0]["content"] == "Message 5"
    assert data[-1]["content"] == "Message 24"
