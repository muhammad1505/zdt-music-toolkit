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
