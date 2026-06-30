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
readonly APP_VERSION="${_APP_VERSION:-4.4.53}"
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
    trap '_trap_ctrlc' SIGINT
    trap '_trap_exit' EXIT
    if [ "${ZDT_DEBUG:-0}" = "1" ] && [ "$DEBUG_TRAP_SET" = false ]; then
        set -o errtrace
        trap '_trap_err $LINENO $?' ERR
        DEBUG_TRAP_SET=true
    fi
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
            # DESKTOP VIEW — "ZDT Studio Console" (Audiophile v5)
            # Split-pane layout with brand identity, status, and grid menu
            # ──────────────────────────────────────────────────────────
            local inner_cols=$(( cols - 4 ))
            [ "$inner_cols" -gt 100 ] && inner_cols=100
            [ "$inner_cols" -lt 56 ] && inner_cols=56
            local left_width=38
            local right_width=$(( inner_cols - left_width - 1 ))
            if [ "$right_width" -lt 30 ]; then
                right_width=30
                left_width=$(( inner_cols - right_width - 1 ))
            fi
            [ "$left_width" -lt 28 ] && left_width=28

            # ── Service status dots ──
            local svc_web_state="off"
            [ "$_svc_web" = "ON" ] && svc_web_state="on"
            local svc_tele_state="off"
            [ "$_svc_tele" = "ON" ] && svc_tele_state="on"
            local svc_watch_state="off"
            [ "$_svc_watch" = "ON" ] && svc_watch_state="on"
            local svc_web_dot=$(_draw_status_dot "$svc_web_state")
            local svc_tele_dot=$(_draw_status_dot "$svc_tele_state")
            local svc_watch_dot=$(_draw_status_dot "$svc_watch_state")

            # Storage status dot
            local st_dot_state="on"
            [ "$storage_pct" -gt 85 ] && st_dot_state="warn"
            [ "$storage_pct" -gt 95 ] && st_dot_state="off"
            local st_dot=$(_draw_status_dot "$st_dot_state")

            # AI status dot
            local ai_dot_state="off"
            [ -f "$HOME/.config/zdt/gemini_key" ] && ai_dot_state="on"
            local ai_dot=$(_draw_status_dot "$ai_dot_state")

            # Daemon status dot
            local dm_state="off"
            [ "$_svc_watch" = "ON" ] || [ "$_svc_web" = "ON" ] || [ "$_svc_tele" = "ON" ] && dm_state="on"
            local dm_dot=$(_draw_status_dot "$dm_state")

            # ── TOP HEADER ──
            _draw_split_top $left_width $right_width

            # Row 1: Brand on left, STORAGE/AI/DAEMON on right
            local logo_text=" ${BOLD}${YELLOW}ZDT${RESET} ${WHITE}Music Toolkit${RESET} ${DIM}v${APP_VERSION}${RESET}"
            local status_text=" ${st_dot} ${WHITE}STORAGE${RESET}  ${ai_dot} ${WHITE}AI${RESET}  ${dm_dot} ${WHITE}DAEMON${RESET}"
            _draw_split_row "$logo_text" "$status_text" $left_width $right_width

            # Row 2: Environment + uptime on left, WEB/TELE/WATCH on right
            local env_text=" ${GRAY}${os_name:0:20}${RESET} ${DIM}|${RESET} ${GRAY}UPT${RESET} ${uptime_val:0:10}"
            local svc_details=" ${svc_web_dot} ${DIM}WEB${RESET}  ${svc_tele_dot} ${DIM}TELE${RESET}  ${svc_watch_dot} ${DIM}WATCH${RESET}"
            _draw_split_row "$env_text" "$svc_details" $left_width $right_width

            # ── RESOURCE BARS ──
            _draw_split_sep $left_width $right_width
            local ram_color="${GREEN}"; [ "$ram_pct" -gt 70 ] && ram_color="${YELLOW}"; [ "$ram_pct" -gt 90 ] && ram_color="${RED}"
            local cpu_val="${_ZDT_CACHED_CPU:-0}"; [ "$cpu_val" = "?" ] && cpu_val=0
            local cpu_color="${GREEN}"; [ "$cpu_val" -gt 70 ] && cpu_color="${YELLOW}"; [ "$cpu_val" -gt 90 ] && cpu_color="${RED}"
            local st_color="${GREEN}"; [ "$storage_pct" -gt 70 ] && st_color="${YELLOW}"; [ "$storage_pct" -gt 90 ] && st_color="${RED}"
            local ram_bar="${YELLOW}RAM${RESET} $(_draw_bar "$ram_pct" 7 "$ram_color")"
            local cpu_bar="${YELLOW}CPU${RESET} $(_draw_bar "$cpu_val" 7 "$cpu_color")"
            local st_bar="${YELLOW}DSK${RESET} $(_draw_bar "$storage_pct" 15 "$st_color")"
            _draw_split_row "${ram_bar}  ${cpu_bar}" "${st_bar}" $left_width $right_width

            # ── MIDDLE DIVIDER ──
            _draw_split_sep $left_width $right_width

            # ── BUILD LEFT (Menu) and RIGHT (System + Recent) content arrays ──

            # LEFT: Menu grid
            local left_items=()
            local menu_rows=(
                "${YELLOW}[1]${RESET} ${BOLD}Spotify${RESET}"
                "${YELLOW}[2]${RESET} ${BOLD}YT Audio${RESET}"
                "${YELLOW}[3]${RESET} ${BOLD}Video DL${RESET}"
                "${YELLOW}[4]${RESET} ${BOLD}Compress${RESET}"
                "${YELLOW}[5]${RESET} ${BOLD}Vocal${RESET}"
                "${YELLOW}[6]${RESET} ${BOLD}Lyrics${RESET}"
                "${YELLOW}[7]${RESET} ${BOLD}Playlist${RESET}"
                "${YELLOW}[8]${RESET} ${BOLD}Sync${RESET}"
                "${YELLOW}[9]${RESET} ${BOLD}System${RESET}"
                "${YELLOW}[A]${RESET} ${BOLD}Zaki AI${RESET}"
            )
            local menu2_rows=(
                "${YELLOW}[S]${RESET} ${BOLD}Storage${RESET}"
                "${YELLOW}[W]${RESET} ${BOLD}Watch${RESET}"
                "${YELLOW}[T]${RESET} ${BOLD}Telegram${RESET}"
                "${YELLOW}[V]${RESET} ${BOLD}Web UI${RESET}"
                "${YELLOW}[U]${RESET} ${BOLD}Update${RESET}"
                "${YELLOW}[R]${RESET} ${BOLD}Uninstall${RESET}"
                "${YELLOW}[M]${RESET} ${BOLD}Metadata${RESET}"
                "${YELLOW}[O]${RESET} ${BOLD}Clean${RESET}"
                "${YELLOW}[P]${RESET} ${BOLD}Playlist${RESET}"
                "${YELLOW}[X]${RESET} ${BOLD}Delete${RESET}"
            )
            left_items+=(" ${BOLD}${YELLOW}MENU${RESET}")
            left_items+=("__HSEP__")
            local half_w=$(( (left_width - 3) / 2 ))
            [ "$half_w" -lt 14 ] && half_w=14
            for ((mi=0; mi<10; mi++)); do
                local c1="${menu_rows[mi]}"
                local c2="${menu2_rows[mi]}"
                local c1_pad=$(_pad_str "$c1" "$half_w")
                left_items+=("${c1_pad} ${c2}")
            done
            local left_count=${#left_items[@]}

            # RIGHT: System Info + Recent
            local right_items=()
            right_items+=(" ${BOLD}${YELLOW}SYSTEM${RESET}")
            right_items+=("__HSEP__")
            local _dot_on="${GREEN}●${RESET}" _dot_off="${RED}○${RESET}"
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
            local _ico_wd="$_dot_off"
            for _wd_p in "${ZDT_VENV_DIR:-$HOME/.local/share/zdt/venv}/lib/python3."*/site-packages/watchdog/__init__.py; do
                [ -f "$_wd_p" ] && { _ico_wd="$_dot_on"; break; }
            done 2>/dev/null
            right_items+=(" ${_ico_ff} ${BOLD}ffmpeg${RESET}")
            right_items+=(" ${_ico_py} ${BOLD}Python 3${RESET}")
            right_items+=(" ${_ico_yt} ${BOLD}yt-dlp${RESET}")
            right_items+=(" ${_ico_sp} ${BOLD}spotdl${RESET}")
            right_items+=(" ${_ico_dm} ${BOLD}Demucs${RESET}")
            right_items+=(" ${_ico_mu} ${BOLD}Mutagen${RESET}")
            right_items+=(" ${_ico_fl} ${BOLD}Flask${RESET}")
            right_items+=(" ${_ico_tb} ${BOLD}Telebot${RESET}")
            right_items+=(" ${_ico_wd} ${BOLD}Watchdog${RESET}")
            # Spacer biar sejajar dengan [A] Zaki AI
            right_items+=("")


            local right_count=${#right_items[@]}
            # Balance rows so both panels have equal height
            if [ "$left_count" -lt "$right_count" ]; then
                for ((_i=left_count; _i<right_count; _i++)); do left_items+=(""); done
                left_count=$right_count
            elif [ "$right_count" -lt "$left_count" ]; then
                for ((_i=right_count; _i<left_count; _i++)); do right_items+=(""); done
                right_count=$left_count
            fi
            local max_rows=$left_count

            for ((ri=0; ri<max_rows; ri++)); do
                local ltxt="${left_items[ri]:-}"
                local rtxt="${right_items[ri]:-}"
                if [ "$rtxt" = "__HSEP__" ] || [ "$ltxt" = "__HSEP__" ]; then
                    _draw_split_sep $left_width $right_width
                else
                    _draw_split_row "$ltxt" "$rtxt" $left_width $right_width
                fi
            done

            # ── BOTTOM SHORTCUT BAR ──
            echo -e "  ${YELLOW}╠$(_repeat_char '═' $left_width)╩$(_repeat_char '═' $right_width)╣${RESET}"
            local shortcut_bar=" ${CYAN}[0]${RESET} Keluar  ${CYAN}[?]${RESET} Help"
            local sc_pad=$(_pad_str "$shortcut_bar" $inner_cols)
            echo -e "  ${YELLOW}║${RESET}${sc_pad}${YELLOW}║${RESET}"
            echo -e "  ${YELLOW}╚$(_repeat_char '═' $inner_cols)╝${RESET}"
        else
            # MOBILE VIEW — CyberTron responsive layout
            local inner_cols=$(( cols - 4 ))
            [ "$inner_cols" -lt 30 ] && inner_cols=30
            local _cyber=false
            [ "${RUNTIME_ENV:-}" = "termux" ] && _cyber=true
            [ "$FORCE_MOBILE" -eq 1 ] && _cyber=true

            # Box chars: double-line for cyber mode
            local _tlc="╭" _trc="╮" _blc="╰" _brc="╯" _hc="─" _vc="│"
            local _sec_bullet="■"
            $_cyber && { _tlc="╔" _trc="╗" _blc="╚" _brc="╝" _hc="═" _vc="║"; _sec_bullet="◉"; }

            local net_icon="${net_col}${ICO_WIFI:-NET}${RESET} ${net_str}"
            local cyber_badge=""
            $_cyber && cyber_badge="${MAGENTA}⚡${RESET} "
            local header_prefix="${cyber_badge}${MAGENTA}${BOLD}ZDT v${APP_VERSION}${RESET}"

            if [ "$inner_cols" -lt 42 ]; then
                # TIER 1: Ultra-narrow
                local header=" ${header_prefix} ${net_icon} "
                local header_pad=$(_pad_str "$header" $inner_cols)
                echo -e "  ${CYAN}${_tlc}$(_repeat_char "${_hc}" $inner_cols)${_trc}${RESET}"
                echo -e "  ${CYAN}${_vc}${RESET}${MAGENTA}${BOLD}${header_pad}${RESET}${CYAN}${_vc}${RESET}"
                echo -e "  ${CYAN}${_blc}$(_repeat_char "${_hc}" $inner_cols)${_brc}${RESET}"

                local s="${_sec_bullet}" bullet="${MAGENTA}"
                local menu_items=(
                    " ${bullet}[1]${RESET} Setup    ${bullet}[6]${RESET} Vocal${RESET}"
                    " ${bullet}[2]${RESET} Spotify  ${bullet}[7]${RESET} Lyrics${RESET}"
                    " ${bullet}[3]${RESET} YT Aud   ${bullet}[8]${RESET} PlSync${RESET}"
                    " ${bullet}[4]${RESET} Video    ${bullet}[9]${RESET} Info${RESET}"
                    " ${bullet}[5]${RESET} Compress${RESET}"
                    "DIVIDER"
                    " ${YELLOW}[S]${RESET} Storage  ${YELLOW}[W]${RESET} Watch${RESET}"
                    " ${YELLOW}[P]${RESET} Playlist ${YELLOW}[M]${RESET} Meta${RESET}"
                    " ${YELLOW}[O]${RESET} Clean    ${YELLOW}[T]${RESET} Telegram${RESET}"
                    " ${YELLOW}[V]${RESET} Web UI   ${YELLOW}[U]${RESET} Update${RESET}"
                    " ${YELLOW}[A]${RESET} Zaki AI  ${RED}[X]${RESET} Delete${RESET}"
                    "DIVIDER"
                    " ${RED}[R]${RESET} Uninstall ${RED}[0]${RESET} Exit${RESET}"
                )
            elif [ "$inner_cols" -lt 55 ]; then
                # TIER 2: Narrow
                local header=" ${header_prefix} | RAM ${ram_pct}% | ${net_icon} "
                local header_pad=$(_pad_str "$header" $inner_cols)
                echo -e "  ${CYAN}${_tlc}$(_repeat_char "${_hc}" $inner_cols)${_trc}${RESET}"
                echo -e "  ${CYAN}${_vc}${RESET}${YELLOW}${BOLD}${header_pad}${RESET}${CYAN}${_vc}${RESET}"
                echo -e "  ${CYAN}${_vc}$(_repeat_char "${_hc}" $inner_cols)${_vc}${RESET}"

                local s="${_sec_bullet}" bullet="${YELLOW}"
                local menu_items=(
                    " ${bullet} ${s} MAIN${RESET}"
                    "  ${CYAN}[1]${RESET} Setup Tools    ${CYAN}[6]${RESET} Vocal${RESET}"
                    "  ${CYAN}[2]${RESET} Spotify DL     ${CYAN}[7]${RESET} Lyrics${RESET}"
                    "  ${CYAN}[3]${RESET} YT Audio       ${CYAN}[8]${RESET} PlSync${RESET}"
                    "  ${CYAN}[4]${RESET} Video DL       ${CYAN}[9]${RESET} System${RESET}"
                    "  ${CYAN}[5]${RESET} Compress${RESET}"
                    "DIVIDER"
                    " ${bullet} ${s} TOOLS${RESET}"
                    "  ${CYAN}[S]${RESET} Storage    ${CYAN}[W]${RESET} Watch${RESET}"
                    "  ${CYAN}[P]${RESET} Playlist   ${CYAN}[M]${RESET} Meta${RESET}"
                    "  ${CYAN}[O]${RESET} Clean      ${CYAN}[T]${RESET} Tele${RESET}"
                    "  ${CYAN}[V]${RESET} Web UI     ${CYAN}[U]${RESET} Update${RESET}"
                    "  ${CYAN}[A]${RESET} Zaki AI    ${RED}[X]${RESET} Delete${RESET}"
                    "DIVIDER"
                    " ${RED} ${s} SYSTEM${RESET}"
                    "  ${RED}[R]${RESET} Uninstall   ${RED}[0]${RESET} Exit${RESET}"
                )
            else
                # TIER 3: Medium (55-74 cols) — full layout
                local header=" ${header_prefix} | RAM ${ram_pct}% | DSK ${storage_pct}% | UPT ${uptime_val} | ${net_icon} "
                local header_pad=$(_pad_str "$header" $inner_cols)
                echo -e "  ${CYAN}${_tlc}$(_repeat_char "${_hc}" $inner_cols)${_trc}${RESET}"
                echo -e "  ${CYAN}${_vc}${RESET}${YELLOW}${BOLD}${header_pad}${RESET}${CYAN}${_vc}${RESET}"
                echo -e "  ${CYAN}${_vc}$(_repeat_char "${_hc}" $inner_cols)${_vc}${RESET}"

                # Quick resource bar (compact)
                local bar_width=$(( (inner_cols - 10) / 3 ))
                [ "$bar_width" -lt 5 ] && bar_width=5
                [ "$bar_width" -gt 10 ] && bar_width=10
                local ram_b=$(_draw_bar "$ram_pct" "$bar_width")
                local cpu_b=$(_draw_bar "${_ZDT_CACHED_CPU:-0}" "$bar_width")
                local st_b=$(_draw_bar "$storage_pct" "$bar_width")
                local bars_line="${CYAN}RAM${RESET} ${ram_b}  ${CYAN}CPU${RESET} ${cpu_b}  ${CYAN}DSK${RESET} ${st_b}"
                local bars_pad=$(_pad_str " $bars_line" $inner_cols)
                echo -e "  ${CYAN}${_vc}${RESET}${bars_pad}${CYAN}${_vc}${RESET}"
                echo -e "  ${CYAN}${_vc}$(_repeat_char "${_hc}" $inner_cols)${_vc}${RESET}"

                local s="${_sec_bullet}" bullet="${YELLOW}"
                local menu_items=(
                    " ${bullet} ${s} MAIN${RESET}"
                    "  ${CYAN}[1]${RESET} Setup Tools      ${CYAN}[6]${RESET} Vocal${RESET}"
                    "  ${CYAN}[2]${RESET} Spotify DL       ${CYAN}[7]${RESET} Lyrics${RESET}"
                    "  ${CYAN}[3]${RESET} YT Audio         ${CYAN}[8]${RESET} PlSync${RESET}"
                    "  ${CYAN}[4]${RESET} Video DL         ${CYAN}[9]${RESET} System${RESET}"
                    "  ${CYAN}[5]${RESET} Compress${RESET}"
                    "DIVIDER"
                    " ${bullet} ${s} TOOLS${RESET}"
                    "  ${CYAN}[S]${RESET} Storage     ${CYAN}[W]${RESET} Watch${RESET}"
                    "  ${CYAN}[P]${RESET} Playlist    ${CYAN}[M]${RESET} Meta${RESET}"
                    "  ${CYAN}[O]${RESET} Clean       ${CYAN}[T]${RESET} Tele${RESET}"
                    "  ${CYAN}[V]${RESET} Web UI      ${CYAN}[U]${RESET} Update${RESET}"
                    "  ${CYAN}[A]${RESET} Zaki AI     ${RED}[X]${RESET} Delete${RESET}"
                    "DIVIDER"
                    " ${RED} ${s} SYSTEM${RESET}"
                    "  ${RED}[R]${RESET} Uninstall    ${RED}[0]${RESET} Exit${RESET}"
                )
            fi

            # Print the menu box
            for item in "${menu_items[@]}"; do
                if [ "$item" = "DIVIDER" ]; then
                    echo -e "  ${CYAN}${_vc}$(_repeat_char "${_hc}" $inner_cols)${_vc}${RESET}"
                else
                    local item_pad=$(_pad_str "$item" $inner_cols)
                    echo -e "  ${CYAN}${_vc}${RESET}${item_pad}${CYAN}${_vc}${RESET}"
                fi
            done

            echo -e "  ${CYAN}╰$(_repeat_char '─' $inner_cols)╯${RESET}"
        fi

        echo ""
        echo -e -n "  ${CYAN}► Pilih menu:${RESET} "
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
            h|\?) wrap_output echo -e "  ${YELLOW}MENU UTAMA${RESET}\n  ${CYAN}[1]${RESET} Setup Tools     ${CYAN}[2]${RESET} Spotify DL   ${CYAN}[3]${RESET} YT Audio\n  ${CYAN}[4]${RESET} Video DL       ${CYAN}[5]${RESET} Compress      ${CYAN}[6]${RESET} Vocal\n  ${CYAN}[7]${RESET} Sync Lirik     ${CYAN}[8]${RESET} PlSync        ${CYAN}[9]${RESET} System\n  ${YELLOW}LAINNYA${RESET}\n  ${CYAN}[S]${RESET} Storage        ${CYAN}[W]${RESET} Watch Daemon  ${CYAN}[P]${RESET} Playlist\n  ${CYAN}[M]${RESET} Metadata       ${CYAN}[O]${RESET} Bersih Nama   ${CYAN}[T]${RESET} Telegram\n  ${CYAN}[V]${RESET} Web Dashboard  ${CYAN}[R]${RESET} Uninstall     ${CYAN}[U]${RESET} Update\n  ${CYAN}[A]${RESET} Zaki AI        ${CYAN}[X]${RESET} Hapus Semua   ${CYAN}[0]${RESET} Keluar";;
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
