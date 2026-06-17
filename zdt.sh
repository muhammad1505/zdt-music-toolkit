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
    disown "$NET_PID" 2>/dev/null
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
        local current_user=$(whoami 2>/dev/null || echo "user")
        local net_str="OFFLINE"
        local net_col="${RED}"
        if [ "$net_status" = "1" ]; then
            net_str="ONLINE "
            net_col="${GREEN}"
        fi
        
        _pad_str() {
            local str="$1"
            local width="$2"
            local plain=$(echo -e "$str" | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2})?)?[mGK]//g")
            local len=${#plain}
            local pad=$((width - len))
            if [ $pad -lt 0 ]; then
                printf "%s" "${plain:0:$width}"
            else
                printf "%b%*s" "$str" "$pad" ""
            fi
        }

        _repeat_char() {
            local char="$1"
            local count="$2"
            local res=""
            for ((i=0; i<count; i++)); do
                res="${res}${char}"
            done
            echo -n "$res"
        }

        local cols=$(tput cols 2>/dev/null || echo 100)
        
        if [ "$cols" -ge 85 ]; then
            # DESKTOP VIEW
            local inner_cols=$(( cols - 4 ))
            local left_width=32
            local right_width=$(( inner_cols - left_width - 1 ))

            local left_lines=(
                " ${MAGENTA}${BOLD}■ MAIN MENU${RESET}"
                "   ${GREEN}[1]${RESET} Setup Tools"
                "   ${GREEN}[2]${RESET} Spotify DL"
                "   ${GREEN}[3]${RESET} YT Audio"
                "   ${GREEN}[4]${RESET} Video DL"
                "   ${GREEN}[5]${RESET} Compress"
                "   ${GREEN}[6]${RESET} Vocal Remover"
                "   ${GREEN}[7]${RESET} Sync Lyrics"
                "   ${GREEN}[8]${RESET} Playlist Sync"
                "   ${GREEN}[9]${RESET} System Info"
                ""
                " ${MAGENTA}${BOLD}■ UTILITIES${RESET}"
                "   ${YELLOW}[S]${RESET} Storage"
                "   ${YELLOW}[W]${RESET} Watch"
                "   ${YELLOW}[P]${RESET} Playlist"
                "   ${YELLOW}[M]${RESET} Metadata"
                "   ${YELLOW}[O]${RESET} Clean"
                "   ${YELLOW}[T]${RESET} Telegram"
                "   ${YELLOW}[V]${RESET} Web UI"
                "   ${YELLOW}[U]${RESET} Update"
                "   ${YELLOW}[A]${RESET} Zaki AI"
                "   ${RED}[X]${RESET} Delete All"
                ""
                " ${RED}${BOLD}■ SYSTEM${RESET}"
                "   ${RED}[0]${RESET} Shutdown Terminal"
            )

            local right_lines=(
                " ${MAGENTA}${BOLD}■ SYSTEM OVERVIEW${RESET}"
                "   ${CYAN}▗▀▀▀▄ ▗▄▄▄▖▗▄▄▖${RESET}    ${GRAY}OS:${RESET} $os_name"
                "   ${CYAN} ▗▄▀▘ ▐▌  █  █ ${RESET}    ${GRAY}RAM:${RESET} ${YELLOW}${ram_pct}% USED${RESET}"
                "   ${CYAN}▄▀▘   ▐▌  █  █ ${RESET}    ${GRAY}DISK:${RESET} ${YELLOW}${storage_pct}% FULL${RESET}"
                "   ${CYAN}█▄▄▄▄ ▝▀▀▀▘  █ ${RESET}    ${GRAY}KERNEL:${RESET} $(uname -r)"
                ""
                " ${MAGENTA}${BOLD}■ NETWORK INTERFACE${RESET}"
                "   ${GRAY}STATUS   :${RESET} ${net_col}${net_str}${RESET}"
                "   ${GRAY}LOCAL IP :${RESET} $(hostname -I 2>/dev/null | awk '{print $1}' || echo "N/A")"
                ""
                " ${MAGENTA}${BOLD}■ LIVE LOGS${RESET}"
                "   ${CYAN}[INFO]${RESET} ZDT Music Toolkit loaded successfully."
                "   ${CYAN}[INFO]${RESET} Establishing secure neural link..."
                "   ${GREEN}[SUCCESS]${RESET} Terminal interface ready."
                "   ${CYAN}[INFO]${RESET} Awaiting user command."
            )

            local max_lines=${#left_lines[@]}
            [ ${#right_lines[@]} -gt $max_lines ] && max_lines=${#right_lines[@]}

            local top_text=" >_ ZDT/CLI v${APP_VERSION}   |   USER: $current_user   |   UPTIME: $uptime_val   |   NET: $net_str "
            local top_pad=$(_pad_str "$top_text" $inner_cols)

            echo -e "  ${CYAN}╭$(_repeat_char '─' $inner_cols)╮${RESET}"
            echo -e "  ${CYAN}│${RESET}${MAGENTA}${BOLD}${top_pad}${RESET}${CYAN}│${RESET}"
            echo -e "  ${CYAN}├$(_repeat_char '─' $left_width)┬$(_repeat_char '─' $right_width)┤${RESET}"

            for ((i=0; i<max_lines; i++)); do
                local l_text="${left_lines[i]:-}"
                local r_text="${right_lines[i]:-}"
                local l_pad=$(_pad_str "$l_text" $left_width)
                local r_pad=$(_pad_str "$r_text" $right_width)
                echo -e "  ${CYAN}│${RESET}${l_pad}${CYAN}│${RESET}${r_pad}${CYAN}│${RESET}"
            done

            echo -e "  ${CYAN}╰$(_repeat_char '─' $left_width)┴$(_repeat_char '─' $right_width)╯${RESET}"
        else
            # MOBILE VIEW (1-Column Stacked Layout)
            local inner_cols=$(( cols - 4 ))
            [ "$inner_cols" -lt 30 ] && inner_cols=30
            
            local mobile_lines=(
                " ${MAGENTA}${BOLD}■ SYSTEM OVERVIEW${RESET}"
                "   ${GRAY}OS:${RESET} ${os_name}"
                "   ${GRAY}RAM:${RESET} ${YELLOW}${ram_pct}% USED${RESET}"
                "   ${GRAY}DISK:${RESET} ${YELLOW}${storage_pct}% FULL${RESET}"
                "   ${GRAY}NET:${RESET} ${net_col}${net_str}${RESET}"
                ""
                " ${MAGENTA}${BOLD}■ MAIN MENU${RESET}"
                "   ${GREEN}[1]${RESET} Setup Tools    ${GREEN}[6]${RESET} Vocal Remover"
                "   ${GREEN}[2]${RESET} Spotify DL     ${GREEN}[7]${RESET} Sync Lyrics"
                "   ${GREEN}[3]${RESET} YT Audio       ${GREEN}[8]${RESET} Playlist Sync"
                "   ${GREEN}[4]${RESET} Video DL       ${GREEN}[9]${RESET} System Info"
                "   ${GREEN}[5]${RESET} Compress"
                ""
                " ${MAGENTA}${BOLD}■ UTILITIES${RESET}"
                "   ${YELLOW}[S]${RESET} Storage        ${YELLOW}[O]${RESET} Clean"
                "   ${YELLOW}[W]${RESET} Watch          ${YELLOW}[T]${RESET} Telegram"
                "   ${YELLOW}[P]${RESET} Playlist       ${YELLOW}[V]${RESET} Web UI"
                "   ${YELLOW}[M]${RESET} Metadata       ${YELLOW}[U]${RESET} Update"
                "   ${YELLOW}[A]${RESET} Zaki AI        ${RED}[X]${RESET} Delete All"
                ""
                " ${RED}${BOLD}■ SYSTEM${RESET}"
                "   ${RED}[0]${RESET} Shutdown Terminal"
            )

            local top_text=" ZDT v${APP_VERSION} | UPT: $uptime_val | NET: $net_str "
            if [ "$inner_cols" -lt 45 ]; then
                top_text=" ZDT v${APP_VERSION} | NET: $net_str "
            fi
            local top_pad=$(_pad_str "$top_text" $inner_cols)

            echo -e "  ${CYAN}╭$(_repeat_char '─' $inner_cols)╮${RESET}"
            echo -e "  ${CYAN}│${RESET}${MAGENTA}${BOLD}${top_pad}${RESET}${CYAN}│${RESET}"
            echo -e "  ${CYAN}├$(_repeat_char '─' $inner_cols)┤${RESET}"

            for ((i=0; i<${#mobile_lines[@]}; i++)); do
                local l_text="${mobile_lines[i]}"
                local l_pad=$(_pad_str "$l_text" $inner_cols)
                echo -e "  ${CYAN}│${RESET}${l_pad}${CYAN}│${RESET}"
            done

            echo -e "  ${CYAN}╰$(_repeat_char '─' $inner_cols)╯${RESET}"
        fi
        
        echo ""
        echo -e -n "  ${BOLD}[?] Awaiting command: ${RESET}"
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
