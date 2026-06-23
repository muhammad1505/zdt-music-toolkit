#!/usr/bin/env python3
"""Apply dual-key + OR fallback changes to zdt-telegram.py with correct indentation."""
import ast, sys

path = "/home/zaki/zdt-project/zdt-telegram.py"

with open(path, "r") as f:
    content = f.read()

changes = 0

# ========== CHANGE 1: Key reading section ==========
# Replace:
#   8sp: gemini_key_file = ...
#   8sp: if os.path.exists(gemini_key_file):
#   12sp: try:
#   16sp: with open(gemini_key_file, "r") as f:
#   20sp: gemini_key = f.read().strip()
#   16sp: if gemini_key:
# With:
#   8sp: gemini_key_file = ...
#   8sp: openrouter_key_file = ...
#   8sp: gemini_key = ""
#   8sp: openrouter_key = ""
#   8sp: if os.path.exists(gemini_key_file):
#   12sp: try:
#   16sp: with open(gemini_key_file, "r") as f:
#   20sp: gemini_key = f.read().strip()
#   12sp: except:
#   16sp: pass
#   8sp: if os.path.exists(openrouter_key_file):
#   12sp: try:
#   16sp: with open(openrouter_key_file, "r") as f:
#   20sp: openrouter_key = f.read().strip()
#   12sp: except:
#   16sp: pass
#   8sp: # Dual-key logic...
#   8sp: if not openrouter_key and gemini_key and gemini_key.startswith("sk-or-"):
#   12sp: openrouter_key = gemini_key
#   12sp: gemini_key = ""
#   12sp: try:   <-- NOTE: this is the NEW try at 12sp (inside if "http" not in text: at 4sp, at 8sp level)
#   16sp: if gemini_key or openrouter_key:

old_key = '''        gemini_key_file = os.path.expanduser("~/.config/zdt/gemini_key")
        if os.path.exists(gemini_key_file):
            try:
                with open(gemini_key_file, "r") as f:
                    gemini_key = f.read().strip()
                if gemini_key:'''

new_key = '''        gemini_key_file = os.path.expanduser("~/.config/zdt/gemini_key")
        openrouter_key_file = os.path.expanduser("~/.config/zdt/openrouter_key")
        gemini_key = ""
        openrouter_key = ""
        if os.path.exists(gemini_key_file):
            try:
                with open(gemini_key_file, "r") as f:
                    gemini_key = f.read().strip()
            except:
                pass
        if os.path.exists(openrouter_key_file):
            try:
                with open(openrouter_key_file, "r") as f:
                    openrouter_key = f.read().strip()
            except:
                pass

        # Dual-key logic: jika gemini_key starts with sk-or- -> backward compat sbg OR key
        if not openrouter_key and gemini_key and gemini_key.startswith("sk-or-"):
            openrouter_key = gemini_key
            gemini_key = ""

            try:
                if gemini_key or openrouter_key:'''

if old_key in content:
    content = content.replace(old_key, new_key, 1)
    changes += 1
    print("OK: Change 1 applied (key reading)")
else:
    print("WARN: Change 1 pattern not found")

# ========== CHANGE 2: API routing section ==========
# Replace the if/else sk-or- routing with dual-key routing
old_routing = '''                    if gemini_key.startswith("sk-or-"):
                        url = "https://openrouter.ai/api/v1/chat/completions"
                        headers = {"Authorization": f"Bearer {gemini_key}", "Content-Type": "application/json"}
                        messages = [{"role": "system", "content": prompt}, {"role": "user", "content": text}]
                        \n                        fallback_arrays = [
                            ["meta-llama/llama-3.3-70b-instruct:free", "qwen/qwen3-next-80b-a3b-instruct:free", "google/gemma-4-31b-it:free"],
                            ["nousresearch/hermes-3-llama-3.1-405b:free", "meta-llama/llama-3.2-3b-instruct:free", "openai/gpt-oss-120b:free"],
                            ["liquid/lfm-2.5-1.2b-instruct:free", "openrouter/free"]
                        ]
                        reply_text = ""
                        import urllib.error
                        for models in fallback_arrays:
                            payload = {"models": models, "messages": messages, "max_tokens": 400}
                            data = json.dumps(payload).encode("utf-8")
                            req = urllib.request.Request(url, data=data, headers=headers)
                            try:
                                with urllib.request.urlopen(req, timeout=20) as response:
                                    res = json.loads(response.read().decode())
                                    if "error" in res:
                                        reply_text = f"API Error: {res['error'].get('message', 'Unknown')}"
                                    else:
                                        content = res.get("choices", [{}])[0].get("message", {}).get("content")
                                        reply_text = f"API Error (Kosong): {json.dumps(res)}" if content is None else content.strip().replace("\\n", " ")
                                    break
                            except urllib.error.HTTPError as e:
                                err_msg = e.read().decode()
                                reply_text = f'Aduh otak AI gua lagi pusing bro wkwk. Error: {err_msg}'
                                continue
                            except Exception as e:
                                reply_text = f'Aduh otak AI gua lagi pusing bro wkwk. Error: {str(e)}'
                                continue
                        process_reply(reply_text)
                        return
                    else:'''

new_routing = '''                    # Dual-key routing: prefer OpenRouter if openrouter_key exists
                    if openrouter_key:
                        url = "https://openrouter.ai/api/v1/chat/completions"
                        headers = {"Authorization": f"Bearer {openrouter_key}", "Content-Type": "application/json"}
                        messages = [{"role": "system", "content": prompt}, {"role": "user", "content": text}]
                        \n                        fallback_arrays = [
                            ["meta-llama/llama-3.3-70b-instruct:free", "qwen/qwen3-next-80b-a3b-instruct:free", "google/gemma-4-31b-it:free"],
                            ["nousresearch/hermes-3-llama-3.1-405b:free", "meta-llama/llama-3.2-3b-instruct:free", "openai/gpt-oss-120b:free"],
                            ["liquid/lfm-2.5-1.2b-instruct:free", "openrouter/free"]
                        ]
                        reply_text = ""
                        import urllib.error
                        for models in fallback_arrays:
                            payload = {"models": models, "messages": messages, "max_tokens": 400}
                            data = json.dumps(payload).encode("utf-8")
                            req = urllib.request.Request(url, data=data, headers=headers)
                            try:
                                with urllib.request.urlopen(req, timeout=20) as response:
                                    res = json.loads(response.read().decode())
                                    if "error" in res:
                                        reply_text = f"API Error: {res['error'].get('message', 'Unknown')}"
                                    else:
                                        content = res.get("choices", [{}])[0].get("message", {}).get("content")
                                        reply_text = f"API Error (Kosong): {json.dumps(res)}" if content is None else content.strip().replace("\\n", " ")
                                    break
                            except urllib.error.HTTPError as e:
                                err_msg = e.read().decode()
                                reply_text = f'Aduh otak AI gua lagi pusing bro wkwk. Error: {err_msg}'
                                continue
                            except Exception as e:
                                reply_text = f'Aduh otak AI gua lagi pusing bro wkwk. Error: {str(e)}'
                                continue
                        \n                        # OR succeeded? Process reply and return.
                        # If all OR tiers failed, fall through to Gemini
                        if not reply_text.startswith("Aduh otak"):
                            process_reply(reply_text)
                            return
                        # OR failed silently - try Gemini below
                    else:'''

if old_routing in content:
    content = content.replace(old_routing, new_routing, 1)
    changes += 1
    print("OK: Change 2 applied (routing)")
else:
    print("WARN: Change 2 routing pattern not found. Trying alternate...")
    # The indentation might differ. Let me try matching "if gemini_key.startswith"
    if 'if gemini_key.startswith("sk-or-"):' in content:
        print("  Found: if gemini_key.startswith exists in file but exact pattern differs")
    else:
        print("  Not found: if gemini_key.startswith does not exist")

# ========== CHANGE 3: Gemini block + fallback ==========
# After the Gemini block, add fallback for when OR failed and no Gemini
# Find the Gemini block's return and add fallback after it
old_after_gemini = '''                        process_reply(reply_text)
                        return
            except Exception as e:'''

new_after_gemini = '''                        process_reply(reply_text)
                        return

                    # OR failed and no Gemini fallback - show the actual error
                    if openrouter_key and reply_text:
                        bot.reply_to(message, reply_text)
                        return
            except Exception as e:'''

if old_after_gemini in content:
    content = content.replace(old_after_gemini, new_after_gemini, 1)
    changes += 1
    print("OK: Change 3 applied (Gemini fallback)")
else:
    print("WARN: Change 3 pattern not found")

# Write result
with open(path, "w") as f:
    f.write(content)

# Validate syntax
try:
    ast.parse(content)
    print(f"\nSYNTAX OK - {changes} changes applied")
    sys.exit(0)
except SyntaxError as e:
    lines = content.split('\n')
    print(f"\nSYNTAX ERROR at line {e.lineno}: {e.msg}")
    start = max(0, e.lineno - 5)
    end = min(len(lines), e.lineno + 3)
    for j in range(start, end):
        marker = ">>>" if j == e.lineno - 1 else "   "
        print(f"{marker} {j+1}: {repr(lines[j])}")
    sys.exit(1)
