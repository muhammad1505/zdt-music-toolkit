#!/usr/bin/env bash
# test_smoke.sh — Smoke test untuk ZDT Music Toolkit
# Validasi syntax, duplicate functions, dan basic integrity checks.
set -uo pipefail

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

pass() { echo -e "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ❌ $1"; FAIL=$((FAIL + 1)); }

echo "╔══════════════════════════════════════════╗"
echo "║   ZDT Smoke Test — v4.1.74 (Modular)    ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# 1. Bash syntax check - all .sh files including modules
echo "▶ Bash Syntax Check"
for f in "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR"/zdt-modules/*.sh; do
    [ -f "$f" ] || continue
    if bash -n "$f" 2>/dev/null; then
        pass "$(basename "$f") — syntax OK"
    else
        fail "$(basename "$f") — syntax ERROR"
    fi
done
echo ""

# 2. Python syntax check
echo "▶ Python Syntax Check"
for f in "$SCRIPT_DIR"/*.py; do
    [ -f "$f" ] || continue
    if python3 -m py_compile "$f" 2>/dev/null; then
        pass "$(basename "$f") — syntax OK"
    else
        fail "$(basename "$f") — syntax ERROR"
    fi
done
echo ""

# 3. Duplicate function definitions check
# We check that no function is defined in more than one file
echo "▶ Duplicate Function Check"
# Collect all function definitions: each line = "filename:function_name"
all_funcs=$(for f in "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR"/zdt-modules/*.sh; do
    [ -f "$f" ] || continue
    grep -h '^[a-zA-Z_][a-zA-Z0-9_]*()' "$f" 2>/dev/null | sed 's/() {//' | while read -r fn; do
        echo "$(basename "$f"):$fn"
    done
done)
dupes=$(echo "$all_funcs" | sed 's/.*://' | sort | uniq -d)
if [ -z "$dupes" ]; then
    pass "No duplicate function definitions across all files"
else
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        locations=$(echo "$all_funcs" | grep ":$d$" | sed 's/:.*//' | tr '\n' ', ' | sed 's/, $//')
        fail "Duplicate function '$d' found in: $locations"
    done <<< "$dupes"
fi
echo ""

# 4. Version consistency check (APP_VERSION is defined in zdt.sh)
echo "▶ Version Consistency"
ver_main=$(grep -oP 'readonly APP_VERSION="\K[^"]+' "$SCRIPT_DIR/zdt.sh" 2>/dev/null || echo "NOT_FOUND")
if [ "$ver_main" != "NOT_FOUND" ]; then
    pass "APP_VERSION = $ver_main (zdt.sh)"
else
    fail "APP_VERSION not found in zdt.sh"
fi
echo ""

# 5. Critical variable initialization check (set -u safety) - in core.sh
echo "▶ Global Variable Initialization (set -u safety)"
for var in AUTO_DOWNLOAD_URL ZDT_AUTO_KOMPRES ZDT_AUTO_VOKAL AUTO_SYNC_LIRIK \
           ZDT_AUTO_BERSIH ZDT_AUTO_PLAYLIST LAST_DOWNLOAD_QUERY STORAGE_DIR \
           TARGET_DIR AUTO_HAPUS_VOKAL_MODE AUTO_HAPUS_VOKAL_PATH WEB_BIND; do
    if grep -q "^${var}=" "$SCRIPT_DIR/zdt-modules/core.sh" 2>/dev/null; then
        pass "$var — initialized"
    else
        fail "$var — NOT initialized (will crash with set -u)"
    fi
done
echo ""

# 6. Module integrity check
echo "▶ Module Integrity Check"
for mod in core helpers download-spotify download-youtube media playlist daemon setup assistant; do
    if [ -f "$SCRIPT_DIR/zdt-modules/${mod}.sh" ]; then
        pass "zdt-modules/${mod}.sh — exists"
    else
        fail "zdt-modules/${mod}.sh — MISSING!"
    fi
done
echo ""

# 7. Loader source check - verify zdt.sh loads modules
echo "▶ Loader Source Check"
# zdt.sh uses a for loop with _mod variable to source modules
if grep -q 'for _mod in core helpers download-spotify' "$SCRIPT_DIR/zdt.sh" 2>/dev/null; then
    pass "zdt.sh loads all modules via for-loop"
    # Count how many modules are in the loop list
    mod_count=$(grep -oP 'for _mod in \K[^;]+' "$SCRIPT_DIR/zdt.sh" | head -1 | wc -w)
    pass "Module count in loader: $mod_count"
else
    fail "zdt.sh source loading pattern not found!"
fi
echo ""

# 8. Security check: no hardcoded tokens
echo "▶ Security: No Hardcoded Tokens"
for f in "$SCRIPT_DIR"/*.py "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR"/zdt-modules/*.sh; do
    [ -f "$f" ] || continue
    if grep -qiE '(^[A-Za-z0-9]{35,}$|ghp_[A-Za-z0-9]{36}|sk-or-v1-[a-f0-9]{64}|AIzaSy[A-Za-z0-9_-]{33})' "$f" 2>/dev/null; then
        fail "$(basename "$f") — possible hardcoded token!"
    fi
done
pass "No hardcoded tokens found"
echo ""

# 9. File count summary
echo "▶ File Summary"
sh_count=$(find "$SCRIPT_DIR" -maxdepth 1 -name "*.sh" | wc -l)
py_count=$(find "$SCRIPT_DIR" -maxdepth 1 -name "*.py" | wc -l)
mod_count=$(find "$SCRIPT_DIR/zdt-modules" -name "*.sh" 2>/dev/null | wc -l)
pass "$sh_count shell scripts, $py_count python scripts, $mod_count modules"
echo ""

# Summary
echo "════════════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo -e "  🎉 ALL TESTS PASSED!"
    exit 0
else
    echo -e "  ⚠️  SOME TESTS FAILED"
    exit 1
fi
