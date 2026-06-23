#!/usr/bin/env python3
"""Fix try: block that's incorrectly indented inside the backward compat if statement."""
import ast

path = "/home/zaki/zdt-project/zdt-telegram.py"

with open(path, "r") as f:
    content = f.read()

# Find the exact block to fix:
# Currently:
#         if not openrouter_key and gemini_key and gemini_key.startswith("sk-or-"):
#             openrouter_key = gemini_key
#             gemini_key = ""
#         
#             try:                             <-- INDENTED WRONG (12 spaces, should be 8)
#                 if gemini_key or openrouter_key:  <-- INDENTED WRONG (16 spaces, should be 12)
#                     ...
#             except Exception as e:           <-- INDENTED WRONG (12 spaces, should be 8)
#                 ...
#                 return
#
# Should be:
#         if not openrouter_key and gemini_key and gemini_key.startswith("sk-or-"):
#             openrouter_key = gemini_key
#             gemini_key = ""
#         
#         try:                                 <-- CORRECT (8 spaces)
#             if gemini_key or openrouter_key:  <-- CORRECT (12 spaces)
#                 ...
#         except Exception as e:               <-- CORRECT (8 spaces)
#             ...

# Find "            try:" (12 spaces) that comes after "            gemini_key = \"\"" (12 spaces)
# and before "                if gemini_key or openrouter_key:" (16 spaces)
target_try = '        \n            try:\n                if gemini_key or openrouter_key:'
replacement = '        \n        try:\n            if gemini_key or openrouter_key:'

if target_try in content:
    content = content.replace(target_try, replacement, 1)
    print("OK: Fixed try: indentation")
else:
    print("WARN: Could not find exact pattern. Trying partial match...")
    # Try without the blank line
    target_try2 = '            gemini_key = ""\n        \n            try:\n                if gemini_key or openrouter_key:'
    replacement2 = '            gemini_key = ""\n        \n        try:\n            if gemini_key or openrouter_key:'
    if target_try2 in content:
        content = content.replace(target_try2, replacement2, 1)
        print("OK: Fixed try: indentation (variant 2)")
    else:
        print("Still trying...")
        # Try just the try line
        old = '\n            try:\n                if gemini_key or openrouter_key:\n                    bot.send_chat_action'
        new = '\n        try:\n            if gemini_key or openrouter_key:\n                bot.send_chat_action'
        if old in content:
            content = content.replace(old, new, 1)
            print("OK: Fixed try: indentation (variant 3)")
        else:
            print("ERROR: Could not fix")

# Also fix "            except Exception as e:" (12 spaces) to "        except Exception as e:" (8 spaces)
# But only the one that's NOT inside nested try/except blocks
# Find "                    return\n            except Exception as e:"
# The nested excepts are at 20 spaces (after the fix), the outer one should be at 8 spaces
old_except = "\n                    return\n            except Exception as e:\n                import urllib.error"
new_except = "\n                    return\n        except Exception as e:\n            import urllib.error"

if old_except in content:
    content = content.replace(old_except, new_except, 1)
    print("OK: Fixed except: indentation")
else:
    print("WARN: Could not find except to fix")

# Fix: "                bot.reply_to(message, \"🤔 Maksud lu apa nih?\"..." at 16 spaces -> "        " at 8 spaces
old_fallback = "\n                bot.reply_to(message, \"\U0001f914 Maksud lu apa nih?"
new_fallback = "\n        bot.reply_to(message, \"\U0001f914 Maksud lu apa nih?"

if old_fallback in content:
    content = content.replace(old_fallback, new_fallback, 1)
    print("OK: Fixed fallback reply indentation")
else:
    print("INFO: Fallback reply pattern not matched (may already be correct)")

# Fix: "                return" after that to "        return"
old_return_fb = "\n                return\n                \n            url = [word for word in text.split()"
new_return_fb = "\n        return\n        \n    url = [word for word in text.split()"

if old_return_fb in content:
    content = content.replace(old_return_fb, new_return_fb, 1)
    print("OK: Fixed return indentation after fallback")
else:
    print("INFO: Return after fallback not matched")

with open(path, "w") as f:
    f.write(content)

# Check syntax
try:
    ast.parse(content)
    print("SYNTAX OK")
except SyntaxError as e:
    # Show context
    lines = content.split('\n')
    print(f"SYNTAX ERROR at line {e.lineno}: {e.msg}")
    start = max(0, e.lineno - 5)
    end = min(len(lines), e.lineno + 3)
    for j in range(start, end):
        marker = ">>>" if j == e.lineno - 1 else "   "
        print(f"{marker} {j+1}: {repr(lines[j])}")
