#!/usr/bin/env bash
#
# zdt.sh — Universal Music Toolkit (Modular Build)
# Version : 3.8.0
set -uo pipefail
readonly APP_VERSION="3.8.0"

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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
    for _mod in core helpers download media playlist daemon setup assistant; do
        curl -sL "https://raw.githubusercontent.com/muhammad1505/zdt-music-toolkit/main/zdt-modules/${_mod}.sh?t=$(date +%s)" -o "$_MODULES_DIR/${_mod}.sh" 2>/dev/null
    done
fi

if [ -d "$_MODULES_DIR" ]; then
    for _mod in core helpers download media playlist daemon setup assistant; do
        if [ -f "$_MODULES_DIR/${_mod}.sh" ]; then
            source "$_MODULES_DIR/${_mod}.sh"
        fi
    done
else
    echo "Error: Module directory not found and failed to download!"
    exit 1
fi

MAIN_MODE=""
DEBUG_TRAP_SET=false

main() {
    _parse_args "$@"
    if [ -n "$MAIN_MODE" ]; then
        _setup_colors; _setup_unicode; _init_logging; _load_config; _load_storage_dir
        case "$MAIN_MODE" in
            download_audio) download_spotdl ;;
            download_video) download_video ;;
            spotify_sync) sync_spotify_playlist ;;
            kompres_media) _kompres_audio_batch ;;
            extract_vocal) AUTO_HAPUS_VOKAL_MODE="1"; hapus_vokal ;;
            sync_lirik) AUTO_SYNC_LIRIK="1"; auto_sync_lirik ;;
            bersih_nama) bersih_nama_otomatis "." ;;
            bikin_playlist) bikin_playlist ;;
        esac
        exit 0
    fi
    _setup_colors; _setup_unicode; _init_logging; _load_config
    RUNTIME_ENV=$(_detect_environment)
    ROOT_DIR="$(pwd)"
    _load_storage_dir
    [ -n "$STORAGE_DIR" ] && ROOT_DIR="$STORAGE_DIR"
    if ! _acquire_lock; then exit 1; fi
    trap '_trap_ctrlc' SIGINT
    trap '_trap_exit' EXIT
    if [ "${ZDT_DEBUG:-0}" = "1" ] && [ "$DEBUG_TRAP_SET" = false ]; then
        set -o errtrace
        trap '_trap_err $LINENO $?' ERR
        DEBUG_TRAP_SET=true
    fi
    NET_TMP=$(mktemp 2>/dev/null || echo "/tmp/.zdt_net_$$")
    ( while true; do ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 && echo "1" || echo "0"; sleep 3; done > "$NET_TMP" 2>/dev/null ) &
    NET_PID=$!
    _log "INFO" "ZDT started in $(pwd)"
    while true; do
        local ram_pct uptime_val storage_pct os_name net_status tools_ok
        ram_pct=$(_get_ram_percent)
        uptime_val=$(_get_uptime)
        storage_pct=$(_get_storage_percent)
        os_name=$(_get_os_name)
        net_status=$(cat "$NET_TMP" 2>/dev/null || echo "?")
        tools_ok=""
        for t in ffmpeg python3 yt-dlp spotdl; do
            if command -v "$t" >/dev/null 2>&1; then
                tools_ok="${tools_ok}${GREEN}${ICO_CHECK_OK}${RESET} "
            else
                tools_ok="${tools_ok}${RED}${ICO_CHECK_FAIL}${RESET} "
            fi
        done
        if [ -z "${NO_COLOR:-}" ]; then
            echo -ne "\033[?25h"
            clear
        fi
        echo ""
        echo -e "  ${CYAN}╔══════════════════════════════════════════════════╗${RESET}"
        echo -e "  ${RED}╔══════════════════════════════════════════════════╗${RESET}"
        echo -e "  ${RED}║${RED}${BOLD}  ███████╗██████╗ ████████╗                       ${RED}║${RESET}"
        echo -e "  ${RED}║${RED}${BOLD}  ╚══███╔╝██╔══██╗╚══██╔══╝ ${YELLOW}■■■■ MUSIC TOOLKIT    ${RED}║${RESET}"
        local ver_str="V${APP_VERSION}"
        local v_pad=$(( 18 - ${#ver_str} ))
        [ $v_pad -lt 0 ] && v_pad=0
        printf "  ${RED}║${RED}${BOLD}    ███╔╝ ██║  ██║   ██║   ${YELLOW}■■■■ %s%*s${RED}║${RESET}\n" "$ver_str" "$v_pad" ""
        echo -e "  ${RED}║${RED}${BOLD}   ███╔╝  ██║  ██║   ██║   ${CYAN}// SECTOR 7G //        ${RED}║${RESET}"
        echo -e "  ${RED}║${RED}${BOLD}  ███████╗██████╔╝   ██║   ${CYAN}// SYS.ONLINE //       ${RED}║${RESET}"
        echo -e "  ${RED}║${RED}${BOLD}  ╚══════╝╚═════╝    ╚═╝   ${MAGENTA}[ NEURAL LINK ]        ${RED}║${RESET}"
        echo -e "  ${RED}╠═${MAGENTA}[ HARDWARE LINK ]${RED}════════════════════════════════╣${RESET}"
        
        local stat_text="[OS] $os_name | [RAM] ${ram_pct}% | [DISK] ${storage_pct}%"
        local s_pad=$(( 48 - ${#stat_text} ))
        [ $s_pad -lt 0 ] && s_pad=0
        printf "  ${RED}║${RESET}${CYAN}${BOLD} %s%*s ${RED}║${RESET}\n" "$stat_text" "$s_pad" ""
        
        echo -e "  ${RED}╠═${MAGENTA}[ SYSTEM MODULES ]${RED}═══════════════════════════════╣${RESET}"
        
        # Function to print perfectly padded row (exactly 50 characters width inside)
        _menu_row() {
            local col1="$1" col2="$2"
            local plain1=$(echo -e "$col1" | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2})?)?[mGK]//g")
            local plain2=$(echo -e "$col2" | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2})?)?[mGK]//g")
            local pad1=$(( 24 - ${#plain1} ))
            local pad2=$(( 24 - ${#plain2} ))
            [ $pad1 -lt 0 ] && pad1=0
            [ $pad2 -lt 0 ] && pad2=0
            printf "  ${RED}║${RESET} %b%*s %b%*s${RED}║${RESET}\n" "$col1" "$pad1" "" "$col2" "$pad2" ""
        }
        
        _menu_row "${RED}[1]${RESET} ${WHITE}Setup Tools${RESET}"     "${RED}[2]${RESET} ${WHITE}Spotify DL${RESET}"
        _menu_row "${RED}[3]${RESET} ${WHITE}YT Audio${RESET}"        "${RED}[4]${RESET} ${WHITE}Video DL${RESET}"
        _menu_row "${RED}[5]${RESET} ${WHITE}Compress${RESET}"        "${RED}[6]${RESET} ${WHITE}Vocal Remover${RESET}"
        _menu_row "${RED}[7]${RESET} ${WHITE}Sync Lyrics${RESET}"     "${RED}[8]${RESET} ${WHITE}Playlist Sync${RESET}"
        _menu_row "${RED}[9]${RESET} ${WHITE}System Info${RESET}"     ""
        echo -e "  ${RED}║${GRAY} ------------------------------------------------ ${RED}║${RESET}"
        _menu_row "${YELLOW}[S]${RESET} ${GRAY}Storage${RESET} | ${YELLOW}[W]${RESET} ${GRAY}Watch${RESET}"   "${YELLOW}[P]${RESET} ${GRAY}Playlist${RESET}"
        _menu_row "${YELLOW}[M]${RESET} ${GRAY}Metadata${RESET} | ${YELLOW}[O]${RESET} ${GRAY}Clean${RESET}"   "${YELLOW}[T]${RESET} ${GRAY}Telegram${RESET}"
        _menu_row "${YELLOW}[V]${RESET} ${GRAY}Web UI${RESET}   | ${YELLOW}[U]${RESET} ${GRAY}Update${RESET}"  "${YELLOW}[A]${RESET} ${GRAY}Zaki AI${RESET}"
        _menu_row "${RED}[X]${RESET} ${RED}Delete All${RESET}"          ""
        echo -e "  ${RED}║${GRAY} ════════════════════════════════════════════════ ${RED}║${RESET}"
        _menu_row "${RED}[0]${RESET} ${RED}${BOLD}SHUTDOWN SYSTEM${RESET}"       ""
        echo -e "  ${RED}╚══════════════════════════════════════════════════╝${RESET}"
        echo ""
        echo -e -n "  ${BOLD}[?] Pilih menu: ${RESET}"
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
            u) update_tools ;;
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
