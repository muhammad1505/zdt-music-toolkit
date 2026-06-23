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

def test_downloads_table(temp_db):
    # Test adding downloads
    run_db_sys(temp_db, "add_download", "song1.mp3", "http://youtube.com/1", "youtube", "5000000")
    run_db_sys(temp_db, "add_download", "song2.m4a", "http://spotify.com/2", "spotify", "3000000")
    
    # Test getting stats
    res = run_db_sys(temp_db, "get_stats")
    assert res.returncode == 0, res.stderr
    data = json.loads(res.stdout.strip())
    
    assert data["total_count"] == 2
    assert data["total_size_bytes"] == 8000000
    assert data["sources"].get("youtube") == 1
    assert data["sources"].get("spotify") == 1
    
    # Check recent downloads
    assert len(data["recent"]) == 2
    # recent is ordered by id DESC
    assert data["recent"][0]["filename"] == "song2.m4a"
    assert data["recent"][0]["source"] == "spotify"
    assert data["recent"][0]["size_bytes"] == 3000000
    
    assert data["recent"][1]["filename"] == "song1.mp3"
    assert data["recent"][1]["source"] == "youtube"
    assert data["recent"][1]["size_bytes"] == 5000000

    # Test check_duplicate
    res = run_db_sys(temp_db, "check_duplicate", "http://youtube.com/1")
    assert res.returncode == 0, res.stderr
    assert res.stdout.strip() == "True"

    res = run_db_sys(temp_db, "check_duplicate", "http://youtube.com/new_url")
    assert res.returncode == 0, res.stderr
    assert res.stdout.strip() == "False"

def test_db_missing_arguments(temp_db):
    # Test check_duplicate missing argument
    res = run_db_sys(temp_db, "check_duplicate")
    assert res.returncode != 0
    
    # Test add_download missing arguments
    res = run_db_sys(temp_db, "add_download", "song1.mp3")
    assert res.returncode != 0
