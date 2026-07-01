#!/usr/bin/env bash
export LC_ALL=C.UTF-8
#
# zdt.sh — Universal Music Toolkit (Modular Build)
# Version : (dibaca dari file VERSION di project root)
set -uo pipefail

# === Baca APP_VERSION dari VERSION file (single source of truth) ===
_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_APP_VERSION=""
# Coba cari VERSION di repo root (dev mode) atau share dir (installed)
if [ -f "$_SCRIPT_DIR/VERSION" ]; then
    _APP_VERSION="$(cat "$_SCRIPT_DIR/VERSION" | tr -d '[:space:]')"
else
    for _share_check in "$HOME/.local/share/zdt" "/usr/local/share/zdt" "/data/data/com.termux/files/usr/share/zdt"; do
        if [ -f "$_share_check/VERSION" ]; then
            _APP_VERSION="$(cat "$_share_check/VERSION" | tr -d '[:space:]')"
            break
        fi
    done
fi
readonly APP_VERSION="${_APP_VERSION:-4.4.54}"
export ZDT_VERSION="$APP_VERSION"

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
SCRIPT_DIR="$_SCRIPT_DIR"
ORIGINAL_ARGS=("$@")

_MODULES_DIR="$SCRIPT_DIR/zdt-modules"
if [ ! -d "$_MODULES_DIR" ]; then
    for _share_dir in "$HOME/.local/share/zdt/zdt-modules" "/usr/local/share/zdt/zdt-modules" "/data/data/com.termux/files/usr/share/zdt/zdt-modules"; do
        if [ -d "$_share_dir" ]; then
            _MODULES_DIR="$_share_dir"
            break
        fi
    done
fi

if [ ! -d "$_MODULES_DIR" ]; then
    echo "Migration: Downloading core modules from GitHub..."
    _MODULES_DIR="$HOME/.local/share/zdt/zdt-modules"
    mkdir -p "$_MODULES_DIR" 2>/dev/null
    for _mod in core helpers download-spotify download-youtube media playlist daemon setup assistant; do
        curl -sL "https://raw.githubusercontent.com/muhammad1505/zdt-music-toolkit/main/zdt-modules/${_mod}.sh?t=$(date +%s)" -o "$_MODULES_DIR/${_mod}.sh" 2>/dev/null
    done
    # Download database helper
    curl -sL "https://raw.githubusercontent.com/muhammad1505/zdt-music-toolkit/main/zdt-modules/zdt_db.py?t=$(date +%s)" -o "$_MODULES_DIR/zdt_db.py" 2>/dev/null
fi

if [ -d "$_MODULES_DIR" ]; then
    # === Resolve canonical _MODULES_DIR path BEFORE source ===
    # This ensures readonly variables (ZDT_DB_HELPER) capture the correct path
    if command -v _get_share_dir >/dev/null 2>&1; then
        _CACHED_SHARE_DIR="$(_get_share_dir)"
        _mods_candidate="$_CACHED_SHARE_DIR/zdt-modules"
        # Only override _MODULES_DIR if the canonical share dir actually has modules
        if [ -d "$_mods_candidate" ]; then
            _MODULES_DIR="$_mods_candidate"
        fi
        # Write VERSION file to share dir (single source of truth for Python scripts)
        echo "$APP_VERSION" > "$_CACHED_SHARE_DIR/VERSION" 2>/dev/null || true
    fi

    for _mod in core helpers download-spotify download-youtube media playlist daemon setup assistant; do
        if [ -f "$_MODULES_DIR/${_mod}.sh" ]; then
            source "$_MODULES_DIR/${_mod}.sh"
        fi
    done
else
    echo "Error: Module directory not found and failed to download!"
    exit 1
fi

# === Post-source: refresh VERSION in case _get_share_dir wasn't available earlier ===
if command -v _get_share_dir >/dev/null 2>&1; then
    echo "$APP_VERSION" > "$(_get_share_dir)/VERSION" 2>/dev/null || true
fi

MAIN_MODE=""
DEBUG_TRAP_SET=false
FORCE_MOBILE=0

main() {
    _parse_args "$@"
    if [ -n "$MAIN_MODE" ]; then
        _setup_colors; _setup_unicode; _init_logging; _load_config; _load_storage_dir
        ROOT_DIR="$(pwd)"
        [ -n "$STORAGE_DIR" ] && ROOT_DIR="$STORAGE_DIR"
        if [ "$ROOT_DIR" != "$(pwd)" ]; then
            cd "$ROOT_DIR" || true
        fi
        case "$MAIN_MODE" in
            download_audio)
                if [[ "$AUTO_DOWNLOAD_URL" == *spotify* ]]; then
                    download_spotdl
                else
                    download_ytdlp
                fi
                ;;
            download_video) download_video ;;
            spotify_sync) sync_spotify_playlist ;;
            kompres_media) _kompres_audio_batch ;;
            extract_vocal) AUTO_HAPUS_VOKAL_MODE="1"; hapus_vokal ;;
            sync_lirik) AUTO_SYNC_LIRIK="1"; auto_sync_lirik ;;
            bersih_nama) bersih_nama_otomatis "." "all" ;;
            bikin_playlist) bikin_playlist ;;
            web) start_web_dashboard ;;
            telegram) start_telegram_bot ;;
        esac
        # Cleanup network monitor before exit to prevent zombie processes
        [ -n "$NET_PID" ] && kill -9 "$NET_PID" 2>/dev/null
        [ -n "$NET_TMP" ] && rm -f "$NET_TMP" 2>/dev/null
        exit 0
    fi
    _setup_colors; _setup_unicode; _init_logging; _load_config
    RUNTIME_ENV=$(_detect_environment)
    ROOT_DIR="$(pwd)"
    _load_storage_dir
    [ -n "$STORAGE_DIR" ] && ROOT_DIR="$STORAGE_DIR"
    if [ "$ROOT_DIR" != "$(pwd)" ]; then
        cd "$ROOT_DIR" || echo -e "  ${YELLOW}${ICO_WARN} Gagal pindah ke $ROOT_DIR. Menggunakan $(pwd)${RESET}"
    fi
    if ! _acquire_lock; then exit 1; fi
    _setup_traps
    DEBUG_TRAP_SET=true
    if [ "${ZDT_DEBUG:-0}" = "1" ]; then trap 'echo "==ERR at line $LINENO (rc=$?)" >&2' ERR; fi
    # Use mktemp with validation; fallback creates a proper file, not a string
    NET_TMP=$(mktemp "${TMPDIR:-/tmp}/zdt_net_XXXXXX" 2>/dev/null || { touch "/tmp/.zdt_net_$$" 2>/dev/null && echo "/tmp/.zdt_net_$$"; } || echo "")
    NET_PID=""
    if [ -n "$NET_TMP" ] && [ -f "$NET_TMP" ] && [ -z "${TERMUX_VERSION:-}" ]; then
        # Network monitor: check every 30s (skip on Termux — no raw socket ping)
        ( while true; do
            if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then echo "1" > "$NET_TMP"; else echo "0" > "$NET_TMP"; fi
            sleep 30
        done 2>/dev/null ) &
        NET_PID=$!
        disown "$NET_PID" 2>/dev/null
    fi
    # On Termux/proot: one-time fast check via /proc/net/route
    if [ -n "${TERMUX_VERSION:-}" ] && [ -f /proc/net/route ]; then
        grep -q '^\w\+' /proc/net/route 2>/dev/null && echo "1" > "$NET_TMP" || echo "0" > "$NET_TMP"
    fi
    _log "INFO" "ZDT started in $(pwd)"
    
    # Initialize UI cache (cache tool status, OS info, system stats)
    _init_ui_cache
    
    # Service status (cached per loop iteration)
    local _svc_cache_time=0
    local _svc_web="OFF" _svc_tele="OFF" _svc_watch="OFF"
    
    # Zaki AI diakses via tombol [A] di menu (tidak auto-launch biar loading cepet)
    
    while true; do
        # Use cached values (updated once at init) instead of recomputing every iteration
        # Fast-changing stats (RAM, uptime, storage) refresh each loop via /proc reads
        _refresh_stats_cache
        local ram_pct="$_ZDT_CACHED_RAM"
        local uptime_val="$_ZDT_CACHED_UPTIME"
        local storage_pct="$_ZDT_CACHED_STORAGE"
        
        # Service status (refresh every 10s to avoid pgrep spam)
        local svc_now=${EPOCHSECONDS:-$(date +%s 2>/dev/null || echo 0)}
        if [ $(( svc_now - _svc_cache_time )) -ge 10 ] || [ "$_svc_cache_time" -eq 0 ]; then
            local svc_raw
            svc_raw=$(_get_service_status)
            _svc_web="${svc_raw%%|*}"; svc_raw="${svc_raw#*|}"
            _svc_tele="${svc_raw%%|*}"; _svc_watch="${svc_raw##*|}"
            _svc_cache_time=$svc_now
        fi
        local os_name="$_ZDT_CACHED_OS_NAME"
        local net_status=$(cat "$NET_TMP" 2>/dev/null || echo "?")
        local tools_ok="$_ZDT_CACHED_TOOLS_STR"
        
        if [ -z "${NO_COLOR:-}" ]; then
            echo -ne "\033[?25h"
            clear
        fi
        local current_user="$_ZDT_CACHED_USER"
        local net_str="OFFLINE"
        local net_col="${RED}"
        if [ "$net_status" = "1" ]; then
            net_str="ONLINE "
            net_col="${GREEN}"
        fi

        local cols=$(tput cols 2>/dev/null || echo 100)
        local lines=$(tput lines 2>/dev/null || echo 30)
        
        local temp="$_ZDT_CACHED_TEMP"
        local kernel_ver="$_ZDT_CACHED_KERNEL"
        local arch="$_ZDT_CACHED_ARCH"
        local pkgs="$_ZDT_CACHED_PKGS"
        local load_avg="$_ZDT_CACHED_LOAD"
        
        if [ "$cols" -ge 75 ] && [ "${RUNTIME_ENV:-}" != "termux" ] && [ "$FORCE_MOBILE" -ne 1 ]; then
            # ──────────────────────────────────────────────────────────
            # DESKTOP VIEW — "ZDT Studio Console" v5.0
            # Split-pane layout with brand identity, resource bars,
            # categorized menu grid, and system info panel
            # ──────────────────────────────────────────────────────────
            local inner_cols=$(( cols - 4 ))
            [ "$inner_cols" -gt 106 ] && inner_cols=106
            [ "$inner_cols" -lt 56 ] && inner_cols=56
            local left_width=44
            local right_width=$(( inner_cols - left_width - 1 ))
            if [ "$right_width" -lt 30 ]; then
                right_width=30
                left_width=$(( inner_cols - right_width - 1 ))
            fi
            [ "$left_width" -lt 30 ] && left_width=30

            # ── Service status dots ──
            local svc_web_state="off"
            [ "$_svc_web" = "ON" ] && svc_web_state="on"
            local svc_tele_state="off"
            [ "$_svc_tele" = "ON" ] && svc_tele_state="on"
            local svc_watch_state="off"
            [ "$_svc_watch" = "ON" ] && svc_watch_state="on"
            local svc_web_dot=$(_draw_status_dot "$svc_web_state" "small")
            local svc_tele_dot=$(_draw_status_dot "$svc_tele_state" "small")
            local svc_watch_dot=$(_draw_status_dot "$svc_watch_state" "small")

            local st_dot_state="on"
            [ "$storage_pct" -gt 85 ] && st_dot_state="warn"
            [ "$storage_pct" -gt 95 ] && st_dot_state="off"
            local st_dot=$(_draw_status_dot "$st_dot_state" "small")
            local _st_dot_small=$(_draw_status_dot "$st_dot_state" "small")

            local ai_dot_state="off"
            [ -f "$HOME/.config/zdt/gemini_key" ] && ai_dot_state="on"
            local ai_dot=$(_draw_status_dot "$ai_dot_state" "small")
            local _ai_dot_small=$(_draw_status_dot "$ai_dot_state" "small")
            local _net_small=$(_draw_status_dot "$([ "$net_status" = "1" ] && echo "on" || echo "off")")

            # ── TOP HEADER ──
            _draw_split_top $left_width $right_width

            # Row 1: Brand identity
            local logo_text=" ${BOLD}${WHITE}ZDT${RESET} ${CYAN}Music Toolkit${RESET} ${DIM}v${APP_VERSION}${RESET}"
            local _dm_dot=$(_draw_status_dot "$([ "$_svc_watch" = "ON" ] || [ "$_svc_web" = "ON" ] || [ "$_svc_tele" = "ON" ] && echo "on" || echo "off")" "small")
            local status_text=" ${_st_dot_small} ${DIM}STORAGE${RESET}  ${_ai_dot_small} ${DIM}AI${RESET}  ${_dm_dot} ${DIM}DM${RESET}  ${_net_small} ${DIM}NET${RESET}"
            _draw_split_row "$logo_text" "$status_text" $left_width $right_width

            # Row 2: Environment + services
            local env_text=" ${DIM}${os_name:0:22}${RESET} ${DIM}│${RESET} ${DIM}UPT${RESET} ${uptime_val:0:10}"
            local svc_text=" ${svc_web_dot} ${DIM}WEB${RESET}  ${svc_tele_dot} ${DIM}TELE${RESET}  ${svc_watch_dot} ${DIM}WATCH${RESET}"
            _draw_split_row "$env_text" "$svc_text" $left_width $right_width

            # ── RESOURCE BARS ──
            _draw_split_sep $left_width $right_width
            local cpu_val="${_ZDT_CACHED_CPU:-0}"; [ "$cpu_val" = "?" ] && cpu_val=0
            local left_bars=" ${DIM}RAM${RESET} $(_draw_bar "$ram_pct" 12)  ${DIM}CPU${RESET} $(_draw_bar "$cpu_val" 12)"
            local right_bars=" ${DIM}DSK${RESET} $(_draw_bar "$storage_pct" 16)"
            _draw_split_row "$left_bars" "$right_bars" $left_width $right_width

            # ── MIDDLE DIVIDER ──
            _draw_split_sep $left_width $right_width

            # ── BUILD LEFT (Menu categories) and RIGHT (System info) ──
            # __SEP__ markers insert ═ separators; per-section boundary alignment
            # is handled at render time (full split when both sides are SEP,
            # mixed content+SEP when only one side needs a boundary).

            local _ci=18 _sepl="$_ZDT_BORDER_PRIMARY$(_repeat_char '═' $left_width)${RESET}"
            local _sepr="$_ZDT_BORDER_PRIMARY$(_repeat_char '═' $right_width)${RESET}"
            local left_items=() right_items=()

            # ── LEFT: DOWNLOAD ──
            left_items+=(" ${BOLD}${CYAN}▸${RESET} DOWNLOAD")
            left_items+=("__SEP__")
            left_items+=("$(_pad_str " ${CYAN}[1]${RESET} Spotify" $_ci) $(_pad_str " ${CYAN}[5]${RESET} Vocal" 25)")
            left_items+=("$(_pad_str " ${CYAN}[2]${RESET} YT Audio" $_ci) $(_pad_str " ${CYAN}[6]${RESET} Lyrics" 25)")
            left_items+=("$(_pad_str " ${CYAN}[3]${RESET} Video DL" $_ci) $(_pad_str " ${CYAN}[7]${RESET} Playlist" 25)")
            left_items+=("$(_pad_str " ${CYAN}[4]${RESET} Compress" $_ci) $(_pad_str " ${CYAN}[8]${RESET} Sync" 25)")
            left_items+=("__SEP__")
            left_items+=(" ${BOLD}${MAGENTA}▸${RESET} TOOLS")
            left_items+=("__SEP__")
            left_items+=("$(_pad_str " ${BLUE}[S]${RESET} Storage" $_ci) $(_pad_str " ${BLUE}[W]${RESET} Watch" 25)")
            left_items+=("$(_pad_str " ${BLUE}[T]${RESET} Telegram" $_ci) $(_pad_str " ${BLUE}[V]${RESET} Web UI" 25)")
            left_items+=("$(_pad_str " ${BLUE}[P]${RESET} Playlist" $_ci) $(_pad_str " ${BLUE}[M]${RESET} Metadata" 25)")
            left_items+=("$(_pad_str " ${BLUE}[O]${RESET} Clean" $_ci) $(_pad_str " ${BLUE}[A]${RESET} Zaki AI" 25)")
            left_items+=("__SEP__")
            left_items+=(" ${BOLD}${YELLOW}▸${RESET} SETTINGS")
            left_items+=("__SEP__")
            left_items+=("$(_pad_str " ${GREEN}[9]${RESET} System" $_ci) $(_pad_str " ${RED}[X]${RESET} Delete" 25)")
            left_items+=("$(_pad_str " ${GREEN}[U]${RESET} Update" $_ci) $(_pad_str " ${RED}[R]${RESET} Uninstall" 25)")

            # ── RIGHT: TOOLS STATUS + ENVIRONMENT ──
            local _dot_on="${GREEN}•${RESET}" _dot_off="${RED}∘${RESET}" _d="${DIM}"
            local _ico_ff=$([ "$_ZDT_CACHED_FFMPEG" = "1" ] && echo "$_dot_on" || echo "$_dot_off")
            local _ico_py=$([ "$_ZDT_CACHED_PYTHON3" = "1" ] && echo "$_dot_on" || echo "$_dot_off")
            local _ico_yt=$([ "$_ZDT_CACHED_YTDLP" = "1" ] && echo "$_dot_on" || echo "$_dot_off")
            local _ico_sp=$([ "$_ZDT_CACHED_SPOTDL" = "1" ] && echo "$_dot_on" || echo "$_dot_off")
            local _ico_dm=$([ "$_ZDT_CACHED_DEMUCS" = "1" ] && echo "$_dot_on" || echo "$_dot_off")
            local _ico_mu=$([ "$_ZDT_CACHED_MUTAGEN" = "1" ] && echo "$_dot_on" || echo "$_dot_off")
            local _ico_fl=$([ -f "${ZDT_VENV_DIR:-$HOME/.local/share/zdt/venv}/bin/flask" ] && echo "$_dot_on" || echo "$_dot_off")
            local _ico_tb="$_dot_off"
            for _tb_p in "${ZDT_VENV_DIR:-$HOME/.local/share/zdt/venv}/lib/python3."*/site-packages/telebot/__init__.py; do
                [ -f "$_tb_p" ] && { _ico_tb="$_dot_on"; break; }
            done 2>/dev/null
            local _ico_wd="$_dot_off"
            for _wd_p in "${ZDT_VENV_DIR:-$HOME/.local/share/zdt/venv}/lib/python3."*/site-packages/watchdog/__init__.py; do
                [ -f "$_wd_p" ] && { _ico_wd="$_dot_on"; break; }
            done 2>/dev/null
            local _tc1=11
            local _tc2=$(( right_width - _tc1 - 2 ))
            right_items+=(" ${BOLD}${GREEN}▸${RESET} ${BOLD}${GREEN}TOOLS STATUS${RESET}")
            right_items+=("__SEP__")
            right_items+=(" $(_pad_str "${_ico_ff} ${_d}ffmpeg${RESET}" $_tc1) $(_pad_str "${_ico_py} ${_d}Python 3${RESET}" $_tc2)")
            right_items+=(" $(_pad_str "${_ico_yt} ${_d}yt-dlp${RESET}" $_tc1) $(_pad_str "${_ico_sp} ${_d}spotdl${RESET}" $_tc2)")
            right_items+=(" $(_pad_str "${_ico_dm} ${_d}Demucs${RESET}" $_tc1) $(_pad_str "${_ico_mu} ${_d}Mutagen${RESET}" $_tc2)")
            right_items+=(" $(_pad_str "${_ico_fl} ${_d}Flask${RESET}" $_tc1) $(_pad_str "${_ico_tb} ${_d}Telebot${RESET}" $_tc2)")
            right_items+=(" $(_pad_str "${_ico_wd} ${_d}Watchdog${RESET}" $(( right_width - 1 )))")
            right_items+=("__SEP__")
            local _ew=8
            right_items+=(" ${BOLD}${CYAN}▸${RESET} ${BOLD}${CYAN}ENVIRONMENT${RESET}")
            right_items+=("__SEP__")
            right_items+=(" $(_pad_str "${DIM}Kernel${RESET}" $_ew) ${DIM}:${RESET} ${kernel_ver:0:18}")
            right_items+=(" $(_pad_str "${DIM}Arch${RESET}" $_ew) ${DIM}:${RESET} ${arch}")
            right_items+=(" $(_pad_str "${DIM}Packages${RESET}" $_ew) ${DIM}:${RESET} ${pkgs}")
            right_items+=(" $(_pad_str "${DIM}Load${RESET}" $_ew) ${DIM}:${RESET} ${load_avg:0:20}")
            [ "$temp" != "N/A" ] && right_items+=(" $(_pad_str "${DIM}Temp${RESET}" $_ew) ${DIM}:${RESET} ${temp}") || right_items+=("")
            # Balance row counts
            local lc=${#left_items[@]} rc=${#right_items[@]}
            if [ "$lc" -lt "$rc" ]; then
                for ((_i=lc; _i<rc; _i++)); do left_items+=(""); done
            elif [ "$rc" -lt "$lc" ]; then
                for ((_i=rc; _i<lc; _i++)); do right_items+=(""); done
            fi
            local mx=${#left_items[@]}; [ "${#right_items[@]}" -gt "$mx" ] && mx=${#right_items[@]}

            # Render — handle __SEP__ for per-panel ═ dividers
            for ((ri=0; ri<mx; ri++)); do
                local lv="${left_items[ri]:-}" rv="${right_items[ri]:-}"
                [ -z "$lv" ] && [ -z "$rv" ] && continue
                if [ "$lv" = "__SEP__" ] && [ "$rv" = "__SEP__" ]; then
                    _draw_split_sep $left_width $right_width
                elif [ "$lv" = "__SEP__" ]; then
                    _draw_split_row "$_sepl" "$rv" $left_width $right_width
                elif [ "$rv" = "__SEP__" ]; then
                    _draw_split_row "$lv" "$_sepr" $left_width $right_width
                else
                    _draw_split_row "$lv" "$rv" $left_width $right_width
                fi
            done

            # ── BOTTOM SHORTCUT BAR with context-sensitive shortcuts ──
            _draw_footer $inner_cols "0" "Exit" "?" "Help" "T" "Telegram" "V" "Web UI"
        else
            # MOBILE VIEW — Responsive compact layout with 3 tiers
            local inner_cols=$(( cols - 4 ))
            [ "$inner_cols" -lt 28 ] && inner_cols=28
            # Cyberpunk mode for mobile
            local _tlc="╭" _trc="╮" _blc="╰" _brc="╯" _hc="─" _vc="│"
            local _sec_bullet="▸" _brand_color="$CYAN"

            local header_prefix=" ${_brand_color}${BOLD}◈${RESET} ${_brand_color}ZDT${RESET} ${DIM}v${APP_VERSION}${RESET}"

            # ── TIER 1: Ultra-narrow (<42 cols) ──
            if [ "$inner_cols" -lt 42 ]; then
                local hdr=" ${header_prefix} ${DIM}|${RESET} ${DIM}RAM${RESET} ${ram_pct}% "
                local hdr_pad=$(_pad_str "$hdr" $inner_cols)
                echo -e "  ${_brand_color}${_tlc}$(_repeat_char "${_hc}" $inner_cols)${_trc}${RESET}"
                echo -e "  ${_brand_color}${_vc}${RESET}${hdr_pad}${_brand_color}${_vc}${RESET}"
                echo -e "  ${_brand_color}${_vc}$(_repeat_char "${_hc}" $inner_cols)${_vc}${RESET}"

                local menu_items=(
                    " ${BOLD}${CYAN}${_sec_bullet}${RESET} ${BOLD}${CYAN}MAIN${RESET}"
                    "DIVIDER"
                    " ${CYAN}[1]${RESET} Setup    ${CYAN}[6]${RESET} Vocal${RESET}"
                    " ${CYAN}[2]${RESET} Spotify  ${CYAN}[7]${RESET} Lyrics${RESET}"
                    " ${CYAN}[3]${RESET} YT Aud   ${CYAN}[8]${RESET} PlSync${RESET}"
                    " ${CYAN}[4]${RESET} Video    ${CYAN}[9]${RESET} Info${RESET}"
                    " ${CYAN}[5]${RESET} Compress${RESET}"
                    "DIVIDER"
                    " ${BOLD}${MAGENTA}${_sec_bullet}${RESET} ${BOLD}${MAGENTA}TOOLS${RESET}"
                    "DIVIDER"
                    " ${BLUE}[S]${RESET} Storage  ${BLUE}[W]${RESET} Watch${RESET}"
                    " ${BLUE}[P]${RESET} Playlist ${BLUE}[M]${RESET} Meta${RESET}"
                    " ${BLUE}[O]${RESET} Clean    ${BLUE}[T]${RESET} Tele${RESET}"
                    " ${BLUE}[V]${RESET} Web UI   ${BLUE}[U]${RESET} Update${RESET}"
                    " ${BLUE}[A]${RESET} Zaki AI  ${RED}[X]${RESET} Delete${RESET}"
                    "DIVIDER"
                    " ${MAGENTA}[R]${RESET} Uninstall  ${RED}[0]${RESET} Exit${RESET}"
                )

            # ── TIER 2: Narrow (42-54 cols) ──
            elif [ "$inner_cols" -lt 55 ]; then
                local hdr=" ${header_prefix} ${DIM}|${RESET} ${DIM}RAM${RESET} ${ram_pct}% ${DIM}CPU${RESET} ${cpu_val}% "
                local hdr_pad=$(_pad_str "$hdr" $inner_cols)
                echo -e "  ${_brand_color}${_tlc}$(_repeat_char "${_hc}" $inner_cols)${_trc}${RESET}"
                echo -e "  ${_brand_color}${_vc}${RESET}${hdr_pad}${_brand_color}${_vc}${RESET}"
                echo -e "  ${_brand_color}${_vc}$(_repeat_char "${_hc}" $inner_cols)${_vc}${RESET}"

                local menu_items=(
                    " ${BOLD}${CYAN}${_sec_bullet}${RESET} ${BOLD}${CYAN}DOWNLOAD${RESET}"
                    "DIVIDER"
                    "  ${CYAN}[1]${RESET} Setup    ${CYAN}[6]${RESET} Vocal${RESET}"
                    "  ${CYAN}[2]${RESET} Spotify  ${CYAN}[7]${RESET} Lyrics${RESET}"
                    "  ${CYAN}[3]${RESET} YT Audio ${CYAN}[8]${RESET} PlSync${RESET}"
                    "  ${CYAN}[4]${RESET} Video DL ${CYAN}[9]${RESET} System${RESET}"
                    "  ${CYAN}[5]${RESET} Compress${RESET}"
                    "DIVIDER"
                    " ${BOLD}${MAGENTA}${_sec_bullet}${RESET} ${BOLD}${MAGENTA}TOOLS${RESET}"
                    "DIVIDER"
                    "  ${BLUE}[S]${RESET} Storage  ${BLUE}[W]${RESET} Watch${RESET}"
                    "  ${BLUE}[P]${RESET} Playlist ${BLUE}[M]${RESET} Meta${RESET}"
                    "  ${BLUE}[O]${RESET} Clean    ${BLUE}[T]${RESET} Tele${RESET}"
                    "  ${BLUE}[V]${RESET} Web UI   ${BLUE}[U]${RESET} Update${RESET}"
                    "  ${BLUE}[A]${RESET} Zaki AI  ${RED}[X]${RESET} Delete${RESET}"
                    "DIVIDER"
                    " ${MAGENTA}[R]${RESET} Uninstall   ${RED}[0]${RESET} Exit${RESET}"
                )

            # ── TIER 3: Medium (55-74 cols) — full layout with resource bars ──
            else
                local hdr=" ${header_prefix} ${DIM}|${RESET} ${DIM}RAM${RESET} ${ram_pct}% ${DIM}DSK${RESET} ${storage_pct}% ${DIM}UPT${RESET} ${uptime_val} "
                local hdr_pad=$(_pad_str "$hdr" $inner_cols)
                echo -e "  ${_brand_color}${_tlc}$(_repeat_char "${_hc}" $inner_cols)${_trc}${RESET}"
                echo -e "  ${_brand_color}${_vc}${RESET}${hdr_pad}${_brand_color}${_vc}${RESET}"
                echo -e "  ${_brand_color}${_vc}$(_repeat_char "${_hc}" $inner_cols)${_vc}${RESET}"

                # Quick resource bar (compact, auto-colored)
                local bar_width=$(( (inner_cols - 10) / 3 ))
                [ "$bar_width" -lt 5 ] && bar_width=5
                [ "$bar_width" -gt 10 ] && bar_width=10
                local ram_b=$(_draw_bar "$ram_pct" "$bar_width" "" false)
                local cpu_b=$(_draw_bar "$cpu_val" "$bar_width" "" false)
                local st_b=$(_draw_bar "$storage_pct" "$bar_width" "" false)
                local bars_line="${DIM}RAM${RESET} ${ram_b}  ${DIM}CPU${RESET} ${cpu_b}  ${DIM}DSK${RESET} ${st_b}"
                local bars_pad=$(_pad_str " $bars_line" $inner_cols)
                echo -e "  ${_brand_color}${_vc}${RESET}${bars_pad}${_brand_color}${_vc}${RESET}"
                echo -e "  ${_brand_color}${_vc}$(_repeat_char "${_hc}" $inner_cols)${_vc}${RESET}"

                local menu_items=(
                    " ${BOLD}${CYAN}${_sec_bullet}${RESET} ${BOLD}${CYAN}DOWNLOAD${RESET}"
                    "DIVIDER"
                    "  ${CYAN}[1]${RESET} Setup      ${CYAN}[6]${RESET} Vocal${RESET}"
                    "  ${CYAN}[2]${RESET} Spotify    ${CYAN}[7]${RESET} Lyrics${RESET}"
                    "  ${CYAN}[3]${RESET} YT Audio   ${CYAN}[8]${RESET} PlSync${RESET}"
                    "  ${CYAN}[4]${RESET} Video DL   ${CYAN}[9]${RESET} System${RESET}"
                    "  ${CYAN}[5]${RESET} Compress${RESET}"
                    "DIVIDER"
                    " ${BOLD}${MAGENTA}${_sec_bullet}${RESET} ${BOLD}${MAGENTA}TOOLS${RESET}"
                    "DIVIDER"
                    "  ${BLUE}[S]${RESET} Storage   ${BLUE}[W]${RESET} Watch${RESET}"
                    "  ${BLUE}[P]${RESET} Playlist  ${BLUE}[M]${RESET} Meta${RESET}"
                    "  ${BLUE}[O]${RESET} Clean     ${BLUE}[T]${RESET} Tele${RESET}"
                    "  ${BLUE}[V]${RESET} Web UI    ${BLUE}[U]${RESET} Update${RESET}"
                    "  ${BLUE}[A]${RESET} Zaki AI   ${RED}[X]${RESET} Delete${RESET}"
                    "DIVIDER"
                    " ${MAGENTA}[R]${RESET} Uninstall    ${RED}[0]${RESET} Exit${RESET}"
                )
            fi

            # Print menu box rows
            for item in "${menu_items[@]}"; do
                if [ "$item" = "DIVIDER" ]; then
                    echo -e "  ${_brand_color}${_vc}$(_repeat_char "${_hc}" $inner_cols)${_vc}${RESET}"
                else
                    local item_pad=$(_pad_str "$item" $inner_cols)
                    echo -e "  ${_brand_color}${_vc}${RESET}${item_pad}${_brand_color}${_vc}${RESET}"
                fi
            done

            # Footer
            echo -e "  ${_brand_color}${_blc}$(_repeat_char "${_hc}" $inner_cols)${_brc}${RESET}"
        fi

        echo ""
        echo -e -n "  ${CYAN}▸${RESET} ${BOLD}Pilih menu:${RESET} "
        local pilihan=""
        IFS= read -r -n 1 pilihan 2>/dev/null || IFS= read -r pilihan || true
        echo ""
        case "${pilihan,,}" in
            0) echo -e "  ${YELLOW}Sampai jumpa!${RESET}"; _log "INFO" "User exited"; break ;;
            1) wrap_output install_missing_tools ;;
            2) wrap_output download_spotdl ;;
            3) wrap_output download_ytdlp ;;
            4) wrap_output download_video ;;
            5) wrap_output kompres_media ;;
            6) wrap_output hapus_vokal ;;
            7) wrap_output auto_sync_lirik ;;
            8) wrap_output sync_spotify_playlist ;;
            9) wrap_output system_info ;;
            s) wrap_output setup_storage_dir ;;
            w) wrap_output start_watch_daemon ;;
            p) wrap_output bikin_playlist ;;
            m) wrap_output edit_metadata_manual ;;
            o) wrap_output bersih_nama ;;
            t) wrap_output start_telegram_bot ;;
            v) wrap_output start_web_dashboard ;;
            r) wrap_output uninstall_global ;;
            u) wrap_output update_zdt_script ;;
            a) zaki_assistant ;;
            x) wrap_output hapus_semua ;;
            h|\?) _draw_help_overlay ;;
            *) wrap_output echo -e "  ${RED}Pilihan tidak valid!${RESET}"; sleep 1 ;;
        esac
        if [ "${pilihan,,}" != "0" ]; then
            _pause
        fi
    done
    [ -n "$NET_PID" ] && kill -9 "$NET_PID" 2>/dev/null
    [ -n "$NET_TMP" ] && rm -f "$NET_TMP" 2>/dev/null
    _release_lock
}

main "$@"
