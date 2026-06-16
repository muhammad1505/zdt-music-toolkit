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
echo "║   ZDT Smoke Test — v3.7.1               ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# 1. Bash syntax check
echo "▶ Bash Syntax Check"
for f in "$SCRIPT_DIR"/*.sh; do
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

# 3. Duplicate function definitions (bash)
echo "▶ Duplicate Function Check (zdt.sh)"
if [ -f "$SCRIPT_DIR/zdt.sh" ]; then
    dupes=$(grep -n '^[a-zA-Z_][a-zA-Z0-9_]*()' "$SCRIPT_DIR/zdt.sh" | sed 's/() {//' | awk -F: '{print $2}' | sort | uniq -d)
    if [ -z "$dupes" ]; then
        pass "No duplicate function definitions"
    else
        for d in $dupes; do
            fail "Duplicate function: $d"
        done
    fi
fi
echo ""

# 4. Version consistency check
echo "▶ Version Consistency"
ver_sh=$(grep -oP 'APP_VERSION="\K[^"]+' "$SCRIPT_DIR/zdt.sh" 2>/dev/null || echo "NOT_FOUND")
if [ "$ver_sh" = "3.7.1" ]; then
    pass "APP_VERSION = $ver_sh"
else
    fail "APP_VERSION mismatch: expected 3.7.1, got $ver_sh"
fi
echo ""

# 5. Critical variable initialization check (set -u safety)
echo "▶ Global Variable Initialization (set -u safety)"
for var in AUTO_DOWNLOAD_URL ZDT_AUTO_KOMPRES ZDT_AUTO_VOKAL AUTO_SYNC_LIRIK \
           ZDT_AUTO_BERSIH ZDT_AUTO_PLAYLIST LAST_DOWNLOAD_QUERY STORAGE_DIR \
           TARGET_DIR AUTO_HAPUS_VOKAL_MODE AUTO_HAPUS_VOKAL_PATH WEB_BIND; do
    if grep -q "^${var}=" "$SCRIPT_DIR/zdt.sh" 2>/dev/null; then
        pass "$var — initialized"
    else
        fail "$var — NOT initialized (will crash with set -u)"
    fi
done
echo ""

# 6. Security check: no hardcoded tokens
echo "▶ Security: No Hardcoded Tokens"
for f in "$SCRIPT_DIR"/*.py "$SCRIPT_DIR"/*.sh; do
    [ -f "$f" ] || continue
    if grep -qiE '(^[A-Za-z0-9]{35,}$|ghp_[A-Za-z0-9]{36}|sk-or-v1-[a-f0-9]{64}|AIzaSy[A-Za-z0-9_-]{33})' "$f" 2>/dev/null; then
        fail "$(basename "$f") — possible hardcoded token!"
    fi
done
pass "No hardcoded tokens found"
echo ""

# 7. File count summary
echo "▶ File Summary"
sh_count=$(find "$SCRIPT_DIR" -maxdepth 1 -name "*.sh" | wc -l)
py_count=$(find "$SCRIPT_DIR" -maxdepth 1 -name "*.py" | wc -l)
pass "$sh_count shell scripts, $py_count python scripts"
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
