#!/usr/bin/env python3
import sys
import os
import importlib.util
from unittest.mock import patch, MagicMock

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

# Need to mock telebot before importing
mock_telebot = MagicMock()
mock_telebot.types = MagicMock()

sys.modules['telebot'] = mock_telebot
sys.modules['telebot.types'] = mock_telebot.types

# Make decorators return the function unmodified
def passthrough_decorator(*args, **kwargs):
    def decorator(func):
        return func
    return decorator

mock_telebot.TeleBot.return_value.message_handler = passthrough_decorator
mock_telebot.TeleBot.return_value.callback_query_handler = passthrough_decorator

os.environ["TELEGRAM_TOKEN"] = "mock_token"

spec = importlib.util.spec_from_file_location("zdt_telegram", os.path.join(os.path.dirname(__file__), "..", "zdt-telegram.py"))
zdt_telegram = importlib.util.module_from_spec(spec)
sys.modules["zdt_telegram"] = zdt_telegram
spec.loader.exec_module(zdt_telegram)

def test_telegram_welcome():
    mock_msg = MagicMock()
    mock_msg.chat.id = 123
    
    # send_welcome is decorated, we can call it directly
    if hasattr(zdt_telegram, 'send_welcome'):
        zdt_telegram.send_welcome(mock_msg)
        
        # Verify bot.reply_to was called
        zdt_telegram.bot.reply_to.assert_called()
        args = zdt_telegram.bot.reply_to.call_args[0]
        assert args[0].chat.id == 123
        assert "ZDT ENTERPRISE" in args[1]

def test_telegram_ping():
    mock_msg = MagicMock()
    mock_msg.chat.id = 456
    
    if hasattr(zdt_telegram, 'send_ping'):
        zdt_telegram.send_ping(mock_msg)
        
        zdt_telegram.original_send_message.assert_called()
        args = zdt_telegram.original_send_message.call_args[0]
        assert args[0] == 456
        assert "PONG" in args[1]

def test_telegram_status():
    mock_msg = MagicMock()
    mock_msg.chat.id = 789
    
    if hasattr(zdt_telegram, 'send_status'):
        zdt_telegram.send_status(mock_msg)
        
        zdt_telegram.original_send_message.assert_called()
        args = zdt_telegram.original_send_message.call_args[0]
        assert args[0] == 789
        assert "Disk Free" in args[1] or "CPU" in args[1]


def test_telegram_gemini_only():
    """Test that when only Gemini key exists (no OR key), Gemini is used directly."""
    import json
    from unittest.mock import patch, MagicMock

    mock_msg = MagicMock()
    mock_msg.chat.id = 99902
    mock_msg.text = "lagu Tulus"

    gemini_response = {
        "candidates": [{
            "content": {"parts": [{"text": "Download Tulus yuk! 🎵"}]}
        }]
    }

    def _mock_urlopen(req, timeout=20):
        url = req.full_url if hasattr(req, 'full_url') else str(req)
        if 'openrouter.ai' not in url:
            # Gemini call succeeds
            mock_resp = MagicMock()
            mock_resp.read.return_value = json.dumps(gemini_response).encode()
            mock_resp.__enter__.return_value = mock_resp
            mock_resp.__exit__.return_value = None
            return mock_resp
        # OR call (should not happen in this test)
        from urllib.error import HTTPError
        raise HTTPError(url, 429, "Mocked", {}, None)

    # Mock only gemini_key to exist — no openrouter_key
    gemini_path = os.path.expanduser("~/.config/zdt/gemini_key")
    or_path = os.path.expanduser("~/.config/zdt/openrouter_key")

    def _mock_open(path, *args, **kwargs):
        if path == gemini_path:
            m = MagicMock()
            m.__enter__.return_value.read.return_value = "AIzaSyTestGeminiKey123"
            return m
        m = MagicMock()
        m.__enter__.return_value.read.return_value = ""
        return m

    def _mock_exists(path):
        return path == gemini_path  # Only gemini_key exists

    with patch.object(zdt_telegram.bot, 'reply_to') as mock_reply, \
         patch.object(zdt_telegram.bot, 'send_chat_action'), \
         patch('urllib.request.urlopen', side_effect=_mock_urlopen), \
         patch('os.path.exists', side_effect=_mock_exists), \
         patch('builtins.open', side_effect=_mock_open):

        zdt_telegram.auto_download_audio(mock_msg)

        assert mock_reply.called, "bot.reply_to should have been called"
        args = mock_reply.call_args[0]
        reply_text = args[1]
        assert "Tulus" in reply_text, f"Gemini response should contain 'Tulus', got: {reply_text}"
        assert "Aduh otak" not in reply_text, f"Should NOT be error, got: {reply_text}"


def test_telegram_or_fallback_to_gemini():
    """Test that when all OR tiers fail (HTTP 429), Gemini is used as fallback."""
    import json
    from unittest.mock import patch, MagicMock
    from urllib.error import HTTPError

    mock_msg = MagicMock()
    mock_msg.chat.id = 99901
    mock_msg.text = "lagu Tulus"

    gemini_response = {
        "candidates": [{
            "content": {"parts": [{"text": "Download Tulus yuk! 🎵"}]}
        }]
    }

    # URL-based routing: fail ALL OR calls (3-tier retry), succeed on Gemini
    def _mock_urlopen(req, timeout=20):
        url = req.full_url if hasattr(req, 'full_url') else str(req)
        if 'openrouter.ai' in url:
            raise HTTPError(url, 429, "Too Many Requests", {}, None)
        # Gemini call succeeds
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps(gemini_response).encode()
        mock_resp.__enter__.return_value = mock_resp
        mock_resp.__exit__.return_value = None
        return mock_resp

    # Mock key files to exist with both keys set
    keyfile_data = {
        os.path.expanduser("~/.config/zdt/gemini_key"): "AIzaSyTestGeminiKey123",
        os.path.expanduser("~/.config/zdt/openrouter_key"): "sk-or-v1-test-openrouter-key-456",
    }

    def _mock_open(path, *args, **kwargs):
        if path in keyfile_data:
            m = MagicMock()
            m.__enter__.return_value.read.return_value = keyfile_data[path]
            return m
        # Unknown file: return empty MagicMock so code doesn't crash
        m = MagicMock()
        m.__enter__.return_value.read.return_value = ""
        return m

    # Only mock key files as "existing" — not the config file
    key_paths = [
        os.path.expanduser("~/.config/zdt/gemini_key"),
        os.path.expanduser("~/.config/zdt/openrouter_key"),
    ]
    def _mock_exists(path):
        return path in key_paths

    with patch.object(zdt_telegram.bot, 'reply_to') as mock_reply, \
         patch.object(zdt_telegram.bot, 'send_chat_action'), \
         patch('urllib.request.urlopen', side_effect=_mock_urlopen), \
         patch('os.path.exists', side_effect=_mock_exists), \
         patch('builtins.open', side_effect=_mock_open):

        zdt_telegram.auto_download_audio(mock_msg)

        # Should have called reply_to with Gemini's response (not the OR error)
        assert mock_reply.called, "bot.reply_to should have been called"
        args = mock_reply.call_args[0]
        reply_text = args[1]
        assert "Tulus" in reply_text, f"Gemini response should contain 'Tulus', got: {reply_text}"
        assert "Aduh otak" not in reply_text, f"Should NOT be OR error, got: {reply_text}"
