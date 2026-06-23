#!/usr/bin/env python3
"""Fix the OR fallback test to properly mock API key files."""
import os

test_path = "/home/zaki/zdt-project/tests/test_telegram.py"

with open(test_path, "r") as f:
    content = f.read()

old_test = '''def test_telegram_or_fallback_to_gemini():
    """Test OR->Gemini fallback: when all OR tiers fail with HTTP errors, Gemini is tried."""
    mock_msg = MagicMock()
    mock_msg.chat.id = 78901
    mock_msg.text = "test"
    
    if not hasattr(zdt_telegram, 'auto_download_audio'):
        return  # Skip if function doesn't exist
    
    # Mock the OR HTTP request to fail, then mock Gemini to succeed
    with patch.object(zdt_telegram.bot, 'send_chat_action'), \\
         patch.object(zdt_telegram.bot, 'reply_to'), \\
         patch('urllib.request.urlopen') as mock_urlopen:
        
        # Make all OR tier requests fail with HTTP error
        from urllib.error import HTTPError
        mock_urlopen.side_effect = HTTPError(
            "http://example.com", 429, "Too Many Requests", {}, None
        )
        
        # Call the function
        zdt_telegram.auto_download_audio(mock_msg)
        
        # Verify bot sent a response (either Gemini or error message)
        assert zdt_telegram.bot.reply_to.called, "Bot should send a response even when OR fails"
'''

new_test = '''def test_telegram_or_fallback_to_gemini():
    """Test OR->Gemini fallback: when all OR tiers fail with HTTP errors, falls through to Gemini."""
    from urllib.error import HTTPError
    
    mock_msg = MagicMock()
    mock_msg.chat.id = 78901
    mock_msg.text = "test"
    
    if not hasattr(zdt_telegram, 'auto_download_audio'):
        return  # Skip if function doesn't exist
    
    # Mock API key files to exist with a valid OR key
    original_expanduser = os.path.expanduser
    
    def mock_exists(path):
        if path.endswith('openrouter_key'):
            return True
        if path.endswith('gemini_key'):
            return True
        return original_expanduser(path) if 'expanduser' in dir() else os.path.exists(path)
    
    with patch.object(zdt_telegram.bot, 'send_chat_action'), \\
         patch.object(zdt_telegram.bot, 'reply_to') as mock_reply, \\
         patch('os.path.exists') as mock_exists, \\
         patch('builtins.open') as mock_open, \\
         patch('urllib.request.urlopen') as mock_urlopen:
        
        # Make openrouter_key file "exist" with a valid key
        mock_exists.side_effect = lambda p: p.endswith('openrouter_key') or p.endswith('gemini_key')
        
        # Mock file read to return a valid OR key
        mock_file = MagicMock()
        mock_file.read.return_value = 'sk-or-test-key-for-fallback'
        mock_file.__enter__.return_value = mock_file
        mock_open.return_value = mock_file
        
        # Make all OR tier requests fail with HTTP 429
        mock_urlopen.side_effect = HTTPError(
            "http://example.com", 429, "Too Many Requests", {}, None
        )
        
        # Call the function
        zdt_telegram.auto_download_audio(mock_msg)
        
        # Bot should respond (either Gemini fallback or error message)
        assert mock_reply.called, "Bot should send a response even when OR fails"
        
        # Verify urlopen was called (OR was actually attempted)
        assert mock_urlopen.called, "OR API should have been called before falling through"
'''

if old_test in content:
    content = content.replace(old_test, new_test)
    with open(test_path, "w") as f:
        f.write(content)
    print("OK: Fixed OR fallback test with proper key mocking")
else:
    print("WARN: Could not find old test to replace. Searching for keywords...")
    if "test_telegram_or_fallback_to_gemini" in content:
        print("Found: test exists but text differs. Manual check needed.")
    else:
        print("Found: test does not exist yet.")
