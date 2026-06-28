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


def test_telegram_auto_action_cek_status():
    """Test AUTO_ACTION: cek status dispatches to server_status()."""
    import json
    from unittest.mock import patch, MagicMock

    mock_msg = MagicMock()
    mock_msg.chat.id = 99910
    mock_msg.text = "cek status server"

    # AI response with AUTO_ACTION: cek status
    ai_response_text = "Cek status bentar! [AUTO_ACTION: cek status]"
    or_response = {
        "choices": [{
            "message": {"content": ai_response_text}
        }]
    }

    def _mock_urlopen(req, timeout=20):
        url = req.full_url if hasattr(req, 'full_url') else str(req)
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps(or_response).encode()
        mock_resp.__enter__.return_value = mock_resp
        mock_resp.__exit__.return_value = None
        return mock_resp

    key_paths = [
        os.path.expanduser("~/.config/zdt/openrouter_key"),
    ]
    def _mock_exists(path):
        return path in key_paths

    def _mock_open(path, *args, **kwargs):
        m = MagicMock()
        m.__enter__.return_value.read.return_value = "sk-or-v1-test-key"
        return m

    with patch.object(zdt_telegram.bot, 'reply_to') as mock_reply, \
         patch.object(zdt_telegram.bot, 'send_chat_action'), \
         patch('urllib.request.urlopen', side_effect=_mock_urlopen), \
         patch('os.path.exists', side_effect=_mock_exists), \
         patch('builtins.open', side_effect=_mock_open), \
         patch.object(zdt_telegram, 'server_status') as mock_server_status:

        zdt_telegram.auto_download_audio(mock_msg)

        # server_status should be called with the message
        mock_server_status.assert_called_once_with(mock_msg)
        # reply should have the clean text (without AUTO_ACTION tag)
        assert mock_reply.called
        args = mock_reply.call_args[0]
        assert "Cek status bentar!" in args[1]


def test_telegram_auto_action_buka_web():
    """Test AUTO_ACTION: buka web sends dashboard URL."""
    import json
    from unittest.mock import patch, MagicMock

    mock_msg = MagicMock()
    mock_msg.chat.id = 99911
    mock_msg.text = "buka web dashboard"

    ai_response_text = "Buka dashboard! [AUTO_ACTION: buka web]"
    or_response = {
        "choices": [{
            "message": {"content": ai_response_text}
        }]
    }

    def _mock_urlopen(req, timeout=20):
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps(or_response).encode()
        mock_resp.__enter__.return_value = mock_resp
        mock_resp.__exit__.return_value = None
        return mock_resp

    key_paths = [os.path.expanduser("~/.config/zdt/openrouter_key")]
    def _mock_exists(path):
        return path in key_paths

    def _mock_open(path, *args, **kwargs):
        m = MagicMock()
        m.__enter__.return_value.read.return_value = "sk-or-v1-test-key"
        return m

    with patch.object(zdt_telegram.bot, 'reply_to') as mock_reply, \
         patch.object(zdt_telegram.bot, 'send_chat_action'), \
         patch('urllib.request.urlopen', side_effect=_mock_urlopen), \
         patch('os.path.exists', side_effect=_mock_exists), \
         patch('builtins.open', side_effect=_mock_open):

        zdt_telegram.auto_download_audio(mock_msg)

        assert mock_reply.called
        args = mock_reply.call_args[0]
        reply_text = args[1]
        assert "Buka dashboard!" in reply_text or "localhost:5678" in reply_text


def test_telegram_auto_action_setup_tools():
    """Test AUTO_ACTION: setup tools runs zdt --setup."""
    import json
    from unittest.mock import patch, MagicMock, call as mock_call

    mock_msg = MagicMock()
    mock_msg.chat.id = 99912
    mock_msg.text = "setup tools"

    ai_response_text = "Setup! [AUTO_ACTION: setup tools]"
    or_response = {
        "choices": [{
            "message": {"content": ai_response_text}
        }]
    }

    def _mock_urlopen(req, timeout=20):
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps(or_response).encode()
        mock_resp.__enter__.return_value = mock_resp
        mock_resp.__exit__.return_value = None
        return mock_resp

    key_paths = [os.path.expanduser("~/.config/zdt/openrouter_key")]
    def _mock_exists(path):
        return path in key_paths

    def _mock_open(path, *args, **kwargs):
        m = MagicMock()
        m.__enter__.return_value.read.return_value = "sk-or-v1-test-key"
        return m

    with patch.object(zdt_telegram.bot, 'reply_to') as mock_reply, \
         patch.object(zdt_telegram.bot, 'send_chat_action'), \
         patch('urllib.request.urlopen', side_effect=_mock_urlopen), \
         patch('os.path.exists', side_effect=_mock_exists), \
         patch('builtins.open', side_effect=_mock_open), \
         patch('subprocess.Popen') as mock_popen:

        zdt_telegram.auto_download_audio(mock_msg)

        # Should call Popen with --setup
        mock_popen.assert_called()
        popen_args = mock_popen.call_args[0][0]
        assert '--setup' in popen_args or 'setup' in str(popen_args)


def test_telegram_auto_action_start_watch():
    """Test AUTO_ACTION: start watch runs zdt --watch."""
    import json
    from unittest.mock import patch, MagicMock

    mock_msg = MagicMock()
    mock_msg.chat.id = 99913
    mock_msg.text = "mulai watch daemon"

    ai_response_text = "Watch started! [AUTO_ACTION: start watch]"
    or_response = {
        "choices": [{
            "message": {"content": ai_response_text}
        }]
    }

    def _mock_urlopen(req, timeout=20):
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps(or_response).encode()
        mock_resp.__enter__.return_value = mock_resp
        mock_resp.__exit__.return_value = None
        return mock_resp

    key_paths = [os.path.expanduser("~/.config/zdt/openrouter_key")]
    def _mock_exists(path):
        return path in key_paths

    def _mock_open(path, *args, **kwargs):
        m = MagicMock()
        m.__enter__.return_value.read.return_value = "sk-or-v1-test-key"
        return m

    with patch.object(zdt_telegram.bot, 'reply_to') as mock_reply, \
         patch.object(zdt_telegram.bot, 'send_chat_action'), \
         patch('urllib.request.urlopen', side_effect=_mock_urlopen), \
         patch('os.path.exists', side_effect=_mock_exists), \
         patch('builtins.open', side_effect=_mock_open), \
         patch('subprocess.Popen') as mock_popen:

        zdt_telegram.auto_download_audio(mock_msg)

        # run_bg_task runs async via thread pool — wait for it to execute
        import time
        time.sleep(0.5)

        # Should call Popen with --watch (via run_bg_task which uses Popen)
        mock_popen.assert_called()
        popen_args = mock_popen.call_args[0][0]
        assert '--watch' in popen_args or 'watch' in str(popen_args)


def test_telegram_auto_action_update_tools():
    """Test AUTO_ACTION: update tools runs zdt --update."""
    import json
    from unittest.mock import patch, MagicMock

    mock_msg = MagicMock()
    mock_msg.chat.id = 99914
    mock_msg.text = "update tools"

    ai_response_text = "Updating! [AUTO_ACTION: update tools]"
    or_response = {
        "choices": [{
            "message": {"content": ai_response_text}
        }]
    }

    def _mock_urlopen(req, timeout=20):
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps(or_response).encode()
        mock_resp.__enter__.return_value = mock_resp
        mock_resp.__exit__.return_value = None
        return mock_resp

    key_paths = [os.path.expanduser("~/.config/zdt/openrouter_key")]
    def _mock_exists(path):
        return path in key_paths

    def _mock_open(path, *args, **kwargs):
        m = MagicMock()
        m.__enter__.return_value.read.return_value = "sk-or-v1-test-key"
        return m

    with patch.object(zdt_telegram.bot, 'reply_to') as mock_reply, \
         patch.object(zdt_telegram.bot, 'send_chat_action'), \
         patch('urllib.request.urlopen', side_effect=_mock_urlopen), \
         patch('os.path.exists', side_effect=_mock_exists), \
         patch('builtins.open', side_effect=_mock_open), \
         patch('subprocess.Popen') as mock_popen:

        zdt_telegram.auto_download_audio(mock_msg)

        mock_popen.assert_called()
        popen_args = mock_popen.call_args[0][0]
        assert '--update' in popen_args or 'update' in str(popen_args)


def test_telegram_auto_action_scheduler():
    """Test info-only AUTO_ACTIONs: buka scheduler, ubah storage, start telegram."""
    import json
    from unittest.mock import patch, MagicMock

    key_paths = [os.path.expanduser("~/.config/zdt/openrouter_key")]

    def _mock_exists(path):
        return path in key_paths

    def _mock_open(path, *args, **kwargs):
        m = MagicMock()
        m.__enter__.return_value.read.return_value = "sk-or-v1-test-key"
        return m

    # Test buka scheduler
    mock_msg = MagicMock()
    mock_msg.chat.id = 99915
    mock_msg.text = "buka scheduler"

    ai_response_text = "Scheduler info [AUTO_ACTION: buka scheduler]"
    or_response = {"choices": [{"message": {"content": ai_response_text}}]}

    def _mock_urlopen_scheduler(req, timeout=20):
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps(or_response).encode()
        mock_resp.__enter__.return_value = mock_resp
        mock_resp.__exit__.return_value = None
        return mock_resp

    with patch.object(zdt_telegram.bot, 'reply_to') as mock_reply, \
         patch.object(zdt_telegram.bot, 'send_chat_action'), \
         patch('urllib.request.urlopen', side_effect=_mock_urlopen_scheduler), \
         patch('os.path.exists', side_effect=_mock_exists), \
         patch('builtins.open', side_effect=_mock_open):

        zdt_telegram.auto_download_audio(mock_msg)
        assert mock_reply.called, "reply_to should be called for buka scheduler"
        args = mock_reply.call_args[0]
        reply_text = args[1]
        assert "Scheduler info" in reply_text or "Web Dashboard" in reply_text or "Tambah URL" in reply_text

    # Test ubah storage
    mock_msg2 = MagicMock()
    mock_msg2.chat.id = 99916
    mock_msg2.text = "ubah storage"

    ai_response_text2 = "Storage info [AUTO_ACTION: ubah storage]"
    or_response2 = {"choices": [{"message": {"content": ai_response_text2}}]}

    def _mock_urlopen_storage(req, timeout=20):
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps(or_response2).encode()
        mock_resp.__enter__.return_value = mock_resp
        mock_resp.__exit__.return_value = None
        return mock_resp

    with patch.object(zdt_telegram.bot, 'reply_to') as mock_reply2, \
         patch.object(zdt_telegram.bot, 'send_chat_action'), \
         patch('urllib.request.urlopen', side_effect=_mock_urlopen_storage), \
         patch('os.path.exists', side_effect=_mock_exists), \
         patch('builtins.open', side_effect=_mock_open):

        zdt_telegram.auto_download_audio(mock_msg2)
        assert mock_reply2.called, "reply_to should be called for ubah storage"
        args2 = mock_reply2.call_args[0]
        reply2 = args2[1]
        assert "Storage info" in reply2 or "config.env" in reply2 or "TARGET_DIR" in reply2

    # Test start telegram
    mock_msg3 = MagicMock()
    mock_msg3.chat.id = 99917
    mock_msg3.text = "start telegram"

    ai_response_text3 = "Bot running [AUTO_ACTION: start telegram]"
    or_response3 = {"choices": [{"message": {"content": ai_response_text3}}]}

    def _mock_urlopen_telegram(req, timeout=20):
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps(or_response3).encode()
        mock_resp.__enter__.return_value = mock_resp
        mock_resp.__exit__.return_value = None
        return mock_resp

    with patch.object(zdt_telegram.bot, 'reply_to') as mock_reply3, \
         patch.object(zdt_telegram.bot, 'send_chat_action'), \
         patch('urllib.request.urlopen', side_effect=_mock_urlopen_telegram), \
         patch('os.path.exists', side_effect=_mock_exists), \
         patch('builtins.open', side_effect=_mock_open):

        zdt_telegram.auto_download_audio(mock_msg3)
        assert mock_reply3.called, "reply_to should be called for start telegram"
        args3 = mock_reply3.call_args[0]
        reply3 = args3[1]
        assert "Bot running" in reply3 or "Telegram Bot" in reply3 or "sudah berjalan" in reply3


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


def test_telegram_keyword_fallback_status():
    """Keyword fallback: AI returns plain text, keyword 'status' triggers action."""
    import json
    from unittest.mock import patch, MagicMock

    mock_msg = MagicMock()
    mock_msg.chat.id = 99930
    mock_msg.text = "cek status server"

    # AI returns plain text WITHOUT AUTO_ACTION — keyword fallback should catch "status"
    or_response = {
        "choices": [{
            "message": {"content": "Siap!"}
        }]
    }

    def _mock_urlopen(req, timeout=20):
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps(or_response).encode()
        mock_resp.__enter__.return_value = mock_resp
        mock_resp.__exit__.return_value = None
        return mock_resp

    key_paths = [os.path.expanduser("~/.config/zdt/openrouter_key")]
    def _mock_exists(path):
        return path in key_paths

    def _mock_open(path, *args, **kwargs):
        m = MagicMock()
        m.__enter__.return_value.read.return_value = "sk-or-v1-test-key"
        return m

    with patch.object(zdt_telegram.bot, 'reply_to') as mock_reply, \
         patch.object(zdt_telegram.bot, 'send_chat_action'), \
         patch('urllib.request.urlopen', side_effect=_mock_urlopen), \
         patch('os.path.exists', side_effect=_mock_exists), \
         patch('builtins.open', side_effect=_mock_open), \
         patch.object(zdt_telegram, 'server_status') as mock_server_status:

        zdt_telegram.auto_download_audio(mock_msg)

        # Keyword fallback should detect "status" and call server_status
        mock_server_status.assert_called_once_with(mock_msg)


def test_telegram_keyword_fallback_download():
    """Keyword fallback: AI returns plain text, keyword 'download' triggers action."""
    import json
    from unittest.mock import patch, MagicMock

    mock_msg = MagicMock()
    mock_msg.chat.id = 99931
    mock_msg.text = "download lagu Tulus"

    or_response = {
        "choices": [{
            "message": {"content": "Oke!"}
        }]
    }

    def _mock_urlopen(req, timeout=20):
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps(or_response).encode()
        mock_resp.__enter__.return_value = mock_resp
        mock_resp.__exit__.return_value = None
        return mock_resp

    key_paths = [os.path.expanduser("~/.config/zdt/openrouter_key")]
    def _mock_exists(path):
        return path in key_paths

    def _mock_open(path, *args, **kwargs):
        m = MagicMock()
        m.__enter__.return_value.read.return_value = "sk-or-v1-test-key"
        return m

    with patch.object(zdt_telegram.bot, 'reply_to') as mock_reply, \
         patch.object(zdt_telegram.bot, 'send_chat_action'), \
         patch('urllib.request.urlopen', side_effect=_mock_urlopen), \
         patch('os.path.exists', side_effect=_mock_exists), \
         patch('builtins.open', side_effect=_mock_open):

        zdt_telegram.auto_download_audio(mock_msg)

        # Keyword fallback should detect "download" — reply_to called with progress msg
        assert mock_reply.called, "bot.reply_to should have been called"
        call_texts = [str(c[0]) for c in mock_reply.call_args_list]
        assert any("Mendownload" in t for t in call_texts), f"Expected progress msg, got: {call_texts}"
