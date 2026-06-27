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
    c.execute('''CREATE TABLE IF NOT EXISTS downloads
                 (id INTEGER PRIMARY KEY AUTOINCREMENT, filename TEXT, url TEXT, source TEXT, size_bytes INTEGER, timestamp DATETIME DEFAULT CURRENT_TIMESTAMP)''')
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

elif CMD == "add_download":
    if len(sys.argv) < 7:
        sys.exit(1)
    filename = sys.argv[3]
    url = sys.argv[4]
    source = sys.argv[5]
    size_bytes = int(sys.argv[6])
    c.execute("INSERT INTO downloads (filename, url, source, size_bytes) VALUES (?, ?, ?, ?)", (filename, url, source, size_bytes))
    conn.commit()
    
    # Keep only the latest 1000 download records to prevent unbounded DB growth
    c.execute("""DELETE FROM downloads WHERE id NOT IN
                 (SELECT id FROM downloads ORDER BY id DESC LIMIT 1000)""")
    conn.commit()

elif CMD == "get_stats":
    c.execute("SELECT COUNT(*), SUM(size_bytes) FROM downloads")
    row = c.fetchone()
    total_count = row[0] or 0
    total_size = row[1] or 0
    
    c.execute("SELECT source, COUNT(*) FROM downloads GROUP BY source")
    sources = dict(c.fetchall())
    
    c.execute("SELECT filename, source, size_bytes, timestamp FROM downloads ORDER BY id DESC LIMIT 10")
    recent = [{"filename": r[0], "source": r[1], "size_bytes": r[2], "timestamp": r[3]} for r in c.fetchall()]
    
    print(json.dumps({
        "total_count": total_count,
        "total_size_bytes": total_size,
        "sources": sources,
        "recent": recent
    }))

elif CMD == "check_duplicate":
    if len(sys.argv) < 4:
        sys.exit(1)
    url = sys.argv[3]
    c.execute("SELECT id FROM downloads WHERE url = ?", (url,))
    if c.fetchone():
        print("True")
    else:
        print("False")

conn.close()
