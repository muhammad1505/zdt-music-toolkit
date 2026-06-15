#!/usr/bin/env bash
#
# ╔══════════════════════════════════════════════════════════════════╗
# ║  zdt.sh — Universal Music Toolkit (Production Build)           ║
# ║  Version : 3.0.0                                               ║
# ║  License : MIT                                                  ║
# ║  Compat  : Linux, Termux, proot-distro, Alpine, WSL            ║
# ╚══════════════════════════════════════════════════════════════════╝
#
# Fitur Utama:
#   1. Batch Download Spotify  (via spotdl)
#   2. Batch Download YouTube  (via yt-dlp)
#   3. Smart Audio Compressor  (via ffmpeg)
#   4. Auto Sync Lirik         (via syncedlyrics)
#   5. Generator Playlist M3U
#   6. Pembersih Nama File Otomatis
#   7. Update & Auto-Install Tools
#
# Cara Pakai:
#   chmod +x zdt.sh
#   ./zdt.sh
#
# Argumen opsional:
#   --no-color        Nonaktifkan warna output
#   --no-unicode      Nonaktifkan karakter unicode/emoji
#   --log-file PATH   Tulis log ke file
#   --version         Tampilkan versi
#   --help            Tampilkan bantuan

# ==========================================
# STRICT MODE & SHELL OPTIONS
# ==========================================
set -uo pipefail

# ==========================================
# CONSTANTS
# ==========================================
readonly APP_VERSION="3.0.1"
readonly APP_NAME="Zaki Downloader Tools"
readonly ZDT_VENV_DIR="$HOME/.local/share/zdt/venv"
readonly ZDT_CONFIG_FILE="$HOME/.config/zdt/config.env"
CONF_AUDIO_CODEC="1"
CONF_AUDIO_BITRATE="1"
CONF_VIDEO_CODEC="2"
CONF_VIDEO_QUAL="1"
CONF_VIDEO_FMT="4"

_load_config() {
    if [ -f "$ZDT_CONFIG_FILE" ]; then
        source "$ZDT_CONFIG_FILE"
    fi
}

_save_config() {
    mkdir -p "$(dirname "$ZDT_CONFIG_FILE")" 2>/dev/null
    cat > "$ZDT_CONFIG_FILE" <<CONFEOF
CONF_AUDIO_CODEC="$CONF_AUDIO_CODEC"
CONF_AUDIO_BITRATE="$CONF_AUDIO_BITRATE"
CONF_VIDEO_CODEC="$CONF_VIDEO_CODEC"
CONF_VIDEO_QUAL="$CONF_VIDEO_QUAL"
CONF_VIDEO_FMT="$CONF_VIDEO_FMT"
CONFEOF
}


# ==========================================
# PORTABILITY LAYER
# ==========================================

# Deteksi environment
_detect_environment() {
    # Check if we are inside PRoot. PRoot usually provides standard Linux root (/).
    # In raw Termux, the root path is usually not used, or $PREFIX is explicitly set.
    if [ -n "${TERMUX_VERSION:-}" ] || { [ -n "${PREFIX:-}" ] && [[ "${PREFIX:-}" == */com.termux/* ]]; }; then
        # This is raw Termux
        echo "termux"
    elif [ -f /etc/alpine-release ]; then
        echo "alpine"
    elif grep -qi microsoft /proc/version 2>/dev/null; then
        echo "wsl"
    elif [ -f /.dockerenv ] || grep -q 'docker\|lxc' /proc/1/cgroup 2>/dev/null; then
        echo "container"
    elif grep -qi 'android' /proc/version 2>/dev/null || uname -a | grep -qi 'android'; then
        # PRoot distros on Android leak the Android kernel string in /proc/version
        # However, they have a standard Linux filesystem.
        # Check if we have standard Linux paths that don't exist in raw Android/Termux
        if [ -d "/usr/share" ] && [ -d "/usr/bin" ]; then
            echo "linux" # PRoot distro behaves like linux
        else
            echo "termux"
        fi
    else
        echo "linux"
    fi
}

# Portable realpath (fallback via python3 atau manual resolution)
_realpath() {
    if command -v realpath >/dev/null 2>&1; then
        realpath "$@" 2>/dev/null && return 0
    fi
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$1" 2>/dev/null && return 0
    fi
    # Fallback manual: resolve via cd
    local target="$1"
    if [ -d "$target" ]; then
        (cd "$target" && pwd)
    elif [ -f "$target" ]; then
        local dir base
        dir=$(cd "$(dirname "$target")" && pwd)
        base=$(basename "$target")
        echo "$dir/$base"
    else
        echo "$target"
    fi
}

# Portable realpath --relative-to
_relpath() {
    local target="$1"
    local base="$2"
    if command -v realpath >/dev/null 2>&1; then
        realpath --relative-to="$base" "$target" 2>/dev/null && return 0
    fi
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$target" "$base" 2>/dev/null && return 0
    fi
    # Final fallback: strip common prefix (naive)
    echo "${target#./}"
}

# Portable memory usage
_get_ram_percent() {
    if command -v free >/dev/null 2>&1; then
        free 2>/dev/null | awk '/Mem:/ {if($2>0) printf "%.0f", $3/$2*100; else print "?"}' 2>/dev/null
        return
    fi
    # Termux / procfs fallback
    if [ -f /proc/meminfo ]; then
        awk '/MemTotal:/ {total=$2} /MemAvailable:/ {avail=$2}
             END {if(total>0) printf "%.0f", (total-avail)/total*100; else print "?"}' /proc/meminfo 2>/dev/null
        return
    fi
    echo "?"
}

# Portable uptime
_get_uptime() {
    if uptime -p >/dev/null 2>&1; then
        uptime -p 2>/dev/null | sed -e 's/^up //' -e 's/ hours\?/h/g' -e 's/ hour/h/g' -e 's/ minutes\?/m/g' -e 's/ minute/m/g' -e 's/ days\?/d/g' -e 's/ day/d/g' -e 's/ weeks\?/w/g' -e 's/ week/w/g' -e 's/,//g'
        return
    fi
    # Fallback via /proc/uptime
    if [ -f /proc/uptime ]; then
        awk '{
            s=int($1); d=int(s/86400); s%=86400;
            h=int(s/3600); s%=3600; m=int(s/60);
            if(d>0) printf "%dd %dh %dm", d, h, m;
            else if(h>0) printf "%dh %dm", h, m;
            else printf "%dm", m;
        }' /proc/uptime 2>/dev/null
        return
    fi
    echo "N/A"
}

# Portable storage usage
_get_storage_percent() {
    df . 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}' 2>/dev/null || echo "?"
}

# Portable OS detection
_get_os_name() {
    if [ -f /etc/os-release ]; then
        grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d '"' -f 2
    elif [ -n "${TERMUX_VERSION:-}" ]; then
        echo "Termux (Android)"
    elif [ -f /etc/alpine-release ]; then
        echo "Alpine $(cat /etc/alpine-release 2>/dev/null)"
    else
        uname -s 2>/dev/null || echo "Unknown"
    fi
}

# Portable mapfile replacement (untuk bash < 4.4)
# Menggunakan while-read loop sebagai fallback
_safe_find_dirs() {
    local -n _result_arr=$1
    local search_path="$2"
    _result_arr=()
    # Cek apakah find mendukung -print0 (GNU findutils)
    if find --version 2>&1 | grep -q 'GNU' 2>/dev/null; then
        while IFS= read -r -d '' dir; do
            _result_arr+=("$dir")
        done < <(find "$search_path" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
    else
        # Fallback untuk BusyBox/Alpine: gunakan newline separator
        while IFS= read -r dir; do
            [ -n "$dir" ] && _result_arr+=("$dir")
        done < <(find "$search_path" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
    fi
}

# Deteksi pip command
_get_pip_cmd() {
    if command -v pip3 >/dev/null 2>&1; then
        echo "pip3"
    elif command -v pip >/dev/null 2>&1; then
        echo "pip"
    else
        echo ""
    fi
}

# Deteksi package manager
_get_pkg_manager() {
    local mgr=""
    local sudo_prefix=""
    if command -v pkg >/dev/null 2>&1 && [ -n "${TERMUX_VERSION:-}" ]; then
        mgr="pkg"
    elif command -v apt-get >/dev/null 2>&1; then
        mgr="apt-get"
        [ "$(id -u)" -ne 0 ] && sudo_prefix="sudo"
    elif command -v apt >/dev/null 2>&1; then
        mgr="apt"
        [ "$(id -u)" -ne 0 ] && sudo_prefix="sudo"
    elif command -v dnf >/dev/null 2>&1; then
        mgr="dnf"
        [ "$(id -u)" -ne 0 ] && sudo_prefix="sudo"
    elif command -v yum >/dev/null 2>&1; then
        mgr="yum"
        [ "$(id -u)" -ne 0 ] && sudo_prefix="sudo"
    elif command -v pacman >/dev/null 2>&1; then
        mgr="pacman"
        [ "$(id -u)" -ne 0 ] && sudo_prefix="sudo"
    elif command -v apk >/dev/null 2>&1; then
        mgr="apk"
        [ "$(id -u)" -ne 0 ] && sudo_prefix="sudo"
    elif command -v zypper >/dev/null 2>&1; then
        mgr="zypper"
        [ "$(id -u)" -ne 0 ] && sudo_prefix="sudo"
    fi
    echo "${sudo_prefix:+$sudo_prefix }$mgr"
}

# Install package via detected manager
_pkg_install() {
    local pkg_name="$1"
    local mgr
    mgr=$(_get_pkg_manager)

    if [ -z "$mgr" ]; then
        _log "ERROR" "Tidak ada package manager yang terdeteksi"
        return 1
    fi

    _log "INFO" "Menginstal $pkg_name via $mgr..."

    case "$mgr" in
        *pkg)      $mgr install -y "$pkg_name" ;;
        *apt-get)  $mgr update -y && $mgr install -y "$pkg_name" ;;
        *apt)      $mgr update -y && $mgr install -y "$pkg_name" ;;
        *dnf)      $mgr install -y "$pkg_name" ;;
        *yum)      $mgr install -y "$pkg_name" ;;
        *pacman)   $mgr -Sy --noconfirm "$pkg_name" ;;
        *apk)      $mgr add "$pkg_name" ;;
        *zypper)   $mgr install -y "$pkg_name" ;;
    esac
}

# ==========================================
# KONFIGURASI WARNA & FORMATTING
# ==========================================
_setup_colors() {
    if [ "${NO_COLOR:-0}" = "1" ] || [ ! -t 1 ]; then
        GREEN='' CYAN='' MAGENTA='' WHITE='' GRAY=''
        RED='' YELLOW='' BOLD='' RESET=''
    else
        GREEN='\033[1;32m'
        CYAN='\033[1;36m'
        MAGENTA='\033[1;35m'
        WHITE='\033[1;37m'
        GRAY='\033[0;37m'
        RED='\033[1;31m'
        YELLOW='\033[1;33m'
        BOLD='\033[1m'
        RESET='\033[0m'
    fi
}

# Unicode/emoji support detection
_setup_unicode() {
    if [ "${NO_UNICODE:-0}" = "1" ]; then
        ICO_OK="[OK]"; ICO_FAIL="[X]"; ICO_WARN="[!]"
        ICO_ARROW="->"; ICO_MUSIC="#"; ICO_GEAR="*"
        ICO_SEARCH="?"; ICO_LIST="="; ICO_CUT=">"
        ICO_UPDATE="@"; ICO_DANGER="!!"; ICO_ROCKET="^"
        ICO_EXIT="x"; ICO_PLAY=">"
        ICO_CHECK_OK="v"; ICO_CHECK_FAIL="x"
    else
        ICO_OK="✔"; ICO_FAIL="✖"; ICO_WARN="⚠"
        ICO_ARROW="➜"; ICO_MUSIC="♫"; ICO_GEAR="⚙"
        ICO_SEARCH="⚲"; ICO_LIST="≡"; ICO_CUT="✄"
        ICO_UPDATE="↻"; ICO_DANGER="⚠"; ICO_ROCKET="🚀"
        ICO_EXIT="✕"; ICO_PLAY="►"
        ICO_CHECK_OK="✔"; ICO_CHECK_FAIL="✖"
    fi
}

# ==========================================
# LOGGING SYSTEM & ERROR HANDLING
# ==========================================
LOG_FILE=""
DEFAULT_LOG_DIR="$HOME/.local/state/zdt"
DEFAULT_LOG_FILE="$DEFAULT_LOG_DIR/zdt.log"
MAX_LOG_SIZE=$((5 * 1024 * 1024)) # 5MB

_init_logging() {
    if [ -z "$LOG_FILE" ]; then
        LOG_FILE="$DEFAULT_LOG_FILE"
    fi
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
}

_rotate_log() {
    if [ -f "$LOG_FILE" ]; then
        local size
        size=$(stat -c%s "$LOG_FILE" 2>/dev/null || stat -f%z "$LOG_FILE" 2>/dev/null || wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$size" -gt "$MAX_LOG_SIZE" ]; then
            mv "$LOG_FILE" "${LOG_FILE}.old" 2>/dev/null || true
        fi
    fi
}

_log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date '+%s')

    if [ -n "$LOG_FILE" ]; then
        _rotate_log
        echo "[$timestamp] [$level] $msg" >> "$LOG_FILE" 2>/dev/null
    fi
}

# Trap unexpected errors
_trap_err() {
    local line=$1
    local code=$2
    _log "ERROR" "Command failed at line $line with exit code $code"
}
# Only trap ERR if explicitly in debug mode to avoid noise in normal usage
if [ "${ZDT_DEBUG:-0}" = "1" ]; then
    set -o errtrace
    trap '_trap_err $LINENO $?' ERR
fi

# ==========================================
# LOCKFILE PROTECTION
# ==========================================
LOCK_FILE="/tmp/.zdt_sh_$(id -u 2>/dev/null || echo 0).lock"

_acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local old_pid
        old_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
            echo -e "  ${RED}${ICO_FAIL} Instance lain sedang berjalan (PID: $old_pid)!${RESET}"
            echo -e "  ${YELLOW}Tutup dulu instance tersebut, atau hapus: $LOCK_FILE${RESET}"
            return 1
        fi
        rm -f "$LOCK_FILE"
    fi
    echo $$ > "$LOCK_FILE"
    return 0
}

_release_lock() {
    rm -f "$LOCK_FILE" 2>/dev/null
}

# ==========================================
# CONFIG FILE MANAGEMENT
# ==========================================
_get_config_dir() {
    if [ -n "${XDG_CONFIG_HOME:-}" ]; then
        echo "$XDG_CONFIG_HOME/zdt"
    elif [ -n "${HOME:-}" ]; then
        echo "$HOME/.config/zdt"
    else
        echo "/tmp/.zdt-config-$(id -u 2>/dev/null || echo 0)"
    fi
}

_get_config_file() {
    echo "$(_get_config_dir)/config"
}

# Baca value dari config file
_config_get() {
    local key="$1"
    local default="${2:-}"
    local config_file
    config_file=$(_get_config_file)

    if [ -f "$config_file" ]; then
        local val
        val=$(grep "^${key}=" "$config_file" 2>/dev/null | head -1 | cut -d'=' -f2-)
        if [ -n "$val" ]; then
            echo "$val"
            return 0
        fi
    fi
    echo "$default"
}

# Tulis value ke config file
_config_set() {
    local key="$1"
    local value="$2"
    local config_dir config_file
    config_dir=$(_get_config_dir)
    config_file=$(_get_config_file)

    mkdir -p "$config_dir" 2>/dev/null

    if [ -f "$config_file" ]; then
        # Hapus key lama, tulis yang baru
        local tmp_file="${config_file}.tmp"
        grep -v "^${key}=" "$config_file" > "$tmp_file" 2>/dev/null || true
        echo "${key}=${value}" >> "$tmp_file"
        mv -- "$tmp_file" "$config_file"
    else
        echo "${key}=${value}" > "$config_file"
    fi
}

# Hapus key dari config
_config_unset() {
    local key="$1"
    local config_file
    config_file=$(_get_config_file)

    if [ -f "$config_file" ]; then
        local tmp_file="${config_file}.tmp"
        grep -v "^${key}=" "$config_file" > "$tmp_file" 2>/dev/null || true
        mv -- "$tmp_file" "$config_file"
    fi
}

# Load dan validasi storage dir dari config
_load_storage_dir() {
    local saved_dir
    saved_dir=$(_config_get "storage_dir" "")

    if [ -n "$saved_dir" ] && [ -d "$saved_dir" ]; then
        STORAGE_DIR="$saved_dir"
    else
        STORAGE_DIR=""
    fi
}

# ==========================================
# GLOBAL STATE
# ==========================================
ROOT_DIR=""
TARGET_DIR="."
RUNTIME_ENV=""
STORAGE_DIR=""
NET_TMP=""
NET_PID=""

# ==========================================
# ANTI-CRASH TRAP
# ==========================================
_trap_ctrlc() {
    [ -n "$NET_PID" ] && kill -9 "$NET_PID" 2>/dev/null
    [ -n "$NET_TMP" ] && rm -f "$NET_TMP" 2>/dev/null
    echo -ne "\033[?1049l\033[?25h"
    echo ""
    echo -e "  ${RED}${ICO_FAIL} PROSES DIBATALKAN (Ctrl+C)!${RESET}"
    echo -e "  ${YELLOW}Membersihkan file temporary...${RESET}"
    find "${ROOT_DIR:-.}" -type f -name "*_temp.*" -delete 2>/dev/null
    echo -e "  ${GREEN}${ICO_OK} Bersih! Kembali ke menu utama...${RESET}"
    sleep 1
    cd "$ROOT_DIR" || exit 1
    _release_lock
    # Restart diri sendiri secara aman
    exec bash "$SCRIPT_PATH" "${ORIGINAL_ARGS[@]}"
}

_trap_exit() {
    [ -n "$NET_PID" ] && kill -9 "$NET_PID" 2>/dev/null
    [ -n "$NET_TMP" ] && rm -f "$NET_TMP" 2>/dev/null
    echo -ne "\033[?1049l\033[?25h"
    _release_lock
}

# ==========================================
# HELPER: PRINT HEADER
# ==========================================
print_header() {
    echo -ne "\033[?25h"
    clear
    echo ""
    local btxt
    printf -v btxt "%-50s" " $1"
    echo -e "  ${CYAN}╔══════════════════════════════════════════════════╗${RESET}"
    echo -e "  ${CYAN}║${RESET}${WHITE}${BOLD}${btxt}${RESET}${CYAN}║${RESET}"
    echo -e "  ${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
    echo ""
}

# ==========================================
# HELPER: PAUSE BEFORE RETURN TO MENU
# ==========================================
_pause() {
    echo ""
    # Flush sisa stdin buffer (newline dari read -n 1 sebelumnya)
    while read -s -r -t 0.01 -n 1000 2>/dev/null; do :; done
    echo -e -n "  ${GRAY}[ Tekan tombol apa aja untuk kembali ke menu... ]${RESET}"
    read -s -r -n 1 2>/dev/null || read -r -n 1 2>/dev/null || true
    echo ""
}

# ==========================================
# HELPER: VALIDASI DEPENDENCY
# ==========================================
_check_dependency() {
    local tool="$1"
    local required="${2:-false}"

    if command -v "$tool" >/dev/null 2>&1; then
        return 0
    fi

    if [ "$required" = "true" ]; then
        echo -e "  ${RED}${ICO_FAIL} '$tool' tidak ditemukan!${RESET}"
        echo -e "  ${YELLOW}Jalankan menu Auto Install Tools untuk memasangnya.${RESET}"
        return 1
    fi
    return 1
}

# ==========================================
# HELPER: SELECT TARGET FOLDER
# ==========================================
pilih_folder_target() {
    echo -e "  ${CYAN}${ICO_ARROW} PILIH TARGET FOLDER${RESET}"
    echo "    [0] ${ICO_FAIL} BATAL / KEMBALI"
    echo "    [1] Semua (Root Direktori Saat Ini)"

    local folder_list=()
    _safe_find_dirs folder_list "."

    local count=${#folder_list[@]}
    if [ "$count" -gt 0 ]; then
        for ((i = 0; i < count; i++)); do
            local nama_f
            nama_f=$(basename "${folder_list[$i]}")
            echo "    [$((i + 2))] $nama_f"
        done
    else
        echo -e "    ${GRAY}(Tidak ada sub-folder terdeteksi)${RESET}"
    fi

    local max_idx=$((count + 1))
    echo -e -n "  ${BOLD}[?] Pilihan [0-$max_idx] (Enter = 1): ${RESET}"
    read -r target_idx
    echo ""

    if [ "$target_idx" = "0" ]; then
        echo -e "  ${YELLOW}${ICO_ARROW} Dibatalkan! Kembali ke menu utama...${RESET}"
        return 1
    elif [ -z "$target_idx" ] || [ "$target_idx" = "1" ]; then
        TARGET_DIR="."
        echo -e "  ${GREEN}${ICO_OK} Target disetel ke: Semua (Root)${RESET}"
        return 0
    elif [[ "$target_idx" =~ ^[0-9]+$ ]] && [ "$target_idx" -le "$max_idx" ] && [ "$target_idx" -gt 1 ]; then
        TARGET_DIR=$(basename "${folder_list[$((target_idx - 2))]}")
        TARGET_DIR="./$TARGET_DIR"
        echo -e "  ${GREEN}${ICO_OK} Target disetel ke: $TARGET_DIR${RESET}"
        return 0
    else
        echo -e "  ${RED}${ICO_FAIL} Pilihan tidak valid! Otomatis disetel ke Semua (Root).${RESET}"
        TARGET_DIR="."
        return 0
    fi
}

# ==========================================
# HELPER: PEMBERSIH NAMA FILE
# ==========================================
_bersih_satu_nama() {
    local file="$1"

    if [ ! -f "$file" ]; then
        return 0
    fi

    local dir base
    dir=$(dirname "$file")
    base=$(basename "$file")

    # Gunakan Python3 untuk pembersihan nama yang aman
    if ! command -v python3 >/dev/null 2>&1; then
        _log "WARN" "python3 tidak tersedia, skip pembersihan nama: $base"
        return 0
    fi

    local newbase
    newbase=$(python3 -c "
import re, sys, os
base = sys.argv[1]
name, ext = os.path.splitext(base)

# Keep up to the end of known anchors, drop trailing junk
m = re.search(r'(\s*[\(\[]\s*(?:Official|Live|Music|Video|Lyric|Audio|Performance|Acoustic|Cover|Lirik).*?[\)\]])', name, flags=re.IGNORECASE)
if m:
    name = name[:m.end()]

# Strip out unwanted pure promotional tags anywhere
name = re.sub(r'[\(\[]\s*(?:4K|8K|HD|HQ|1080p|720p).*?[\)\]]', '', name, flags=re.IGNORECASE)

# Clean up spaces
name = re.sub(r'  +', ' ', name).strip()
name = re.sub(r' \.', '.', name)

print(name + ext)
" "$base" 2>/dev/null || echo "$base")

    if [ "$base" != "$newbase" ] && [ -n "$newbase" ]; then
        if [ -e "$dir/$newbase" ]; then
            local filename extension
            if [[ "$newbase" == *.* ]]; then
                filename="${newbase%.*}"
                extension="${newbase##*.}"
            else
                filename="$newbase"
                extension=""
            fi

            local counter=1
            if [ -n "$extension" ]; then
                while [ -e "$dir/${filename} (${counter}).${extension}" ]; do
                    ((counter++))
                done
                newbase="${filename} (${counter}).${extension}"
            else
                while [ -e "$dir/${filename} (${counter})" ]; do
                    ((counter++))
                done
                newbase="${filename} (${counter})"
            fi
        fi
        mv -- "$file" "$dir/$newbase" && echo -e "    ${GREEN}${ICO_OK} Dirapikan:${RESET} $newbase"
        _log "INFO" "Renamed: $base -> $newbase"
        
        # AUTO-TAGGER METADATA (Berdasarkan nama file bersih)
        local final_file="$dir/$newbase"
        if [[ -f "$ZDT_VENV_DIR/bin/python" ]]; then
            "$ZDT_VENV_DIR/bin/python" -c "
import sys, os
try:
    import mutagen
    from mutagen.easyid3 import EasyID3
    from mutagen.mp4 import MP4
    from mutagen.flac import FLAC
    file_path = sys.argv[1]
    name_noext = os.path.splitext(os.path.basename(file_path))[0]
    artist = 'Unknown Artist'
    title = name_noext
    if ' - ' in name_noext:
        parts = name_noext.split(' - ', 1)
        artist = parts[0].strip()
        title = parts[1].strip()
    
    if file_path.lower().endswith('.mp3'):
        try:
            audio = EasyID3(file_path)
        except mutagen.id3.ID3NoHeaderError:
            audio = mutagen.File(file_path, easy=True)
            audio.add_tags()
        audio['title'] = title
        audio['artist'] = artist
        audio.save()
    elif file_path.lower().endswith('.m4a'):
        audio = MP4(file_path)
        audio['\xa9nam'] = title
        audio['\xa9ART'] = artist
        audio.save()
    elif file_path.lower().endswith('.flac'):
        audio = FLAC(file_path)
        audio['title'] = title
        audio['artist'] = artist
        audio.save()
except Exception:
    pass
" "$final_file" 2>/dev/null
        fi
    else
        echo -e "    ${GRAY}${ICO_CHECK_OK} Sudah rapi:${RESET} $base"
    fi
}

bersih_nama_otomatis() {
    local scan_dir="${1:-.}"
    echo -e "  ${CYAN}${ICO_ARROW} AUTO CLEAN NAMA FILE${RESET}"
    while IFS= read -r file; do
        _bersih_satu_nama "$file"
    done < <(find "$scan_dir" -type f \( -iname "*.m4a" -o -iname "*.mp3" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.ogg" -o -iname "*.opus" -o -iname "*.mp4" -o -iname "*.lrc" \) -mmin -60 2>/dev/null)
}

# ==========================================
# HELPER: KOMPRES AUDIO TUNGGAL
# ==========================================
_kompres_audio_file() {
    local file="$1"
    local codec="${2:-aac}"
    local bitrate="${3:-128k}"
    local target_ext="${4:-m4a}"

    if [ ! -f "$file" ]; then
        return 0
    fi

    if ! command -v ffmpeg >/dev/null 2>&1; then
        echo -e "    ${RED}${ICO_FAIL} ffmpeg tidak tersedia!${RESET}"
        return 1
    fi

    local dir base filename_noext ext_original
    dir=$(dirname "$file")
    base=$(basename "$file")
    filename_noext="${base%.*}"
    ext_original="${base##*.}"

    local temp_file="$dir/${filename_noext}_temp.${target_ext}"

    if ffmpeg -y -nostdin -v quiet -threads 2 -i "$file" -c:v copy -c:a "$codec" -b:a "$bitrate" "$temp_file"; then
        # Hapus file asli hanya jika beda nama dengan output
        if [ "$file" != "$dir/${filename_noext}.${target_ext}" ]; then
            rm -f "$file"
        fi
        mv -- "$temp_file" "$dir/${filename_noext}.${target_ext}"
        if [ "$ext_original" != "$target_ext" ]; then
            echo -e "    ${GREEN}${ICO_OK} SUKSES KOMPRES:${RESET} $base ${GRAY}→ .${target_ext} ($codec $bitrate)${RESET}"
        else
            echo -e "    ${GREEN}${ICO_OK} SUKSES KOMPRES:${RESET} $base"
        fi
        _log "INFO" "Compressed: $base -> ${filename_noext}.${target_ext}"
    else
        rm -f "$temp_file"
        echo -e "    ${RED}${ICO_FAIL} GAGAL KOMPRES:${RESET} $base"
        _log "ERROR" "Compression failed: $base"
    fi
}

# ==========================================
# HELPER: KOMPRES VIDEO TUNGGAL (x265)
# ==========================================
_kompres_video_file() {
    local file="$1"
    local codec="${2:-libx265}"
    local v_qual="${3:--crf 28}"
    local target_ext="${4:-mp4}"

    if [ ! -f "$file" ]; then
        return 0
    fi

    if ! command -v ffmpeg >/dev/null 2>&1; then
        echo -e "    ${RED}${ICO_FAIL} ffmpeg tidak tersedia!${RESET}"
        return 1
    fi

    local dir base filename_noext ext_original
    dir=$(dirname "$file")
    base=$(basename "$file")
    filename_noext="${base%.*}"
    ext_original="${base##*.}"

    local temp_file="$dir/${filename_noext}_temp.${target_ext}"

    echo -e -n "    ${CYAN}${ICO_ARROW} Mengompresi ke $codec... Harap sabar! "
    local qual_arr=()
    read -r -a qual_arr <<< "$v_qual"

    ffmpeg -y -nostdin -v quiet -threads 2 -i "$file" -c:v "$codec" "${qual_arr[@]}" -preset fast -c:a aac -b:a 128k "$temp_file" &
    local fpid=$!
    local spin='-\|/'
    local i=0
    while kill -0 $fpid 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\b${spin:$i:1}"
        sleep 0.1
    done
    wait $fpid
    local f_exit=$?
    echo -e "\b "

    if [ "$f_exit" -eq 0 ] && [ -f "$temp_file" ]; then
        if [ "$file" != "$dir/${filename_noext}.${target_ext}" ]; then
            rm -f "$file"
        fi
        mv -- "$temp_file" "$dir/${filename_noext}.${target_ext}"
        echo -e "    ${GREEN}${ICO_OK} SUKSES KOMPRES VIDEO:${RESET} $base ${GRAY}→ .${target_ext} ($codec)${RESET}"
        _log "INFO" "Video compressed to $codec: $base"
    else
        rm -f "$temp_file"
        echo -e "    ${RED}${ICO_FAIL} GAGAL KOMPRES VIDEO:${RESET} $base"
        _log "ERROR" "Video compression failed: $base"
    fi
}

# ==========================================
# FUNGSI UTAMA: KOMPRES MEDIA
# ==========================================
# ==========================================
# FUNGSI UTAMA: KOMPRES MEDIA (WRAPPER)
# ==========================================
kompres_media() {
    while true; do
        print_header "SMART MEDIA COMPRESSOR"

        echo -e "  ${CYAN}${ICO_ARROW} TIPE MEDIA${RESET}"
        echo "    1. Audio"
        echo "    2. Video"
        echo "    0. ${ICO_FAIL} KEMBALI KE MENU UTAMA"
        echo -e -n "  ${BOLD}[?] Pilih Mode [0-2]: ${RESET}"
        local mode_media
        read -r -n 1 mode_media
        echo ""
        [ "$mode_media" = "0" ] && { echo -e "  ${YELLOW}${ICO_ARROW} Kembali ke menu utama!${RESET}"; return 0; }
        [[ ! "$mode_media" =~ ^[1-2]$ ]] && { echo -e "  ${RED}${ICO_FAIL} Pilihan tidak valid!${RESET}"; sleep 1; continue; }

        if [ "$mode_media" = "1" ]; then
            _kompres_audio_batch && return 0
        else
            _kompres_video_batch && return 0
        fi
    done
}

_kompres_audio_batch() {
    if ! _check_dependency "ffmpeg" "true"; then return 1; fi

    local step=1 target_dir=""
    local c_opt="" codec="" ext_pilih=""
    local b_opt="" bitrate=""
    local mode_scan=""

    while true; do
        if [ "$step" -eq 1 ]; then
            echo ""
            echo -e "  ${CYAN}${ICO_ARROW} MODE AUDIO COMPRESSOR${RESET}"
            if ! pilih_folder_target; then return 1; fi
            target_dir="$TARGET_DIR"
            step=2
        elif [ "$step" -eq 2 ]; then
            echo -e "  ${CYAN}${ICO_ARROW} CODEC AUDIO${RESET}"
            echo "    1. AAC (Default, sangat kompatibel, .m4a)"
            echo "    2. MP3 (Libmp3lame, universal, .mp3)"
            echo "    3. FLAC (Lossless, ukuran besar, .flac)"
            echo "    4. OPUS (Ukuran kecil, suara jernih, .opus)"
            echo "    0. ${ICO_FAIL} KEMBALI"
            echo -e -n "  ${BOLD}[?] Pilih Codec [1-4, 0=Kembali, Default=1]: ${RESET}"
            read -r -n 1 c_opt; echo ""
            if [ "$c_opt" = "0" ]; then step=1; continue; fi
            case "$c_opt" in
                2) codec="libmp3lame"; ext_pilih="mp3" ;;
                3) codec="flac"; ext_pilih="flac" ;;
                4) codec="libopus"; ext_pilih="opus" ;;
                *) codec="aac"; ext_pilih="m4a" ;;
            esac
            if [ "$codec" = "flac" ]; then step=4; else step=3; fi
        elif [ "$step" -eq 3 ]; then
            echo -e "  ${CYAN}${ICO_ARROW} BITRATE AUDIO${RESET}"
            echo "    1. 128k (Standar, ukuran kecil)"
            echo "    2. 192k (Menengah, bagus)"
            echo "    3. 256k (Tinggi, sangat bagus)"
            echo "    4. 320k (Maksimal, HQ)"
            echo "    0. ${ICO_FAIL} KEMBALI"
            echo -e -n "  ${BOLD}[?] Pilih Bitrate [1-4, 0=Kembali, Default=1]: ${RESET}"
            read -r -n 1 b_opt; echo ""
            if [ "$b_opt" = "0" ]; then step=2; continue; fi
            case "$b_opt" in
                2) bitrate="192k" ;;
                3) bitrate="256k" ;;
                4) bitrate="320k" ;;
                *) bitrate="128k" ;;
            esac
            step=4
        elif [ "$step" -eq 4 ]; then
            echo -e "  ${CYAN}${ICO_ARROW} JANGKAUAN SCAN${RESET}"
            echo "    1. Semua file di target folder"
            echo "    2. File baru saja (60 menit terakhir)"
            echo "    0. ${ICO_FAIL} KEMBALI"
            echo -e -n "  ${BOLD}[?] Pilih Mode [0-2, 0=Kembali, Default=1]: ${RESET}"
            read -r -n 1 mode_scan; echo ""
            if [ "$mode_scan" = "0" ]; then
                if [ "$codec" = "flac" ]; then step=2; else step=3; fi
                continue
            fi
            step=5
        elif [ "$step" -eq 5 ]; then
            break
        fi
    done

    local time_arg=()
    [ "$mode_scan" = "2" ] && time_arg=(-mmin -60)

    # Bersihkan temp files yang nyangkut
    find "$target_dir" -type f -name "*_temp.*" -delete 2>/dev/null

    local find_args=("$target_dir" -type f)
    if [ -z "$ext_pilih" ]; then
        find_args+=(\( -iname "*.m4a" -o -iname "*.mp3" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.ogg" \))
    else
        find_args+=(-iname "*.$ext_pilih")
    fi
    find_args+=("!" -name "*_temp.*" "${time_arg[@]}")

    local total_files
    total_files=$(find "${find_args[@]}" 2>/dev/null | wc -l)

    if [ "$total_files" -eq 0 ]; then
        echo -e "  ${RED}${ICO_FAIL} Tidak ada file yang cocok untuk dikompres!${RESET}"
        return
    fi

    echo -e "  ${YELLOW}${ICO_ARROW} Total: $total_files file. Memulai eksekusi...${RESET}"
    echo ""

    local current=0
    local bg_pids=()
    local max_jobs=$(nproc 2>/dev/null || echo 4)
    [ "$max_jobs" -gt 4 ] && max_jobs=4 # Batasi max 4 biar gak berat

    while IFS= read -r file; do
        ((current++))
        local percent=$((current * 100 / total_files))
        printf "  [%3d%%] %s ...\n" "$percent" "$(basename "$file")"
        
        # Jalankan di latar belakang
        _kompres_audio_file "$file" "$codec" "$bitrate" "$ext_pilih" >/dev/null 2>&1 &
        bg_pids+=($!)
        
        # Tunggu jika worker penuh
        if [ ${#bg_pids[@]} -ge $max_jobs ]; then
            wait -n 2>/dev/null
            # Hapus pid yang udah kelar
            local new_pids=()
            for pid in "${bg_pids[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    new_pids+=("$pid")
                fi
            done
            bg_pids=("${new_pids[@]}")
        fi
    done < <(find "${find_args[@]}" 2>/dev/null)
    
    # Tunggu sisa proses
    wait 2>/dev/null
    echo -e "  ──────────────────────────────────────────────────"


    echo -e "  ${GREEN}${ICO_OK} 100% Kompresi Selesai!${RESET}"
    _log "INFO" "Audio compression complete: $current files processed"
}

_kompres_video_batch() {
    if ! _check_dependency "ffmpeg" "true"; then return 1; fi

    local step=1 target_dir=""
    local c_opt="" codec="" default_ext=""
    local b_opt="" v_qual=""
    local f_opt="" target_ext=""
    local mode_scan=""

    while true; do
        if [ "$step" -eq 1 ]; then
            echo ""
            echo -e "  ${CYAN}${ICO_ARROW} MODE VIDEO COMPRESSOR${RESET}"
            if ! pilih_folder_target; then return 1; fi
            target_dir="$TARGET_DIR"
            step=2
        elif [ "$step" -eq 2 ]; then
            echo -e "  ${CYAN}${ICO_ARROW} CODEC VIDEO${RESET}"
            echo "    1. x264/AVC (Kompatibel, cepat)"
            echo "    2. x265/HEVC (Default, ukuran sangat kecil)"
            echo "    3. AV1 (Ukuran terkecil, sangat lambat)"
            echo "    4. VP9 (Ringan, cocok untuk WebM)"
            echo "    0. ${ICO_FAIL} KEMBALI"
            echo -e -n "  ${BOLD}[?] Pilih Codec [1-4, 0=Kembali, Default=2]: ${RESET}"
            read -r -n 1 c_opt; echo ""
            if [ "$c_opt" = "0" ]; then step=1; continue; fi
            case "$c_opt" in
                1) codec="libx264"; default_ext="mp4" ;;
                3) codec="libsvtav1"; default_ext="mkv" ;;
                4) codec="libvpx-vp9"; default_ext="webm" ;;
                *) codec="libx265"; default_ext="mp4" ;;
            esac
            step=3
        elif [ "$step" -eq 3 ]; then
            echo -e "  ${CYAN}${ICO_ARROW} KUALITAS (CRF / BITRATE)${RESET}"
            echo "    1. CRF 28 (Default, ukuran kecil)"
            echo "    2. CRF 23 (Kualitas bagus, ukuran sedang)"
            echo "    3. Bitrate 2M (Kualitas stabil menengah)"
            echo "    4. Bitrate 5M (Kualitas tinggi)"
            echo "    0. ${ICO_FAIL} KEMBALI"
            echo -e -n "  ${BOLD}[?] Pilih Kualitas [1-4, 0=Kembali, Default=1]: ${RESET}"
            read -r -n 1 b_opt; echo ""
            if [ "$b_opt" = "0" ]; then step=2; continue; fi
            case "$b_opt" in
                2) v_qual="-crf 23" ;;
                3) v_qual="-b:v 2M" ;;
                4) v_qual="-b:v 5M" ;;
                *) v_qual="-crf 28" ;;
            esac
            step=4
        elif [ "$step" -eq 4 ]; then
            echo -e "  ${CYAN}${ICO_ARROW} FORMAT OUTPUT${RESET}"
            echo "    1. MP4 (Paling Kompatibel)"
            echo "    2. MKV (Support banyak fitur/subtitle)"
            echo "    3. WebM (Khusus VP9/AV1)"
            echo "    4. Ikuti Codec (Default, .${default_ext})"
            echo "    0. ${ICO_FAIL} KEMBALI"
            echo -e -n "  ${BOLD}[?] Pilih Format [1-4, 0=Kembali, Default=4]: ${RESET}"
            read -r -n 1 f_opt; echo ""
            if [ "$f_opt" = "0" ]; then step=3; continue; fi
            case "$f_opt" in
                1) target_ext="mp4" ;;
                2) target_ext="mkv" ;;
                3) target_ext="webm" ;;
                *) target_ext="$default_ext" ;;
            esac
            step=5
        elif [ "$step" -eq 5 ]; then
            echo -e "  ${CYAN}${ICO_ARROW} JANGKAUAN SCAN${RESET}"
            echo "    1. Semua file di target folder"
            echo "    2. File baru saja (60 menit terakhir)"
            echo "    0. ${ICO_FAIL} KEMBALI"
            echo -e -n "  ${BOLD}[?] Pilih Mode [0-2, 0=Kembali, Default=1]: ${RESET}"
            read -r -n 1 mode_scan; echo ""
            if [ "$mode_scan" = "0" ]; then step=4; continue; fi
            step=6
        elif [ "$step" -eq 6 ]; then
            break
        fi
    done

    local time_arg=()
    [ "$mode_scan" = "2" ] && time_arg=(-mmin -60)

    # Bersihkan temp files yang nyangkut
    find "$target_dir" -type f -name "*_temp.*" -delete 2>/dev/null

    local find_args=("$target_dir" -type f)
    find_args+=(\( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.webm" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.ts" \))
    find_args+=("!" -name "*_temp.*" "${time_arg[@]}")

    local total_files
    total_files=$(find "${find_args[@]}" 2>/dev/null | wc -l)

    if [ "$total_files" -eq 0 ]; then
        echo -e "  ${RED}${ICO_FAIL} Tidak ada file yang cocok untuk dikompres!${RESET}"
        return
    fi

    echo -e "  ${YELLOW}${ICO_ARROW} Total: $total_files file. Memulai eksekusi...${RESET}"
    echo ""

    local current=0
    local bg_pids=()
    local max_jobs=$(nproc 2>/dev/null || echo 2)
    [ "$max_jobs" -gt 2 ] && max_jobs=2 # Video berat, batasi max 2

    while IFS= read -r file; do
        ((current++))
        local percent=$((current * 100 / total_files))
        printf "  [%3d%%] %s ...\n" "$percent" "$(basename "$file")"
        
        _kompres_video_file "$file" "$codec" "$v_qual" "$target_ext" >/dev/null 2>&1 &
        bg_pids+=($!)
        
        if [ ${#bg_pids[@]} -ge $max_jobs ]; then
            wait -n 2>/dev/null
            local new_pids=()
            for pid in "${bg_pids[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    new_pids+=("$pid")
                fi
            done
            bg_pids=("${new_pids[@]}")
        fi
    done < <(find "${find_args[@]}" 2>/dev/null)
    wait 2>/dev/null
    echo -e "  ──────────────────────────────────────────────────"


    echo -e "  ${GREEN}${ICO_OK} 100% Kompresi Selesai!${RESET}"
    _log "INFO" "Video compression complete: $current files processed"
}

# ==========================================
# FUNGSI UTAMA: HAPUS VOKAL (KARAOKE DEMUCS AI)
# ==========================================
hapus_vokal() {
    print_header "HAPUS VOKAL (AI DEMUCS)"

    local venv_dir="$HOME/.local/share/zdt/demucs_venv"
    local demucs_bin="$venv_dir/bin/demucs"

    if [ ! -f "$demucs_bin" ]; then
        echo -e "  ${YELLOW}${ICO_WARN} Demucs AI belum terinstal.${RESET}"
        echo -e "  ${GRAY}Proses instalasi akan membuat virtual environment dan mendownload${RESET}"
        echo -e "  ${GRAY}library PyTorch & Demucs (total sekitar 2-3 GB).${RESET}"
        echo -e -n "  ${BOLD}[?] Lanjutkan instalasi sekarang? [Y/n]: ${RESET}"
        local confirm
        read -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]] && [ -n "$confirm" ]; then
            echo -e "  ${RED}${ICO_FAIL} Instalasi dibatalkan.${RESET}"
            return 0
        fi

        echo -e "\n  ${CYAN}${ICO_ARROW} Membuat Python Virtual Environment...${RESET}"
        if ! python3 -m venv "$venv_dir"; then
            echo -e "  ${RED}${ICO_FAIL} Gagal membuat virtual environment. Pastikan paket python3-venv terinstal.${RESET}"
            return 1
        fi

        echo -e "  ${CYAN}${ICO_ARROW} Mendownload & Menginstal Demucs (Ini butuh waktu cukup lama)...${RESET}"
        if ! "$venv_dir/bin/pip" install -U pip setuptools demucs torchcodec; then
            echo -e "  ${RED}${ICO_FAIL} Gagal menginstal Demucs!${RESET}"
            rm -rf "$venv_dir"
            return 1
        fi
        echo -e "  ${GREEN}${ICO_OK} Demucs berhasil diinstal!${RESET}\n"
    fi

    local step=1
    local mode_proses=""
    local files_to_process=()

    if [ -n "$AUTO_HAPUS_VOKAL_MODE" ]; then
        mode_proses="$AUTO_HAPUS_VOKAL_MODE"
        if [ "$mode_proses" = "1" ]; then
            local target_dir="${TARGET_DIR:-$(pwd)}"
            local find_args=("$target_dir" -type f \( -iname "*.mp3" -o -iname "*.m4a" -o -iname "*.wav" -o -iname "*.flac" -o -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.webm" \) ! -name "*_karaoke.*" -mmin -60)
            while IFS= read -r f; do
                files_to_process+=("$f")
            done < <(find "${find_args[@]}" 2>/dev/null)
        elif [ "$mode_proses" = "2" ]; then
            if [ -n "$AUTO_HAPUS_VOKAL_PATH" ] && [ -f "$AUTO_HAPUS_VOKAL_PATH" ]; then
                files_to_process+=("$AUTO_HAPUS_VOKAL_PATH")
            fi
        fi
        AUTO_HAPUS_VOKAL_MODE=""
        AUTO_HAPUS_VOKAL_PATH=""
    else
        while true; do
            if [ "$step" -eq 1 ]; then
                echo -e "  ${CYAN}${ICO_ARROW} MODE PROSES${RESET}"
                echo "    1. Batch (Satu Folder Penuh)"
                echo "    2. Satu File Spesifik"
                echo "    0. ${ICO_FAIL} KEMBALI"
                echo -e -n "  ${BOLD}[?] Pilih Mode [0-2]: ${RESET}"
                read -r -n 1 mode_proses
                echo ""
                [ "$mode_proses" = "0" ] && return 0
                if [[ ! "$mode_proses" =~ ^[1-2]$ ]]; then
                    echo -e "  ${RED}${ICO_FAIL} Pilihan tidak valid!${RESET}"
                    continue
                fi
                step=2
            elif [ "$step" -eq 2 ]; then
                files_to_process=()
                if [ "$mode_proses" = "1" ]; then
                    if ! pilih_folder_target; then step=1; continue; fi
                    local target_dir="$TARGET_DIR"

                    local find_args=("$target_dir" -type f \( -iname "*.mp3" -o -iname "*.m4a" -o -iname "*.wav" -o -iname "*.flac" -o -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.webm" \) ! -name "*_karaoke.*")
                    while IFS= read -r f; do
                        files_to_process+=("$f")
                    done < <(find "${find_args[@]}" 2>/dev/null)

                elif [ "$mode_proses" = "2" ]; then
                    echo -e -n "  ${BOLD}[?] Masukkan path file lengkap (drag & drop, 0=Kembali): ${RESET}"
                    local file_input
                    read -r -e file_input
                    if [ "$file_input" = "0" ]; then step=1; continue; fi
                    
                    file_input="${file_input//\'/}"
                    file_input="${file_input//\"/}"
                    file_input="${file_input#"${file_input%%[![:space:]]*}"}"
                    file_input="${file_input%"${file_input##*[![:space:]]}"}"

                    if [ ! -f "$file_input" ]; then
                        echo -e "  ${RED}${ICO_FAIL} File tidak ditemukan!${RESET}"
                        continue
                    fi
                    files_to_process+=("$file_input")
                fi
                step=3
            elif [ "$step" -eq 3 ]; then
                break
            fi
        done
    fi

    local total_files=${#files_to_process[@]}

    if [ "$total_files" -eq 0 ]; then
        echo -e "  ${RED}${ICO_FAIL} Tidak ada file media untuk diproses!${RESET}"
        return
    fi

    echo -e "  ${YELLOW}${ICO_ARROW} Total: $total_files file. Memulai AI Separation...${RESET}"
    echo -e "  ${GRAY}Peringatan: Pemrosesan AI memakan memori/CPU tinggi dan cukup lama per lagu.${RESET}\n"

    local current=0
    for file in "${files_to_process[@]}"; do
        ((current++))
        local percent=$((current * 100 / total_files))
        local base
        base=$(basename "$file")
        printf "  [%3d%%] %s ...\n" "$percent" "$base"

        local dir filename_noext ext_original
        dir=$(dirname "$file")
        filename_noext="${base%.*}"
        ext_original="${base##*.}"

        local tmp_out_dir="$dir/.demucs_tmp_$$"
        mkdir -p "$tmp_out_dir"

        echo -e -n "    ${CYAN}${ICO_ARROW} [AI Demucs] Membedah vokal & instrumen... "
        OMP_NUM_THREADS=2 "$demucs_bin" -n htdemucs --two-stems=vocals "$file" -o "$tmp_out_dir" >/dev/null 2>&1 &
        local fpid=$!
        local spin='-\|/'
        local i=0
        while kill -0 $fpid 2>/dev/null; do
            i=$(( (i+1) %4 ))
            printf "\b${spin:$i:1}"
            sleep 0.1
        done
        wait $fpid
        local f_exit=$?
        echo -e "\b "

        # Demucs menyimpan output dalam tmp_out_dir/htdemucs/<track_name>/no_vocals.wav
        local novocals_file
        novocals_file=$(find "$tmp_out_dir" -name "no_vocals.wav" -type f 2>/dev/null | head -n 1)
        local final_output="$dir/${filename_noext}_karaoke.$ext_original"

        if [ "$f_exit" -eq 0 ] && [ -n "$novocals_file" ] && [ -f "$novocals_file" ]; then
            echo -e -n "    ${CYAN}${ICO_ARROW} Mengonversi ke format asli... "
            
            # Deteksi bitrate asli file sumber
            local src_bitrate
            src_bitrate=$(ffprobe -v error -select_streams a:0 -show_entries stream=bit_rate -of default=nw=1:nk=1 "$file" 2>/dev/null)
            # Konversi dari bps ke kbps, fallback 128k jika gagal
            if [[ "$src_bitrate" =~ ^[0-9]+$ ]] && [ "$src_bitrate" -gt 0 ] 2>/dev/null; then
                src_bitrate="$(( src_bitrate / 1000 ))k"
            else
                src_bitrate="128k"
            fi

            # Cek apakah file asli punya video stream
            local has_video=0
            if ffprobe -v error -select_streams v:0 -show_entries stream=codec_type -of default=nw=1:nk=1 "$file" 2>/dev/null | grep -q "video"; then
                has_video=1
            fi

            local ext_lower
            ext_lower=$(echo "$ext_original" | tr '[:upper:]' '[:lower:]')

            if [ "$has_video" -eq 1 ]; then
                # Video: gabungkan video asli + audio instrumen
                ffmpeg -y -nostdin -v quiet -threads 2 -i "$file" -i "$novocals_file" -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a "$src_bitrate" "$final_output" &
            elif [ "$ext_lower" = "wav" ] || [ "$ext_lower" = "flac" ]; then
                # Lossless: salin langsung tanpa re-encode
                cp "$novocals_file" "$final_output" &
            elif [ "$ext_lower" = "mp3" ]; then
                ffmpeg -y -nostdin -v quiet -threads 2 -i "$novocals_file" -c:a libmp3lame -b:a "$src_bitrate" "$final_output" &
            else
                # Default (m4a/aac/ogg dll)
                ffmpeg -y -nostdin -v quiet -threads 2 -i "$novocals_file" -c:a aac -b:a "$src_bitrate" "$final_output" &
            fi
            
            local fpid2=$!
            local spin2='-\|/'
            local j=0
            while kill -0 $fpid2 2>/dev/null; do
                j=$(( (j+1) %4 ))
                printf "\b${spin2:$j:1}"
                sleep 0.1
            done
            wait $fpid2
            echo -e "\b "

            rm -rf "$tmp_out_dir"
            echo -e "    ${GREEN}${ICO_OK} SUKSES:${RESET} ${filename_noext}_karaoke.$ext_original"
        else
            rm -rf "$tmp_out_dir"
            echo -e "    ${RED}${ICO_FAIL} GAGAL PROSES:${RESET} Pastikan RAM cukup & file tidak corrupt."
        fi
        echo -e "  ──────────────────────────────────────────────────"
    done

    echo -e "  ${GREEN}${ICO_OK} 100% Selesai!${RESET}"
    _log "INFO" "Demucs vocal removal complete: $current files"
}

# ==========================================
# FUNGSI UTAMA: DOWNLOAD SPOTIFY
# ==========================================
download_spotdl() {
    print_header "DOWNLOAD DARI SPOTIFY"

    local link file
    local links=()
    local step=1

    if ! _check_dependency "spotdl" "true"; then
        return 1
    fi

    local original_dir
    original_dir=$(pwd)

    local folder_mode="" folder_manual_name="" format_pilih="" spotdl_ext=""
    local pilih_archive="" pilih_lirik="" lirik_args=() pilih_kompres="n"

    if [ -n "$AUTO_DOWNLOAD_URL" ]; then
        links=("$AUTO_DOWNLOAD_URL")
        folder_mode="3"
        spotdl_ext="m4a"
        pilih_archive="y"
        pilih_lirik="y"
        lirik_args=("--generate-lrc")
        pilih_kompres="n"
        AUTO_DOWNLOAD_URL=""
    else
        while true; do
            if [ "$step" -eq 1 ]; then
                links=()
                for i in {1..10}; do
                    echo -e -n "  ${BOLD}[?] Link/Judul ke-$i (Enter=Cukup, 0=Kembali ke Menu Utama): ${RESET}"
                    local input_link
                    read -r input_link
                    [ "$input_link" = "0" ] && return 0
                    [ -z "$input_link" ] && break

                    if [[ "$input_link" =~ (youtube\.com|youtu\.be|music\.youtube\.com) ]]; then
                        echo -e "  ${RED}${ICO_FAIL} Ini link YouTube/YouTube Music!${RESET}"
                        echo -e "  ${YELLOW}${ICO_ARROW} Gunakan menu ${BOLD}[3] SEDOT YOUTUBE${RESET}${YELLOW} untuk link ini.${RESET}"
                        echo -e "  ${GRAY}  spotdl hanya menerima link Spotify atau judul lagu.${RESET}"
                        continue
                    fi
                    links+=("$input_link")
                done
                if [ ${#links[@]} -eq 0 ]; then
                    echo -e "  ${RED}${ICO_FAIL} Input kosong! Batal.${RESET}"
                    return 0
                fi
                step=2
            elif [ "$step" -eq 2 ]; then
                echo -e "  ${CYAN}${ICO_ARROW} MANAJEMEN FOLDER OUTPUT${RESET}"
                echo "    1. Auto-Folder per Artis Utama"
                echo "    2. Bikin 1 Folder Manual"
                echo "    3. Tanpa folder baru"
                echo "    0. ${ICO_FAIL} KEMBALI"
                echo -e -n "  ${BOLD}[?] Pilih Mode [0-3]: ${RESET}"
                read -r -n 1 folder_mode
                echo ""
                if [ "$folder_mode" = "0" ]; then step=1; continue; fi
                if [ "$folder_mode" = "2" ]; then step=3; else step=4; fi
            elif [ "$step" -eq 3 ]; then
                echo -e -n "  ${BOLD}[?] Nama folder (0=Kembali): ${RESET}"
                local nama_folder_input
                read -r nama_folder_input
                if [ "$nama_folder_input" = "0" ]; then step=2; continue; fi
                if [ -z "$nama_folder_input" ]; then
                    echo -e "  ${YELLOW}${ICO_WARN} Nama folder kosong! Otomatis download ke direktori saat ini.${RESET}"
                    folder_manual_name=""
                else
                    folder_manual_name="${nama_folder_input// /-}"
                fi
                step=4
            elif [ "$step" -eq 4 ]; then
                echo -e "  ${CYAN}${ICO_ARROW} FORMAT OUTPUT${RESET}"
                echo "    1. M4A  (Default, paling kompatibel, kualitas bagus)"
                echo "    2. MP3  (Universal, didukung semua perangkat lama)"
                echo "    3. FLAC (Lossless, kualitas tertinggi, ukuran besar)"
                echo "    4. WAV  (Uncompressed, untuk studio/editing)"
                echo "    5. OPUS (Modern, ukuran kecil, suara jernih)"
                echo "    6. OGG  (Open source, bagus untuk streaming/game)"
                echo "    0. KEMBALI"
                echo -e -n "  ${BOLD}[?] Pilihan [0-6]: ${RESET}"
                read -r -n 1 format_pilih
                echo ""
                if [ "$format_pilih" = "0" ]; then
                    if [ "$folder_mode" = "2" ]; then step=3; else step=2; fi
                    continue
                fi
                case $format_pilih in
                    2) spotdl_ext="mp3" ;;
                    3) spotdl_ext="flac" ;;
                    4) spotdl_ext="wav" ;;
                    5) spotdl_ext="opus" ;;
                    6) spotdl_ext="ogg" ;;
                    *) spotdl_ext="m4a" ;;
                esac
                step=5
            elif [ "$step" -eq 5 ]; then
                echo -e -n "  ${BOLD}[?] Gunakan Archive System (Skip lagu yg sudah didownload)? (y/n/0=Kembali): ${RESET}"
                read -r -n 1 pilih_archive
                echo ""
                if [ "$pilih_archive" = "0" ]; then step=4; continue; fi
                step=6
            elif [ "$step" -eq 6 ]; then
                echo -e -n "  ${BOLD}[?] Sedot lirik murni (.lrc)? (y/n/0=Kembali): ${RESET}"
                read -r -n 1 pilih_lirik
                echo ""
                if [ "$pilih_lirik" = "0" ]; then step=5; continue; fi
                lirik_args=()
                [[ "$pilih_lirik" =~ ^[Yy]$ ]] && lirik_args+=("--generate-lrc")

                if [[ "$spotdl_ext" == "m4a" || "$spotdl_ext" == "mp3" ]]; then
                    step=7
                else
                    step=8
                fi
            elif [ "$step" -eq 7 ]; then
                echo -e -n "  ${BOLD}[?] Kompres otomatis 128kbps AAC? (y/n/0=Kembali): ${RESET}"
                read -r -n 1 pilih_kompres
                echo ""
                if [ "$pilih_kompres" = "0" ]; then step=6; continue; fi
                step=8
            elif [ "$step" -eq 8 ]; then
                break
            fi
        done
    fi

    if [ -n "$folder_manual_name" ]; then
        mkdir -p "$folder_manual_name"
    fi

    echo -e "  ${CYAN}${ICO_ARROW} Mengeksekusi ${#links[@]} antrean Spotify...${RESET}"
    _log "INFO" "Spotify download started: ${#links[@]} links"

    # PROSES SEQUENTIAL PER-LINK
    for link in "${links[@]}"; do
        echo -e "  ${GRAY}──────────────────────────────────────────────────${RESET}"
        echo -e "  ${YELLOW}${ICO_ARROW} Memproses:${RESET} $link"

        # 1. Tentukan output template berdasarkan folder mode
        local output_tpl
        local auto_folder_name=""
        case "$folder_mode" in
            1)
                # Auto-Folder per Artis Utama: ambil dari metadata track pertama
                echo -e "  ${CYAN}${ICO_ARROW} Mendeteksi artis utama...${RESET}"
                local file_tmp="meta_temp_$$.spotdl"
                spotdl save "$link" --save-file "$file_tmp" >/dev/null 2>&1
                local artis_raw=""
                if [ -f "$file_tmp" ]; then
                    if command -v python3 >/dev/null 2>&1; then
                        artis_raw=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[0]["artist"])' "$file_tmp" 2>/dev/null)
                    fi
                    rm -f "$file_tmp"
                fi
                if [ -n "$artis_raw" ]; then
                    if command -v python3 >/dev/null 2>&1; then
                        auto_folder_name=$(python3 -c "import sys; print('-'.join(w.capitalize() for w in sys.argv[1].split()))" "$artis_raw")
                    else
                        auto_folder_name="${artis_raw// /-}"
                    fi
                fi
                [ -z "$auto_folder_name" ] && auto_folder_name="Unknown-Artist"
                mkdir -p "$auto_folder_name"
                output_tpl="${auto_folder_name}/{artists} - {title}"
                echo -e "  ${GREEN}${ICO_OK} Auto-Folder:${RESET} $auto_folder_name/"
                ;;
            2)
                if [ -n "$folder_manual_name" ]; then
                    output_tpl="${folder_manual_name}/{artists} - {title}"
                else
                    output_tpl="{artists} - {title}"
                fi
                ;;
            *)
                output_tpl="{artists} - {title}"
                ;;
        esac

        # 2. Download — spotdl handle playlist secara native
        echo -e "  ${CYAN}${ICO_ARROW} Mendownload Media...${RESET}"
        local dl_ok=true
        local archive_arg=()
        if [[ "$pilih_archive" =~ ^[Yy]$ ]]; then
            archive_arg=("--archive" ".spotdl_archive.txt")
        fi

        if ! spotdl download "$link" \
            --audio youtube \
            --format "$spotdl_ext" \
            --output "$output_tpl" \
            "${archive_arg[@]}" \
            "${lirik_args[@]}"; then
            echo -e "  ${YELLOW}${ICO_WARN} Peringatan: Ada file yang gagal diunduh! Melanjutkan proses file yang berhasil...${RESET}"
            _log "WARN" "spotdl reported errors for: $link"
        fi

        # Tentukan area scan
        local scan_dir="."
        if [ "$folder_mode" = "1" ] && [ -n "$auto_folder_name" ]; then
            scan_dir="./$auto_folder_name"
        elif [ "$folder_mode" = "2" ] && [ -n "$folder_manual_name" ]; then
            scan_dir="./$folder_manual_name"
        fi

        # 3. Kompres
        if [[ "$pilih_kompres" =~ ^[Yy]$ ]]; then
            echo -e "  ${CYAN}${ICO_ARROW} AUTO COMPRESS AUDIO${RESET}"
            while IFS= read -r file; do
                _kompres_audio_file "$file"
            done < <(find "$scan_dir" -type f -iname "*.$spotdl_ext" ! -name "*_temp.*" -mmin -60 2>/dev/null)
        fi

        # 4. Bersihkan nama
        echo -e "  ${CYAN}${ICO_ARROW} AUTO CLEAN NAMA FILE${RESET}"
        while IFS= read -r file; do
            _bersih_satu_nama "$file"
        done < <(find "$scan_dir" -type f \( -iname "*.$spotdl_ext" -o -iname "*.m4a" -o -iname "*.lrc" \) -mmin -60 2>/dev/null)
    done

    _log "INFO" "Spotify download batch complete"
}

# ==========================================
# FUNGSI UTAMA: DOWNLOAD YOUTUBE
# ==========================================
download_ytdlp() {
    print_header "SEDOT AUDIO (YOUTUBE/TIKTOK/IG/DLL)"

    local link file
    local links=()
    local step=1

    if ! _check_dependency "yt-dlp" "true"; then
        return 1
    fi

    local original_dir
    original_dir=$(pwd)

    local folder_mode="" folder_manual_name="" format_pilih="" yt_ext=""
    local pilih_archive="" pilih_chapter="" pilih_lirik="" pilih_kompres="n"
    if [ -n "$AUTO_DOWNLOAD_URL" ]; then
        links=("$AUTO_DOWNLOAD_URL")
        AUTO_DOWNLOAD_URL=""
        folder_mode="3"
        format_pilih="1"
        yt_ext="m4a"
        pilih_archive="y"
        pilih_lirik="n"
        pilih_kompres="n"
        pilih_chapter="n"
    else
        while true; do
            if [ "$step" -eq 1 ]; then
                links=()
                echo -e "  ${CYAN}${ICO_ARROW} Masukkan link YouTube/YT Music (Maks 10 link)${RESET}"
                for i in {1..10}; do
                    echo -e -n "  ${BOLD}[?] Link ke-$i (Enter=Cukup, 0=Kembali ke Menu Utama): ${RESET}"
                    local input_link
                    read -r input_link
                    [ "$input_link" = "0" ] && return 0
                    [ -z "$input_link" ] && break

                    if [[ "$input_link" =~ open\.spotify\.com ]]; then
                        echo -e "  ${RED}${ICO_FAIL} Ini link Spotify!${RESET}"
                        echo -e "  ${YELLOW}${ICO_ARROW} Gunakan menu ${BOLD}[2] SEDOT SPOTIFY${RESET}${YELLOW} untuk link ini.${RESET}"
                        echo -e "  ${GRAY}  Gunakan menu ini untuk link YouTube, TikTok, IG, FB, dll.${RESET}"
                        continue
                    fi
                    links+=("$input_link")
                done
                if [ ${#links[@]} -eq 0 ]; then
                    echo -e "  ${RED}${ICO_FAIL} Input kosong! Batal.${RESET}"
                    return 0
                fi
                step=2
            elif [ "$step" -eq 2 ]; then
                echo -e "  ${CYAN}${ICO_ARROW} MANAJEMEN FOLDER OUTPUT${RESET}"
                echo "    1. Auto-Folder per Artis/Channel Utama"
                echo "    2. Bikin 1 Folder Manual"
                echo "    3. Tanpa folder baru"
                echo "    0. ${ICO_FAIL} KEMBALI"
                echo -e -n "  ${BOLD}[?] Pilih Mode [0-3]: ${RESET}"
                read -r -n 1 folder_mode
                echo ""
                if [ "$folder_mode" = "0" ]; then step=1; continue; fi
                if [ "$folder_mode" = "2" ]; then step=3; else step=4; fi
            elif [ "$step" -eq 3 ]; then
                echo -e -n "  ${BOLD}[?] Nama folder (0=Kembali): ${RESET}"
                local nama_folder_input
                read -r nama_folder_input
                if [ "$nama_folder_input" = "0" ]; then step=2; continue; fi
                if [ -z "$nama_folder_input" ]; then
                    echo -e "  ${YELLOW}${ICO_WARN} Nama folder kosong! Otomatis download ke direktori saat ini.${RESET}"
                    folder_manual_name=""
                else
                    folder_manual_name="${nama_folder_input// /-}"
                fi
                step=4
            elif [ "$step" -eq 4 ]; then
                echo -e "  ${CYAN}${ICO_ARROW} FORMAT OUTPUT${RESET}"
                echo "    1. M4A  (Default, paling kompatibel, kualitas bagus)"
                echo "    2. MP3  (Universal, didukung semua perangkat lama)"
                echo "    3. FLAC (Lossless, kualitas tertinggi, ukuran besar)"
                echo "    4. WAV  (Uncompressed, untuk studio/editing)"
                echo "    5. OPUS (Modern, ukuran kecil, suara jernih)"
                echo "    6. OGG  (Open source, bagus untuk streaming/game)"
                echo "    0. KEMBALI"
                echo -e -n "  ${BOLD}[?] Pilihan [0-6]: ${RESET}"
                read -r -n 1 format_pilih
                echo ""
                if [ "$format_pilih" = "0" ]; then
                    if [ "$folder_mode" = "2" ]; then step=3; else step=2; fi
                    continue
                fi
                case $format_pilih in
                    1) yt_ext="m4a" ;;
                    2) yt_ext="mp3" ;;
                    3) yt_ext="flac" ;;
                    4) yt_ext="wav" ;;
                    5) yt_ext="opus" ;;
                    6) yt_ext="ogg" ;;
                    *) echo -e "  ${RED}${ICO_FAIL} Pilihan tidak valid!${RESET}"; continue ;;
                esac
                step=5
            elif [ "$step" -eq 5 ]; then
                echo -e -n "  ${BOLD}[?] Gunakan Archive System (Skip lagu yg sudah didownload)? (y/n/0=Kembali): ${RESET}"
                read -r -n 1 pilih_archive
                echo ""
                if [ "$pilih_archive" = "0" ]; then step=4; continue; fi
                step=6
            elif [ "$step" -eq 6 ]; then
                echo -e -n "  ${BOLD}[?] Potong audio berdasarkan Chapter (jika ada)? (y/n/0=Kembali): ${RESET}"
                read -r -n 1 pilih_chapter
                echo ""
                if [ "$pilih_chapter" = "0" ]; then step=5; continue; fi
                step=7
            elif [ "$step" -eq 7 ]; then
            echo -e -n "  ${BOLD}[?] Auto-lirik via SyncedLyrics? (y/n/0=Kembali): ${RESET}"
            read -r -n 1 pilih_lirik
            echo ""
            if [ "$pilih_lirik" = "0" ]; then step=6; continue; fi
            if [[ "$yt_ext" == "m4a" || "$yt_ext" == "mp3" ]]; then step=8; else step=9; fi
        elif [ "$step" -eq 8 ]; then
            echo -e -n "  ${BOLD}[?] Kompres otomatis 128kbps AAC? (y/n/0=Kembali): ${RESET}"
            read -r -n 1 pilih_kompres
            echo ""
            if [ "$pilih_kompres" = "0" ]; then step=7; continue; fi
            step=9
        elif [ "$step" -eq 9 ]; then
            break
        fi
    done
    fi

    if [ -n "$folder_manual_name" ]; then
        mkdir -p "$folder_manual_name"
    fi

    echo -e "  ${CYAN}${ICO_ARROW} Mengeksekusi ${#links[@]} antrean YouTube...${RESET}"
    _log "INFO" "YouTube download started: ${#links[@]} links"

    # PROSES SEQUENTIAL PER-LINK
    for link in "${links[@]}"; do
        echo -e "  ${GRAY}──────────────────────────────────────────────────${RESET}"
        echo -e "  ${YELLOW}${ICO_ARROW} Memproses:${RESET} $link"

        # 1. Tentukan output template berdasarkan folder mode
        local output_template
        local auto_folder_name=""
        case "$folder_mode" in
            1)
                # Auto-Folder per Artis/Channel: ambil dari video pertama di playlist
                echo -e "  ${CYAN}${ICO_ARROW} Mendeteksi channel/artis utama...${RESET}"
                local channel_raw
                channel_raw=$(yt-dlp --no-warnings -O "%(channel,uploader,artist)s" --playlist-items 1 "$link" 2>/dev/null | head -n 1)
                if [ -n "$channel_raw" ]; then
                    if command -v python3 >/dev/null 2>&1; then
                        auto_folder_name=$(python3 -c "import sys; print('-'.join(w.capitalize() for w in sys.argv[1].split()))" "$channel_raw")
                    else
                        auto_folder_name="${channel_raw// /-}"
                    fi
                fi
                [ -z "$auto_folder_name" ] && auto_folder_name="Unknown-Channel"
                mkdir -p "$auto_folder_name"
                output_template="${auto_folder_name}/%(artist,uploader)s - %(title)s.%(ext)s"
                echo -e "  ${GREEN}${ICO_OK} Auto-Folder:${RESET} $auto_folder_name/"
                ;;
            2)
                if [ -n "$folder_manual_name" ]; then
                    output_template="${folder_manual_name}/%(artist,uploader)s - %(title)s.%(ext)s"
                else
                    output_template="%(artist,uploader)s - %(title)s.%(ext)s"
                fi
                ;;
            *)
                output_template="%(artist,uploader)s - %(title)s.%(ext)s"
                ;;
        esac

        # 2. Download — yt-dlp handle playlist secara native
        echo -e "  ${CYAN}${ICO_ARROW} Mendownload Media...${RESET}"
        local dl_status=0
        local archive_arg=()
        if [[ "$pilih_archive" =~ ^[Yy]$ ]]; then
            archive_arg=("--download-archive" ".ytdlp_archive.txt")
        fi
        
        local chapter_arg=()
        if [[ "$pilih_chapter" =~ ^[Yy]$ ]]; then
            chapter_arg=("--split-chapters")
        fi

        case $format_pilih in
            1) yt-dlp --no-warnings --no-mtime -f "ba[ext=m4a]/ba" --embed-metadata --embed-thumbnail -o "$output_template" "${archive_arg[@]}" "${chapter_arg[@]}" "$link" || dl_status=$? ;;
            2) yt-dlp --no-warnings --no-mtime -x --audio-format mp3 --embed-metadata --embed-thumbnail -o "$output_template" "${archive_arg[@]}" "${chapter_arg[@]}" "$link" || dl_status=$? ;;
            3) yt-dlp --no-warnings --no-mtime -x --audio-format flac --embed-metadata --embed-thumbnail -o "$output_template" "${archive_arg[@]}" "${chapter_arg[@]}" "$link" || dl_status=$? ;;
            4) yt-dlp --no-warnings --no-mtime -x --audio-format wav -o "$output_template" "${archive_arg[@]}" "${chapter_arg[@]}" "$link" || dl_status=$? ;;
            5) yt-dlp --no-warnings --no-mtime -x --audio-format opus --embed-metadata --embed-thumbnail -o "$output_template" "${archive_arg[@]}" "${chapter_arg[@]}" "$link" || dl_status=$? ;;
            6) yt-dlp --no-warnings --no-mtime -x --audio-format ogg --embed-metadata --embed-thumbnail -o "$output_template" "${archive_arg[@]}" "${chapter_arg[@]}" "$link" || dl_status=$? ;;
        esac

        if [ "$dl_status" -ne 0 ]; then
            echo -e "  ${YELLOW}${ICO_WARN} Peringatan: Ada file yang gagal diunduh! Melanjutkan proses file yang berhasil...${RESET}"
            _log "WARN" "yt-dlp reported errors for: $link (exit: $dl_status)"
        fi

        # Tentukan area scan
        local scan_dir="."
        if [ "$folder_mode" = "1" ] && [ -n "$auto_folder_name" ]; then
            scan_dir="./$auto_folder_name"
        elif [ "$folder_mode" = "2" ] && [ -n "$folder_manual_name" ]; then
            scan_dir="./$folder_manual_name"
        fi

        # 3. Cari Lirik
        if [[ "$pilih_lirik" =~ ^[Yy]$ && "$yt_ext" != "mp4" ]]; then
            echo -e "  ${CYAN}${ICO_ARROW} MENCARI LIRIK${RESET}"
            if _check_dependency "syncedlyrics"; then
                while IFS= read -r file; do
                    local fname fname_noext lrc_file query
                    fname=$(basename "$file")
                    fname_noext="${fname%.*}"
                    lrc_file="$(dirname "$file")/$fname_noext.lrc"

                    if [ ! -f "$lrc_file" ]; then
                        query=$(echo "$fname_noext" | sed -E 's/\([^)]*\)//g' | sed -E 's/\[[^]]*\]//g' | sed 's/-/ /g' | sed 's/  */ /g')
                        echo -e "    ${YELLOW}Mencari lirik untuk:${RESET} $query"
                        syncedlyrics "$query" -o "$lrc_file" >/dev/null 2>&1
                    fi
                done < <(find "$scan_dir" -type f -iname "*.$yt_ext" -mmin -60 2>/dev/null)
            else
                echo -e "    ${YELLOW}syncedlyrics tidak terpasang, skip lirik.${RESET}"
            fi
        fi

        # 4. Kompres
        if [[ "$pilih_kompres" =~ ^[Yy]$ && "$yt_ext" != "mp4" ]]; then
            echo -e "  ${CYAN}${ICO_ARROW} AUTO COMPRESS AUDIO${RESET}"
            while IFS= read -r file; do
                _kompres_audio_file "$file"
            done < <(find "$scan_dir" -type f -iname "*.$yt_ext" ! -name "*_temp.*" -mmin -60 2>/dev/null)
        fi

        # 5. Bersihkan Nama
        echo -e "  ${CYAN}${ICO_ARROW} AUTO CLEAN NAMA FILE${RESET}"
        while IFS= read -r file; do
            _bersih_satu_nama "$file"
        done < <(find "$scan_dir" -type f \( -iname "*.$yt_ext" -o -iname "*.m4a" -o -iname "*.lrc" \) -mmin -60 2>/dev/null)
    done

    _log "INFO" "YouTube download batch complete"
}

# ==========================================
# FUNGSI UTAMA: SEDOT VIDEO
# ==========================================
download_video() {
    print_header "SEDOT VIDEO (YOUTUBE/TIKTOK/IG/DLL)"

    local link file i
    local links=()
    local step=1

    if ! _check_dependency "yt-dlp" "true"; then
        return 1
    fi

    local original_dir
    original_dir=$(pwd)

    local kualitas_pilih="" format_pilih="" merge_format="" ext_video=""
    local codec_pilih="" sub_pilih="" sub_langs="id,en" sub_args=()
    local folder_mode="" folder_manual_name="" pilih_archive="" pilih_chapter=""

    if [ -n "$AUTO_DOWNLOAD_URL" ]; then
        links=("$AUTO_DOWNLOAD_URL")
        AUTO_DOWNLOAD_URL=""
        kualitas_pilih="1"
        format_pilih="1"
        merge_format="mp4"
        ext_video="mp4"
        codec_pilih="3"
        sub_pilih="n"
        folder_mode="3"
        pilih_archive="y"
        pilih_chapter="n"
    else
        while true; do
            if [ "$step" -eq 1 ]; then
                links=()
                echo -e "  ${CYAN}${ICO_ARROW} Masukkan link video/playlist (Maks 10 link)${RESET}"
                for i in {1..10}; do
                    echo -e -n "  ${BOLD}[?] Link ke-$i (Enter=Cukup, 0=Kembali ke Menu Utama): ${RESET}"
                    local input_link
                    read -r input_link
                    [ "$input_link" = "0" ] && { cd "$original_dir" || true; return 0; }
                    [ -z "$input_link" ] && break
                    links+=("$input_link")
                done
                if [ ${#links[@]} -eq 0 ]; then
                    echo -e "  ${YELLOW}${ICO_ARROW} Tidak ada link. Dibatalkan!${RESET}"
                    cd "$original_dir" || true
                    return 0
                fi
                step=2
            elif [ "$step" -eq 2 ]; then
                echo -e "  ${CYAN}${ICO_ARROW} KUALITAS VIDEO${RESET}"
                echo "    1. Best Quality (Up to 4K/1080p)"
                echo "    2. 1080p"
                echo "    3. 720p"
                echo "    4. 480p"
                echo "    5. 360p"
                echo "    0. KEMBALI"
                echo -e -n "  ${BOLD}[?] Pilihan [0-5]: ${RESET}"
                read -r -n 1 kualitas_pilih
                echo ""
                if [ "$kualitas_pilih" = "0" ]; then step=1; continue; fi
                step=3
            elif [ "$step" -eq 3 ]; then
                echo -e "  ${CYAN}${ICO_ARROW} FORMAT VIDEO OUTPUT${RESET}"
                echo "    1. MP4  (Paling Kompatibel)"
                echo "    2. MKV  (Multi-Track, Multi-Sub)"
                echo "    3. WebM (Ringan, VP9/AV1)"
                echo "    4. AVI  (Legacy / Kompatibel Lama)"
                echo "    5. MOV  (Apple / Final Cut Pro)"
                echo "    6. TS   (MPEG Transport Stream)"
                echo "    0. KEMBALI"
                echo -e -n "  ${BOLD}[?] Pilih Format [0-6]: ${RESET}"
                read -r -n 1 format_pilih
                echo ""
                if [ "$format_pilih" = "0" ]; then step=2; continue; fi
            case "$format_pilih" in
                2) merge_format="mkv";  ext_video="mkv"  ;;
                3) merge_format="webm"; ext_video="webm" ;;
                4) merge_format="avi";  ext_video="avi"  ;;
                5) merge_format="mov";  ext_video="mov"  ;;
                6) merge_format="mpegts"; ext_video="ts"  ;;
                *) merge_format="mp4";  ext_video="mp4"  ;;
            esac
            step=4
        elif [ "$step" -eq 4 ]; then
            echo -e "  ${CYAN}${ICO_ARROW} CODEC VIDEO${RESET}"
            echo "    1. Copy     (Tanpa Re-encode, Cepat)"
            echo "    2. x264/H264 (Kompatibel, Cepat)"
            echo "    3. x265/HEVC (Ukuran Kecil, Lambat)"
            echo "    0. KEMBALI"
            echo -e -n "  ${BOLD}[?] Pilih Codec [0-3]: ${RESET}"
            read -r -n 1 codec_pilih
            echo ""
            if [ "$codec_pilih" = "0" ]; then step=3; continue; fi
            step=5
        elif [ "$step" -eq 5 ]; then
            echo -e "  ${CYAN}${ICO_ARROW} SUBTITLE${RESET}"
            echo "    1. Embed Subtitle ke Video (jika ada)"
            echo "    2. Download Subtitle Terpisah (.srt)"
            echo "    3. Embed + Terpisah"
            echo "    4. Tanpa Subtitle"
            echo "    0. KEMBALI"
            echo -e -n "  ${BOLD}[?] Pilih Mode Subtitle [0-4]: ${RESET}"
            read -r -n 1 sub_pilih
            echo ""
            if [ "$sub_pilih" = "0" ]; then step=4; continue; fi
            case "$sub_pilih" in
                1) sub_args=("--embed-subs" "--write-subs" "--sub-langs" "$sub_langs") ;;
                2) sub_args=("--write-subs" "--sub-langs" "$sub_langs" "--convert-subs" "srt") ;;
                3) sub_args=("--embed-subs" "--write-subs" "--sub-langs" "$sub_langs" "--convert-subs" "srt") ;;
                *) sub_args=() ;;
            esac
            step=6
        elif [ "$step" -eq 6 ]; then
            echo -e "  ${CYAN}${ICO_ARROW} MANAJEMEN FOLDER OUTPUT${RESET}"
            echo "    1. Auto-Folder per Channel/Playlist"
            echo "    2. Bikin 1 Folder Manual"
            echo "    3. Tanpa folder baru"
            echo "    0. KEMBALI"
            echo -e -n "  ${BOLD}[?] Pilih Mode [0-3]: ${RESET}"
            read -r -n 1 folder_mode
            echo ""
            if [ "$folder_mode" = "0" ]; then step=5; continue; fi
            if [ "$folder_mode" = "2" ]; then step=7; else step=8; fi
        elif [ "$step" -eq 7 ]; then
            echo -e -n "  ${BOLD}[?] Nama folder (0=Kembali): ${RESET}"
            local nama_folder_input
            read -r nama_folder_input
            if [ "$nama_folder_input" = "0" ]; then step=6; continue; fi
            if [ -z "$nama_folder_input" ]; then
                echo -e "  ${YELLOW}${ICO_WARN} Nama folder kosong! Otomatis download ke direktori saat ini.${RESET}"
                folder_manual_name=""
            else
                folder_manual_name="${nama_folder_input// /-}"
            fi
            step=8
        elif [ "$step" -eq 8 ]; then
            echo -e -n "  ${BOLD}[?] Gunakan Archive System (Skip video yg sudah didownload)? (y/n/0=Kembali): ${RESET}"
            read -r -n 1 pilih_archive
            echo ""
            if [ "$pilih_archive" = "0" ]; then
                if [ "$folder_mode" = "2" ]; then step=7; else step=6; fi
                continue
            fi
            step=9
        elif [ "$step" -eq 9 ]; then
            echo -e -n "  ${BOLD}[?] Potong video berdasarkan Chapter (jika ada)? (y/n/0=Kembali): ${RESET}"
            read -r -n 1 pilih_chapter
            echo ""
            if [ "$pilih_chapter" = "0" ]; then step=8; continue; fi
            step=10
        elif [ "$step" -eq 10 ]; then
            break
        fi
    done
    fi

    if [ -n "$folder_manual_name" ]; then
        mkdir -p "$folder_manual_name"
    fi


    echo -e "  ${GREEN}${ICO_OK} Mengeksekusi ${#links[@]} antrean Video...${RESET}"

    for link in "${links[@]}"; do
        echo -e "  ${GRAY}──────────────────────────────────────────────────${RESET}"
        echo -e "  ${YELLOW}${ICO_ARROW} Memproses:${RESET} $link"

        local output_template
        local auto_folder_name=""
        case "$folder_mode" in
            1)
                echo -e "  ${CYAN}${ICO_ARROW} Mendeteksi channel utama...${RESET}"
                local channel_raw
                channel_raw=$(yt-dlp --no-warnings -O "%(channel,uploader)s" --playlist-items 1 "$link" 2>/dev/null | head -n 1)
                if [ -n "$channel_raw" ]; then
                    if command -v python3 >/dev/null 2>&1; then
                        auto_folder_name=$(python3 -c "import sys; print('-'.join(w.capitalize() for w in sys.argv[1].split()))" "$channel_raw")
                    else
                        auto_folder_name="${channel_raw// /-}"
                    fi
                fi
                [ -z "$auto_folder_name" ] && auto_folder_name="Unknown-Channel"
                mkdir -p "$auto_folder_name"
                output_template="${auto_folder_name}/%(title)s [%(id)s].%(ext)s"
                echo -e "  ${GREEN}${ICO_OK} Auto-Folder:${RESET} $auto_folder_name/"
                ;;
            2)
                if [ -n "$folder_manual_name" ]; then
                    output_template="${folder_manual_name}/%(title)s [%(id)s].%(ext)s"
                else
                    output_template="%(title)s [%(id)s].%(ext)s"
                fi
                ;;
            *)
                output_template="%(title)s [%(id)s].%(ext)s"
                ;;
        esac

        echo -e "  ${CYAN}${ICO_ARROW} Mendownload Video...${RESET}"
        local dl_status=0
        local archive_arg=()
        if [[ "$pilih_archive" =~ ^[Yy]$ ]]; then
            archive_arg=("--download-archive" ".ytdlp_video_archive.txt")
        fi
        
        local chapter_arg=()
        if [[ "$pilih_chapter" =~ ^[Yy]$ ]]; then
            chapter_arg=("--split-chapters")
        fi

        local format_str
        case $kualitas_pilih in
            1) format_str="bv*+ba/b" ;;
            2) format_str="bv*[height<=1080]+ba/b[height<=1080]" ;;
            3) format_str="bv*[height<=720]+ba/b[height<=720]" ;;
            4) format_str="bv*[height<=480]+ba/b[height<=480]" ;;
            5) format_str="bv*[height<=360]+ba/b[height<=360]" ;;
            *) format_str="bv*[height<=1080]+ba/b[height<=1080]" ;;
        esac

        yt-dlp --no-warnings --no-mtime -f "$format_str" --embed-metadata --merge-output-format "$merge_format" -o "$output_template" "${archive_arg[@]}" "${chapter_arg[@]}" "${sub_args[@]}" "$link" || dl_status=$?

        if [ "$dl_status" -ne 0 ]; then
            echo -e "  ${YELLOW}${ICO_WARN} Peringatan: Ada file yang gagal diunduh! Melanjutkan proses file yang berhasil...${RESET}"
            _log "WARN" "yt-dlp video reported errors: $link (exit: $dl_status)"
        fi

        local scan_dir="."
        if [ "$folder_mode" = "1" ] && [ -n "$auto_folder_name" ]; then
            scan_dir="./$auto_folder_name"
        elif [ "$folder_mode" = "2" ] && [ -n "$folder_manual_name" ]; then
            scan_dir="./$folder_manual_name"
        fi
        
        # 4. Re-encode Video — jika codec bukan "copy"
        if [[ "$codec_pilih" =~ ^[23]$ ]]; then
            local vcodec
            [ "$codec_pilih" = "2" ] && vcodec="libx264" || vcodec="libx265"
            echo -e "  ${CYAN}${ICO_ARROW} RE-ENCODE VIDEO ($vcodec)${RESET}"
            while IFS= read -r file; do
                local tmpfile="${file%.*}_temp.${file##*.}"
                echo -e -n "    ${CYAN}${ICO_ARROW} Encoding: $(basename "$file")... "
                ffmpeg -y -nostdin -v quiet -threads 2 -i "$file" -c:v "$vcodec" -crf 23 -preset fast -c:a copy "$tmpfile" &
                local epid=$!
                local spin='-\|/'
                local si=0
                while kill -0 $epid 2>/dev/null; do
                    si=$(( (si+1) %4 ))
                    printf "\b${spin:$si:1}"
                    sleep 0.1
                done
                wait $epid
                if [ $? -eq 0 ] && [ -f "$tmpfile" ]; then
                    mv "$tmpfile" "$file"
                    echo -e "\b${GREEN}${ICO_OK}${RESET}"
                else
                    rm -f "$tmpfile"
                    echo -e "\b${RED}${ICO_FAIL}${RESET}"
                fi
            done < <(find "$scan_dir" -type f -iname "*.$ext_video" ! -name "*_temp.*" -mmin -60 2>/dev/null)
        fi

        # 5. Bersihkan Nama
        echo -e "  ${CYAN}${ICO_ARROW} AUTO CLEAN NAMA FILE${RESET}"
        while IFS= read -r file; do
            _bersih_satu_nama "$file"
        done < <(find "$scan_dir" -type f -iname "*.$ext_video" -mmin -60 2>/dev/null)
    done

    cd "$original_dir" || true
    _log "INFO" "Video download batch complete"
}

# ==========================================
# FUNGSI UTAMA: AUTO SYNC LIRIK
# ==========================================
auto_sync_lirik() {
    print_header "AUTO SYNC LIRIK (SCAN MISSING .LRC)"

    if ! _check_dependency "syncedlyrics" "true"; then
        return 1
    fi

    echo -e "  ${GRAY}Fitur ini akan mengecek lagu yang belum punya file lirik,${RESET}"
    echo -e "  ${GRAY}lalu mengunduh liriknya secara otomatis.${RESET}"
    echo ""

    local step=1
    local target_dir=""
    local total_audio=0
    local total_missing=0

    if [ -n "$AUTO_SYNC_LIRIK" ]; then
        target_dir="${TARGET_DIR:-$(pwd)}"
        AUTO_SYNC_LIRIK=""
        total_audio=$(find "$target_dir" -type f \( -iname "*.m4a" -o -iname "*.mp3" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.webm" \) 2>/dev/null | wc -l)
        total_missing=0
        while IFS= read -r af; do
            local fn="${af%.*}.lrc"
            [ ! -f "$fn" ] && ((total_missing++))
        done < <(find "$target_dir" -type f \( -iname "*.m4a" -o -iname "*.mp3" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.webm" \) 2>/dev/null)
        if [ "$total_missing" -eq 0 ]; then
            return 0
        fi
    else
        while true; do
        if [ "$step" -eq 1 ]; then
            if ! pilih_folder_target; then return 0; fi
            target_dir="$TARGET_DIR"

            # Hitung jumlah file dulu sebelum konfirmasi
            total_audio=$(find "$target_dir" -type f \( -iname "*.m4a" -o -iname "*.mp3" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.webm" \) 2>/dev/null | wc -l)
            total_missing=0
            while IFS= read -r af; do
                local fn="${af%.*}.lrc"
                [ ! -f "$fn" ] && ((total_missing++))
            done < <(find "$target_dir" -type f \( -iname "*.m4a" -o -iname "*.mp3" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.webm" \) 2>/dev/null)

            echo -e "  ${CYAN}${ICO_ARROW} Direktori target: ${YELLOW}$target_dir${RESET}"
            echo -e "  ${WHITE}Total file audio :${RESET} $total_audio"
            echo -e "  ${WHITE}Belum punya lirik:${RESET} $total_missing"
            echo ""

            if [ "$total_missing" -eq 0 ]; then
                echo -e "  ${GREEN}${ICO_OK} Semua lagu sudah punya lirik!${RESET}"
                return 0
            fi
            step=2
        elif [ "$step" -eq 2 ]; then
            echo -e -n "  ${BOLD}[?] Lanjut download lirik untuk $total_missing lagu? (y/n/0=Kembali): ${RESET}"
            local konfirmasi_sync
            read -r -n 1 konfirmasi_sync
            echo ""

            if [ "$konfirmasi_sync" = "0" ]; then
                step=1; continue
            fi
            if [[ ! "$konfirmasi_sync" =~ ^[Yy]$ ]]; then
                echo -e "  ${YELLOW}${ICO_ARROW} Dibatalkan!${RESET}"
                return 0
            fi
            step=3
        elif [ "$step" -eq 3 ]; then
            break
        fi
    done
    fi

    echo -e "  ${CYAN}${ICO_ARROW} Menyisir direktori: ${YELLOW}$target_dir${RESET}"

    local count_success=0
    local count_failed=0
    local count_skipped=0

    while IFS= read -r audio_file; do
        local dir_path base_name filename_noext lrc_file
        dir_path=$(dirname "$audio_file")
        base_name=$(basename "$audio_file")
        filename_noext="${base_name%.*}"
        lrc_file="$dir_path/$filename_noext.lrc"

        if [ -f "$lrc_file" ]; then
            ((count_skipped++))
            continue
        fi

        local query=""
        if [ -n "$LAST_DOWNLOAD_QUERY" ]; then
            if [[ "$LAST_DOWNLOAD_QUERY" == *"ytsearch1:"* ]]; then
                query=$(echo "$LAST_DOWNLOAD_QUERY" | sed 's/.*ytsearch1://' | tr '+' ' ' | tr -d '"'\''')
            fi
            LAST_DOWNLOAD_QUERY=""
        fi

        if [ -z "$query" ]; then
            query=$(echo "$filename_noext" | sed -E 's/\([^)]*\)//g' | sed -E 's/\[[^]]*\]//g' | sed 's/-/ /g' | sed 's/  */ /g')
        fi

        echo -e "  ${YELLOW}${ICO_ARROW} Mendownload lirik:${RESET} $filename_noext"

        syncedlyrics "$query" -o "$lrc_file" >/dev/null 2>&1

        if [ -f "$lrc_file" ] && [ -s "$lrc_file" ]; then
            echo -e "    ${GREEN}${ICO_OK} Lirik Ditemukan!${RESET}"
            ((count_success++))
        else
            rm -f "$lrc_file" 2>/dev/null  # Hapus file kosong
            echo -e "    ${RED}${ICO_FAIL} Gagal menemukan lirik.${RESET}"
            ((count_failed++))
        fi
    done < <(find "$target_dir" -type f \( -iname "*.m4a" -o -iname "*.mp3" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.webm" \) -print0 2>/dev/null | xargs -0 --no-run-if-empty ls -t 2>/dev/null)

    echo -e "  ${CYAN}${ICO_ARROW} LAPORAN AUTO SYNC:${RESET}"
    echo -e "    ${GREEN}Sukses  :${RESET} $count_success lagu"
    echo -e "    ${RED}Gagal   :${RESET} $count_failed lagu"
    echo -e "    ${GRAY}Dilewati:${RESET} $count_skipped lagu (sudah punya lirik)"
    _log "INFO" "Lyric sync: success=$count_success failed=$count_failed skipped=$count_skipped"
}

# ==========================================
# FUNGSI UTAMA: GENERATOR PLAYLIST
# ==========================================
sync_spotify_playlist() {
    print_header "SPOTIFY PLAYLIST SYNC"
    
    if ! command -v spotdl >/dev/null 2>&1; then
        echo -e "  ${RED}${ICO_FAIL} SpotDL belum terinstall! Gunakan Menu [A] dulu.${RESET}"
        return 1
    fi

    local target_dir
    if ! pilih_folder_target; then return 0; fi
    target_dir="$TARGET_DIR"

    # Load from config or ask
    local playlist_url=""
    if [ -f "$HOME/.config/zdt/spotify_playlist.txt" ]; then
        playlist_url=$(cat "$HOME/.config/zdt/spotify_playlist.txt")
        echo -e "  ${CYAN}${ICO_ARROW} Playlist tersimpan: ${YELLOW}$playlist_url${RESET}"
        echo -e -n "  ${BOLD}[?] Gunakan playlist ini? (Y/n/0=Kembali): ${RESET}"
        local pakai_lama
        read -r -n 1 pakai_lama; echo ""
        if [ "$pakai_lama" = "0" ]; then return 0; fi
        if [[ "$pakai_lama" =~ ^[Nn]$ ]]; then
            playlist_url=""
        fi
    fi

    if [ -z "$playlist_url" ]; then
        echo -e -n "  ${BOLD}[?] Paste link Spotify Playlist: ${RESET}"
        read -r playlist_url
        if [ -z "$playlist_url" ]; then return 0; fi
        mkdir -p "$HOME/.config/zdt"
        echo "$playlist_url" > "$HOME/.config/zdt/spotify_playlist.txt"
    fi

    echo -e "  ${YELLOW}${ICO_ARROW} Memulai sinkronisasi playlist (Mencari lagu baru)...${RESET}"
    cd "$target_dir" || return 1
    
    # Run spotdl with save-errors and m3u for sync tracking
    spotdl download "$playlist_url" --m3u "sync_playlist.m3u" --save-errors "sync_errors.txt" --format m4a --bitrate 128k
    
    echo -e "  ${GREEN}${ICO_OK} Sinkronisasi Selesai!${RESET}"
    _log "INFO" "Spotify Sync Completed: $playlist_url"
}


bikin_playlist() {
    print_header "GENERATOR PLAYLIST (.m3u)"
    local step=1
    local target_dir=""
    local nama_pl=""

    while true; do
        if [ "$step" -eq 1 ]; then
            if ! pilih_folder_target; then return 0; fi
            target_dir="$TARGET_DIR"
            step=2
        elif [ "$step" -eq 2 ]; then
            echo -e -n "  ${BOLD}[?] Nama playlist (contoh: Koplo_Viral, 0=Kembali): ${RESET}"
            read -r nama_pl
            
            if [ "$nama_pl" = "0" ]; then step=1; continue; fi

            if [ -z "$nama_pl" ]; then
                echo -e "  ${RED}${ICO_FAIL} Input kosong!${RESET}"
                continue
            fi
            step=3
        elif [ "$step" -eq 3 ]; then
            break
        fi
    done

    nama_pl="${nama_pl// /-}"
    nama_pl=$(echo "$nama_pl" | tr -cd '[:alnum:]_-')
    local playlist_file="${nama_pl}.m3u"

    echo "#EXTM3U" > "$playlist_file"
    echo -e "  ${YELLOW}${ICO_ARROW} Menyisir lagu di '$target_dir'...${RESET}"

    local lagu_ditemukan=0
    while IFS= read -r f; do
        local relpath
        relpath=$(_relpath "$f" "$(dirname "$(_realpath "$playlist_file")")")
        echo "$relpath" >> "$playlist_file"
        ((lagu_ditemukan++))
    done < <(find "$target_dir" -type f \( -iname "*.m4a" -o -iname "*.mp3" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.ogg" \) 2>/dev/null | sort)

    if [ "$lagu_ditemukan" -le 0 ]; then
        echo -e "  ${RED}${ICO_FAIL} Tidak ada file lagu di target tersebut.${RESET}"
        rm -f "$playlist_file"
    else
        echo -e "  ${GREEN}${ICO_OK} Playlist ${playlist_file} berhasil dibuat (${lagu_ditemukan} lagu).${RESET}"
        _log "INFO" "Playlist created: $playlist_file ($lagu_ditemukan songs)"
    fi
}

# ==========================================
# FUNGSI UTAMA: BERSIH NAMA FILE MANUAL
# ==========================================
edit_metadata_manual() {
    print_header "METADATA & COVER ART EDITOR"
    if [ ! -f "$ZDT_VENV_DIR/bin/python" ]; then
        echo -e "  ${RED}${ICO_FAIL} VENV Python tidak tersedia. Jalankan Menu [A] dulu.${RESET}"
        return 1
    fi

    echo -e "  ${CYAN}${ICO_ARROW} Menampilkan daftar file audio di folder saat ini...${RESET}"
    local count=0
    local files=()
    while IFS= read -r f; do
        ((count++))
        files+=("$f")
        printf "    %2d. %s\n" "$count" "$(basename "$f")"
    done < <(ls -t "${TARGET_DIR:-$(pwd)}"/*.{mp3,m4a,flac} 2>/dev/null | head -n 20)

    if [ "$count" -eq 0 ]; then
        echo -e "  ${RED}${ICO_FAIL} Tidak ada file audio di direktori ini!${RESET}"
        return 0
    fi

    echo -e -n "\n  ${BOLD}[?] Pilih nomor lagu (0=Kembali): ${RESET}"
    local pilih_file
    read -r pilih_file
    if [ -z "$pilih_file" ] || [ "$pilih_file" = "0" ] || [ "$pilih_file" -gt "$count" ]; then
        return 0
    fi

    local selected_file="${files[$((pilih_file-1))]}"
    echo -e "  ${YELLOW}Terpilih:${RESET} $(basename "$selected_file")\n"

    echo -e -n "  ${CYAN}Judul Lagu baru (Kosongkan jika tidak diubah): ${RESET}"
    local new_title; read -r new_title
    
    echo -e -n "  ${CYAN}Nama Artis baru (Kosongkan jika tidak diubah): ${RESET}"
    local new_artist; read -r new_artist
    
    echo -e -n "  ${CYAN}Path gambar untuk Cover Art (Kosongkan jika tidak diubah): ${RESET}"
    local new_cover; read -r new_cover
    
    # Hilangkan tanda kutip jika ditarik/drag-and-drop
    new_cover=$(echo "$new_cover" | tr -d '"' | tr -d "'")

    echo -e "  ${YELLOW}${ICO_ARROW} Menyuntikkan metadata...${RESET}"
    "$ZDT_VENV_DIR/bin/python" -c "
import sys, os
try:
    from mutagen.easyid3 import EasyID3
    from mutagen.mp4 import MP4, MP4Cover
    from mutagen.flac import FLAC, Picture
    import mutagen.id3
    
    file_path = sys.argv[1]
    title = sys.argv[2]
    artist = sys.argv[3]
    cover_path = sys.argv[4]

    ext = file_path.lower()
    
    if ext.endswith('.mp3'):
        try: audio = mutagen.id3.ID3(file_path)
        except: 
            audio = mutagen.id3.ID3()
            audio.save(file_path)
        if title: audio.add(mutagen.id3.TIT2(encoding=3, text=title))
        if artist: audio.add(mutagen.id3.TPE1(encoding=3, text=artist))
        if cover_path and os.path.exists(cover_path):
            with open(cover_path, 'rb') as c:
                audio.add(mutagen.id3.APIC(encoding=3, mime='image/jpeg', type=3, desc='Cover', data=c.read()))
        audio.save()

    elif ext.endswith('.m4a'):
        audio = MP4(file_path)
        if title: audio['\xa9nam'] = title
        if artist: audio['\xa9ART'] = artist
        if cover_path and os.path.exists(cover_path):
            with open(cover_path, 'rb') as c:
                audio['covr'] = [MP4Cover(c.read(), imageformat=MP4Cover.FORMAT_JPEG)]
        audio.save()

    elif ext.endswith('.flac'):
        audio = FLAC(file_path)
        if title: audio['title'] = title
        if artist: audio['artist'] = artist
        if cover_path and os.path.exists(cover_path):
            pic = Picture()
            pic.type = 3
            pic.mime = 'image/jpeg'
            with open(cover_path, 'rb') as c:
                pic.data = c.read()
            audio.clear_pictures()
            audio.add_picture(pic)
        audio.save()
        
    print('SUCCESS')
except Exception as e:
    print(f'ERROR: {str(e)}')
" "$selected_file" "$new_title" "$new_artist" "$new_cover"

    echo -e "  ${GREEN}${ICO_OK} Metadata berhasil diperbarui!${RESET}"
}


bersih_nama() {
    print_header "PEMBERSIH NAMA FILE MANUAL"

    if ! _check_dependency "python3" "true"; then
        return 1
    fi

    local step=1
    local target_dir=""
    local mode_scan=""
    local gas=""
    local time_arg=()

    while true; do
        if [ "$step" -eq 1 ]; then
            if ! pilih_folder_target; then return 0; fi
            target_dir="$TARGET_DIR"
            step=2
        elif [ "$step" -eq 2 ]; then
            echo -e "  ${CYAN}${ICO_ARROW} JANGKAUAN SCAN${RESET}"
            echo "    1. Semua file di folder tersebut"
            echo "    2. File baru saja (60 menit terakhir)"
            echo "    0. ${ICO_FAIL} KEMBALI"
            echo -e -n "  ${BOLD}[?] Pilih Mode [0-2]: ${RESET}"
            read -r -n 1 mode_scan
            echo ""
            if [ "$mode_scan" = "0" ]; then step=1; continue; fi
            if [[ ! "$mode_scan" =~ ^[1-2]$ ]]; then
                echo -e "  ${RED}${ICO_FAIL} Pilihan tidak valid!${RESET}"
                continue
            fi
            
            time_arg=()
            [ "$mode_scan" = "2" ] && time_arg=(-mmin -60)
            step=3
        elif [ "$step" -eq 3 ]; then
            echo -e -n "  ${BOLD}[?] Eksekusi pembersihan? (y/n, 0=Kembali): ${RESET}"
            read -r -n 1 gas
            echo ""
            if [ "$gas" = "0" ]; then step=2; continue; fi
            if [[ ! "$gas" =~ ^[Yy]$ ]]; then
                echo -e "  ${YELLOW}${ICO_ARROW} Dibatalkan!${RESET}"
                return 0
            fi
            step=4
        elif [ "$step" -eq 4 ]; then
            break
        fi
    done

    echo ""
        local count=0
        while IFS= read -r file; do
            _bersih_satu_nama "$file"
            ((count++))
        done < <(find "$target_dir" -type f \( -iname "*.m4a" -o -iname "*.mp3" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.ogg" -o -iname "*.opus" -o -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.webm" -o -iname "*.lrc" \) "${time_arg[@]}" 2>/dev/null)
        echo -e "  ${GREEN}${ICO_OK} Proses perapian nama selesai! ($count file diproses)${RESET}"
        _log "INFO" "Name cleaning done: $count files scanned"

}

# ==========================================
# FUNGSI UTAMA: UPDATE TOOLS
# ==========================================
start_web_dashboard() {
    print_header "ZDT WEB DASHBOARD"
    if ! _check_dependency "python3" "true"; then return 1; fi
    
    local web_script="$HOME/.local/share/zdt/zdt-web.py"
    if [ ! -f "$web_script" ]; then
        echo -e "  ${RED}${ICO_FAIL} Script zdt-web.py tidak ditemukan di $web_script${RESET}"
        return 1
    fi
    
    echo -e "  ${YELLOW}${ICO_ARROW} Menjalankan Local Web Server (Flask)...${RESET}"
    echo -e "  ${CYAN}${ICO_OK} Silakan buka browser dan akses: ${BOLD}http://localhost:5000${RESET}"
    echo -e "  ${GRAY}  (Tekan Ctrl+C untuk mematikan server)${RESET}"
    echo ""
    
    if [ -f "$ZDT_VENV_DIR/bin/python" ]; then
        "$ZDT_VENV_DIR/bin/python" "$web_script" "$ROOT_DIR"
    else
        python3 "$web_script" "$ROOT_DIR"
    fi
}

update_zdt_script() {

    print_header "AUTO-UPDATER ZDT SCRIPT"
    echo -e "  ${YELLOW}${ICO_ARROW} Mengecek versi terbaru dari GitHub...${RESET}"
    local latest_script
    if ! latest_script=$(curl -sL https://raw.githubusercontent.com/muhammad1505/zdt-music-toolkit/main/zdt.sh); then
        echo -e "  ${RED}${ICO_FAIL} Gagal terhubung ke GitHub!${RESET}"
        return 1
    fi
    local latest_version
    latest_version=$(echo "$latest_script" | grep '^readonly APP_VERSION=' | head -1 | cut -d'"' -f2)
    
    if [ -z "$latest_version" ]; then
        echo -e "  ${RED}${ICO_FAIL} Gagal mendeteksi versi terbaru!${RESET}"
        return 1
    fi
    
    if [ "$latest_version" = "$APP_VERSION" ]; then
        echo -e "  ${GREEN}${ICO_OK} Anda menggunakan versi terbaru (v$APP_VERSION)!${RESET}"
    else
        echo -e "  ${CYAN}${ICO_ARROW} Versi baru tersedia: v$latest_version (Saat ini: v$APP_VERSION)${RESET}"
        echo -e -n "  ${BOLD}[?] Lakukan pembaruan sekarang? (y/n): ${RESET}"
        read -r -n 1 gas_up
        echo ""
        if [[ "$gas_up" =~ ^[Yy]$ ]]; then
            echo -e "  ${YELLOW}${ICO_ARROW} Mengunduh dan menimpa script...${RESET}"
            local script_path
            script_path=$(_realpath "$0")
            echo "$latest_script" > "$script_path"
            chmod +x "$script_path"
            
            # Jika terinstal global, timpa juga
            if command -v zdt >/dev/null 2>&1; then
                local global_path
                global_path=$(command -v zdt)
                cp "$script_path" "$global_path" 2>/dev/null || sudo cp "$script_path" "$global_path" 2>/dev/null || true
            fi
            
            echo -e "  ${GREEN}${ICO_OK} Pembaruan Selesai! Menjalankan ulang aplikasi...${RESET}"
            sleep 2
            exec "$script_path" "$@"
        fi
    fi
}

update_tools() {
    print_header "UPDATE ALAT TEMPUR"
    echo -e -n "  ${BOLD}[?] Lanjut Update Tools? (y/n, 0=Batal): ${RESET}"
    local konfirmasi
    read -r -n 1 konfirmasi
    echo ""

    if [ "$konfirmasi" = "0" ] || [[ ! "$konfirmasi" =~ ^[Yy]$ ]]; then
        echo -e "  ${YELLOW}${ICO_ARROW} Dibatalkan!${RESET}"
        return 0
    fi

    local pip_cmd="$ZDT_VENV_DIR/bin/pip"

    if [ ! -f "$pip_cmd" ]; then
        echo -e "  ${RED}${ICO_FAIL} Virtual Environment (VENV) belum terpasang!${RESET}"
        echo -e "  ${YELLOW}Silakan masuk ke menu Auto Install Tools terlebih dahulu.${RESET}"
        return 1
    fi

    echo -e "  ${YELLOW}${ICO_ARROW} Menghubungkan ke server Python menggunakan VENV...${RESET}"

    if "$pip_cmd" install -U pip setuptools >/dev/null 2>&1; then
        echo -e "  ${GREEN}${ICO_CHECK_OK} PIP berhasil diperbarui.${RESET}"
    fi

    if "$pip_cmd" install -U yt-dlp spotdl syncedlyrics; then
        echo -e "  ${GREEN}${ICO_OK} Pembaruan Selesai!${RESET}"
        _log "INFO" "Tools updated successfully via VENV"
    else
        echo -e "  ${RED}${ICO_FAIL} Gagal melakukan update. Cek koneksi internet atau permission sistem.${RESET}"
        _log "ERROR" "Tool update failed in VENV"
    fi
}

# ==========================================
# FUNGSI UTAMA: HAPUS SEMUA
# ==========================================
hapus_semua() {
    print_header "HAPUS SEMUA FILE & FOLDER (DANGER)"
    echo -e "  ${RED}${BOLD}PERINGATAN KERAS!${RESET}"
    echo -e "  ${YELLOW}Ini akan MENGHAPUS PERMANEN seluruh isi direktori:${RESET}"
    echo -e "  ${WHITE}$(pwd)${RESET}"
    echo ""
    local konfirmasi konfirmasi2 total
    
    local current_pwd
    current_pwd=$(pwd)
    
    # Mencegah eksekusi di direktori sistem/kritis
    if [[ "$current_pwd" == "/" || "$current_pwd" == "/home" || "$current_pwd" == "/root" || "$current_pwd" == "/etc" || "$current_pwd" == "$HOME" ]]; then
        echo -e "  ${RED}${ICO_FAIL} AKSES DITOLAK!${RESET}"
        echo -e "  ${YELLOW}Sistem keamanan memblokir penghapusan di direktori kritis: $current_pwd${RESET}"
        return 1
    fi

    # Double confirmation
    echo -e -n "  ${BOLD}[?] Ketik 'YAKIN' (huruf besar) untuk lanjut (Enter/0=Batal): ${RESET}"
    read -r konfirmasi

    if [ "$konfirmasi" = "0" ] || [ -z "$konfirmasi" ]; then
        echo -e "  ${GREEN}${ICO_OK} Dibatalkan. Data aman!${RESET}"
        return 0
    elif [ "$konfirmasi" = "YAKIN" ]; then
        # Final safety: count files
        local total
        total=$(find . -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
        echo -e "  ${YELLOW}Akan menghapus $total item. Yakin?${RESET}"
        echo -e -n "  ${BOLD}[?] Ketik 'HAPUS' untuk konfirmasi final: ${RESET}"
        read -r konfirmasi2

        if [ "$konfirmasi2" = "HAPUS" ]; then
            echo -e "  ${RED}${ICO_ARROW} Mengeksekusi penghapusan massal...${RESET}"
            find . -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
            echo -e "  ${GREEN}${ICO_OK} Direktori bersih total!${RESET}"
            _log "WARN" "Mass deletion executed at $(pwd)"
        else
            echo -e "  ${GREEN}${ICO_OK} Dibatalkan. Data aman!${RESET}"
        fi
    else
        echo -e "  ${GREEN}${ICO_OK} Dibatalkan. Data aman!${RESET}"
    fi
}

# ==========================================
# FUNGSI UTAMA: AUTO INSTALL TOOLS
# ==========================================
install_missing_tools() {
    print_header "AUTO INSTALL TOOLS YANG KURANG"
    echo -e "  ${YELLOW}${ICO_ARROW} Memulai instalasi otomatis...${RESET}"
    echo -e "  ${GRAY}Environment: $RUNTIME_ENV${RESET}"
    echo ""

    local pkg_mgr
    pkg_mgr=$(_get_pkg_manager)

    if [ -z "$pkg_mgr" ]; then
        echo -e "  ${RED}${ICO_FAIL} Tidak ada package manager yang terdeteksi!${RESET}"
        echo -e "  ${YELLOW}Package manager yang didukung: apt, pkg (Termux), dnf, yum, pacman, apk, zypper${RESET}"
        return 1
    fi

    echo -e "  ${CYAN}Package manager: $pkg_mgr${RESET}"
    echo ""

    # 1. Install Python3 & venv
    if ! command -v python3 >/dev/null 2>&1 || ! python3 -c "import venv" >/dev/null 2>&1; then
        echo -e "  ${CYAN}${ICO_ARROW} Menginstal Python3 dan modul venv...${RESET}"
        case "$pkg_mgr" in
            *pkg)     $pkg_mgr install -y python ;;
            *pacman)  $pkg_mgr -Sy --noconfirm python ;;
            *apk)     $pkg_mgr add python3 ;;
            *apt*)    $pkg_mgr update -y && $pkg_mgr install -y python3 python3-venv ;;
            *dnf|*yum) _pkg_install python3 ;;
            *zypper)  _pkg_install python3 ;;
            *)        _pkg_install python3 ;;
        esac
    else
        echo -e "  ${GREEN}${ICO_OK} Python3 dan venv sudah siap${RESET}"
    fi

    # 2. Install FFmpeg
    if ! command -v ffmpeg >/dev/null 2>&1; then
        echo -e "  ${CYAN}${ICO_ARROW} Menginstal FFmpeg...${RESET}"
        _pkg_install ffmpeg
    else
        echo -e "  ${GREEN}${ICO_OK} FFmpeg sudah terinstal${RESET}"
    fi

    # 3. Setup Virtual Environment
    echo -e "  ${CYAN}${ICO_ARROW} Menyiapkan Python Virtual Environment (VENV)...${RESET}"
    if [ ! -d "$ZDT_VENV_DIR" ]; then
        if ! python3 -m venv "$ZDT_VENV_DIR"; then
            echo -e "  ${RED}${ICO_FAIL} Gagal membuat virtual environment di $ZDT_VENV_DIR!${RESET}"
            echo -e "  ${YELLOW}Pastikan paket python3-venv terinstal di sistem Anda.${RESET}"
            return 1
        fi
    fi
    echo -e "  ${GREEN}${ICO_OK} VENV siap di $ZDT_VENV_DIR${RESET}"

    # 4. Install Python tools di dalam VENV
    local pip_cmd="$ZDT_VENV_DIR/bin/pip"
    if [ -f "$pip_cmd" ]; then
        local pip_tools=("yt-dlp" "spotdl" "syncedlyrics" "mutagen" "flask" "werkzeug")
        
        echo -e "  ${CYAN}${ICO_ARROW} Menginstal tools Python: ${YELLOW}${pip_tools[*]}${RESET}"
        echo -e "  ${GRAY}Ini mungkin memakan waktu beberapa menit, harap tunggu...${RESET}"
        
        # Upgrade pip itself first inside venv
        "$pip_cmd" install -U pip setuptools >/dev/null 2>&1 || true

        if "$pip_cmd" install -U "${pip_tools[@]}"; then
            echo -e "  ${GREEN}${ICO_OK} Instalasi Python tools berhasil!${RESET}"
        else
            echo -e "  ${RED}${ICO_FAIL} Beberapa tools gagal diinstal. Coba jalankan manual:${RESET}"
            echo -e "  ${GRAY}$pip_cmd install -U ${pip_tools[*]}${RESET}"
        fi
    else
        echo -e "  ${RED}${ICO_FAIL} Gagal menemukan pip di dalam VENV.${RESET}"
        return 1
    fi

    echo ""
    echo -e "  ${GREEN}${ICO_OK} Proses instalasi selesai!${RESET}"
    _log "INFO" "Auto-install completed using VENV"
}

# ==========================================
# FUNGSI UTAMA: SYSTEM INFO
# ==========================================
system_info() {
    print_header "INFORMASI SISTEM"

    echo -e "  ${WHITE}App Version  :${RESET} ${CYAN}$APP_VERSION${RESET}"
    echo -e "  ${WHITE}Environment  :${RESET} ${CYAN}$RUNTIME_ENV${RESET}"
    echo -e "  ${WHITE}OS           :${RESET} ${CYAN}$(_get_os_name)${RESET}"
    echo -e "  ${WHITE}Shell        :${RESET} ${CYAN}${BASH_VERSION:-unknown}${RESET}"
    echo -e "  ${WHITE}User         :${RESET} ${CYAN}$(whoami 2>/dev/null || echo 'unknown')${RESET}"
    echo -e "  ${WHITE}Working Dir  :${RESET} ${CYAN}$(pwd)${RESET}"
    if [ -n "$STORAGE_DIR" ]; then
        echo -e "  ${WHITE}Storage Dir  :${RESET} ${MAGENTA}$STORAGE_DIR${RESET}"
    else
        echo -e "  ${WHITE}Storage Dir  :${RESET} ${YELLOW}(default — pakai dir saat menjalankan)${RESET}"
    fi
    local config_file
    config_file=$(_get_config_file)
    echo -e "  ${WHITE}Config File  :${RESET} ${CYAN}$config_file${RESET}"

    echo -e "  ${WHITE}RAM Usage    :${RESET} ${CYAN}$(_get_ram_percent)%${RESET}"
    echo -e "  ${WHITE}Storage      :${RESET} ${CYAN}$(_get_storage_percent)%${RESET}"
    echo -e "  ${WHITE}Uptime       :${RESET} ${CYAN}$(_get_uptime)${RESET}"
    echo ""

    echo -e "  ${BOLD}TOOL STATUS:${RESET}"
    local tools=("python3" "pip3" "ffmpeg" "spotdl" "yt-dlp" "syncedlyrics")
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            local ver=""
            case "$tool" in
                python3)      ver=$($tool --version 2>&1 | head -1) ;;
                pip3)         ver=$($tool --version 2>&1 | head -1) ;;
                ffmpeg)       ver=$($tool -version 2>&1 | head -1) ;;
                spotdl)       ver=$($tool --version 2>&1 | head -1) ;;
                yt-dlp)       ver=$($tool --version 2>&1 | head -1) ;;
                syncedlyrics) ver="installed" ;;
            esac
            printf "    ${GREEN}${ICO_CHECK_OK}${RESET} %-14s %s\n" "$tool" "${ver:0:50}"
        else
            printf "    ${RED}${ICO_CHECK_FAIL}${RESET} %-14s %s\n" "$tool" "NOT INSTALLED"
        fi
    done

    # Demucs AI (hanya tampil di desktop)
    if [ "$RUNTIME_ENV" != "termux" ]; then
        echo ""
        echo -e "  ${BOLD}AI TOOLS:${RESET}"
        local demucs_venv="$HOME/.local/share/zdt/demucs_venv"
        if [ -f "$demucs_venv/bin/demucs" ]; then
            local dver
            dver=$("$demucs_venv/bin/pip" show demucs 2>/dev/null | grep -i "^Version:" | awk '{print $2}')
            printf "    ${GREEN}${ICO_CHECK_OK}${RESET} %-14s %s\n" "demucs" "v${dver:-unknown}"
        else
            printf "    ${RED}${ICO_CHECK_FAIL}${RESET} %-14s %s\n" "demucs" "NOT INSTALLED (instal via Menu [V])"
        fi
    fi
}

# ==========================================
# BANTUAN & DOKUMENTASI
# ==========================================
tampilkan_dokumentasi() {
    print_header "DOKUMENTASI & BANTUAN"
    
    local doc_text="
  ${CYAN}╔══════════════════════════════════════════════════════════════════╗${RESET}
  ${CYAN}║${RESET}${BOLD}${WHITE}            Z Λ K I   D O W N L O Λ D Ξ R   T O O L S             ${RESET}${CYAN}║${RESET}
  ${CYAN}║${RESET}${BOLD}${YELLOW}                  PANDUAN & DOKUMENTASI LENGKAP                   ${RESET}${CYAN}║${RESET}
  ${CYAN}╚══════════════════════════════════════════════════════════════════╝${RESET}

  ${YELLOW}${BOLD}=== PENGANTAR ===${RESET}
  Zaki Downloader Tools (ZDT) adalah ekosistem media otomatis. Tools ini
  dirancang untuk mempermudah kamu mendownload, merapikan, dan mengelola 
  file musik/video dari Spotify, YouTube, dan TikTok secara otomatis.

  ${YELLOW}${BOLD}=== PANDUAN PENGGUNAAN SETIAP MENU (DETAIL) ===${RESET}

  ${CYAN}• [1] Spotify HQ Downloader${RESET}
    Mendownload lagu atau playlist langsung dari Spotify lengkap dengan
    Cover Art (gambar album), lirik (jika tersedia), dan Metadata.
    ${WHITE}Cara Pakai:${RESET} Pilih menu 1, lalu paste link lagu/playlist Spotify. 
    Script akan otomatis membuat folder nama artis jika mendownload playlist.

  ${CYAN}• [2] Audio Downloader (YouTube & TikTok)${RESET}
    Mengambil audio berkualitas tinggi dari video YouTube atau TikTok. 
    ${WHITE}Cara Pakai:${RESET} Pilih menu 2, paste link video YT/TikTok. Proses akan
    berjalan dan audio otomatis diubah ke format M4A/MP3 terbaik.

  ${CYAN}• [3] Video Downloader (YouTube & TikTok)${RESET}
    Mendownload video lengkap dari YouTube atau TikTok.
    ${WHITE}Cara Pakai:${RESET} Pilih menu 3, paste link video. Script akan menanyakan
    kualitas resolusi yang diinginkan (contoh: 1080p, 720p).

  ${CYAN}• [4] Kompres Media Cerdas (Multi-Processing)${RESET}
    Memperkecil ukuran file musik (M4A/MP3) atau video tanpa mengurangi 
    kualitas yang terdengar. Mampu mengompres hingga 4 file secara paralel!
    ${WHITE}Cara Pakai:${RESET} Pilih menu 4. Preferensi kualitas Anda akan otomatis disimpan ke dalam file konfigurasi ~/.config/zdt/config.env.

  ${CYAN}• [5] Auto Sync Lirik (.lrc)${RESET}
    Mencari dan mendownload lirik berjalan (.lrc) yang pas dengan ketukan
    lagu. File akan diletakkan berdampingan dengan lagu asli.
    ${WHITE}Cara Pakai:${RESET} Pilih menu 5. Script otomatis memindai lagu di folder
    dan mengunduh lirik untuk lagu yang belum memiliki lirik.

  ${CYAN}• [6] Smart Renamer & Auto-Tagger Metadata${RESET}
    Menghapus teks kotor seperti '(Official Music Video)', '(Lyrics)', 
    lalu otomatis menyuntikkan ID3 Metadata (Judul & Artis) menggunakan Mutagen.
    ${WHITE}Cara Pakai:${RESET} Pilih menu 6. Script akan me-rename otomatis semua 
    lagu, lalu menyuntikkan metadatanya secara permanen.

  ${CYAN}• [7] Bikin Playlist (.m3u8)${RESET}
    Membuat file playlist (.m3u8) sekali klik agar lagu di dalam folder
    bisa diputar berurutan di aplikasi pemutar musik.
    ${WHITE}Cara Pakai:${RESET} Pilih menu 7. Script langsung menghasilkan file m3u8
    berisi semua daftar lagu di direktori aktif.

  ${CYAN}• [S] Setup Direktori Permanen${RESET}
    Menentukan satu folder khusus agar semua hasil download selalu
    disimpan ke dalam folder tersebut (misal: /sdcard/Music).
    ${WHITE}Cara Pakai:${RESET} Pilih menu S. Ketik path folder yang diinginkan atau
    pilih folder saat ini.

  ${CYAN}• [W] ZDT Web Dashboard (Local UI)${RESET}
    Menyalakan Local Web Server. Anda bisa mendownload lagu via browser HP/PC
    tanpa harus menyentuh terminal.
    ${WHITE}Cara Pakai:${RESET} Pilih menu W, lalu buka link http://localhost:5000 di browser.

  ${CYAN}• [P] Spotify Playlist Sync Manager${RESET}
    Menyinkronkan (download) sebuah Playlist Spotify. ZDT akan menyimpan
    link playlist Anda dan hanya mendownload lagu-lagu baru yang belum ada.
    ${WHITE}Cara Pakai:${RESET} Pilih menu P. Masukkan link playlist, lalu tunggu ZDT bekerja.

  ${CYAN}• [M] Metadata & Cover Art Editor${RESET}
    Mengubah Judul, Nama Artis, dan menambahkan gambar (Cover Art) ke dalam
    file MP3/M4A/FLAC Anda secara manual.
    ${WHITE}Cara Pakai:${RESET} Pilih menu M. Pilih lagu, lalu ketik judul dan path gambar.


  ${CYAN}• [V] Hapus Vokal AI (Demucs Pro)${RESET}
    Memisahkan suara vokal penyanyi dan musik instrumen menggunakan 
    teknologi AI dari Meta Research (Kualitas Profesional).
    ${WHITE}Cara Pakai:${RESET} Pilih menu V. Pilih file lagu, lalu AI akan bekerja
    menghasilkan 2 file: Vokal Only dan Instrumen Only.
    ${RED}⚠ Syarat:${RESET} Hanya tersedia di PC/Linux (RAM min 4GB). Tidak di HP.

  ${CYAN}• [8] Update Alat Tempur (SpotDL & YT-DLP)${RESET}
    Memperbarui mesin utama ke versi terbaru agar download tidak sering error
    karena perubahan algoritma YouTube/Spotify.
    ${WHITE}Cara Pakai:${RESET} Pilih menu 8. Script akan update otomatis via internet.

  ${CYAN}• [U] Cek Pembaruan ZDT Script (Auto-Updater)${RESET}
    Fitur Over-The-Air (OTA) untuk mengecek kode terbaru langsung dari GitHub.
    ${WHITE}Cara Pakai:${RESET} Pilih menu U. Skrip otomatis diunduh dan dipasang menimpa versi lama.

  ${CYAN}• [9] Info Sistem & Diagnostik${RESET}
    Mengecek RAM, status Storage, versi Sistem Operasi, dan dependensi
    (FFmpeg, Demucs, dll). Berguna untuk troubleshooting.
    ${WHITE}Cara Pakai:${RESET} Pilih menu 9 untuk menampilkan status komprehensif.

  ${CYAN}• [A] Zaki AI Assistant (Pro)${RESET}
    Asisten pintar berbasis Google Gemini AI. Bisa diajak ngobrol santai,
    nyuruh download otomatis lewat chat, dan punya fitur "Auto-Healing"
    (otomatis pindah server/mirror kalau link utama gagal download).
    ${WHITE}Cara Pakai:${RESET} Pilih menu A. Ketik perintah seperti biasa. Untuk
    mengaktifkan otak AI-nya, ketik "set api key" di dalam chat bot.

  ${CYAN}• [X] Hapus Semua (Wipe)${RESET}
    Menghapus semua file dan folder sementara di direktori saat ini.
    ${WHITE}Cara Pakai:${RESET} Pilih menu X. Terdapat konfirmasi sebelum menghapus
    sehingga file kamu tidak sengaja terhapus.

  ${YELLOW}${BOLD}=== TROUBLESHOOTING (SOLUSI CEPAT) ===${RESET}
  ${RED}✖ Download tiba-tiba sering gagal / Timeout?${RESET} 
    ➜ Youtube/Spotify mengubah sistemnya. Jalankan Menu [8] untuk update.
  ${RED}✖ Lirik lagu tidak ditemukan?${RESET}
    ➜ Nama file kotor. Jalankan Menu [6] (Bersih Nama) lalu cari lirik lagi [5].

  ${GRAY}────────────────────────────────────────────────────────────────────${RESET}
  ${WHITE}${BOLD}Zaki Downloader Tools | Dikembangkan Khusus Untuk Efisiensi & Kualitas${RESET}
  ${GRAY}────────────────────────────────────────────────────────────────────${RESET}
"

    # Gunakan pager (less) jika tersedia dan output panjang, kalau tidak echo biasa
    if command -v less >/dev/null 2>&1; then
        local doc_prompt="Tekan 'q' untuk kembali ke menu utama, panah atas/bawah untuk scroll"
        echo -e "$doc_text" | less -r -P "$doc_prompt"
    else
        echo -e "$doc_text"
        echo ""
        echo -e "  ${GRAY}--- Akhir Dokumentasi ---${RESET}"
        _pause
    fi
}

# ==========================================
# ZAKI AI ASSISTANT (SMART MODE)
# ==========================================
zaki_assistant() {
    local gemini_key_file="$HOME/.config/zdt/gemini_key"
    local ZDT_GEMINI_KEY=""
    [ -f "$gemini_key_file" ] && ZDT_GEMINI_KEY=$(cat "$gemini_key_file")
    
    print_bot_header() {
        echo -ne "\033[?25h"
        clear
        echo ""
        echo -e "  ${CYAN}╔══════════════════════════════════════════════════╗${RESET}"
        local btxt
        printf -v btxt "%-50s" " ZAKI SMART ASSISTANT (PRO)"
        echo -e "  ${CYAN}║${RESET}${WHITE}${BOLD}${btxt}${RESET}${CYAN}║${RESET}"
    }

    print_bot_header
    
    local hour
    hour=$(date +%H)
    local sapaan="Halo bos"
    if [ "$hour" -ge 4 ] && [ "$hour" -lt 11 ]; then sapaan="Pagi bro"
    elif [ "$hour" -ge 11 ] && [ "$hour" -lt 15 ]; then sapaan="Siang bro"
    elif [ "$hour" -ge 15 ] && [ "$hour" -lt 18 ]; then sapaan="Sore bro"
    else sapaan="Malam bro"
    fi

    local storage_status=""
    if command -v df >/dev/null 2>&1; then
        local target_check="${TARGET_DIR:-$ROOT_DIR}"
        local free_space
        free_space=$(df -h "$target_check" 2>/dev/null | awk 'NR==2 {print $4}')
        storage_status="(Storage lu sisa $free_space)"
    fi

    local bot_prompt="${sapaan}! ${storage_status} Lagi pengen ngapain nih? (Ketik 'keluar' buat balik)"

    local next_user_input=""
    # Chat loop timbal-balik berbasis State (bot_prompt)
    while true; do
        # Gambar Chat Bubble (Satu Kolom)
        echo -e "  ${CYAN}╟──────────────────────────────────────────────────╢${RESET}"
        local is_first=1
        if [ -z "$bot_prompt" ]; then
            printf "  ${CYAN}║${RESET} 🤖 ${WHITE}%-45s${RESET} ${CYAN}║${RESET}\n" ""
        else
            mapfile -t b_lines < <(echo "$bot_prompt" | fold -w 45 -s)
            for line in "${b_lines[@]}"; do
                # Trim trailing spaces if any
                line="${line%"${line##*[![:space:]]}"}"
                if [ "$is_first" -eq 1 ]; then
                    printf "  ${CYAN}║${RESET} 🤖 ${WHITE}%-45s${RESET} ${CYAN}║${RESET}\n" "$line"
                    is_first=0
                else
                    printf "  ${CYAN}║${RESET}    ${WHITE}%-45s${RESET} ${CYAN}║${RESET}\n" "$line"
                fi
            done
        fi
        
        echo -e "  ${CYAN}╟──────────────────────────────────────────────────╢${RESET}"
        
        local user_input
        # JIKA ADA AUTO ACTION, GAK USAH NAMPILIN PROMPT INPUT!
        if [ -n "$next_user_input" ]; then
            user_input="$next_user_input"
            next_user_input=""
            # Skip reading, just let it render below
        else
            printf "  ${CYAN}║${RESET} 💬 ${BOLD}Lu: ❯ ${RESET}%-40s${CYAN}║${RESET}\n" ""
            echo -e "  ${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
            
            # Pindahkan kursor naik 2 baris & maju 15 kolom ke dalam area input
            echo -en "\033[2A\033[15G"
            
            # Matikan auto-wrap biar text panjang ga ngerusak border UI
            echo -en "\033[?7l"
            read -r user_input || { echo -en "\033[?7h"; return 0; }
            echo -en "\033[?7h"

            # Redraw tulisan user ke dalam box word-wrap biar super rapi!
            echo -en "\033[2A"
            echo -en "\033[J"
        fi

        local display_input="$user_input"
        if [[ "$display_input" == *"ytsearch1:"* ]]; then
            if [[ "$display_input" == *"tonton"* ]]; then
                display_input="[Auto-Stream Video]"
            elif [[ "$display_input" == *"video"* ]]; then
                display_input="[Auto-Download Video]"
            else
                display_input="[Auto-Download Lagu]"
            fi
        fi

        if [ -z "$display_input" ]; then
            printf "  ${CYAN}║${RESET} 💬 ${BOLD}Lu: ❯ ${RESET}%-40s${CYAN}║${RESET}\n" ""
        else
            local u_first=1
            mapfile -t u_lines < <(echo "$display_input" | fold -w 40 -s)
            for line in "${u_lines[@]}"; do
                # Trim trailing spaces if any
                line="${line%"${line##*[![:space:]]}"}"
                if [ "$u_first" -eq 1 ]; then
                    printf "  ${CYAN}║${RESET} 💬 ${BOLD}Lu: ❯ ${RESET}%-40s${CYAN}║${RESET}\n" "$line"
                    u_first=0
                else
                    printf "  ${CYAN}║${RESET}          %-40s${CYAN}║${RESET}\n" "$line"
                fi
            done
        fi
        echo -e "  ${CYAN}╚══════════════════════════════════════════════════╝${RESET}"

        local lower_input
        lower_input=$(echo "$user_input" | tr '[:upper:]' '[:lower:]')

        # Cek apakah user mau keluar aplikasi atau ke menu
        if [[ "$lower_input" == *"keluar aplikasi"* ]] || [[ "$lower_input" == *"exit"* ]] || [[ "$lower_input" == *"tutup"* ]]; then
            printf "  ${CYAN}║${RESET} 🤖 ${WHITE}%-45s${RESET} ${CYAN}║${RESET}\n" "Sip bro, gua pamit undur diri ya. Sampai jumpa!"
            echo -e "  ${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
            sleep 1
            printf '\033c'
            exit 0
        elif [ "$user_input" = "0" ] || [[ "$lower_input" == *"keluar"* ]] || [[ "$lower_input" == *"menu"* ]]; then
            printf "  ${CYAN}║${RESET} 🤖 ${WHITE}%-45s${RESET} ${CYAN}║${RESET}\n" "Sip, santai bro. Kita balik ke menu utama ya!"
            echo -e "  ${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
            sleep 1
            return 0
        fi

        [ -z "$user_input" ] && continue

        # Simpan prompt AI sebelumnya buat konteks ngobrol
        local prev_bot_prompt="$bot_prompt"
        # Simpan input asli user buat nebak niat download (karena input bakal ditimpa link)
        local original_lower_input="$lower_input"

        # Deteksi URL pintar: dari input user ATAU nyomot dari balasan AI sebelumnya!
        local link_terdeteksi=""
        local is_smart_download=0
        if [[ "$lower_input" == *"http"* ]]; then
            link_terdeteksi=$(echo "$user_input" | grep -o -E 'https?://[^ ]+' | head -n 1)
        elif [[ "$lower_input" == *"download"* ]] || [[ "$lower_input" == *"sedot"* ]] || [[ "$lower_input" == *"gas"* ]] || [[ "$lower_input" == *"sikat"* ]] || [[ "$lower_input" == *"unduh"* ]] || [[ "$lower_input" == *"tonton"* ]] || [[ "$lower_input" == *"stream"* ]] || [[ "$lower_input" == *"nonton"* ]] || [[ "$lower_input" == *"buka"* ]] || [[ "$lower_input" == *"putar"* ]]; then
            if [[ "$prev_bot_prompt" == *"http"* ]]; then
                link_terdeteksi=$(echo "$prev_bot_prompt" | grep -o -E 'https?://[^]"'\'' \)]+' | head -n 1)
                is_smart_download=1
            fi
        fi

        # Reset prompt default (kalau misalnya beneran nge-download)
        bot_prompt="Beres disedot bro! Ada lagi yang mau dikerjain?"

        if [ -n "$link_terdeteksi" ]; then
            user_input="$link_terdeteksi"
            if [[ "$user_input" == *"youtube.com/results?search_query="* ]] || [[ "$user_input" == *"music.youtube.com/search?q="* ]]; then
                local query
                query=$(echo "$user_input" | sed 's/.*search_query=//' | sed 's/.*search?q=//' | sed 's/&.*//' | tr '+' ' ' | tr -d '"'\''')
                user_input="ytsearch1:$query"
            fi
            lower_input=$(echo "$user_input" | tr '[:upper:]' '[:lower:]')
        fi

        # Bersihkan input menjadi murni URL/Search Query buat dieksekusi yt-dlp/spotdl
        if [[ "$user_input" == *"ytsearch1:"* ]]; then
            user_input="ytsearch1:$(echo "$user_input" | sed 's/.*ytsearch1://')"
        elif [[ "$user_input" == *"scsearch:"* ]]; then
            user_input="scsearch1:$(echo "$user_input" | sed 's/.*scsearch://')"
        elif [[ "$user_input" == *"spotsearch:"* ]]; then
            user_input="$(echo "$user_input" | sed 's/.*spotsearch://')"
        elif [[ "$user_input" == *"http"* ]] && [ -z "$link_terdeteksi" ]; then
            user_input=$(echo "$user_input" | grep -o -E 'https?://[^ ]+' | head -n 1)
        fi

        # Deteksi URL
        if [[ "$lower_input" == *"http"* ]] || [[ "$lower_input" == *"ytsearch1:"* ]] || [[ "$lower_input" == *"scsearch:"* ]] || [[ "$lower_input" == *"spotsearch:"* ]]; then
            if [[ "$original_lower_input" == *"stream"* ]] || [[ "$original_lower_input" == *"nonton"* ]] || [[ "$original_lower_input" == *"tonton"* ]] || [[ "$original_lower_input" == *"buka link"* ]] || [[ "$original_lower_input" == *"putar dari"* ]] || [[ "$original_lower_input" == *"putar langsung"* ]]; then
                printf "  ${CYAN}║${RESET} 🤖 ${WHITE}%-45s${RESET} ${CYAN}║${RESET}\n" "Otw buka linknya buat streaming langsung bro!"
                echo -e "  ${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
                sleep 1
                
                local final_url="$user_input"
                # Bersihin prefix command
                final_url=$(echo "$final_url" | sed -E 's/^(tonton|nonton|stream|buka link|putar dari|putar langsung) *//i')

                local is_yt_music=0
                if [[ "$original_lower_input" == *"youtube music"* ]] || [[ "$original_lower_input" == *"yt music"* ]]; then
                    is_yt_music=1
                fi

                if [[ "$final_url" == *"ytsearch1:"* ]] || [[ "$final_url" == *"scsearch1:"* ]]; then
                    if command -v mpv >/dev/null 2>&1; then
                        mpv "$final_url" >/dev/null 2>&1 &
                        bot_prompt="Media lagi dimainin lewat mpv player bro! Asik dah."
                        continue
                    fi
                    
                    echo -e "  🤖 ${CYAN}${BOLD}Zaki-Bot:${RESET} ${WHITE}Lagi narik URL spesifiknya bro...${RESET}"
                    local fetched_url
                    fetched_url=$(yt-dlp --print webpage_url "$final_url" 2>/dev/null | grep "^http" | head -n 1)
                    if [ -n "$fetched_url" ]; then
                        final_url="$fetched_url"
                        if [ "$is_yt_music" -eq 1 ] && [[ "$final_url" == *"youtube.com/watch"* ]]; then
                            final_url="${final_url/www.youtube.com/music.youtube.com}"
                        fi
                    else
                        # Fallback jika gagal ekstrak URL
                        if [[ "$final_url" == *"scsearch1:"* ]]; then
                            final_url=$(echo "$final_url" | sed 's/scsearch1:/https:\/\/soundcloud.com\/search?q=/')
                        else
                            if [ "$is_yt_music" -eq 1 ]; then
                                final_url=$(echo "$final_url" | sed 's/ytsearch1:/https:\/\/music.youtube.com\/search?q=/')
                            else
                                final_url=$(echo "$final_url" | sed 's/ytsearch1:/https:\/\/www.youtube.com\/results?search_query=/')
                            fi
                        fi
                    fi
                else
                    if [ "$is_yt_music" -eq 1 ] && [[ "$final_url" == *"youtube.com/watch"* ]]; then
                        final_url="${final_url/www.youtube.com/music.youtube.com}"
                    fi
                fi

                if command -v termux-open >/dev/null 2>&1; then
                    termux-open "$final_url"
                    bot_prompt="Video udah gua puter di aplikasi YouTube HP lu bro!"
                elif command -v xdg-open >/dev/null 2>&1; then
                    xdg-open "$final_url" >/dev/null 2>&1 &
                    bot_prompt="Video udah gua buka di browser / app lu bro!"
                elif command -v mpv >/dev/null 2>&1; then
                    mpv "$final_url" >/dev/null 2>&1 &
                    bot_prompt="Lagi stream lewat mpv player bro!"
                else
                    bot_prompt="Yah bro, lu butuh app player (mpv) atau browser buat buka link langsung."
                fi
                continue
            fi
            if [[ "$lower_input" == *"spotify.com"* ]] || [[ "$lower_input" == *"spotsearch:"* ]]; then
                printf "  ${CYAN}║${RESET} 🤖 ${WHITE}%-45s${RESET} ${CYAN}║${RESET}\n" "Otw buka menu SEDOT SPOTIFY..."
                echo -e "  ${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
                sleep 1
                AUTO_DOWNLOAD_URL="$user_input"
                download_spotdl
                print_bot_header
                bot_prompt="Lagu Spotify udah kelar diproses bro! Mau sedot apa lagi?"
                
            elif [[ "$lower_input" == *"music.youtube.com"* ]]; then
                printf "  ${CYAN}║${RESET} 🤖 ${WHITE}%-45s${RESET} ${CYAN}║${RESET}\n" "Otw buka menu SEDOT YOUTUBE (Audio Mode)..."
                echo -e "  ${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
                sleep 1
                AUTO_DOWNLOAD_URL="$user_input"
                download_ytdlp
                print_bot_header
                bot_prompt="YT Music udah ditarik jadi M4A. Next mau apa?"
                
            else
                local vid_choice=""
                if [[ "$original_lower_input" == *"audio"* ]] || [[ "$original_lower_input" == *"lagu"* ]] || [[ "$original_lower_input" == *"mp3"* ]] || [[ "$original_lower_input" == *"suara"* ]] || [[ "$original_lower_input" == *"m4a"* ]]; then
                    vid_choice="1"
                elif [[ "$original_lower_input" == *"video"* ]] || [[ "$original_lower_input" == *"mp4"* ]] || [[ "$original_lower_input" == *"visual"* ]] || [[ "$original_lower_input" == *"gambar"* ]]; then
                    vid_choice="2"
                fi

                if [ -z "$vid_choice" ]; then
                    if [ "$is_smart_download" = "1" ]; then
                        vid_choice="1"
                    else
                        printf "  ${CYAN}║${RESET} 🤖 ${WHITE}%-45s${RESET} ${CYAN}║${RESET}\n" "Ini link media nih. Mau ambil apanya bro?"
                        printf "  ${CYAN}║${RESET}    ${WHITE}%-45s${RESET} ${CYAN}║${RESET}\n" "1. Audionya aja (Lagu/Sound/Podcast)"
                        printf "  ${CYAN}║${RESET}    ${WHITE}%-45s${RESET} ${CYAN}║${RESET}\n" "2. Videonya utuh (Terbaik)"
                        printf "  ${CYAN}║${RESET} 💬 ${BOLD}Lu (1/2) ❯ ${RESET}%-35s${CYAN}║${RESET}\n" ""
                        echo -e "  ${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
                        echo -en "\033[2A\033[20G"
                        read -r vid_choice || return 0
                        echo ""
                    fi
                fi
                
                local lower_vid_choice
                lower_vid_choice=$(echo "$vid_choice" | tr '[:upper:]' '[:lower:]')
                echo ""
                local clean_url
                clean_url=$(echo "$user_input" | sed -E 's/^(gas download audio|gas download video|download audio|download video|download|sedot) *//i')
                
                if [ "$vid_choice" = "1" ] || [[ "$lower_vid_choice" == *"audio"* ]] || [[ "$lower_vid_choice" == *"lagu"* ]]; then
                    AUTO_DOWNLOAD_URL="$clean_url"
                    LAST_DOWNLOAD_QUERY="$clean_url"
                    download_ytdlp
                    print_bot_header
                    bot_prompt="Audio dari medianya kelar diproses. Ada lagi?"
                elif [ "$vid_choice" = "2" ] || [[ "$lower_vid_choice" == *"video"* ]]; then
                    AUTO_DOWNLOAD_URL="$clean_url"
                    LAST_DOWNLOAD_QUERY="$clean_url"
                    download_video
                    print_bot_header
                    bot_prompt="Video berhasil diproses. Lanjut yang lain?"
                else
                    bot_prompt="Pilihan lu ga valid tadi bro. Coba paste ulang linknya."
                fi
            fi
        else
            # ----------------------------------
            # PERINTAH SISTEM / INTERNAL TOOLS
            # ----------------------------------
            if [[ "$lower_input" == "clear" ]] || [[ "$lower_input" == *"bersihkan layar"* ]] || [[ "$lower_input" == *"bersihkan chat"* ]] || [[ "$lower_input" == *"hapus chat"* ]] || [[ "$lower_input" == *"clear chat"* ]]; then
                print_bot_header
                bot_prompt="Layar udah gua bersihin bro biar ga pusing. Mau lanjut ngobrol apa nih?"
                continue
            elif [[ "$lower_input" == "matikan" ]] || [[ "$lower_input" == "stop" ]] || [[ "$lower_input" == "berhenti" ]] || [[ "$lower_input" == "matiin" ]] || [[ "$lower_input" == "stop lagu" ]] || [[ "$lower_input" == "matikan lagu" ]] || [[ "$lower_input" == "matikan musik" ]] || [[ "$lower_input" == "stop music" ]] || [[ "$lower_input" == "stop musik" ]]; then
                printf "  ${CYAN}║${RESET} 🤖 ${WHITE}%-45s${RESET} ${CYAN}║${RESET}\n" "Oke bro, lagu gua matiin..."
                echo -e "  ${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
                sleep 1
                if command -v termux-media-player >/dev/null 2>&1; then
                    termux-media-player stop >/dev/null 2>&1
                fi
                killall mpv ffplay play 2>/dev/null
                bot_prompt="Musik udah dimatiin bro. Lanjut ngapain nih?"
                continue
            elif [[ "$lower_input" == "putar" ]] || [[ "$lower_input" == "play" ]] || [[ "$lower_input" == "mainkan" ]] || [[ "$lower_input" == "putar lagu" ]] || [[ "$lower_input" == "play lagu" ]] || [[ "$lower_input" == "putar hasil" ]] || [[ "$lower_input" == "play lokal" ]] || [[ "$lower_input" == "putar lokal" ]] || [[ "$lower_input" == "play music" ]] || [[ "$lower_input" == "putar musik" ]]; then
                local latest_file
                latest_file=$(ls -t "${TARGET_DIR:-$(pwd)}"/*.{m4a,mp3,mp4,webm,mkv} 2>/dev/null | head -n 1)
                if [ -n "$latest_file" ]; then
                    printf "  ${CYAN}║${RESET} 🤖 ${WHITE}%-45s${RESET} ${CYAN}║${RESET}\n" "Otw muter lagunya bro..."
                    echo -e "  ${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
                    sleep 1
                    if command -v termux-media-player >/dev/null 2>&1; then
                        termux-media-player play "$latest_file" >/dev/null 2>&1 &
                    elif command -v mpv >/dev/null 2>&1; then
                        mpv "$latest_file" >/dev/null 2>&1 &
                    elif command -v ffplay >/dev/null 2>&1; then
                        ffplay -nodisp -autoexit "$latest_file" >/dev/null 2>&1 &
                    elif command -v play >/dev/null 2>&1; then
                        play "$latest_file" >/dev/null 2>&1 &
                    else
                        bot_prompt="Yah bro, lu butuh app player (mpv/termux-api) buat muter file ini."
                        continue
                    fi
                    bot_prompt="Lagu udah gua puter di latar belakang bro! Asik gak?"
                else
                    bot_prompt="Waduh, gua ga nemu file musik/video di folder lu bro."
                fi
                continue
            elif [[ "$lower_input" == "hapus vokal" ]] || [[ "$lower_input" == "remove vocal" ]] || [[ "$lower_input" == "hapus vocal" ]] || [[ "$lower_input" == "karaoke" ]] || [[ "$lower_input" == "pisahin vokal" ]]; then
                printf "  ${CYAN}║${RESET} 🤖 ${WHITE}%-45s${RESET} ${CYAN}║${RESET}\n" "Otw misahin vokal lagu terakhir pake AI..."
                echo -e "  ${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
                sleep 1
                local latest_file
                latest_file=$(ls -t "${TARGET_DIR:-$(pwd)}"/*.{m4a,mp3,mp4,webm,mkv,wav,flac} 2>/dev/null | head -n 1)
                if [ -n "$latest_file" ]; then
                    AUTO_HAPUS_VOKAL_MODE="2"
                    AUTO_HAPUS_VOKAL_PATH="$latest_file"
                    hapus_vokal
                    print_bot_header
                    bot_prompt="Beres bro! Vokal dari lagu barusan udah berhasil gua pisahin."
                else
                    bot_prompt="Waduh, belum ada lagu/video yang bisa gua pisahin vokalnya bro."
                fi
                continue
            elif [[ "$lower_input" == "download subtitle" ]] || [[ "$lower_input" == "ambil subtitle" ]] || [[ "$lower_input" == "sedot subtitle" ]] || [[ "$lower_input" == "download lirik" ]] || [[ "$lower_input" == "sinkron lirik" ]] || [[ "$lower_input" == "cari lirik" ]] || [[ "$lower_input" == "sync lirik" ]]; then
                printf "  ${CYAN}║${RESET} 🤖 ${WHITE}%-45s${RESET} ${CYAN}║${RESET}\n" "Otw nyariin lirik/subtitle otomatis bro..."
                echo -e "  ${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
                sleep 1
                AUTO_SYNC_LIRIK="1"
                auto_sync_lirik
                print_bot_header
                bot_prompt="Lirik/Subtitle berhasil dicariin bro! Cek aja di foldernya."
                continue
            elif [[ "$lower_input" == "hapus semua" ]] || [[ "$lower_input" == "bersihkan dir" ]] || [[ "$lower_input" == "bersihkan folder" ]] || [[ "$lower_input" == "kosongkan folder" ]] || [[ "$lower_input" == "kosongkan dir" ]]; then
                printf "  ${CYAN}║${RESET} 🤖 ${WHITE}%-45s${RESET} ${CYAN}║${RESET}\n" "Otw buka menu Hapus Semua (DANGER)..."
                echo -e "  ${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
                sleep 1
                hapus_semua
                print_bot_header
                bot_prompt="Proses hapus massal udah ditutup. Mau ngapain lagi nih?"
                continue
            elif [[ "$lower_input" == "hapus file" ]] || [[ "$lower_input" == "hapus lagu" ]] || [[ "$lower_input" == "buang lagu" ]] || [[ "$lower_input" == "delete file" ]] || [[ "$lower_input" == "hapus" ]]; then
                local latest_file
                latest_file=$(ls -t "${TARGET_DIR:-$(pwd)}"/*.{m4a,mp3,mp4,webm,mkv} 2>/dev/null | head -n 1)
                if [ -n "$latest_file" ]; then
                    rm -f "$latest_file"
                    bot_prompt="Beres bro! File $(basename "$latest_file" | cut -c 1-20)... udah gua buang ke tong sampah."
                else
                    bot_prompt="Gak ada file musik/video buat dihapus bro."
                fi
                continue
            elif [[ "$lower_input" == "buka folder" ]] || [[ "$lower_input" == "buka penyimpanan" ]] || [[ "$lower_input" == "lihat file" ]]; then
                if command -v termux-open >/dev/null 2>&1; then
                    termux-open "${TARGET_DIR:-$(pwd)}"
                elif command -v xdg-open >/dev/null 2>&1; then
                    xdg-open "${TARGET_DIR:-$(pwd)}" >/dev/null 2>&1 &
                elif command -v explorer.exe >/dev/null 2>&1; then
                    explorer.exe "$(wslpath -w "${TARGET_DIR:-$(pwd)}")" >/dev/null 2>&1 &
                fi
                bot_prompt="Foldernya udah gua bukain bro! Cek aja di pop-up layar lu."
                continue
            elif [[ "$lower_input" == "suara max" ]] || [[ "$lower_input" == "volume max" ]] || [[ "$lower_input" == "gedein suara" ]] || [[ "$lower_input" == "besarin suara" ]]; then
                if command -v termux-volume >/dev/null 2>&1; then
                    termux-volume music 15 >/dev/null 2>&1
                    bot_prompt="Volume udah gua pantengin rata kanan (MAX) bro! 🔊"
                else
                    bot_prompt="Yah bro, ngatur volume otomatis cuma bisa di Termux HP doang."
                fi
                continue
            elif [[ "$lower_input" == "suara min" ]] || [[ "$lower_input" == "volume min" ]] || [[ "$lower_input" == "kecilin suara" ]] || [[ "$lower_input" == "pelanin suara" ]]; then
                if command -v termux-volume >/dev/null 2>&1; then
                    termux-volume music 5 >/dev/null 2>&1
                    bot_prompt="Volume udah gua kecilin bro biar santuy. 🔉"
                else
                    bot_prompt="Yah bro, ngatur volume otomatis cuma bisa di Termux HP doang."
                fi
                continue
            elif [[ "$lower_input" == "bersih" ]] || [[ "$lower_input" == "rename" ]] || [[ "$lower_input" == "bersihkan nama" ]] || [[ "$lower_input" == "smart renamer" ]]; then
                printf "  ${CYAN}║${RESET} 🤖 ${WHITE}%-45s${RESET} ${CYAN}║${RESET}\n" "Lu mau bersihin nama? Otw Smart Renamer..."
                echo -e "  ${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
                sleep 1
                bersih_nama
                print_bot_header
                bot_prompt="Udah selesai bersihin file kan. Mau lanjut ngapain nih?"
            elif [[ "$lower_input" == "lirik" ]] || [[ "$lower_input" == "sync" ]] || [[ "$lower_input" == "cari lirik" ]] || [[ "$lower_input" == "download lirik" ]]; then
                printf "  ${CYAN}║${RESET} 🤖 ${WHITE}%-45s${RESET} ${CYAN}║${RESET}\n" "Oke bro, mari kita cari lirik lagu lu..."
                echo -e "  ${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
                sleep 1
                auto_sync_lirik
                print_bot_header
                bot_prompt="Pencarian lirik selesai. Lanjut apa lagi bos?"
            elif [[ "$lower_input" == "vokal" ]] || [[ "$lower_input" == "demucs" ]] || [[ "$lower_input" == "hapus vokal" ]]; then
                printf "  ${CYAN}║${RESET} 🤖 ${WHITE}%-45s${RESET} ${CYAN}║${RESET}\n" "Wih mau karaokean? Otw buka AI Demucs..."
                echo -e "  ${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
                sleep 1
                hapus_vokal
                print_bot_header
                bot_prompt="Mantap vokalnya udah misah. Ada request lain?"
            elif [[ "$lower_input" == "ubah storage" ]] || [[ "$lower_input" == "set storage" ]] || [[ "$lower_input" == "setting penyimpanan" ]] || [[ "$lower_input" == "seting penyimpanan" ]]; then
                printf "  ${CYAN}║${RESET} 🤖 ${WHITE}%-45s${RESET} ${CYAN}║${RESET}\n" "Otw buka menu Seting Penyimpanan..."
                echo -e "  ${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
                sleep 1
                setup_storage_dir
                print_bot_header
                bot_prompt="Sip, direktori penyimpanan udah di-update bro. Mau sedot apa lagi?"
            elif [[ "$lower_input" == "playlist" ]] || [[ "$lower_input" == "bikin playlist" ]] || [[ "$lower_input" == "buat playlist" ]]; then
                printf "  ${CYAN}║${RESET} 🤖 ${WHITE}%-45s${RESET} ${CYAN}║${RESET}\n" "Gaskeun bikin playlist m3u8 bos..."
                echo -e "  ${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
                sleep 1
                bikin_playlist
                print_bot_header
                bot_prompt="Playlist udah kelar dibikin. Apa lagi nih?"
            elif [[ "$lower_input" == "dokumentasi" ]] || [[ "$lower_input" == "panduan" ]] || [[ "$lower_input" == "bantuan" ]] || [[ "$lower_input" == "help" ]]; then
                printf "  ${CYAN}║${RESET} 🤖 ${WHITE}%-45s${RESET} ${CYAN}║${RESET}\n" "Siap bos! Otw buka buku panduan ZDT..."
                echo -e "  ${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
                sleep 1
                tampilkan_dokumentasi
                print_bot_header
                bot_prompt="Gimana bro, udah jelas kan panduannya? Ada lagi?"
            elif [[ "$lower_input" == "set api key" ]] || [[ "$lower_input" == "aktifkan ai" ]] || [[ "$lower_input" == "pasang otak" ]]; then
                printf "  ${CYAN}║${RESET} 🤖 ${WHITE}%-45s${RESET} ${CYAN}║${RESET}\n" "Wih mau upgrade otak? Masukin API Key lu:"
                printf "  ${CYAN}║${RESET}    ${GRAY}%-45s${RESET} ${CYAN}║${RESET}\n" "(Bisa pakai kunci Gemini atau OpenRouter)"
                printf "  ${CYAN}║${RESET} 💬 ${BOLD}Key: ❯ ${RESET}%-39s${CYAN}║${RESET}\n" ""
                echo -e "  ${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
                echo -en "\033[2A\033[16G"
                local new_key
                read -r new_key
                echo ""
                if [ -n "$new_key" ]; then
                    mkdir -p "$HOME/.config/zdt"
                    echo "$new_key" > "$gemini_key_file"
                    ZDT_GEMINI_KEY="$new_key"
                    bot_prompt="GILA BRO! Otak gua udah nyambung ke Gemini AI. Sekarang gua se-pinter lu! Tanya apa aja bebas."
                else
                    bot_prompt="Batal masukin kunci ya bro? Yaudah gapapa wkwk."
                fi
            elif [[ "$lower_input" == "cek update" ]] || [[ "$lower_input" == "perbarui aplikasi" ]] || [[ "$lower_input" == "update zdt" ]]; then
                printf "  ${CYAN}║${RESET} 🤖 ${WHITE}%-45s${RESET} ${CYAN}║${RESET}\n" "Otw ngecek update ke GitHub bentar bos..."
                echo -e "  ${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
                sleep 1
                update_zdt_script
                print_bot_header
                bot_prompt="Proses update selesai dieksekusi. Ada lagi bos?"
            elif [[ "$lower_input" == "hapus api key" ]] || [[ "$lower_input" == "reset api key" ]] || [[ "$lower_input" == "matikan ai" ]] || [[ "$lower_input" == "cabut otak" ]]; then
                printf "  ${CYAN}║${RESET} 🤖 ${WHITE}%-45s${RESET} ${CYAN}║${RESET}\n" "Yakin nih mau nyabut otak gua? (y/n)"
                printf "  ${CYAN}║${RESET} 💬 ${BOLD}Pilihan: ❯ ${RESET}%-35s${CYAN}║${RESET}\n" ""
                echo -e "  ${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
                echo -en "\033[2A\033[20G"
                local konfirmasi
                read -r konfirmasi
                echo ""
                if [[ "$konfirmasi" =~ ^[Yy]$ ]]; then
                    rm -f "$gemini_key_file"
                    ZDT_GEMINI_KEY=""
                    bot_prompt="Oke bro, API Key udah dihapus. Gua balik jadi bot bego lagi wkwk."
                else
                    bot_prompt="Sip, ga jadi dicabut. Kita tetep gaskeun bareng AI!"
                fi
            
            # ----------------------------------
            # NLP LOGIC (GEMINI AI ATAU LOKAL)
            # ----------------------------------
            elif [ -n "$ZDT_GEMINI_KEY" ]; then
                printf "  ${CYAN}║${RESET} 🤖 ${WHITE}%-45s${RESET} ${CYAN}║${RESET}\n" "Mikir bentar bro..."
                echo -e "  ${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
                echo -en "\033[2A\033[1G"
                
                local dir_contents
                dir_contents=$(ls -1 "${TARGET_DIR:-$(pwd)}" 2>/dev/null | head -n 20 | tr '\n' ', ' || echo "Kosong")
                
                local current_abs_path
                current_abs_path=$(_realpath "${TARGET_DIR:-$(pwd)}")
                
                local ai_response
                ai_response=$(python3 - "$ZDT_GEMINI_KEY" "$user_input" "$prev_bot_prompt" "$dir_contents" "$current_abs_path" "$APP_VERSION" << 'EOF'
import urllib.request, json, sys
try:
    key = sys.argv[1]
    user_msg = sys.argv[2]
    prev_msg = sys.argv[3] if len(sys.argv) > 3 else ""
    dir_contents = sys.argv[4] if len(sys.argv) > 4 else ""
    abs_path = sys.argv[5] if len(sys.argv) > 5 else ""
    app_version = sys.argv[6] if len(sys.argv) > 6 else ""
    prompt = f'Peranmu Zaki-Bot, asisten terminal gaul pada ZDT Music Toolkit versi {app_version}. Jika user ngobrol biasa, jawab santai max 3 kalimat. Info penting: Lokasi penyimpanan saat ini ada di "{abs_path}" dengan isi file: {dir_contents}. ATURAN SUPER PENTING: 1) Download AUDIO/LAGU (Youtube/Soundcloud) balas HANYA dgn: [AUTO_ACTION: gas download audio ytsearch1:judul lagu]. Gunakan LINK jika user ngasih link. 2) Download SPOTIFY balas HANYA dgn: [AUTO_ACTION: gas download spotify spotsearch:judul lagu]. 3) Download VIDEO balas HANYA dgn: [AUTO_ACTION: gas download video ytsearch1:judul]. 4) NONTON/PLAY/PUTAR balas HANYA dgn: [AUTO_ACTION: tonton ytsearch1:judul]. 5) Keluar/Tutup balas: [AUTO_ACTION: keluar]. 6) Pisahkan vokal/demucs balas: [AUTO_ACTION: hapus vokal]. 7) Cari Lirik balas: [AUTO_ACTION: sync lirik]. 8) Buat playlist balas: [AUTO_ACTION: bikin playlist]. 9) Rapikan/bersihkan nama file balas: [AUTO_ACTION: bersih nama]. 10) Ubah/seting direktori penyimpanan balas: [AUTO_ACTION: ubah storage]. 11) Cek update/perbarui aplikasi balas: [AUTO_ACTION: cek update]. Sistem akan jalankan otomatis.'
    
    if key.startswith("sk-or-"):
        url = "https://openrouter.ai/api/v1/chat/completions"
        headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
        messages = [{"role": "system", "content": prompt}]
        if prev_msg and prev_msg != "Mikir bentar bro...":
            messages.append({"role": "assistant", "content": prev_msg})
        messages.append({"role": "user", "content": user_msg})
        
        fallback_arrays = [
            ["meta-llama/llama-3.3-70b-instruct:free", "qwen/qwen3-next-80b-a3b-instruct:free", "google/gemma-4-31b-it:free"],
            ["nousresearch/hermes-3-llama-3.1-405b:free", "meta-llama/llama-3.2-3b-instruct:free", "openai/gpt-oss-120b:free"],
            ["liquid/lfm-2.5-1.2b-instruct:free", "openrouter/free"]
        ]
        text = ""
        import urllib.error
        for models in fallback_arrays:
            payload = {"models": models, "messages": messages, "max_tokens": 100}
            data = json.dumps(payload).encode("utf-8")
            req = urllib.request.Request(url, data=data, headers=headers)
            try:
                with urllib.request.urlopen(req, timeout=10) as response:
                    res = json.loads(response.read().decode())
                    if "error" in res:
                        text = f"API Error: {res['error'].get('message', 'Unknown')}"
                    else:
                        content = res.get("choices", [{}])[0].get("message", {}).get("content")
                        if content is None:
                            text = f"API Error (Kosong): {json.dumps(res)}"
                        else:
                            text = content.strip().replace("\n", " ")
                    break
            except urllib.error.HTTPError as e:
                err_msg = e.read().decode()
                text = f'Aduh koneksi otak AI gua lagi putus nih bro wkwk. Error: {err_msg}'
                if e.code == 429:
                    continue
                break
            except Exception as e:
                text = f'Aduh koneksi otak AI gua lagi putus nih bro wkwk. Error: {str(e)}'
                break
        print(text)
    else:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={key}"
        headers = {"Content-Type": "application/json"}
        contents = []
        if prev_msg and prev_msg != "Mikir bentar bro...":
            contents.append({"role": "model", "parts": [{"text": prev_msg}]})
        contents.append({"role": "user", "parts": [{"text": user_msg}]})
        payload = {"system_instruction": {"parts": [{"text": prompt}]}, "contents": contents, "generationConfig": {"maxOutputTokens": 100}}
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers=headers)
        with urllib.request.urlopen(req, timeout=10) as response:
            res = json.loads(response.read().decode())
            if "error" in res:
                print(f"API Error: {res['error'].get('message', 'Unknown')}")
            else:
                content = res.get("candidates", [{}])[0].get("content", {}).get("parts", [{}])[0].get("text")
                if content is None:
                    print(f"API Error (Kosong): {json.dumps(res)}")
                else:
                    print(content.strip().replace("\n", " "))
except Exception as e:
    import urllib.error
    err_msg = e.read().decode() if isinstance(e, urllib.error.HTTPError) else str(e)
    print(f'Aduh koneksi otak AI gua lagi putus nih bro wkwk. Error: {err_msg}')
EOF
)
                # Intercept Auto-Action dari AI buat "Terima Beres"
                if [[ "$ai_response" == *"[AUTO_ACTION:"* ]]; then
                    local auto_cmd=$(echo "$ai_response" | grep -o '\[AUTO_ACTION: [^]]*\]' | sed 's/\[AUTO_ACTION: //;s/\]//')
                    bot_prompt="Siap laksanakan bos! Tunggu bentar..."
                    next_user_input="$auto_cmd"
                    continue
                fi

                bot_prompt="$ai_response"
            
            else
                # Fallback Lokal kalau belum ada API Key
                if [[ "$lower_input" == *"ga mau"* ]] || [[ "$lower_input" == *"nggak mau"* ]] || [[ "$lower_input" == *"gak"* ]] || [[ "$lower_input" == *"tidak"* ]]; then
                    bot_prompt="Loh kok ga mau? Terus lu buka Zaki-Bot mau ngapain bos? Kita bisa sedot lagu, cari lirik, atau misahin vokal lho."
                elif [[ "$lower_input" == *"apa ya"* ]] || [[ "$lower_input" == *"bingung"* ]]; then
                    bot_prompt="Kalo bingung, cobain aja sedot lagu favorit lu dari Spotify, tinggal paste linknya ke sini."
                elif [[ "$lower_input" == *"kacau"* ]] || [[ "$lower_input" == *"rusak"* ]] || [[ "$lower_input" == *"error"* ]]; then
                    bot_prompt="Waduh kacau gimana nih? Coba jelasin bro, biar Zaki-Bot benerin!"
                elif [[ "$lower_input" == *"halo"* ]] || [[ "$lower_input" == *"hai"* ]] || [[ "$lower_input" == *"hei"* ]] || [[ "$lower_input" == *"bro"* ]] || [[ "$lower_input" == *"bos"* ]]; then
                    bot_prompt="Yoww bosku! Udah siap kerja nih, kasih link atau perintah dong wkwk."
                elif [[ "$lower_input" == *"assalamualaikum"* ]] || [[ "$lower_input" == *"samlekum"* ]]; then
                    bot_prompt="Waalaikumsalam bos! Ada yang bisa gua bantu hari ini?"
                elif [[ "$lower_input" == *"makasih"* ]] || [[ "$lower_input" == *"terima kasih"* ]] || [[ "$lower_input" == *"thanks"* ]] || [[ "$lower_input" == *"tengkyu"* ]]; then
                    bot_prompt="Yoi sama-sama bro! Santai aja, kan tugas gua emang ngebantu lu. Ada lagi?"
                elif [[ "$lower_input" == *"mantap"* ]] || [[ "$lower_input" == *"keren"* ]] || [[ "$lower_input" == *"gg"* ]] || [[ "$lower_input" == *"gila"* ]]; then
                    bot_prompt="Wkwkwk jelas dong, Zaki-Bot gitu loh! Lanjut nyedot apa nih kita?"
                elif [[ "$lower_input" == *"goblok"* ]] || [[ "$lower_input" == *"bego"* ]] || [[ "$lower_input" == *"tolol"* ]] || [[ "$lower_input" == *"jelek"* ]] || [[ "$lower_input" == *"anjing"* ]] || [[ "$lower_input" == *"njir"* ]]; then
                    bot_prompt="Woles bos wkwk, jangan ngegas ah. Mending kita lanjut sedot lagu aja yak?"
                elif [[ "$lower_input" == *"siapa"* ]] || [[ "$lower_input" == *"namamu"* ]] || [[ "$lower_input" == *"pembuat"* ]]; then
                    bot_prompt="Gua Zaki-Bot, asisten digital super canggih buatan bos Zaki sendiri! 🤖"
                elif [[ "$lower_input" == *"gimana"* ]] || [[ "$lower_input" == *"cara"* ]] || [[ "$lower_input" == *"bantu"* ]] || [[ "$lower_input" == *"help"* ]]; then
                    bot_prompt="Gini bro, lu tinggal copy link dari Youtube/Spotify/Tiktok terus paste di sini. Ntar gua urus sisanya!"
                elif [[ "$lower_input" == *"pinter"* ]] || [[ "$lower_input" == *"pintar"* ]] || [[ "$lower_input" == *"chatgpt"* ]] || [[ "$lower_input" == *"ai"* ]]; then
                    bot_prompt="Wkwkwk kalau lu pengen gua pinter beneran, ketik 'set api key' buat nyalain otak Gemini AI gua bro!"
                elif [[ "$lower_input" == *"lagu"* ]] || [[ "$lower_input" == *"audio"* ]] || [[ "$lower_input" == *"musik"* ]] || [[ "$lower_input" == *"mp3"* ]]; then
                    bot_prompt="Oh mau nyedot lagu? Cari lagunya di Spotify/YouTube, terus paste linknya ke sini bro."
                elif [[ "$lower_input" == *"video"* ]] || [[ "$lower_input" == *"mp4"* ]]; then
                    bot_prompt="Siap, mau nyedot video ya. Copy link dari YouTube/TikTok, terus paste di mari."
                elif [[ "$lower_input" == *"download"* ]] || [[ "$lower_input" == *"sedot"* ]] || [[ "$lower_input" == *"ambil"* ]]; then
                    bot_prompt="Langsung aja paste linknya (Youtube/Spotify/Tiktok) di sini bos!"
                else
                    local fallbacks=(
                        "Bro, otak AI gua belom nyala nih wkwk. Ketik 'set api key' kalo pengen gua mikir pinter!"
                        "Waduh gua kurang nangkep bro. Mending langsung paste link aja deh."
                        "Bahasanya agak rumit nih bos wkwk. Ketik 'set api key' dulu dong biar AI gua aktif."
                        "Njir ga ngerti gua wkwkwk. Langsung paste link aja bro!"
                        "Bro, gua ini cuma bot tukang sedot. Kalau pengen gua pinter, pasang AI dong! (Ketik: set api key)"
                        "Hmm... gua lagi loading nih nangkep maksud lu. Mending paste link YouTube aja deh."
                        "Wkwk sumpah gua bingung lu ngomong apa. Lu mau sedot video atau lagu nih?"
                        "Kalo lu pengen jawaban pinter, ketik 'set api key' terus masukin kunci Gemini lu bro!"
                        "Sabi sih bahasanya, tapi gua ga ngerti wkwk. Kasih link aja ya bos."
                        "Error 404: Maksud lu apa nih? Wkwk canda, aktifin otak AI gua gih (set api key)."
                    )
                    bot_prompt="${fallbacks[$((RANDOM % 10))]}"
                fi
            fi
        fi
    done
}

# ==========================================
# FUNGSI UTAMA: SETUP DIREKTORI PENYIMPANAN
# ==========================================
setup_storage_dir() {
    print_header "SETUP DIREKTORI PENYIMPANAN"

    local config_file
    config_file=$(_get_config_file)

    echo -e "  ${GRAY}Atur folder default tempat semua file musik disimpan.${RESET}"
    echo -e "  ${GRAY}Setting ini akan tersimpan permanen di config file.${RESET}"
    echo ""

    # Tampilkan status saat ini
    echo -e "  ${CYAN}${ICO_ARROW} STATUS SAAT INI${RESET}"
    if [ -n "$STORAGE_DIR" ]; then
        echo -e "    ${WHITE}Storage Dir :${RESET} ${GREEN}$STORAGE_DIR${RESET}"
        local dir_size
        dir_size=$(du -sh "$STORAGE_DIR" 2>/dev/null | cut -f1 || echo "?")
        local file_count
        file_count=$(find "$STORAGE_DIR" -type f \( -iname "*.m4a" -o -iname "*.mp3" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.ogg" \) 2>/dev/null | wc -l)
        echo -e "    ${WHITE}Ukuran      :${RESET} ${CYAN}$dir_size${RESET}"
        echo -e "    ${WHITE}Total Lagu  :${RESET} ${CYAN}$file_count file${RESET}"
    else
        echo -e "    ${WHITE}Storage Dir :${RESET} ${YELLOW}(belum diset — pakai direktori saat menjalankan script)${RESET}"
        echo -e "    ${WHITE}Aktif di    :${RESET} ${CYAN}$ROOT_DIR${RESET}"
    fi
    echo -e "    ${WHITE}Config File :${RESET} ${GRAY}$config_file${RESET}"
    echo ""

    echo -e "  ${CYAN}${ICO_ARROW} PILIH AKSI${RESET}"
    echo "    [1] Set path langsung (ketik manual)"
    echo "    [2] Pilih dari folder yang ada di sini"
    echo "    [3] Bikin folder baru & set sebagai default"
    echo "    [4] Reset ke default (pakai dir saat menjalankan)"
    echo "    [0] ${ICO_FAIL} Batal / Kembali"
    echo ""
    echo -e -n "  ${BOLD}[?] Pilihan [0-4]: ${RESET}"
    local aksi
    read -r -n 1 aksi
    echo ""

    case "$aksi" in
        0)
            echo -e "  ${YELLOW}${ICO_ARROW} Dibatalkan!${RESET}"
            return 0
            ;;

        1)
            # SET PATH MANUAL
            echo ""
            echo -e "  ${CYAN}${ICO_ARROW} MASUKKAN PATH DIREKTORI${RESET}"
            echo -e "  ${GRAY}Contoh: /home/user/Music, /sdcard/Music, ~/Downloads/Musik${RESET}"
            echo ""
            echo -e -n "  ${BOLD}[?] Path: ${RESET}"
            read -r input_path

            if [ -z "$input_path" ] || [ "$input_path" = "0" ]; then
                echo -e "  ${YELLOW}${ICO_ARROW} Dibatalkan!${RESET}"
                return 0
            fi

            # Expand ~ menjadi $HOME
            input_path="${input_path/#\~/$HOME}"

            # Buat folder jika belum ada
            if [ ! -d "$input_path" ]; then
                echo -e "  ${YELLOW}Folder belum ada. Buat sekarang?${RESET}"
                echo -e -n "  ${BOLD}[?] (y/n): ${RESET}"
                read -r -n 1 buat
                echo ""
                if [[ "$buat" =~ ^[Yy]$ ]]; then
                    if mkdir -p "$input_path" 2>/dev/null; then
                        echo -e "  ${GREEN}${ICO_OK} Folder berhasil dibuat!${RESET}"
                    else
                        echo -e "  ${RED}${ICO_FAIL} Gagal membuat folder! Cek permission.${RESET}"
                        return 1
                    fi
                else
                    echo -e "  ${YELLOW}${ICO_ARROW} Dibatalkan!${RESET}"
                    return 0
                fi
            fi

            # Validasi bisa ditulis
            if [ ! -w "$input_path" ]; then
                echo -e "  ${RED}${ICO_FAIL} Folder tidak bisa ditulis (permission denied)!${RESET}"
                return 1
            fi

            # Resolve ke absolute path
            local resolved_path
            resolved_path=$(_realpath "$input_path")

            STORAGE_DIR="$resolved_path"
            ROOT_DIR="$resolved_path"
            _config_set "storage_dir" "$resolved_path"

            echo -e "  ${GREEN}${ICO_OK} Storage dir berhasil diset ke:${RESET}"
            echo -e "  ${CYAN}  $resolved_path${RESET}"
            _log "INFO" "Storage dir set to: $resolved_path"
            ;;

        2)
            # PILIH DARI FOLDER YANG ADA
            echo ""
            echo -e "  ${CYAN}${ICO_ARROW} FOLDER DI LOKASI SAAT INI ($ROOT_DIR):${RESET}"

            local folder_list=()
            _safe_find_dirs folder_list "$ROOT_DIR"

            local count=${#folder_list[@]}
            if [ "$count" -eq 0 ]; then
                echo -e "  ${RED}${ICO_FAIL} Tidak ada subfolder di sini!${RESET}"
                return 0
            fi

            echo "    [0] ${ICO_FAIL} Batal"
            for ((i = 0; i < count; i++)); do
                local nama_f dir_sz
                nama_f=$(basename "${folder_list[$i]}")
                dir_sz=$(du -sh "${folder_list[$i]}" 2>/dev/null | cut -f1 || echo "?")
                printf "    [%d] %-30s %s\n" "$((i + 1))" "$nama_f" "($dir_sz)"
            done

            echo ""
            echo -e -n "  ${BOLD}[?] Pilih folder [0-$count]: ${RESET}"
            read -r folder_idx

            if [ "$folder_idx" = "0" ] || [ -z "$folder_idx" ]; then
                echo -e "  ${YELLOW}${ICO_ARROW} Dibatalkan!${RESET}"
                return 0
            fi

            if [[ "$folder_idx" =~ ^[0-9]+$ ]] && [ "$folder_idx" -ge 1 ] && [ "$folder_idx" -le "$count" ]; then
                local selected
                selected=$(_realpath "${folder_list[$((folder_idx - 1))]}")

                STORAGE_DIR="$selected"
                ROOT_DIR="$selected"
                _config_set "storage_dir" "$selected"

                echo -e "  ${GREEN}${ICO_OK} Storage dir berhasil diset ke:${RESET}"
                echo -e "  ${CYAN}  $selected${RESET}"
                _log "INFO" "Storage dir set to: $selected"
            else
                echo -e "  ${RED}${ICO_FAIL} Pilihan tidak valid!${RESET}"
            fi
            ;;

        3)
            # BIKIN FOLDER BARU
            echo ""
            echo -e "  ${CYAN}${ICO_ARROW} BUAT FOLDER BARU${RESET}"
            echo -e "  ${GRAY}Folder akan dibuat di: $ROOT_DIR${RESET}"
            echo ""
            echo -e -n "  ${BOLD}[?] Nama folder baru: ${RESET}"
            read -r nama_baru

            if [ -z "$nama_baru" ] || [ "$nama_baru" = "0" ]; then
                echo -e "  ${YELLOW}${ICO_ARROW} Dibatalkan!${RESET}"
                return 0
            fi

            # Sanitize nama folder
            nama_baru=$(echo "$nama_baru" | tr -cd '[:alnum:][:space:]_-.' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')
            if [ -z "$nama_baru" ]; then
                echo -e "  ${RED}${ICO_FAIL} Nama folder tidak valid!${RESET}"
                return 1
            fi

            local new_path="$ROOT_DIR/$nama_baru"

            if [ -d "$new_path" ]; then
                echo -e "  ${YELLOW}Folder sudah ada. Akan dipakai sebagai storage dir.${RESET}"
            else
                if mkdir -p "$new_path" 2>/dev/null; then
                    echo -e "  ${GREEN}${ICO_OK} Folder '$nama_baru' berhasil dibuat!${RESET}"
                else
                    echo -e "  ${RED}${ICO_FAIL} Gagal membuat folder!${RESET}"
                    return 1
                fi
            fi

            local resolved_new
            resolved_new=$(_realpath "$new_path")
            STORAGE_DIR="$resolved_new"
            ROOT_DIR="$resolved_new"
            _config_set "storage_dir" "$resolved_new"

            echo -e "  ${GREEN}${ICO_OK} Storage dir berhasil diset ke:${RESET}"
            echo -e "  ${CYAN}  $resolved_new${RESET}"
            _log "INFO" "Storage dir created and set to: $resolved_new"
            ;;

        4)
            # RESET KE DEFAULT
            echo ""
            if [ -z "$STORAGE_DIR" ]; then
                echo -e "  ${GRAY}Storage dir sudah dalam mode default.${RESET}"
                return 0
            fi

            echo -e "  ${YELLOW}${ICO_ARROW} Menghapus setting storage dir...${RESET}"
            _config_unset "storage_dir"
            STORAGE_DIR=""
            ROOT_DIR=$(pwd)

            echo -e "  ${GREEN}${ICO_OK} Reset berhasil! Sekarang pakai direktori saat menjalankan script.${RESET}"
            echo -e "  ${CYAN}  Aktif di: $ROOT_DIR${RESET}"
            _log "INFO" "Storage dir reset to default"
            ;;

        *)
            echo -e "  ${RED}${ICO_FAIL} Pilihan tidak valid!${RESET}"
            ;;
    esac
}

# ==========================================
# CLI ARGUMENT PARSING
# ==========================================
ORIGINAL_ARGS=("$@")

# Simpan path script absolut untuk restart (kalau pindah direktori)
if command -v realpath >/dev/null 2>&1; then
    SCRIPT_PATH=$(realpath "$0")
else
    SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
fi

install_global() {
    _setup_colors
    _setup_unicode
    _load_config
    echo -e "  ${CYAN}${ICO_ARROW} MENGINSTAL ZDT SECARA GLOBAL${RESET}"
    
    # Deteksi target folder (biasanya ~/.local/bin untuk user biasa, atau /usr/local/bin)
    local target_dir="$HOME/.local/bin"
    if [ "$(id -u)" -eq 0 ] && [ -n "${TERMUX_VERSION:-}" ] == false; then
        target_dir="/usr/local/bin"
    fi
    
    if [ -n "${TERMUX_VERSION:-}" ]; then
        target_dir="$PREFIX/bin"
    fi

    mkdir -p "$target_dir" 2>/dev/null

    local target_bin="$target_dir/zdt"
    
    # Menyalin file (bukan symlink agar aman jika folder asli terhapus)
    if cp "$SCRIPT_PATH" "$target_bin"; then
        chmod +x "$target_bin"
        echo -e "  ${GREEN}${ICO_OK} Berhasil menyalin ke: $target_bin${RESET}"
        
        # Buat Desktop entry jika di Linux GUI (bukan Termux/WSL)
        local os_name
        os_name=$(_get_os_name)
        if [[ ! "$os_name" =~ (Termux|Unknown) ]] && [ -d "$HOME/.local/share/applications" ]; then
            local desk_file="$HOME/.local/share/applications/zdt.desktop"
            cat > "$desk_file" <<EOF
[Desktop Entry]
Name=ZDT Music Toolkit
Comment=Universal Music Toolkit
Exec=$target_bin
Terminal=true
Type=Application
Categories=AudioVideo;Utility;
Icon=utilities-terminal
EOF
            chmod +x "$desk_file"
            echo -e "  ${GREEN}${ICO_OK} Desktop entry dibuat: ZDT Music Toolkit${RESET}"
        fi
        
        echo -e "  ${YELLOW}Pastikan direktori '$target_dir' ada di dalam PATH Anda.${RESET}"
        echo -e "  ${GREEN}Sekarang Anda bisa menjalankan perintah 'zdt' dari mana saja!${RESET}"
    else
        echo -e "  ${RED}${ICO_FAIL} Gagal menginstal. Coba jalankan dengan sudo jika perlu.${RESET}"
    fi
    exit 0
}

_parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --debug)
                ZDT_DEBUG=1
                set -x
                ;;
            --no-color)
                NO_COLOR=1
                ;;
            --no-unicode)
                NO_UNICODE=1
                ;;
            --download-audio)
                shift
                if [ -n "${1:-}" ]; then
                    AUTO_DOWNLOAD_URL="$1"
                    LAST_DOWNLOAD_QUERY="$1"
                    _setup_colors
                    _setup_unicode
                    if [[ "$1" == *"spotify.com"* ]]; then
                        download_spotdl
                    else
                        download_ytdlp
                    fi
                    exit 0
                fi
                ;;
            --download-video)
                shift
                if [ -n "${1:-}" ]; then
                    AUTO_DOWNLOAD_URL="$1"
                    LAST_DOWNLOAD_QUERY="$1"
                    _setup_colors
                    _setup_unicode
                    download_video
                    exit 0
                fi
                ;;
            --web|web)
                _setup_colors
                _setup_unicode
                start_web_dashboard
                exit 0
                ;;
            --install)
                install_global
                ;;
            update|--update)
                _setup_colors
                _setup_unicode
                update_zdt_script
                exit 0
                ;;
            --log-file)
                shift
                if [ -n "${1:-}" ]; then
                    LOG_FILE="$1"
                    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
                else
                    echo "Error: --log-file memerlukan path" >&2
                    exit 1
                fi
                ;;
            --version|-v)
                echo "$APP_NAME v$APP_VERSION"
                exit 0
                ;;
            --help|-h)
                cat <<HELPEOF
$APP_NAME v$APP_VERSION — Universal Music Toolkit

Usage: $APP_NAME [OPTIONS]

Options:
  --install         Instal script ini secara global (bisa diakses via perintah 'zdt')
  --update          Update script ZDT ke versi terbaru dari GitHub
  --debug           Aktifkan mode debug (verbose logging)
  --no-color        Nonaktifkan warna output
  --no-unicode      Nonaktifkan karakter unicode/emoji
  --log-file PATH   Tulis log ke file tertentu
  --version, -v     Tampilkan versi aplikasi
  --help, -h        Tampilkan bantuan ini

Fitur:
  1. Sedot Spotify               (spotdl)
  2. Sedot Audio YT/TikTok/dll   (yt-dlp)
  3. Sedot Video YT/TikTok/dll   (yt-dlp)
  4. Kompres Media Massal        (ffmpeg)
  5. Auto Sync Lirik             (syncedlyrics)
  6. Pembersih Nama File
  7. Generator Playlist (.m3u)
  8. Update Alat Tempur
  9. Info Sistem

Kompatibel: Linux, Termux, proot-distro, Alpine, WSL

HELPEOF
                exit 0
                ;;
            -*)
                echo "Error: Opsi tidak dikenal '$1'. Gunakan --help untuk daftar opsi." >&2
                exit 1
                ;;
            *)
                echo "Error: Argumen '$1' tidak valid di luar konteks opsi." >&2
                exit 1
                ;;
        esac
        shift
    done
}

# ==========================================
# MAIN MENU LOOP
# ==========================================
main() {
    # Parse arguments
    _parse_args "$@"

    # Inject VENV PATH agar eksekusi spotdl, yt-dlp, syncedlyrics selalu terarah ke VENV jika ada
    if [ -d "$ZDT_VENV_DIR/bin" ]; then
        export PATH="$ZDT_VENV_DIR/bin:$PATH"
    fi

    # Setup colors & unicode
    _setup_colors
    _setup_unicode

    # Detect environment
    RUNTIME_ENV=$(_detect_environment)

    # Auto Timezone Fix untuk PRoot Termux
    if [ "$RUNTIME_ENV" = "termux" ] && [ -z "$TZ" ]; then
        if [[ "$(date +%z)" == "+0000" || "$(date +%z)" == "-0000" || ! -f /etc/localtime ]]; then
            local tz_cache_file="$HOME/.config/zdt/timezone"
            if [ -f "$tz_cache_file" ]; then
                export TZ="$(cat "$tz_cache_file")"
            else
                local auto_tz
                auto_tz=$(curl -s --connect-timeout 2 "http://ip-api.com/line?fields=timezone" 2>/dev/null)
                if [ -n "$auto_tz" ] && [ "$auto_tz" != "fail" ] && [[ "$auto_tz" =~ "/" ]]; then
                    export TZ="$auto_tz"
                    mkdir -p "$HOME/.config/zdt"
                    echo "$auto_tz" > "$tz_cache_file"
                    _log "INFO" "Auto-set Timezone to $auto_tz via ip-api"
                fi
            fi
        fi
    fi

    # Set root dir
    ROOT_DIR=$(pwd)

    # Load storage dir dari config
    _load_storage_dir
    if [ -n "$STORAGE_DIR" ]; then
        ROOT_DIR="$STORAGE_DIR"
        cd "$ROOT_DIR" || {
            echo -e "  ${YELLOW}${ICO_WARN} Storage dir '$STORAGE_DIR' tidak bisa diakses, fallback ke $(pwd)${RESET}"
            ROOT_DIR=$(pwd)
            STORAGE_DIR=""
        }
    fi

    # Acquire lock
    if ! _acquire_lock; then
        exit 1
    fi

    # Setup traps
    trap _trap_ctrlc SIGINT
    trap _trap_exit EXIT

    # Start network ping loop
    export NET_TMP="/tmp/.zdt_net_$$.tmp"
    echo "Menghubungkan..." > "$NET_TMP"
    (
        while true; do
            if ms=$(ping -c 1 -W 1 1.1.1.1 2>/dev/null | grep -o 'time=[0-9.]*' | head -1 | cut -d= -f2 | cut -d. -f1); then
                [ -z "$ms" ] && ms="?"
                echo "Online (${ms}ms)" > "$NET_TMP"
            else
                echo "Offline" > "$NET_TMP"
            fi
            sleep 3
        done
    ) >/dev/null 2>&1 &
    export NET_PID=$!
    disown "$NET_PID" 2>/dev/null

    # Log startup
    _log "INFO" "Application started (v$APP_VERSION, env=$RUNTIME_ENV, storage=$ROOT_DIR)"

    # Auto-start Zaki Assistant as default landing page
    zaki_assistant

    # --- Persiapan Static ---
    local local_os
    local_os=$(_get_os_name)
    local_os="${local_os:0:38}"

    local local_user
    local_user=$(whoami 2>/dev/null | cut -c1-18 || echo "user")

    # Banner Text
    while true; do
        cd "$ROOT_DIR" || exit 1

        # Hitung Tool status
        local missing_tools=0
        local chk_s chk_y chk_f chk_l

        chk_s="${RED}${ICO_CHECK_FAIL}${RESET}"
        if command -v spotdl >/dev/null 2>&1; then
            chk_s="${GREEN}${ICO_CHECK_OK}${RESET}"
        else
            ((missing_tools++))
        fi

        chk_y="${RED}${ICO_CHECK_FAIL}${RESET}"
        if command -v yt-dlp >/dev/null 2>&1; then
            chk_y="${GREEN}${ICO_CHECK_OK}${RESET}"
        else
            ((missing_tools++))
        fi

        chk_f="${RED}${ICO_CHECK_FAIL}${RESET}"
        if command -v ffmpeg >/dev/null 2>&1; then
            chk_f="${GREEN}${ICO_CHECK_OK}${RESET}"
        else
            ((missing_tools++))
        fi

        chk_l="${RED}${ICO_CHECK_FAIL}${RESET}"
        if command -v syncedlyrics >/dev/null 2>&1; then
            chk_l="${GREEN}${ICO_CHECK_OK}${RESET}"
        else
            ((missing_tools++))
        fi

        # Demucs AI check (hanya di desktop)
        local chk_d=""
        if [ "$RUNTIME_ENV" != "termux" ]; then
            if [ -f "$HOME/.local/share/zdt/demucs_venv/bin/demucs" ]; then
                chk_d="${GREEN}${ICO_CHECK_OK}${RESET}"
            else
                chk_d="${RED}${ICO_CHECK_FAIL}${RESET}"
            fi
        fi



        local local_dir
        local_dir=$(basename "$PWD" | cut -c1-18)

        # Masuk ke alternate screen
        echo -ne "\033[?1049h\033[?25l\033[2J"

        local pilihan=""
        while true; do
            # --- Dynamic info ---
            local local_time local_uptime local_ram local_storage local_net
            local_time=$(date +"%H:%M:%S" 2>/dev/null || date '+%s')
            local_uptime=$(_get_uptime)
            local_uptime="${local_uptime:0:14}"
            local_ram=$(_get_ram_percent)
            [ -z "$local_ram" ] && local_ram="?"
            local_storage=$(_get_storage_percent)
            [ -z "$local_storage" ] && local_storage="?"
            
            local_net=$(cat "$NET_TMP" 2>/dev/null || echo "Menghitung...")

            # --- Build Frame ---
            local FRAME
            FRAME="\033[H\n"

            # ── Main Box (Cyberpunk Style, 50-char inner width) ──
            local btxt_ansi="    ${CYAN}Z Λ K I${RESET}   ${MAGENTA}D O W N L O Λ D Ξ R${RESET}   ${YELLOW}T O O L S${RESET}     "
            if [ -n "${NO_UNICODE:-}" ]; then
                btxt_ansi="    ${CYAN}Z A K I${RESET}   ${MAGENTA}D O W N L O A D E R${RESET}   ${YELLOW}T O O L S${RESET}     "
            fi

            FRAME+="  ${CYAN}╔══════════════════════════════════════════════════╗${RESET}\n"
            FRAME+="  ${CYAN}║${RESET}${BOLD}${btxt_ansi}${CYAN}║${RESET}\n"
            FRAME+="  ${CYAN}╠════════════════[ STATUS SISTEM ]═════════════════╣${RESET}\n"

            # ── System Info (printf -v on plain text only — no ANSI bugs) ──
            local pu pt pr pd pe pt_time po ps pnet
            printf -v pu "%-14s" "${local_user:0:14}"
            printf -v pt "%-12s" "${local_uptime:0:12}"
            printf -v pr "%-14s" "${local_ram}%"
            printf -v pd "%-12s" "${local_storage}%"
            printf -v pe "%-14s" "${RUNTIME_ENV:0:14}"
            printf -v pt_time "%-12s" "${local_time:0:12}"
            
            printf -v pnet "%-40s" "${local_net:0:40}"
            printf -v po "%-40s" "${local_os:0:40}"
            if [ -n "$STORAGE_DIR" ]; then
                printf -v ps "%-40s" "${STORAGE_DIR:0:40}"
            else
                printf -v ps "%-40s" "(direktori saat ini)"
            fi
            
            FRAME+="  ${CYAN}║${RESET} ${GRAY}USER   :${RESET} ${CYAN}${pu}${RESET}     ${GRAY}UPTIME :${RESET} ${CYAN}${pt}${RESET}${CYAN}║${RESET}\n"
            FRAME+="  ${CYAN}║${RESET} ${GRAY}RAM    :${RESET} ${YELLOW}${pr}${RESET}     ${GRAY}DISK   :${RESET} ${CYAN}${pd}${RESET}${CYAN}║${RESET}\n"
            FRAME+="  ${CYAN}║${RESET} ${GRAY}ENV    :${RESET} ${GREEN}${pe}${RESET}     ${GRAY}TIME   :${RESET} ${WHITE}${BOLD}${pt_time}${RESET}${CYAN}║${RESET}\n"
            FRAME+="  ${CYAN}║${RESET} ${GRAY}NET    :${RESET} ${CYAN}${pnet}${RESET}${CYAN}║${RESET}\n"
            FRAME+="  ${CYAN}║${RESET} ${GRAY}OS     :${RESET} ${CYAN}${po}${RESET}${CYAN}║${RESET}\n"
            FRAME+="  ${CYAN}║${RESET} ${GRAY}SAVE   :${RESET} ${MAGENTA}${ps}${RESET}${CYAN}║${RESET}\n"
            FRAME+="  ${CYAN}╟─────────────────[ ALAT TEMPUR ]──────────────────╢${RESET}\n"
            
            # The visible length of tools string is exactly 39 chars. Pad 11 spaces.
            local tools_str=" SpotDL[${chk_s}] YT-DLP[${chk_y}] FFmpeg[${chk_f}] Lirik[${chk_l}]"
            local p_tools="           "
            FRAME+="  ${CYAN}║${RESET}${WHITE}${tools_str}${RESET}${p_tools}${CYAN}║${RESET}\n"
            if [ -n "$chk_d" ]; then
                # "Demucs AI[x]" = 12 chars visible. 1 leading space = 13. Pad 37 spaces to fill 50.
                local demucs_pad="                                     "
                FRAME+="  ${CYAN}║${RESET}${WHITE} Demucs AI[${chk_d}${WHITE}]${RESET}${demucs_pad}${CYAN}║${RESET}\n"
            fi
            FRAME+="  ${CYAN}╠══════════════════[ MENU UTAMA ]══════════════════╣${RESET}\n"

            # ── Menu items (pure ASCII — no emoji, guaranteed alignment) ──
            local m1 m2 m3 m4 m5 m6 m7 m8 m9 mh ms mv mx emp
            printf -v m1 "%-20s" "Spotify"
            printf -v m6 "%-20s" "Bersih Nama"
            printf -v m2 "%-20s" "Audio (YT/Tk)"
            printf -v m7 "%-20s" "Bikin Playlist"
            printf -v m3 "%-20s" "Video (YT/Tk)"
            printf -v m8 "%-20s" "Update Tools"
            printf -v m4 "%-20s" "Kompres Media"
            printf -v m9 "%-20s" "Info Sistem"
            printf -v m5 "%-20s" "Sync Lirik"
            printf -v mh "%-20s" "Dokumentasi"
            printf -v ms "%-20s" "Setup Folder"
            printf -v mv "%-20s" "Hapus Vokal AI"
            printf -v mx "%-20s" "Hapus Semua"
            printf -v mw "%-20s" "Web Dashboard"
            printf -v mp "%-20s" "Spotify Sync"
            printf -v mm "%-20s" "Edit Metadata"
            printf -v emp "%-25s" ""

            FRAME+="  ${CYAN}║${RESET} ${WHITE}[1]${RESET} ${GREEN}${m1}${RESET} ${WHITE}[6]${RESET} ${WHITE}${m6}${RESET}${CYAN}║${RESET}\n"
            FRAME+="  ${CYAN}║${RESET} ${WHITE}[2]${RESET} ${RED}${m2}${RESET} ${WHITE}[7]${RESET} ${YELLOW}${m7}${RESET}${CYAN}║${RESET}\n"
            FRAME+="  ${CYAN}║${RESET} ${WHITE}[3]${RESET} ${MAGENTA}${m3}${RESET} ${WHITE}[8]${RESET} ${CYAN}${m8}${RESET}${CYAN}║${RESET}\n"
            FRAME+="  ${CYAN}║${RESET} ${WHITE}[4]${RESET} ${CYAN}${m4}${RESET} ${WHITE}[9]${RESET} ${WHITE}${m9}${RESET}${CYAN}║${RESET}\n"
            FRAME+="  ${CYAN}║${RESET} ${WHITE}[5]${RESET} ${MAGENTA}${m5}${RESET} ${WHITE}[H]${RESET} ${CYAN}${mh}${RESET}${CYAN}║${RESET}\n"
            FRAME+="  ${CYAN}╟──────────────────────────────────────────────────╢${RESET}\n"
            
            if [ "$RUNTIME_ENV" != "termux" ]; then
                FRAME+="  ${CYAN}║${RESET} ${WHITE}[S]${RESET} ${MAGENTA}${ms}${RESET} ${WHITE}[V]${RESET} ${GREEN}${mv}${RESET}${CYAN}║${RESET}\n"
                FRAME+="  ${CYAN}║${RESET} ${WHITE}[W]${RESET} ${CYAN}${mw}${RESET} ${WHITE}[P]${RESET} ${GREEN}${mp}${RESET}${CYAN}║${RESET}\n"
                FRAME+="  ${CYAN}║${RESET} ${WHITE}[M]${RESET} ${YELLOW}${mm}${RESET} ${WHITE}[X]${RESET} ${RED}${mx}${RESET}${CYAN}║${RESET}\n"
            else
                FRAME+="  ${CYAN}║${RESET} ${WHITE}[S]${RESET} ${MAGENTA}${ms}${RESET} ${WHITE}[X]${RESET} ${RED}${mx}${RESET}${CYAN}║${RESET}\n"
            fi

            if [ "$missing_tools" -gt 0 ]; then
                local ma
                printf -v ma "%-45s" "Auto Install Tools"
                FRAME+="  ${CYAN}║${RESET} ${WHITE}[A]${RESET} ${GREEN}${ma}${RESET}${CYAN}║${RESET}\n"
            fi
            
            local mz
            printf -v mz "%-45s" "ZDT AI Assistant (Smart Download)"
            FRAME+="  ${CYAN}║${RESET} ${WHITE}[Z]${RESET} ${YELLOW}${mz}${RESET}${CYAN}║${RESET}\n"

            local m0
            printf -v m0 "%-45s" "Keluar Aplikasi"
            FRAME+="  ${CYAN}║${RESET} ${WHITE}[0]${RESET} ${GRAY}${m0}${RESET}${CYAN}║${RESET}\n"
            FRAME+="  ${CYAN}╚══════════════════════════════════════════════════╝${RESET}\n"
            
            FRAME+="\n\033[J"
            FRAME+="  ${CYAN}${BOLD}❯ Silakan Pilih Menu : ${RESET}"

            # Render frame
            echo -ne "$FRAME"

            # Input handling
            read -s -r -t 1 -n 1 char 2>/dev/null
            local read_status=$?

            if [ "$read_status" -eq 0 ]; then
                # Filter escape sequences (arrow keys, etc.)
                if [[ "$char" == $'\e' ]]; then
                    # Flush remaining escape sequence bytes
                    read -s -r -t 0.05 -n 10 2>/dev/null || true
                    continue
                fi

                pilihan="$char"
                break
            fi
        done

        # Keluar alternate screen & restore cursor
        echo -ne "\033[?1049l\033[?25h"
        echo ""

        case "$pilihan" in
            1) download_spotdl ;;
            2) download_ytdlp ;;
            3) download_video ;;
            4) kompres_media ;;
            5) auto_sync_lirik ;;
            6) bersih_nama ;;
            7) bikin_playlist ;;
            8) update_tools ;;
            9) system_info ;;
            [Xx]) hapus_semua ;;
            [Ss]) setup_storage_dir ;;
            [Ww]) start_web_dashboard ;;
            [Pp]) sync_spotify_playlist ;;
            [Mm]) edit_metadata_manual ;;

            [Vv])
                if [ "$RUNTIME_ENV" != "termux" ]; then
                    hapus_vokal
                else
                    echo -e "  ${RED}${ICO_FAIL} Pilihan tidak valid!${RESET}"
                    sleep 1
                    continue
                fi
                ;;
            [Zz]) zaki_assistant ;;
            [Hh]) tampilkan_dokumentasi ;;
            [Aa])
                if [ "$missing_tools" -gt 0 ]; then
                    install_missing_tools
                else
                    echo -e "  ${RED}${ICO_FAIL} Pilihan tidak valid!${RESET}"
                    sleep 1
                    continue
                fi
                ;;
            0)
                trap - SIGINT
                printf '\033c'
                echo -e "  ${GREEN}${ICO_OK} Keluar ke Terminal. Sampai jumpa!${RESET}"
                echo ""
                exit 0
                ;;
            "") continue ;;
            *)
                echo -e "  ${RED}${ICO_FAIL} Pilihan tidak valid!${RESET}"
                sleep 1
                continue
                ;;
        esac

        # Pause setelah aksi
        if [[ "$pilihan" =~ ^[1-9XxAaSsVv]$ ]]; then
            _pause
        fi
    done
}

# ==========================================
# ENTRYPOINT
# ==========================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi