# ==========================================
# ZDT Core Module
# ==========================================
# Constants, Configuration, Colors, Logging,
# Portability Layer, Lockfile, Signal Traps
# ==========================================

# ==========================================
# CONSTANTS
# ==========================================
# APP_VERSION is defined in the main zdt.sh entrypoint
readonly APP_NAME="Zaki Downloader Tools"
readonly ZDT_VENV_DIR="$HOME/.local/share/zdt/venv"
readonly ZDT_CONFIG_FILE="$HOME/.config/zdt/config.env"
CONF_AUDIO_CODEC="1"
CONF_AUDIO_BITRATE="1"
CONF_VIDEO_CODEC="2"
CONF_VIDEO_QUAL="1"
CONF_VIDEO_FMT="4"

# Global Variables Initialization (Strict Mode Safe)
AUTO_DOWNLOAD_URL=""
AUTO_MODE=""
AUTO_FORMAT_SPEC=""
AUTO_BITRATE=""
ZDT_AUTO_KOMPRES=""
ZDT_AUTO_VOKAL=""
AUTO_SYNC_LIRIK=""
ZDT_AUTO_BERSIH=""
ZDT_AUTO_PLAYLIST=""
LAST_DOWNLOAD_QUERY=""
STORAGE_DIR=""
TARGET_DIR=""
AUTO_HAPUS_VOKAL_MODE=""
AUTO_HAPUS_VOKAL_PATH=""
WEB_BIND="127.0.0.1"

# Initialize UI variables to prevent unbound errors under set -u
GREEN='' CYAN='' MAGENTA='' WHITE='' GRAY=''
RED='' YELLOW='' BOLD='' RESET=''
ICO_OK="" ICO_FAIL="" ICO_WARN="" ICO_ARROW="" ICO_MUSIC="" ICO_GEAR=""
ICO_SEARCH="" ICO_LIST="" ICO_CUT="" ICO_UPDATE="" ICO_DANGER="" ICO_ROCKET=""
ICO_EXIT="" ICO_PLAY="" ICO_CHECK_OK="" ICO_CHECK_FAIL=""
_load_config() {
    if [ -f "$ZDT_CONFIG_FILE" ]; then
        # Safe parser: read key=value pairs without shell evaluation (prevents RCE via config injection)
        while IFS='=' read -r key value; do
            # Trim leading and trailing whitespace from key
            key="${key#"${key%%[![:space:]]*}"}"
            key="${key%"${key##*[![:space:]]}"}"
            # Skip comments, empty keys, or keys with invalid characters
            [[ -z "$key" || "$key" == \#* || "$key" != [a-zA-Z_]* ]] && continue
            # Strip surrounding quotes from value
            value="${value%\"}" && value="${value#\"}"
            value="${value%\'}" && value="${value#\'}"
            # Assign safely using printf -v (no shell expansion)
            printf -v "$key" "%s" "$value" 2>/dev/null || true
        done < "$ZDT_CONFIG_FILE"
    fi
}

_save_config() {
    mkdir -p "$(dirname "$ZDT_CONFIG_FILE")" 2>/dev/null
    _config_set "CONF_AUDIO_CODEC" "$CONF_AUDIO_CODEC"
    _config_set "CONF_AUDIO_BITRATE" "$CONF_AUDIO_BITRATE"
    _config_set "CONF_VIDEO_CODEC" "$CONF_VIDEO_CODEC"
    _config_set "CONF_VIDEO_QUAL" "$CONF_VIDEO_QUAL"
    _config_set "CONF_VIDEO_FMT" "$CONF_VIDEO_FMT"
}

# ==========================================
# PORTABILITY LAYER
# ==========================================

# Deteksi environment
_detect_environment() {
    if [ -n "${TERMUX_VERSION:-}" ] || { [ -n "${PREFIX:-}" ] && [[ "${PREFIX:-}" == */com.termux/* ]]; }; then
        echo "termux"
    elif [ -f /etc/alpine-release ]; then
        echo "alpine"
    elif grep -qi microsoft /proc/version 2>/dev/null; then
        echo "wsl"
    elif [ -f /.dockerenv ] || grep -q 'docker\|lxc' /proc/1/cgroup 2>/dev/null; then
        echo "container"
    elif grep -qi 'android' /proc/version 2>/dev/null || uname -a | grep -qi 'android'; then
        if [ -d "/usr/share" ] && [ -d "/usr/bin" ]; then
            echo "linux"
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
    echo "${target#./}"
}

# Portable memory usage
_get_ram_percent() {
    if command -v free >/dev/null 2>&1; then
        free 2>/dev/null | awk '/Mem:/ {if($2>0) printf "%.0f", $3/$2*100; else print "?"}' 2>/dev/null
        return
    fi
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
_safe_find_dirs() {
    local -n _result_arr=$1
    local search_path="$2"
    _result_arr=()
    if find --version 2>&1 | grep -q 'GNU' 2>/dev/null; then
        while IFS= read -r -d '' dir; do
            _result_arr+=("$dir")
        done < <(find "$search_path" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
    else
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
            # Keep up to 5 rotated logs, compressed
            if [ -f "${LOG_FILE}.4.gz" ]; then mv "${LOG_FILE}.4.gz" "${LOG_FILE}.5.gz" 2>/dev/null || true; fi
            if [ -f "${LOG_FILE}.3.gz" ]; then mv "${LOG_FILE}.3.gz" "${LOG_FILE}.4.gz" 2>/dev/null || true; fi
            if [ -f "${LOG_FILE}.2.gz" ]; then mv "${LOG_FILE}.2.gz" "${LOG_FILE}.3.gz" 2>/dev/null || true; fi
            if [ -f "${LOG_FILE}.1.gz" ]; then mv "${LOG_FILE}.1.gz" "${LOG_FILE}.2.gz" 2>/dev/null || true; fi
            if [ -f "${LOG_FILE}.old" ]; then
                gzip -c "${LOG_FILE}.old" > "${LOG_FILE}.1.gz" 2>/dev/null || true
                rm -f "${LOG_FILE}.old" 2>/dev/null || true
            fi
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

# ==========================================
# LOCKFILE PROTECTION
# ==========================================
LOCK_FILE="/tmp/.zdt_sh_$(id -u 2>/dev/null || echo 0).lock"

_acquire_lock() {
    # Use flock on a lock file descriptor for atomic locking
    if ! command -v flock >/dev/null 2>&1; then
        # Fallback: PID file with check (non-atomic but better than nothing)
        if [ -f "$LOCK_FILE" ]; then
            local old_pid
            old_pid=$(cat "$LOCK_FILE" 2>/dev/null)
            if [ -n "$old_pid" ] && [ "$old_pid" != "$$" ] && kill -0 "$old_pid" 2>/dev/null; then
                echo -e "  ${RED}${ICO_FAIL} Instance lain sedang berjalan (PID: $old_pid)!${RESET}"
                echo -e "  ${YELLOW}Tutup dulu instance tersebut, atau hapus: $LOCK_FILE${RESET}"
                return 1
            fi
            rm -f "$LOCK_FILE"
        fi
        echo $$ > "$LOCK_FILE"
        return 0
    fi
    
    # Atomic flock-based locking
    exec 200>"$LOCK_FILE" 2>/dev/null || true
    if ! flock -n 200 2>/dev/null; then
        echo -e "  ${RED}${ICO_FAIL} Instance lain sedang berjalan!${RESET}"
        echo -e "  ${YELLOW}Tutup instance lain atau tunggu hingga selesai.${RESET}"
        return 1
    fi
    echo $$ >&200
    return 0
}

_release_lock() {
    if command -v flock >/dev/null 2>&1; then
        flock -u 200 2>/dev/null || true
    fi
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
    # Consolidated: semua komponen (Bash, web, Telegram) pakai satu file config.env
    echo "$(_get_config_dir)/config.env"
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

# Tulis value ke config file (portable, atomic via tmp+mv)
_config_set() {
    local key="$1"
    local value="$2"
    local config_dir config_file
    config_dir=$(_get_config_dir)
    config_file=$(_get_config_file)

    mkdir -p "$config_dir" 2>/dev/null

    if command -v flock >/dev/null 2>&1; then
        local lock_fd=200
        eval "exec $lock_fd>\"${config_file}.lock\"" 2>/dev/null
        flock -w 5 $lock_fd 2>/dev/null || true
    fi

    # Atomic write: read entire file, modify, write back — all inside lock scope
    if [ -f "$config_file" ]; then
        # Use mktemp for safe temp file (prevents symlink attacks & race conditions)
        local tmp_file
        tmp_file=$(mktemp "${TMPDIR:-/tmp}/zdt_config_XXXXXX" 2>/dev/null || echo "/tmp/zdt_config_$$")
        # Baca file di dalam lock, tulis key baru, lalu mv atomic
        grep -v "^${key}=" "$config_file" > "$tmp_file" 2>/dev/null || true
        echo "${key}=${value}" >> "$tmp_file"
        mv -- "$tmp_file" "$config_file"
    else
        echo "${key}=${value}" > "$config_file"
    fi
    # Secure config file permission: hanya owner yang bisa baca
    chmod 600 "$config_file" 2>/dev/null || true

    if command -v flock >/dev/null 2>&1; then
        eval "exec 200>-" 2>/dev/null
    fi
}

# Hapus key dari config (portable, atomic via tmp+mv)
_config_unset() {
    local key="$1"
    local config_file
    config_file=$(_get_config_file)

    if [ -f "$config_file" ]; then
        if command -v flock >/dev/null 2>&1; then
            local lock_fd=200
            eval "exec $lock_fd>\"${config_file}.lock\"" 2>/dev/null
            flock -w 5 $lock_fd 2>/dev/null || true
        fi

        local tmp_file
        tmp_file=$(mktemp "${TMPDIR:-/tmp}/zdt_config_XXXXXX" 2>/dev/null || echo "/tmp/zdt_config_$$")
        grep -v "^${key}=" "$config_file" > "$tmp_file" 2>/dev/null || true
        mv -- "$tmp_file" "$config_file"

        if command -v flock >/dev/null 2>&1; then
            eval "exec 200>-" 2>/dev/null
        fi
    fi
}

# Load dan validasi storage dir dari config
_load_storage_dir() {
    local saved_dir
    saved_dir=$(_config_get "storage_dir" "")

    # Fallback: coba baca dari old config file untuk backward compatibility
    if [ -z "$saved_dir" ]; then
        local old_config="$(_get_config_dir)/config"
        if [ -f "$old_config" ]; then
            saved_dir=$(grep "^storage_dir=" "$old_config" 2>/dev/null | head -1 | cut -d'=' -f2-)
            # Strip quotes
            saved_dir="${saved_dir%\"}" && saved_dir="${saved_dir#\"}"
            saved_dir="${saved_dir%\'}" && saved_dir="${saved_dir#\'}"
        fi
    fi

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
# UI CACHE SYSTEM (Terminal Rendah Optimization)
# ==========================================
# Reduce redundant system calls in main loop by caching
# values that don't change frequently.
# ==========================================

# UI Cache timestamps
_ZDT_CACHE_TIME_STATS=0
_ZDT_CACHE_TIME_TOOLS=0
_ZDT_CACHE_TIME_SYS=0

# Cached values
_ZDT_CACHED_RAM=""
_ZDT_CACHED_UPTIME=""
_ZDT_CACHED_STORAGE=""
_ZDT_CACHED_OS_NAME=""
_ZDT_CACHED_KERNEL=""
_ZDT_CACHED_ARCH=""
_ZDT_CACHED_USER=""
_ZDT_CACHED_PKGS=""
_ZDT_CACHED_LOAD=""
_ZDT_CACHED_TEMP=""
_ZDT_CACHED_CPU=""
_ZDT_CACHED_FFMPEG=""
_ZDT_CACHED_PYTHON3=""
_ZDT_CACHED_YTDLP=""
_ZDT_CACHED_SPOTDL=""
_ZDT_CACHED_DEMUCS=""
_ZDT_CACHED_MUTAGEN=""
_ZDT_CACHED_TOOLS_STR=""

# Initialize cache: run once at session start
_init_ui_cache() {
    local now
    now=$(date +%s 2>/dev/null || echo 0)

    # Refresh all caches
    _ZDT_CACHE_TIME_STATS=$now
    _ZDT_CACHED_RAM=$(_get_ram_percent)
    _ZDT_CACHED_UPTIME=$(_get_uptime)
    _ZDT_CACHED_STORAGE=$(_get_storage_percent)

    _ZDT_CACHE_TIME_SYS=$now
    _ZDT_CACHED_OS_NAME=$(_get_os_name)
    _ZDT_CACHED_KERNEL=$(uname -r 2>/dev/null | cut -d'-' -f1,2 || echo "N/A")
    _ZDT_CACHED_ARCH=$(uname -m 2>/dev/null || echo "N/A")
    _ZDT_CACHED_USER=$(whoami 2>/dev/null || echo "user")
    _ZDT_CACHED_PKGS=$(dpkg-query -f '.\n' -W 2>/dev/null | wc -l || echo 0)
    _ZDT_CACHED_LOAD=$(cat /proc/loadavg 2>/dev/null | awk '{print $1" "$2" "$3}' || echo "N/A")
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        _ZDT_CACHED_TEMP="$(($(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null) / 1000))°C"
    else
        _ZDT_CACHED_TEMP="N/A"
    fi
    _ZDT_CACHED_CPU=$(grep 'cpu ' /proc/stat 2>/dev/null | awk '{print ($2+$4)*100/($2+$4+$5)}' | cut -d. -f1 || echo "?")

    _ZDT_CACHE_TIME_TOOLS=$now
    _ZDT_CACHED_FFMPEG=$(command -v ffmpeg >/dev/null 2>&1 && echo "1" || echo "0")
    _ZDT_CACHED_PYTHON3=$(command -v python3 >/dev/null 2>&1 && echo "1" || echo "0")
    _ZDT_CACHED_YTDLP=$(command -v yt-dlp >/dev/null 2>&1 && echo "1" || echo "0")
    _ZDT_CACHED_SPOTDL=$(command -v spotdl >/dev/null 2>&1 && echo "1" || echo "0")
    _ZDT_CACHED_DEMUCS=$([ -f "$HOME/.local/share/zdt/demucs_venv/bin/demucs" ] && echo "1" || echo "0")
    # Mutagen check: cache result (heavy Python import)
    if [ -f "$HOME/.local/share/zdt/venv/bin/python" ]; then
        "$HOME/.local/share/zdt/venv/bin/python" -c "import mutagen" >/dev/null 2>&1 && _ZDT_CACHED_MUTAGEN="1" || _ZDT_CACHED_MUTAGEN="0"
    else
        _ZDT_CACHED_MUTAGEN="0"
    fi

    # Build tools status string (for desktop & mobile views)
    _ZDT_CACHED_TOOLS_STR=""
    for _t_status in "$_ZDT_CACHED_FFMPEG" "$_ZDT_CACHED_PYTHON3" "$_ZDT_CACHED_YTDLP" "$_ZDT_CACHED_SPOTDL"; do
        if [ "$_t_status" = "1" ]; then
            _ZDT_CACHED_TOOLS_STR="${_ZDT_CACHED_TOOLS_STR}${GREEN}${ICO_CHECK_OK}${RESET} "
        else
            _ZDT_CACHED_TOOLS_STR="${_ZDT_CACHED_TOOLS_STR}${RED}${ICO_CHECK_FAIL}${RESET} "
        fi
    done
}

# Refresh fast-changing stats (RAM, uptime, storage, CPU)
# CPU and load use TTL (2s) since they need awk computation
_refresh_stats_cache() {
    local now
    now=$(date +%s 2>/dev/null || echo 0)
    local elapsed=$(( now - _ZDT_CACHE_TIME_STATS ))

    # Fast /proc reads — always refresh
    _ZDT_CACHED_RAM=$(_get_ram_percent)
    _ZDT_CACHED_UPTIME=$(_get_uptime)
    _ZDT_CACHED_STORAGE=$(_get_storage_percent)

    # CPU & load — refresh max every 2 seconds (save awk/grep)
    if [ "$elapsed" -ge 2 ] || [ "$_ZDT_CACHE_TIME_STATS" -eq 0 ]; then
        _ZDT_CACHED_LOAD=$(cat /proc/loadavg 2>/dev/null | awk '{print $1" "$2" "$3}' || echo "N/A")
        _ZDT_CACHED_CPU=$(grep 'cpu ' /proc/stat 2>/dev/null | awk '{print ($2+$4)*100/($2+$4+$5)}' | cut -d. -f1 || echo "?")
        _ZDT_CACHE_TIME_STATS=$now
    fi
}

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
    cd "$ROOT_DIR" || true
    _release_lock
    # Jangan restart aplikasi — biarkan fungsi yang terinterupsi selesai
    # lalu kembali ke main loop secara alami. Subprocess (yt-dlp, ffmpeg) sudah di-kill oleh sinyal.
}

_trap_exit() {
    [ -n "$NET_PID" ] && kill -9 "$NET_PID" 2>/dev/null
    [ -n "$NET_TMP" ] && rm -f "$NET_TMP" 2>/dev/null
    echo -ne "\033[?1049l\033[?25h"
    _release_lock
}

# ==========================================
# ==========================================
# UI HELPERS: PADDING & BORDERS
# ==========================================
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

# ==========================================
# HELPER: PRINT HEADER
# ==========================================
print_header() {
    if [ -z "${NO_COLOR:-}" ]; then
        echo -ne "\033[?25h"
        clear
    fi
    echo ""
    local cols=$(tput cols 2>/dev/null || echo 80)
    local width=$(( cols - 4 ))
    [ "$width" -lt 50 ] && width=50
    [ "$width" -gt 76 ] && width=76

    local title=" $1 "
    local title_pad=$(_pad_str "$title" $width)

    echo -e "  ${CYAN}╭$(_repeat_char '─' $width)╮${RESET}"
    echo -e "  ${CYAN}│${RESET}${MAGENTA}${BOLD}${title_pad}${RESET}${CYAN}│${RESET}"
    echo -e "  ${CYAN}╰$(_repeat_char '─' $width)╯${RESET}"
    echo ""
}

# ==========================================
# HELPER: PRINT MENU BOX
# ==========================================
_print_menu_box() {
    local title="$1"
    shift
    local options=("$@")

    local cols=$(tput cols 2>/dev/null || echo 80)
    local width=$(( cols - 4 ))
    [ "$width" -lt 50 ] && width=50
    [ "$width" -gt 76 ] && width=76

    local title_pad=$(_pad_str " ${MAGENTA}${BOLD}■ ${title}${RESET}" $width)

    echo -e "  ${CYAN}╭$(_repeat_char '─' $width)╮${RESET}"
    echo -e "  ${CYAN}│${RESET}${title_pad}${CYAN}│${RESET}"
    echo -e "  ${CYAN}├$(_repeat_char '─' $width)┤${RESET}"

    for opt in "${options[@]}"; do
        if [ "$opt" = "DIVIDER" ]; then
            echo -e "  ${CYAN}├$(_repeat_char '─' $width)┤${RESET}"
        else
            local opt_pad=$(_pad_str "   $opt" $width)
            echo -e "  ${CYAN}│${RESET}${opt_pad}${CYAN}│${RESET}"
        fi
    done
    echo -e "  ${CYAN}╰$(_repeat_char '─' $width)╯${RESET}"
}

# ==========================================
# HELPER: PAUSE BEFORE RETURN TO MENU
# ==========================================
_pause() {
    echo ""
    while read -s -r -t 0.01 -n 1000 2>/dev/null; do :; done
    echo -e -n "  ${GRAY}[ Tekan tombol apa aja untuk kembali ke menu... ]${RESET}"
    read -s -r -n 1 2>/dev/null || read -r -n 1 2>/dev/null || true
    echo ""
}
