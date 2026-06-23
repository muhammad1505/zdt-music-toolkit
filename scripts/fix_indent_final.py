#!/usr/bin/env python3
"""Fix indentation bug: try: is at 12 spaces inside if not openrouter_key block.
Should be at 8 spaces (same level as the if statement).
De-indent everything inside the try block by 4 spaces."""

import re

with open("zdt-telegram.py", "r") as f:
    content = f.read()

# Find the buggy section:
# The pattern: blank line, then "            try:" (12 spaces), then "                if gemini_key or openrouter_key:" (16 spaces)
# Should be: blank line, then "        try:" (8 spaces), then "            if gemini_key or openrouter_key:" (12 spaces)

# Strategy: Find the exact line that starts with "            try:" (12 spaces)
# and the matching "            except Exception as e:" (12 spaces)
# Then de-indent everything in between by 4 spaces

lines = content.split('\n')

# Find the buggy try and its matching except
try_line_idx = None
except_line_idx = None

for i, line in enumerate(lines):
    stripped = line.lstrip()
    indent = len(line) - len(stripped)
    if stripped == 'try:' and indent == 12:
        try_line_idx = i
    if stripped.startswith('except Exception as e:') and indent == 12 and try_line_idx is not None:
        except_line_idx = i
        break

if try_line_idx is None:
    print("ERROR: Could not find try: at 12 spaces")
    exit(1)

if except_line_idx is None:
    print("ERROR: Could not find matching except Exception as e:")
    exit(1)

print(f"Found try: at line {try_line_idx + 1}")
print(f"Found except at line {except_line_idx + 1}")

# De-indent everything from try_line_idx to except_line_idx (inclusive) by 4 spaces
for i in range(try_line_idx, except_line_idx + 1):
    line = lines[i]
    if line.lstrip():  # non-empty line
        stripped = line.lstrip()
        old_indent = len(line) - len(stripped)
        new_indent = old_indent - 4
        if new_indent < 0:
            print(f"WARNING: Line {i+1} would have negative indent! Skipping.")
        else:
            lines[i] = ' ' * new_indent + stripped

result = '\n'.join(lines)

with open("zdt-telegram.py", "w") as f:
    f.write(result)

# Validate syntax
import ast
try:
    ast.parse(result)
    print("SYNTAX OK")
except SyntaxError as e:
    print(f"SYNTAX ERROR: {e}")
    # Show the problematic line
    print(f"Line {e.lineno}: {result.split(chr(10))[e.lineno - 1] if e.lineno else 'N/A'}")
    exit(1)
