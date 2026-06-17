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
        curl -sL "https://raw.githubusercontent.com/muhammad1505/zdt-music-toolkit/main/zdt-modules/${_mod}.sh" -o "$_MODULES_DIR/${_mod}.sh" 2>/dev/null
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
        echo -e "  ${CYAN}║${RESET}${WHITE}${BOLD}   ${APP_NAME} v${APP_VERSION}   ${RESET}${CYAN}║${RESET}"
        echo -e "  ${CYAN}╠══════════════════════════════════════════════════╣${RESET}"
        echo -e "  ${CYAN}║${RESET}  ${GRAY}OS:${RESET} $os_name  ${GRAY}RAM:${RESET} ${ram_pct}%  ${GRAY}Disk:${RESET} ${storage_pct}%  ${CYAN}║${RESET}"
        echo -e "  ${CYAN}╠══════════════════════════════════════════════════╣${RESET}"
        echo -e "  ${CYAN}║${RESET}  ${MAGENTA}[1]${RESET} Setup Tools    ${MAGENTA}[2]${RESET} Spotify DL    ${CYAN}║${RESET}"
        echo -e "  ${CYAN}║${RESET}  ${MAGENTA}[3]${RESET} YT Audio       ${MAGENTA}[4]${RESET} Video DL      ${CYAN}║${RESET}"
        echo -e "  ${CYAN}║${RESET}  ${MAGENTA}[5]${RESET} Compress       ${MAGENTA}[6]${RESET} Vocal Remover ${CYAN}║${RESET}"
        echo -e "  ${CYAN}║${RESET}  ${MAGENTA}[7]${RESET} Sync Lyrics    ${MAGENTA}[8]${RESET} Playlist Sync ${CYAN}║${RESET}"
        echo -e "  ${CYAN}║${RESET}  ${MAGENTA}[9]${RESET} System Info                              ${CYAN}║${RESET}"
        echo -e "  ${CYAN}║${RESET}                                                       ${CYAN}║${RESET}"
        echo -e "  ${CYAN}║${RESET}  ${YELLOW}[S]${RESET} Storage   ${YELLOW}[W]${RESET} Watch   ${YELLOW}[P]${RESET} Playlist  ${CYAN}║${RESET}"
        echo -e "  ${CYAN}║${RESET}  ${YELLOW}[M]${RESET} Metadata  ${YELLOW}[O]${RESET} Clean   ${YELLOW}[T]${RESET} Telegram  ${CYAN}║${RESET}"
        echo -e "  ${CYAN}║${RESET}  ${YELLOW}[V]${RESET} Web UI    ${YELLOW}[U]${RESET} Update  ${YELLOW}[A]${RESET} Zaki AI   ${CYAN}║${RESET}"
        echo -e "  ${CYAN}║${RESET}  ${YELLOW}[X]${RESET} Delete All                               ${CYAN}║${RESET}"
        echo -e "  ${CYAN}║${RESET}                                                       ${CYAN}║${RESET}"
        echo -e "  ${CYAN}║${RESET}  ${RED}[0]${RESET} Exit                                       ${CYAN}║${RESET}"
        echo -e "  ${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
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
