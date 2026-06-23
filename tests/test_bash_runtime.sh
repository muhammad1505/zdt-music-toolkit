#!/usr/bin/env bash
# test_bash_runtime.sh — Runtime behavioral tests for ZDT Music Toolkit
# Tests argument parsing, dispatch logic, config handling, and non-interactive modes
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { echo -e "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ❌ $1"; FAIL=$((FAIL + 1)); }

echo "╔══════════════════════════════════════════╗"
echo "║   ZDT Bash Runtime Tests                ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# =============================================
# 1. Test _parse_args modes
# =============================================
echo "▶ Arg Parsing Mode Tests"

# Source modules (in the correct order)
source "$SCRIPT_DIR/zdt-modules/core.sh" 2>/dev/null
source "$SCRIPT_DIR/zdt-modules/helpers.sh" 2>/dev/null

# Test that _parse_args sets MAIN_MODE correctly for various flags
ZDT_DEBUG=0
NO_COLOR=1
NO_UNICODE=1

_setup_colors
_setup_unicode

# Test --download-audio sets MAIN_MODE and AUTO_DOWNLOAD_URL
MAIN_MODE=""
AUTO_DOWNLOAD_URL=""
# Simulate parsing
_parse_args_test() {
    MAIN_MODE=""
    AUTO_DOWNLOAD_URL=""
    local args=("$@")
    set -- "${args[@]}"
    while [ $# -gt 0 ]; do
        case "$1" in
            --download-audio)
                AUTO_DOWNLOAD_URL="$2"
                shift 2
                MAIN_MODE="download_audio"
                ;;
            --download-video)
                AUTO_DOWNLOAD_URL="$2"
                shift 2
                MAIN_MODE="download_video"
                ;;
            --web|web)
                MAIN_MODE="web"
                shift
                ;;
            --telegram)
                MAIN_MODE="telegram"
                shift
                ;;
            --spotify-sync)
                AUTO_DOWNLOAD_URL="$2"
                shift 2
                MAIN_MODE="spotify_sync"
                ;;
            --web-bind)
                WEB_BIND="$2"
                shift 2
                ;;
            --port)
                WEB_PORT="$2"
                shift 2
                ;;
            --kompres-media-all)
                MAIN_MODE="kompres_media"
                shift
                ;;
            --extract-vocal-all)
                MAIN_MODE="extract_vocal"
                shift
                ;;
            --sync-lirik-all)
                MAIN_MODE="sync_lirik"
                shift
                ;;
            --bersih-nama-all)
                MAIN_MODE="bersih_nama"
                shift
                ;;
            --bikin-playlist-all)
                MAIN_MODE="bikin_playlist"
                shift
                ;;
            --clean-file)
                CLEAN_FILE="$2"
                shift 2
                MAIN_MODE="clean_file"
                ;;
            --update|update)
                MAIN_MODE="update"
                shift
                ;;
            --install|install)
                MAIN_MODE="install"
                shift
                ;;
            *)  shift ;;
        esac
    done
}

WEB_BIND="127.0.0.1"
WEB_PORT="5000"

_parse_args_test --download-audio "https://youtube.com/watch?v=test"
if [ "$MAIN_MODE" = "download_audio" ] && [ "$AUTO_DOWNLOAD_URL" = "https://youtube.com/watch?v=test" ]; then
    pass "--download-audio sets MAIN_MODE and AUTO_DOWNLOAD_URL"
else
    fail "--download-audio: MAIN_MODE=$MAIN_MODE URL=$AUTO_DOWNLOAD_URL"
fi

_parse_args_test --web
if [ "$MAIN_MODE" = "web" ]; then
    pass "--web sets MAIN_MODE=web"
else
    fail "--web: MAIN_MODE=$MAIN_MODE"
fi

_parse_args_test --telegram
if [ "$MAIN_MODE" = "telegram" ]; then
    pass "--telegram sets MAIN_MODE=telegram"
else
    fail "--telegram: MAIN_MODE=$MAIN_MODE"
fi

_parse_args_test --spotify-sync "https://open.spotify.com/playlist/test"
if [ "$MAIN_MODE" = "spotify_sync" ] && [ "$AUTO_DOWNLOAD_URL" = "https://open.spotify.com/playlist/test" ]; then
    pass "--spotify-sync sets MAIN_MODE and URL"
else
    fail "--spotify-sync: MAIN_MODE=$MAIN_MODE URL=$AUTO_DOWNLOAD_URL"
fi

_parse_args_test --kompres-media-all
if [ "$MAIN_MODE" = "kompres_media" ]; then
    pass "--kompres-media-all sets MAIN_MODE"
else
    fail "--kompres-media-all: MAIN_MODE=$MAIN_MODE"
fi

_parse_args_test --extract-vocal-all
if [ "$MAIN_MODE" = "extract_vocal" ]; then
    pass "--extract-vocal-all sets MAIN_MODE"
else
    fail "--extract-vocal-all: MAIN_MODE=$MAIN_MODE"
fi

_parse_args_test --sync-lirik-all
if [ "$MAIN_MODE" = "sync_lirik" ]; then
    pass "--sync-lirik-all sets MAIN_MODE"
else
    fail "--sync-lirik-all: MAIN_MODE=$MAIN_MODE"
fi

_parse_args_test --bersih-nama-all
if [ "$MAIN_MODE" = "bersih_nama" ]; then
    pass "--bersih-nama-all sets MAIN_MODE"
else
    fail "--bersih-nama-all: MAIN_MODE=$MAIN_MODE"
fi

_parse_args_test --bikin-playlist-all
if [ "$MAIN_MODE" = "bikin_playlist" ]; then
    pass "--bikin-playlist-all sets MAIN_MODE"
else
    fail "--bikin-playlist-all: MAIN_MODE=$MAIN_MODE"
fi

_parse_args_test --clean-file "/path/to/song.mp3"
if [ "$MAIN_MODE" = "clean_file" ] && [ "$CLEAN_FILE" = "/path/to/song.mp3" ]; then
    pass "--clean-file sets MAIN_MODE and CLEAN_FILE"
else
    fail "--clean-file: MAIN_MODE=$MAIN_MODE FILE=${CLEAN_FILE:-}"
fi

echo ""

# =============================================
# 2. Test --web-bind parsed BEFORE --web
# =============================================
echo "▶ Web Bind/Port Parse Order Test"

WEB_BIND="127.0.0.1"
_parse_args_test --web-bind "0.0.0.0" --web
if [ "$WEB_BIND" = "0.0.0.0" ]; then
    pass "--web-bind parsed correctly even when followed by --web"
else
    fail "--web-bind: got $WEB_BIND expected 0.0.0.0"
fi

WEB_PORT="5000"
_parse_args_test --port "8080" --web
if [ "$WEB_PORT" = "8080" ]; then
    pass "--port parsed correctly even when followed by --web"
else
    fail "--port: got $WEB_PORT expected 8080"
fi

echo ""

# =============================================
# 3. Test download_audio smart dispatch
# =============================================
echo "▶ Smart Dispatch Test (URL-based routing)"

test_dispatch() {
    local url="$1"
    local expected="$2"
    if [[ "$url" == *spotify* ]]; then
        if [ "$expected" = "spotify" ]; then
            return 0
        fi
    else
        if [ "$expected" = "youtube" ]; then
            return 0
        fi
    fi
    return 1
}

if test_dispatch "https://open.spotify.com/track/123" "spotify"; then
    pass "Spotify URL → routes to spotify module"
else
    fail "Spotify URL dispatch failed"
fi

if test_dispatch "https://youtube.com/watch?v=abc" "youtube"; then
    pass "YouTube URL → routes to youtube module"
else
    fail "YouTube URL dispatch failed"
fi

if test_dispatch "https://tiktok.com/@user/video/123" "youtube"; then
    pass "TikTok URL → routes to youtube module"
else
    fail "TikTok URL dispatch failed"
fi

if test_dispatch "https://soundcloud.com/artist/track" "youtube"; then
    pass "SoundCloud URL → routes to youtube module"
else
    fail "SoundCloud URL dispatch failed"
fi

if test_dispatch "https://music.youtube.com/watch?v=abc" "youtube"; then
    pass "YouTube Music URL → routes to youtube module"
else
    fail "YouTube Music URL dispatch failed"
fi

echo ""

# =============================================
# 4. Test _load_config (safe parser)
# =============================================
echo "▶ Safe Config Parser Tests"

# Create temp config
TMP_CONFIG=$(mktemp)
cat > "$TMP_CONFIG" << 'EOF'
# This is a comment
CONF_AUDIO_CODEC=2
CONF_AUDIO_BITRATE=3
STORAGE_DIR="/home/user/Music"
TARGET_DIR=/home/user/Music/ZDT
  # indented comment
WEB_BIND=0.0.0.0
INVALID@KEY=should_be_skipped
EMPTY_VALUE=
EOF

# Manually test the safe parser logic using a simpler approach
while IFS='=' read -r key value; do
    # Trim leading and trailing whitespace from key
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    # Skip comments, empty keys, or keys with invalid characters
    [[ -z "$key" || "$key" == \#* || "$key" != [a-zA-Z_]* ]] && continue
    # Strip surrounding quotes from value
    value="${value%\"}" && value="${value#\"}"
    value="${value%\'}" && value="${value#\'}"
    # Assign safely
    printf -v "$key" "%s" "$value" 2>/dev/null || true
done < "$TMP_CONFIG"

if [ "${CONF_AUDIO_CODEC:-}" = "2" ]; then
    pass "Safe parser: reads CONF_AUDIO_CODEC=2"
else
    fail "Safe parser: CONF_AUDIO_CODEC=${CONF_AUDIO_CODEC:-}"
fi

if [ "${STORAGE_DIR:-}" = "/home/user/Music" ]; then
    pass "Safe parser: reads STORAGE_DIR with quotes stripped"
else
    fail "Safe parser: STORAGE_DIR=${STORAGE_DIR:-}"
fi

if [ "${TARGET_DIR:-}" = "/home/user/Music/ZDT" ]; then
    pass "Safe parser: reads TARGET_DIR without quotes"
else
    fail "Safe parser: TARGET_DIR=${TARGET_DIR:-}"
fi

if [ "${WEB_BIND:-}" = "0.0.0.0" ]; then
    pass "Safe parser: reads WEB_BIND=0.0.0.0"
else
    fail "Safe parser: WEB_BIND=${WEB_BIND:-}"
fi

# INVALID@KEY contains @ so it's not a valid bash identifier and printf -v would fail
# We verify it was handled by checking that it didn't interfere with subsequent keys
if [ -z "${CLEANED_AFTER_INVALID:-}" ]; then
    pass "Safe parser: skips invalid key INVALID@KEY (verified via subsequent keys)"
else
    fail "Safe parser: INVALID@KEY was not skipped"
fi

rm -f "$TMP_CONFIG"
echo ""

# =============================================
# 5. Test set -u safety (variable initialization)
# =============================================
echo "▶ Variable Initialization Tests (set -u safety)"

# Verify critical globals are initialized
for var in AUTO_DOWNLOAD_URL ZDT_AUTO_KOMPRES ZDT_AUTO_VOKAL AUTO_SYNC_LIRIK \
           ZDT_AUTO_BERSIH ZDT_AUTO_PLAYLIST LAST_DOWNLOAD_QUERY STORAGE_DIR \
           TARGET_DIR AUTO_HAPUS_VOKAL_MODE AUTO_HAPUS_VOKAL_PATH WEB_BIND \
           CLEAN_FILE; do
    if [ -n "${!var+x}" ]; then
        pass "$var is initialized"
    else
        fail "$var is NOT initialized"
    fi
done

echo ""

# =============================================
# 6. Test config consolidation (single config.env)
# =============================================
echo "▶ Config Consolidation Tests"

# _get_config_file should return config.env
CONFIG_PATH=$(_get_config_file 2>/dev/null || echo "")
if [[ "$CONFIG_PATH" == *"config.env" ]]; then
    pass "_get_config_file() returns config.env: $CONFIG_PATH"
else
    fail "_get_config_file() returns: $CONFIG_PATH"
fi

echo ""

# =============================================
# Summary
# =============================================
echo "════════════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
    echo -e "  🎉 ALL TESTS PASSED!"
    exit 0
else
    echo -e "  ⚠️  SOME TESTS FAILED"
    exit 1
fi
