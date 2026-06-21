#!/usr/bin/env bash
export LC_ALL=C.UTF-8
#
# zdt.sh — Universal Music Toolkit (Modular Build)
# Version : 4.1.29
set -uo pipefail
readonly APP_VERSION="4.1.29"
export ZDT_VERSION="$APP_VERSION"

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
        ROOT_DIR="$(pwd)"
        [ -n "$STORAGE_DIR" ] && ROOT_DIR="$STORAGE_DIR"
        if [ "$ROOT_DIR" != "$(pwd)" ]; then
            cd "$ROOT_DIR" || true
        fi
        case "$MAIN_MODE" in
            download_audio) download_spotdl ;;
            download_video) download_video ;;
            spotify_sync) sync_spotify_playlist ;;
            kompres_media) _kompres_audio_batch ;;
            extract_vocal) AUTO_HAPUS_VOKAL_MODE="1"; hapus_vokal ;;
            sync_lirik) AUTO_SYNC_LIRIK="1"; auto_sync_lirik ;;
            bersih_nama) bersih_nama_otomatis "." "all" ;;
            bikin_playlist) bikin_playlist ;;
        esac
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
    NET_TMP=$(mktemp 2>/dev/null || echo "/tmp/.zdt_net_$$")
    ( while true; do if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then echo "1" > "$NET_TMP"; else echo "0" > "$NET_TMP"; fi; sleep 3; done 2>/dev/null ) &
    NET_PID=$!
    disown "$NET_PID" 2>/dev/null
    _log "INFO" "ZDT started in $(pwd)"
    
    # Auto-Launch Zaki AI on Startup
    zaki_assistant
    
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
        local current_user=$(whoami 2>/dev/null || echo "user")
        local net_str="OFFLINE"
        local net_col="${RED}"
        if [ "$net_status" = "1" ]; then
            net_str="ONLINE "
            net_col="${GREEN}"
        fi

        local cols=$(tput cols 2>/dev/null || echo 100)
        local lines=$(tput lines 2>/dev/null || echo 30)
        
        # We need CPU temp if possible
        local temp="N/A"
        if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
            temp="$(($(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null) / 1000))°C"
        fi
        
        local kernel_ver=$(uname -r | cut -d'-' -f1,2)
        local arch=$(uname -m)
        local pkgs=$(dpkg-query -f '.\n' -W 2>/dev/null | wc -l || echo 0)
        local load_avg=$(cat /proc/loadavg 2>/dev/null | awk '{print $1" "$2" "$3}' || echo "N/A")
        
        if [ "$cols" -ge 75 ]; then
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
            
            local stats_text="  CPU: $(grep 'cpu ' /proc/stat | awk '{print ($2+$4)*100/($2+$4+$5)}' | cut -d. -f1)%   RAM: ${ram_pct}%   DISK: ${storage_pct}%   TEMP: ${temp}   NET: ${net_str} "
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
                "  ${RED}⏻ [0]${RESET} Shutdown Terminal"
            )

            local right_lines=(
                " ${MAGENTA}QUICK INFO${RESET}"
                "  ${CYAN}UI Mode ${RESET}: Desktop (${cols}x${lines})"
                "  ${CYAN}Distro  ${RESET}: ${os_name:0:22}"
                "  ${CYAN}Storage ${RESET}: $([ -n "$STORAGE_DIR" ] && echo "${YELLOW}${STORAGE_DIR:0:22}${RESET}" || echo "${GRAY}(Default)${RESET}")"
                "  ${CYAN}Hostname${RESET}: $(hostname)"
                ""
                "DIVIDER"
                " ${MAGENTA}DEPENDENCIES${RESET}"
                "  ${CYAN}FFmpeg  ${RESET}: $(command -v ffmpeg >/dev/null 2>&1 && echo "${GREEN}Installed${RESET}" || echo "${RED}Missing${RESET}")"
                "  ${CYAN}Python3 ${RESET}: $(command -v python3 >/dev/null 2>&1 && echo "${GREEN}Installed${RESET}" || echo "${RED}Missing${RESET}")"
                "  ${CYAN}YT-DLP  ${RESET}: $(command -v yt-dlp >/dev/null 2>&1 && echo "${GREEN}Installed${RESET}" || echo "${RED}Missing${RESET}")"
                "  ${CYAN}SpotDL  ${RESET}: $(command -v spotdl >/dev/null 2>&1 && echo "${GREEN}Installed${RESET}" || echo "${RED}Missing${RESET}")"
                "  ${CYAN}Demucs  ${RESET}: $([ -f "$HOME/.local/share/zdt/demucs_venv/bin/demucs" ] && echo "${GREEN}Installed${RESET}" || echo "${RED}Missing${RESET}")"
                "  ${CYAN}Mutagen ${RESET}: $([ -f "$HOME/.local/share/zdt/venv/bin/python" ] && "$HOME/.local/share/zdt/venv/bin/python" -c "import mutagen" >/dev/null 2>&1 && echo "${GREEN}Installed${RESET}" || echo "${RED}Missing${RESET}")"
                "DIVIDER"
                " ${MAGENTA}RECENT LOGS${RESET}"
                "  [$(date +'%H:%M:%S')] ${GREEN}●${RESET} System initialized"
                "  [$(date +'%H:%M:%S')] ${GREEN}●${RESET} Dependencies checked"
                "  [$(date +'%H:%M:%S')] ${GREEN}●${RESET} Ready for commands"
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
            # MOBILE VIEW (1-Column Stacked Layout)
            local inner_cols=$(( cols - 4 ))
            [ "$inner_cols" -lt 30 ] && inner_cols=30
            
            local mobile_lines=(
                " ${MAGENTA}${BOLD}■ SYSTEM OVERVIEW${RESET}"
                "   ${GRAY}UI: ${RESET} Mobile (${cols}x${lines})"
                "   ${GRAY}OS: ${RESET} ${os_name}"
                "   ${GRAY}Dir:${RESET} $([ -n "$STORAGE_DIR" ] && echo "${YELLOW}${STORAGE_DIR:0:30}${RESET}" || echo "${GRAY}(Default)${RESET}")"
                "   ${GRAY}RAM:${RESET} ${YELLOW}${ram_pct}% USED${RESET}   ${GRAY}DISK:${RESET} ${YELLOW}${storage_pct}% FULL${RESET}"
                "   ${GRAY}NET:${RESET} ${net_col}${net_str}${RESET}"
                "DIVIDER"
                " ${MAGENTA}${BOLD}■ DEPENDENCIES${RESET}"
                "   ${GRAY}FFmpeg :${RESET} $(command -v ffmpeg >/dev/null 2>&1 && echo "${GREEN}Installed${RESET}" || echo "${RED}Missing${RESET}")"
                "   ${GRAY}Python3:${RESET} $(command -v python3 >/dev/null 2>&1 && echo "${GREEN}Installed${RESET}" || echo "${RED}Missing${RESET}")"
                "   ${GRAY}YT-DLP :${RESET} $(command -v yt-dlp >/dev/null 2>&1 && echo "${GREEN}Installed${RESET}" || echo "${RED}Missing${RESET}")"
                "   ${GRAY}SpotDL :${RESET} $(command -v spotdl >/dev/null 2>&1 && echo "${GREEN}Installed${RESET}" || echo "${RED}Missing${RESET}")"
                "   ${GRAY}Demucs :${RESET} $([ -f "$HOME/.local/share/zdt/demucs_venv/bin/demucs" ] && echo "${GREEN}Installed${RESET}" || echo "${RED}Missing${RESET}")"
                "   ${GRAY}Mutagen:${RESET} $([ -f "$HOME/.local/share/zdt/venv/bin/python" ] && "$HOME/.local/share/zdt/venv/bin/python" -c "import mutagen" >/dev/null 2>&1 && echo "${GREEN}Installed${RESET}" || echo "${RED}Missing${RESET}")"
                "DIVIDER"
                " ${MAGENTA}${BOLD}■ MAIN MENU${RESET}"
                "   ${GREEN}[1]${RESET} Setup Tools      ${GREEN}[6]${RESET} Vocal Remover"
                "   ${GREEN}[2]${RESET} Spotify DL       ${GREEN}[7]${RESET} Sync Lyrics"
                "   ${GREEN}[3]${RESET} YT Audio         ${GREEN}[8]${RESET} Playlist Sync"
                "   ${GREEN}[4]${RESET} Video DL         ${GREEN}[9]${RESET} System Info"
                "   ${GREEN}[5]${RESET} Compress"
                "DIVIDER"
                " ${MAGENTA}${BOLD}■ UTILITIES${RESET}"
                "   ${YELLOW}[S]${RESET} Storage          ${YELLOW}[O]${RESET} Clean"
                "   ${YELLOW}[W]${RESET} Watch            ${YELLOW}[T]${RESET} Telegram"
                "   ${YELLOW}[P]${RESET} Playlist         ${YELLOW}[V]${RESET} Web UI"
                "   ${YELLOW}[M]${RESET} Metadata         ${YELLOW}[U]${RESET} Update"
                "   ${YELLOW}[A]${RESET} Zaki AI          ${RED}[X]${RESET} Delete All"
                "DIVIDER"
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
                if [ "$l_text" = "DIVIDER" ]; then
                    echo -e "  ${CYAN}├$(_repeat_char '─' $inner_cols)┤${RESET}"
                else
                    local l_pad=$(_pad_str "$l_text" $inner_cols)
                    echo -e "  ${CYAN}│${RESET}${l_pad}${CYAN}│${RESET}"
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
