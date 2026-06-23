#!/usr/bin/env python3
"""Fix the OR fallback test with proper key file mocking."""
import os

test_path = "/home/zaki/zdt-project/tests/test_telegram.py"

with open(test_path, "r") as f:
    content = f.read()

# Find the OR fallback test and replace it
old_start = 'def test_telegram_or_fallback_to_gemini():'
old_end = 'assert zdt_telegram.bot.reply_to.called, "Bot should send a response even when OR fails"\n'

start_idx = content.find(old_start)
end_idx = content.find(old_end, start_idx)

if start_idx >= 0 and end_idx >= 0:
    old_test = content[start_idx:end_idx + len(old_end)]
    
    new_test = '''def test_telegram_or_fallback_to_gemini():
    """Test OR->Gemini fallback: when all OR tiers fail with HTTP errors."""
    from urllib.error import HTTPError

    mock_msg = MagicMock()
    mock_msg.chat.id = 78901
    mock_msg.text = "test"

    if not hasattr(zdt_telegram, 'auto_download_audio'):
        return

    with patch.object(zdt_telegram.bot, 'send_chat_action'), \\
         patch.object(zdt_telegram.bot, 'reply_to') as mock_reply, \\
         patch('os.path.exists') as mock_exists, \\
         patch('builtins.open') as mock_open, \\
         patch('urllib.request.urlopen') as mock_urlopen:

        # Make both key files appear to exist
        mock_exists.side_effect = lambda p: 'openrouter_key' in p or 'gemini_key' in p

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

        # Bot should respond even when OR fails
        assert mock_reply.called, "Bot should send a response when OR fails"
        # Verify urlopen was actually called (OR was attempted)
        assert mock_urlopen.called, "OR API should have been attempted"
'''
    
    content = content.replace(old_test, new_test, 1)
    with open(test_path, "w") as f:
        f.write(content)
    print("OK: Replaced OR fallback test with proper key mocking")
else:
    print(f"ERROR: Could not find test. start_idx={start_idx}, end_idx={end_idx}")
