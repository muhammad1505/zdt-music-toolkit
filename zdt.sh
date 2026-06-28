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
readonly APP_VERSION="${_APP_VERSION:-4.4.33}"
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
    for _mod in core helpers download-spotify download-youtube media playlist daemon setup assistant; do
        if [ -f "$_MODULES_DIR/${_mod}.sh" ]; then
            source "$_MODULES_DIR/${_mod}.sh"
        fi
    done
else
    echo "Error: Module directory not found and failed to download!"
    exit 1
fi

# === Post-init: re-resolve paths using loaded modules ===
# helpers.sh (loaded above) provides _get_share_dir, _get_zdt_bin, _find_script, etc.
# Re-resolve _MODULES_DIR to canonical path using shared functions
if command -v _get_share_dir >/dev/null 2>&1; then
    _CACHED_SHARE_DIR="$(_get_share_dir)"
    _MODULES_DIR="$_CACHED_SHARE_DIR/zdt-modules"
    # Write VERSION file to share dir (single source of truth for Python scripts)
    echo "$APP_VERSION" > "$_CACHED_SHARE_DIR/VERSION" 2>/dev/null || true
fi

MAIN_MODE=""
DEBUG_TRAP_SET=false

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
    
    # Zaki AI diakses via tombol [A] di menu (tidak auto-launch biar loading cepet)
    
    while true; do
        # Use cached values (updated once at init) instead of recomputing every iteration
        # Fast-changing stats (RAM, uptime, storage) refresh each loop via /proc reads
        _refresh_stats_cache
        local ram_pct="$_ZDT_CACHED_RAM"
        local uptime_val="$_ZDT_CACHED_UPTIME"
        local storage_pct="$_ZDT_CACHED_STORAGE"
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
        
        if [ "$cols" -ge 90 ] && [ "${RUNTIME_ENV:-}" != "termux" ]; then
            # DESKTOP VIEW (Gacor Graphic Dashboard)
            local inner_cols=$(( cols - 4 ))
            local left_width=41
            local right_width=$(( inner_cols - left_width - 1 ))

            echo -e "  ${CYAN}███████╗██████╗ ████████╗${RESET}   ${MAGENTA}ZDT v${APP_VERSION}${RESET}"
            echo -e "  ${CYAN}╚══███╔╝██╔══██╗╚══██╔══╝${RESET}   ${CYAN}OS     :${RESET} $os_name"
            echo -e "  ${CYAN}  ███╔╝ ██║  ██║   ██║   ${RESET}   ${CYAN}KERNEL :${RESET} $kernel_ver"
            echo -e "  ${CYAN} ███╔╝  ██║  ██║   ██║   ${RESET}   ${CYAN}ARCH   :${RESET} $arch"
            echo -e "  ${CYAN}███████╗██████╔╝   ██║   ${RESET}   ${CYAN}UPTIME :${RESET} $uptime_val"
            echo -e "  ${CYAN}╚══════╝╚═════╝    ╚═╝   ${RESET}   ${CYAN}USER   :${RESET} $current_user"
            
            local stats_text="  CPU: ${_ZDT_CACHED_CPU}%   RAM: ${ram_pct}%   DISK: ${storage_pct}%   TEMP: ${temp}   NET: ${net_str} "
            local stats_pad=$(_pad_str "$stats_text" $((inner_cols)))
            echo -e "  ${CYAN}╭$(_repeat_char '─' $inner_cols)╮${RESET}"
            echo -e "  ${CYAN}│${RESET}${CYAN}${stats_pad}${RESET}${CYAN}│${RESET}"
            echo -e "  ${CYAN}├$(_repeat_char '─' $left_width)┬$(_repeat_char '─' $right_width)┤${RESET}"

            local left_lines=(
                " ${MAGENTA}MAIN MENU${RESET}"
                "  ${CYAN}[1]${RESET} Setup Tools      ${CYAN}[6]${RESET} Vocal Remover"
                "  ${CYAN}[2]${RESET} Spotify DL       ${CYAN}[7]${RESET} Sync Lyrics"
                "  ${CYAN}[3]${RESET} YT Audio         ${CYAN}[8]${RESET} Playlist Sync"
                "  ${CYAN}[4]${RESET} Video DL         ${CYAN}[9]${RESET} System Info"
                "  ${CYAN}[5]${RESET} Compress"
                "DIVIDER"
                " ${MAGENTA}UTILITIES${RESET}"
                "  ${YELLOW}[S]${RESET} Storage          ${YELLOW}[O]${RESET} Clean"
                "  ${YELLOW}[W]${RESET} Watch            ${YELLOW}[T]${RESET} Telegram"
                "  ${YELLOW}[P]${RESET} Playlist         ${YELLOW}[V]${RESET} Web UI"
                "  ${YELLOW}[M]${RESET} Metadata         ${YELLOW}[U]${RESET} Update"
                "  ${YELLOW}[A]${RESET} Zaki AI          ${RED}[X]${RESET} Delete All"
                ""
                "DIVIDER"
                " ${RED}SYSTEM${RESET}"
                "  ${RED}[R]${RESET} Uninstall ZDT   ${RED}[0]${RESET} Shutdown"
            )

            # Dependency status strings (cached, no command -v calls per iteration)
            local dep_ffmpeg="$([ "$_ZDT_CACHED_FFMPEG" = "1" ] && echo "${GREEN}Installed${RESET}" || echo "${RED}Missing${RESET}")"
            local dep_python3="$([ "$_ZDT_CACHED_PYTHON3" = "1" ] && echo "${GREEN}Installed${RESET}" || echo "${RED}Missing${RESET}")"
            local dep_ytdlp="$([ "$_ZDT_CACHED_YTDLP" = "1" ] && echo "${GREEN}Installed${RESET}" || echo "${RED}Missing${RESET}")"
            local dep_spotdl="$([ "$_ZDT_CACHED_SPOTDL" = "1" ] && echo "${GREEN}Installed${RESET}" || echo "${RED}Missing${RESET}")"
            local dep_demucs="$([ "$_ZDT_CACHED_DEMUCS" = "1" ] && echo "${GREEN}Installed${RESET}" || echo "${RED}Missing${RESET}")"
            local dep_mutagen="$([ "$_ZDT_CACHED_MUTAGEN" = "1" ] && echo "${GREEN}Installed${RESET}" || echo "${RED}Missing${RESET}")"

            local right_lines=(
                " ${MAGENTA}QUICK INFO${RESET}"
                "  ${CYAN}UI Mode ${RESET}: Desktop (${cols}x${lines})"
                "  ${CYAN}Distro  ${RESET}: ${os_name:0:22}"
                "  ${CYAN}Storage ${RESET}: $([ -n "$STORAGE_DIR" ] && echo "${YELLOW}${STORAGE_DIR:0:22}${RESET}" || echo "${GRAY}(Default)${RESET}")"
                "  ${CYAN}Hostname${RESET}: $(hostname)"
                ""
                "DIVIDER"
                " ${MAGENTA}DEPENDENCIES${RESET}"
                "  ${CYAN}FFmpeg  ${RESET}: $dep_ffmpeg"
                "  ${CYAN}Python3 ${RESET}: $dep_python3"
                "  ${CYAN}YT-DLP  ${RESET}: $dep_ytdlp"
                "  ${CYAN}SpotDL  ${RESET}: $dep_spotdl"
                "  ${CYAN}Demucs  ${RESET}: $dep_demucs"
                "  ${CYAN}Mutagen ${RESET}: $dep_mutagen"
                "DIVIDER"
                " ${MAGENTA}RECENT LOGS${RESET}"
                "  [$(date +'%H:%M:%S')] ${GREEN}●${RESET} System init"
                "  [$(date +'%H:%M:%S')] ${GREEN}●${RESET} Deps checked"
                "  [$(date +'%H:%M:%S')] ${GREEN}●${RESET} Ready"
            )

            local max_lines=${#left_lines[@]}
            [ ${#right_lines[@]} -gt $max_lines ] && max_lines=${#right_lines[@]}

            for ((i=0; i<max_lines; i++)); do
                local l_text="${left_lines[i]:-}"
                local r_text="${right_lines[i]:-}"
                
                if [ "$l_text" = "DIVIDER" ] || [ "$r_text" = "DIVIDER" ]; then
                    echo -e "  ${CYAN}├$(_repeat_char '─' $left_width)┼$(_repeat_char '─' $right_width)┤${RESET}"
                else
                    local l_pad=$(_pad_str "$l_text" $left_width)
                    local r_pad=$(_pad_str "$r_text" $right_width)
                    echo -e "  ${CYAN}│${RESET}${l_pad}${CYAN}│${RESET}${r_pad}${CYAN}│${RESET}"
                fi
            done

            echo -e "  ${CYAN}╰$(_repeat_char '─' $left_width)┴$(_repeat_char '─' $right_width)╯${RESET}"
        else
            # MOBILE VIEW — CyberTron responsive layout
            local inner_cols=$(( cols - 4 ))
            [ "$inner_cols" -lt 30 ] && inner_cols=30
            local _cyber=false
            [ "${RUNTIME_ENV:-}" = "termux" ] && _cyber=true

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
                echo -e "  ${CYAN}${_vc}${RESET}${MAGENTA}${BOLD}${header_pad}${RESET}${CYAN}${_vc}${RESET}"
                echo -e "  ${CYAN}${_vc}$(_repeat_char "${_hc}" $inner_cols)${_vc}${RESET}"

                local s="${_sec_bullet}" bullet="${MAGENTA}"
                local menu_items=(
                    " ${bullet} ${s} MAIN${RESET}"
                    "  ${GREEN}[1]${RESET} Setup Tools    ${GREEN}[6]${RESET} Vocal${RESET}"
                    "  ${GREEN}[2]${RESET} Spotify DL     ${GREEN}[7]${RESET} Lyrics${RESET}"
                    "  ${GREEN}[3]${RESET} YT Audio       ${GREEN}[8]${RESET} PlSync${RESET}"
                    "  ${GREEN}[4]${RESET} Video DL       ${GREEN}[9]${RESET} System${RESET}"
                    "  ${GREEN}[5]${RESET} Compress${RESET}"
                    "DIVIDER"
                    " ${bullet} ${s} TOOLS${RESET}"
                    "  ${YELLOW}[S]${RESET} Storage    ${YELLOW}[W]${RESET} Watch${RESET}"
                    "  ${YELLOW}[P]${RESET} Playlist   ${YELLOW}[M]${RESET} Meta${RESET}"
                    "  ${YELLOW}[O]${RESET} Clean      ${YELLOW}[T]${RESET} Telegram${RESET}"
                    "  ${YELLOW}[V]${RESET} Web UI     ${YELLOW}[U]${RESET} Update${RESET}"
                    "  ${YELLOW}[A]${RESET} Zaki AI    ${RED}[X]${RESET} Delete${RESET}"
                    "DIVIDER"
                    " ${RED} ${s} SYSTEM${RESET}"
                    "  ${RED}[R]${RESET} Uninstall   ${RED}[0]${RESET} Shutdown${RESET}"
                )
            else
                # TIER 3: Medium (55-74 cols) — full layout
                local header=" ${header_prefix} | RAM ${ram_pct}% | DSK ${storage_pct}% | UPT ${uptime_val} | ${net_icon} "
                local header_pad=$(_pad_str "$header" $inner_cols)
                echo -e "  ${CYAN}${_tlc}$(_repeat_char "${_hc}" $inner_cols)${_trc}${RESET}"
                echo -e "  ${CYAN}${_vc}${RESET}${MAGENTA}${BOLD}${header_pad}${RESET}${CYAN}${_vc}${RESET}"
                echo -e "  ${CYAN}${_vc}$(_repeat_char "${_hc}" $inner_cols)${_vc}${RESET}"

                local s="${_sec_bullet}" bullet="${MAGENTA}"
                local menu_items=(
                    " ${bullet} ${s} MAIN PROTOCOLS${RESET}"
                    "  ${GREEN}[1]${RESET} Setup Tools      ${GREEN}[6]${RESET} Vocal Remover${RESET}"
                    "  ${GREEN}[2]${RESET} Spotify DL       ${GREEN}[7]${RESET} Sync Lyrics${RESET}"
                    "  ${GREEN}[3]${RESET} YT Audio         ${GREEN}[8]${RESET} Playlist Sync${RESET}"
                    "  ${GREEN}[4]${RESET} Video DL         ${GREEN}[9]${RESET} System Info${RESET}"
                    "  ${GREEN}[5]${RESET} Compress${RESET}"
                    "DIVIDER"
                    " ${bullet} ${s} UTILITIES${RESET}"
                    "  ${YELLOW}[S]${RESET} Storage          ${YELLOW}[W]${RESET} Watch Daemon${RESET}"
                    "  ${YELLOW}[P]${RESET} Playlist         ${YELLOW}[M]${RESET} Metadata${RESET}"
                    "  ${YELLOW}[O]${RESET} Clean Files      ${YELLOW}[T]${RESET} Telegram Bot${RESET}"
                    "  ${YELLOW}[V]${RESET} Web Dashboard    ${YELLOW}[U]${RESET} Update ZDT${RESET}"
                    "  ${YELLOW}[A]${RESET} Zaki AI          ${RED}[X]${RESET} Delete All${RESET}"
                    "DIVIDER"
                    " ${RED} ${s} SYSTEM${RESET}"
                    "  ${RED}[R]${RESET} Uninstall ZDT   ${RED}[0]${RESET} Shutdown${RESET}"
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
        echo -e -n "  ${CYAN}► Silakan pilih menu:${RESET} "
        local pilihan
        read -r -n 1 pilihan 2>/dev/null || read -r pilihan
        echo ""
        case "${pilihan,,}" in
            0|q) echo -e "  ${YELLOW}Sampai jumpa!${RESET}"; _log "INFO" "User exited"; break ;;
            1) install_missing_tools ;;
            2) download_spotdl ;;
            3) download_ytdlp ;;
            4) download_video ;;
            5) kompres_media ;;
            6) hapus_vokal ;;
            7) auto_sync_lirik ;;
            8) sync_spotify_playlist ;;
            9) system_info ;;
            s) setup_storage_dir ;;
            w) start_watch_daemon ;;
            p) bikin_playlist ;;
            m) edit_metadata_manual ;;
            o) bersih_nama ;;
            t) start_telegram_bot ;;
            v) start_web_dashboard ;;
            r) uninstall_global ;;
            u) update_zdt_script ;;
            a) zaki_assistant ;;
            x) hapus_semua ;;
            *) echo -e "  ${RED}Pilihan tidak valid!${RESET}"; sleep 1; continue ;;
        esac
        if [ "${pilihan,,}" != "0" ] && [ "${pilihan,,}" != "q" ]; then
            _pause
        fi
    done
    [ -n "$NET_PID" ] && kill -9 "$NET_PID" 2>/dev/null
    [ -n "$NET_TMP" ] && rm -f "$NET_TMP" 2>/dev/null
    _release_lock
}

main "$@"
