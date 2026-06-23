#!/usr/bin/env python3
import sqlite3
import sys
import json
import os

if len(sys.argv) < 3:
    print("Usage: zdt_db.py <db_file> <cmd> [args...]")
    sys.exit(1)

DB_FILE = sys.argv[1]
CMD = sys.argv[2]

# Ensure directory exists
db_dir = os.path.dirname(DB_FILE)
if db_dir and not os.path.exists(db_dir):
    os.makedirs(db_dir, exist_ok=True)

try:
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS chat_history
                 (id INTEGER PRIMARY KEY AUTOINCREMENT, role TEXT, content TEXT)''')
    conn.commit()
except Exception as e:
    print(f"Error initializing DB: {e}", file=sys.stderr)
    sys.exit(1)

if CMD == "add":
    if len(sys.argv) < 5:
        sys.exit(1)
    role = sys.argv[3]
    content = sys.argv[4]
    
    # Insert new message
    c.execute("INSERT INTO chat_history (role, content) VALUES (?, ?)", (role, content))
    
    # Keep only the last 20 messages to prevent infinite DB growth and token overflow
    c.execute("""DELETE FROM chat_history WHERE id NOT IN 
                 (SELECT id FROM chat_history ORDER BY id DESC LIMIT 20)""")
    conn.commit()

elif CMD == "get_gemini_json":
    # Returns a comma-separated JSON string of message objects, ready to be injected into the parts array
    c.execute("SELECT role, content FROM chat_history ORDER BY id ASC")
    rows = c.fetchall()
    
    out_parts = []
    for r, content in rows:
        # Gemini roles must be "user" or "model"
        api_role = "model" if r != "user" else "user"
        # Create dict object for each message
        msg_obj = {"role": api_role, "parts": [{"text": content}]}
        out_parts.append(json.dumps(msg_obj))
    
    # Print them joined by commas so bash can easily construct the payload: [%s]
    print(", ".join(out_parts))

elif CMD == "get_openai_json":
    c.execute("SELECT role, content FROM chat_history ORDER BY id ASC")
    rows = c.fetchall()
    out_parts = []
    for r, content in rows:
        api_role = "assistant" if r != "user" else "user"
        msg_obj = {"role": api_role, "content": content}
        out_parts.append(json.dumps(msg_obj))
    print(", ".join(out_parts))

elif CMD == "get_count":
    c.execute("SELECT COUNT(*) FROM chat_history")
    count = c.fetchone()[0]
    print(count)

elif CMD == "clear":
    c.execute("DELETE FROM chat_history")
    conn.commit()

conn.close()
