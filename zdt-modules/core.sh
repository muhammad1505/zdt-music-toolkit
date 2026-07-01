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
# ZDT_VENV_DIR dan ZDT_CONFIG_FILE didefinisikan di helpers.sh (di-source setelah core.sh)
# Fallback pattern untuk akses sebelum helpers.sh: ${ZDT_VENV_DIR:-$HOME/.local/share/zdt/venv}
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
RED='' YELLOW='' BOLD='' RESET='' DIM=''
BLUE='' ORANGE='' PURPLE=''
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
            # Skip comments, empty keys, or keys with invalid characters/untrusted prefixes
            [[ -z "$key" || "$key" == \#* ]] && continue
            [[ ! "$key" =~ ^(CONF_|ZDT_|TELEGRAM_|AUTO_|storage_dir|LAST_)[a-zA-Z0-9_]*$ ]] && continue
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
    # Termux native: env vars
    if [ -n "${TERMUX_VERSION:-}" ]; then echo "termux"; return; fi
    if [ -n "${PREFIX:-}" ] && [[ "${PREFIX:-}" == */com.termux/* ]]; then echo "termux"; return; fi

    # Proot: executable path (readlink /proc/self/exe menunjukkan path Termux asli)
    if [ -L /proc/self/exe ] 2>/dev/null; then
        local _exe
        _exe=$(readlink /proc/self/exe 2>/dev/null)
        if [[ "$_exe" == */com.termux/* ]] || [[ "$_exe" == */data/data/* ]]; then
            echo "termux"; return
        fi
    fi

    # Android kernel: Termux native + proot
    if grep -qi 'android' /proc/version 2>/dev/null || uname -a | grep -qi 'android' 2>/dev/null; then
        echo "termux"; return
    fi
    # Android system paths (bind-mounted di proot)
    if [ -d /system/app ] || [ -f /system/build.prop ]; then
        echo "termux"; return
    fi

    # Proot Debian: deteksi Android via karakteristik lain
    # Beberapa proot setup tidak punya /system tapi masih Android
    # Cek /sdcard atau /storage/emulated — khas Android, bukan Linux biasa
    if [ -d /sdcard ] || [ -d /storage/emulated ]; then
        echo "termux"; return
    fi
    # Cek SELinux context spesifik Android (bukan SELinux generic)
    if [ -f /proc/self/attr/current ] && grep -q 'u:r:' /proc/self/attr/current 2>/dev/null; then
        echo "termux"; return
    fi
    # Cek uname -o untuk Android (fallback)
    if [ "$(uname -o 2>/dev/null)" = "Android" ]; then
        echo "termux"; return
    fi

    if [ -f /etc/alpine-release ]; then echo "alpine"; return; fi
    if grep -qi microsoft /proc/version 2>/dev/null; then echo "wsl"; return; fi
    if [ -f /.dockerenv ] || grep -q 'docker\|lxc' /proc/1/cgroup 2>/dev/null; then echo "container"; return; fi

    echo "linux"
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
# ── Terminal Color Detection ──
_ZDT_HAS_TRUECOLOR=0
_detect_truecolor() {
    if [ "${NO_COLOR:-0}" = "1" ] || [ ! -t 1 ]; then
        _ZDT_HAS_TRUECOLOR=0
        return
    fi
    case "${COLORTERM:-}" in
        truecolor|24bit) _ZDT_HAS_TRUECOLOR=1 ;;
        *) _ZDT_HAS_TRUECOLOR=0 ;;
    esac
}

# ── Semantic Color System ──
# Semantic slots: define intent, not appearance
# Usage: _clr <slot> [format]
#   slot: fg.default, fg.muted, fg.emphasis, bg.base, bg.surface, bg.overlay,
#         bg.selection, accent.primary, accent.secondary,
#         status.error, status.warning, status.success, status.info,
#         brand, brand.subtle
#   format: --fg (default), --bg, --bold, --dim, --reset
_ZDT_CLR_CACHE=""
_clr() {
    local slot="$1"
    local fmt="${2:---fg}"
    if [ "$fmt" = "--reset" ]; then
        echo -ne "\033[0m"
        return
    fi
    if [ "${NO_COLOR:-0}" = "1" ] || [ ! -t 1 ]; then
        return
    fi
    case "$slot" in
        fg.default)       echo -ne "\033[0;37m";;
        fg.muted)         echo -ne "\033[2;37m";;
        fg.emphasis)      echo -ne "\033[1;37m";;
        bg.base)          [ "$fmt" = "--bg" ] && echo -ne "\033[40m" || echo -ne "\033[0;37m";;
        bg.surface)       [ "$fmt" = "--bg" ] && echo -ne "\033[44m" || echo -ne "\033[0;37m";;
        bg.overlay)       [ "$fmt" = "--bg" ] && echo -ne "\033[45m" || echo -ne "\033[0;37m";;
        bg.selection)     [ "$fmt" = "--bg" ] && echo -ne "\033[46m" || echo -ne "\033[0;37m";;
        accent.primary)   echo -ne "\033[1;36m";;
        accent.secondary) echo -ne "\033[1;35m";;
        status.error)     echo -ne "\033[1;31m";;
        status.warning)   echo -ne "\033[1;33m";;
        status.success)   echo -ne "\033[1;32m";;
        status.info)      echo -ne "\033[1;34m";;
        brand)            echo -ne "\033[1;33m";;
        brand.subtle)     echo -ne "\033[0;33m";;
        *)                echo -ne "\033[0m";;
    esac
}

# ── Traditional Color Variables (backward compatible) ──
_setup_colors() {
    _detect_truecolor
    if [ "${NO_COLOR:-0}" = "1" ] || [ ! -t 1 ]; then
        GREEN='' CYAN='' MAGENTA='' WHITE='' GRAY=''
        RED='' YELLOW='' BOLD='' RESET='' DIM=''
        BLUE='' ORANGE='' PURPLE=''
    elif [ "$_ZDT_HAS_TRUECOLOR" = "1" ]; then
        # Truecolor palette — Cyberpunk Neon
        GREEN='\033[38;2;0;255;128m'
        CYAN='\033[38;2;0;200;255m'
        MAGENTA='\033[38;2;255;64;255m'
        WHITE='\033[38;2;224;224;224m'
        GRAY='\033[38;2;128;128;160m'
        RED='\033[38;2;255;48;80m'
        YELLOW='\033[38;2;255;220;64m'
        BLUE='\033[38;2;64;160;255m'
        ORANGE='\033[38;2;255;160;0m'
        PURPLE='\033[38;2;200;128;255m'
        DIM='\033[2m'
        BOLD='\033[1m'
        RESET='\033[0m'
    else
        # 16/256 ANSI fallback — works on all terminals
        GREEN='\033[1;32m'
        CYAN='\033[1;36m'
        MAGENTA='\033[1;35m'
        WHITE='\033[1;37m'
        GRAY='\033[0;37m'
        RED='\033[1;31m'
        YELLOW='\033[1;33m'
        BLUE='\033[1;34m'
        ORANGE='\033[0;33m'
        PURPLE='\033[1;35m'
        DIM='\033[2m'
        BOLD='\033[1m'
        RESET='\033[0m'
    fi
    # Resolve border colors after color variables are set
    _ZDT_BORDER_PRIMARY="${CYAN}"
    _ZDT_BORDER_SECONDARY="${DIM}${BLUE}"
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
    local config_dir config_file lock_fd
    config_dir=$(_get_config_dir)
    config_file=$(_get_config_file)

    mkdir -p "$config_dir" 2>/dev/null

    if command -v flock >/dev/null 2>&1; then
        exec {lock_fd}>"${config_file}.lock" 2>/dev/null
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
        eval "exec $lock_fd>-" 2>/dev/null
    fi
}

# Hapus key dari config (portable, atomic via tmp+mv)
_config_unset() {
    local key="$1"
    local config_file lock_fd
    config_file=$(_get_config_file)

    if [ -f "$config_file" ]; then
        if command -v flock >/dev/null 2>&1; then
            exec {lock_fd}>"${config_file}.lock" 2>/dev/null
            flock -w 5 $lock_fd 2>/dev/null || true
        fi

        local tmp_file
        tmp_file=$(mktemp "${TMPDIR:-/tmp}/zdt_config_XXXXXX" 2>/dev/null || echo "/tmp/zdt_config_$$")
        grep -v "^${key}=" "$config_file" > "$tmp_file" 2>/dev/null || true
        mv -- "$tmp_file" "$config_file"

        if command -v flock >/dev/null 2>&1; then
            eval "exec $lock_fd>-" 2>/dev/null
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

# UI Cache timestamps — separate per metric to prevent timer starvation
_ZDT_CACHE_TIME_STATS=0    # CPU & Load (3s interval)
_ZDT_CACHE_TIME_SYS=0      # System info (static, refresh once)
_ZDT_CACHE_TIME_RAM=0      # RAM, Uptime, Storage (5s interval)
_ZDT_CACHE_TIME_TOOLS=0    # Tools status (not used dynamically)

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
    local now=${EPOCHSECONDS:-$(date +%s 2>/dev/null || echo 0)}

    # Refresh all caches with separate timestamps
    _ZDT_CACHE_TIME_RAM=$now
    _ZDT_CACHED_RAM=$(_get_ram_percent)
    _ZDT_CACHED_UPTIME=$(_get_uptime)
    _ZDT_CACHED_STORAGE=$(_get_storage_percent)

    _ZDT_CACHE_TIME_STATS=$now
    _ZDT_CACHE_TIME_SYS=$now
    _ZDT_CACHED_OS_NAME=$(_get_os_name)
    _ZDT_CACHED_KERNEL=$(uname -r 2>/dev/null | cut -d'-' -f1,2 || echo "N/A")
    _ZDT_CACHED_ARCH=$(uname -m 2>/dev/null || echo "N/A")
    _ZDT_CACHED_USER=$(whoami 2>/dev/null || echo "user")
    _ZDT_CACHED_PKGS=$(grep -c '^Package:' /var/lib/dpkg/status 2>/dev/null || dpkg-query -f '.\n' -W 2>/dev/null | wc -l || echo 0)
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
    _ZDT_CACHED_DEMUCS=$([ -f "${ZDT_DEMUCS_BIN:-$HOME/.local/share/zdt/demucs_venv/bin/demucs}" ] && echo "1" || echo "0")
    # Mutagen: file existence check (no Python fork)
    local _mu_venv="${ZDT_VENV_DIR:-$HOME/.local/share/zdt/venv}"
    _ZDT_CACHED_MUTAGEN="0"
    for _mu_p in "$_mu_venv/lib/python3."*/site-packages/mutagen/__init__.py; do
        [ -f "$_mu_p" ] && { _ZDT_CACHED_MUTAGEN="1"; break; }
    done

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
# All metrics use TTL to avoid forking on every menu loop
_refresh_stats_cache() {
    local now=${EPOCHSECONDS:-$(date +%s 2>/dev/null || echo 0)}
    local elapsed_ram=$(( now - _ZDT_CACHE_TIME_RAM ))
    local elapsed_cpu=$(( now - _ZDT_CACHE_TIME_STATS ))

    # RAM, uptime, storage — refresh max every 5 seconds (independent timer)
    if [ "$elapsed_ram" -ge 5 ] || [ "$_ZDT_CACHE_TIME_RAM" -eq 0 ]; then
        _ZDT_CACHED_RAM=$(_get_ram_percent)
        _ZDT_CACHED_UPTIME=$(_get_uptime)
        _ZDT_CACHED_STORAGE=$(_get_storage_percent)
        _ZDT_CACHE_TIME_RAM=$now
    fi

    # CPU & load — refresh max every 3 seconds (independent timer)
    if [ "$elapsed_cpu" -ge 3 ] || [ "$_ZDT_CACHE_TIME_STATS" -eq 0 ]; then
        _ZDT_CACHED_LOAD=$(cat /proc/loadavg 2>/dev/null | awk '{print $1" "$2" "$3}' || echo "N/A")
        _ZDT_CACHED_CPU=$(grep 'cpu ' /proc/stat 2>/dev/null | awk '{print ($2+$4)*100/($2+$4+$5)}' | cut -d. -f1 || echo "?")
        _ZDT_CACHE_TIME_STATS=$now
    fi
}

# ==========================================
# SERVICE STATUS (Live process detection)
# ==========================================
_get_service_status() {
    local web_stat="OFF" tele_stat="OFF" watch_stat="OFF"
    pgrep -f "zdt-web.py" >/dev/null 2>&1 && web_stat="ON"
    pgrep -f "zdt-telegram.py" >/dev/null 2>&1 && tele_stat="ON"
    pgrep -f "zdt-watch.py" >/dev/null 2>&1 && watch_stat="ON"
    echo "${web_stat}|${tele_stat}|${watch_stat}"
}

# ==========================================
# RECENT DOWNLOADS (SQLite-backed)
# ==========================================
_get_recent_downloads() {
    local db_path="${STORAGE_DIR:-$HOME/Music/ZDT}/.zdt.db"
    local db_helper="${_MODULES_DIR:-.}/zdt_db.py"
    if [ -f "$db_path" ] && [ -f "$db_helper" ] && command -v python3 >/dev/null 2>&1; then
        python3 "$db_helper" "$db_path" "get_recent" "3" 2>/dev/null || echo "[]"
    else
        echo "[]"
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
    echo -ne "\033[?25h"
    _release_lock
}

# SIGWINCH handler — triggered on terminal resize
_ZDT_WINCH=0
_trap_winch() {
    _ZDT_WINCH=1
}

# Set up all signal traps
_setup_traps() {
    trap '_trap_ctrlc' SIGINT
    trap '_trap_exit' EXIT
    trap '_trap_winch' SIGWINCH
    if [ "${ZDT_DEBUG:-0}" = "1" ]; then
        set -o errtrace
        trap '_trap_err $LINENO $?' ERR
    fi
}

# ==========================================
# ==========================================
# UI HELPERS: PADDING & BORDERS
# ==========================================
# Normalize ANSI escapes: convert literal \033 to ESC byte
_esc() {
    printf '%s' "$1" | sed 's/\\033/\x1b/g'
}

_strip_ansi() {
    sed -r 's/\x1B\[[0-9;]*[a-zA-Z]//g; s/\x1B[(][0-9;]*[a-zA-Z]//g'
}

_pad_str() {
    local raw="$1"
    local width="$2"
    # Normalize: convert literal \033 → ESC byte so string is consistent
    local str
    str=$(_esc "$raw")
    local plain
    plain=$(printf '%s' "$str" | _strip_ansi)
    local len=${#plain}
    local pad=$((width - len))
    if [ "$pad" -lt 0 ]; then
        printf '%s' "${plain:0:$width}"
    else
        printf '%s%*s' "$str" "$pad" ""
    fi
}

_repeat_char() {
    local char="$1"
    local count="$2"
    local res=""
    local i
    for ((i=0; i<count; i++)); do
        res="${res}${char}"
    done
    echo -n "$res"
}

# ==========================================
# HELPER: DRAW PROGRESS BAR (Enhanced)
# ==========================================
# Draw a visual progress bar with optional color gradient
# Usage: _draw_bar <percentage> [width] [color_var] [show_label]
# Example: _draw_bar 45 10 "$YELLOW" true
_draw_bar() {
    local pct=$1
    local width=${2:-10}
    local color="${3:-}"
    local show_label="${4:-true}"
    
    # Clamp percentage
    [ "$pct" -lt 0 ] && pct=0
    [ "$pct" -gt 100 ] && pct=100
    
    # Auto-color by threshold if no color specified
    if [ -z "$color" ]; then
        if [ "$pct" -gt 90 ]; then color="$RED"
        elif [ "$pct" -gt 70 ]; then color="$YELLOW"
        elif [ "$pct" -gt 40 ]; then color="$CYAN"
        else color="${GREEN}"
        fi
    fi
    
    local filled=$(( pct * width / 100 ))
    [ "$filled" -lt 0 ] && filled=0
    [ "$filled" -gt "$width" ] && filled=$width
    local empty=$(( width - filled ))

    local bar_chars=""
    if [ "${NO_UNICODE:-0}" = "1" ]; then
        bar_chars="$(_repeat_char '#' "$filled")$(_repeat_char '-' "$empty")"
    else
        # Gradient blocks: █ for high, ▓ for mid, ▒ for low, ░ for empty
        local g=""
        local i
        for ((i=0; i<filled; i++)); do
            local rel=$(( (i + 1) * 100 / width ))
            if [ "$rel" -gt 75 ]; then g="${g}█"
            elif [ "$rel" -gt 50 ]; then g="${g}▓"
            elif [ "$rel" -gt 25 ]; then g="${g}▒"
            else g="${g}░"
            fi
        done
        bar_chars="$g$(_repeat_char '░' "$empty")"
    fi
    
    local pct_str="$(printf '%3s' "${pct}%")"
    # Use printf to avoid echo -e inconsistencies with captured output
    printf '%s%s%s %s%s%s' "$color" "$bar_chars" "$RESET" "$DIM" "$pct_str" "$RESET"
}

# ==========================================
# HELPER: ANIMATED SPINNER (Enhanced)
# ==========================================
# Usage: _zdt_spinner <pid> [message]
# Enhanced version with multiple frame sets
_zdt_spinner() {
    local pid=$1
    local msg="${2:-Processing...}"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  %s %s  " "${frames[$i]}" "$msg"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.12
    done
    printf "\r%*s\r" "$(( ${#msg} + 6 ))" ""
}

# ==========================================
# HELPER: TOAST NOTIFICATION
# ==========================================
# Display a brief auto-dismissing notification
# Usage: _toast <type> <message>
# type: ok, fail, warn, info
_toast() {
    local type="$1"
    shift
    local msg="$*"
    local icon=""
    local color=""
    case "$type" in
        ok)   icon="${ICO_OK}"; color="${GREEN}" ;;
        fail) icon="${ICO_FAIL}"; color="${RED}" ;;
        warn) icon="${ICO_WARN}"; color="${YELLOW}" ;;
        info) icon="${ICO_ARROW}"; color="${CYAN}" ;;
        *)    icon="*"; color="${WHITE}" ;;
    esac
    echo -e "  ${color}${icon}${RESET} ${msg}"
}

# ==========================================
# HELPER: SECTION HEADER
# ==========================================
# Draw a section header with optional accent color
# Usage: _draw_section <title> [color]
_draw_section() {
    local title="$1"
    local color="${2:-$YELLOW}"
    local cols=$(tput cols 2>/dev/null || echo 80)
    local width=$(( cols - 4 ))
    [ "$width" -lt 30 ] && width=30
    [ "$width" -gt 80 ] && width=80
    local title_str=" ${color}${BOLD}■${RESET} ${BOLD}${title}${RESET}"
    local pad=$(_pad_str "$title_str" "$width")
    echo -e "  ${DIM}${color}╭${RESET}${pad}${DIM}${color}╮${RESET}"
}

# ==========================================
# HELPER: BADGE
# ==========================================
# Draw a labeled badge
# Usage: _draw_badge <label> <value> [value_color]
_draw_badge() {
    local label="$1"
    local value="$2"
    local vcolor="${3:-$WHITE}"
    echo -n "${DIM}${label}${RESET} ${vcolor}${value}${RESET}"
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

    local title="$1"
    local subtitle="${2:-}"
    
    # Top border
    echo -e "  ${YELLOW}╔$(_repeat_char '═' $width)╗${RESET}"

    # Title line
    local title_disp=" ${BOLD}${title}${RESET}"
    if [ -n "$subtitle" ]; then
        title_disp=" ${BOLD}${title}${RESET} ${GRAY}— ${subtitle}${RESET}"
    fi
    local title_pad=$(_pad_str "$title_disp" $width)
    echo -e "  ${YELLOW}║${RESET}${title_pad}${YELLOW}║${RESET}"

    # Separator between caption and content
    echo -e "  ${YELLOW}╠$(_repeat_char '═' $width)╣${RESET}"
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

    # Title with bullet
    local title_disp=" ${BOLD}${title}${RESET}"
    local title_pad=$(_pad_str "$title_disp" $width)

    echo -e "  ${YELLOW}╔$(_repeat_char '═' $width)╗${RESET}"
    echo -e "  ${YELLOW}║${RESET}${title_pad}${YELLOW}║${RESET}"
    echo -e "  ${YELLOW}╠$(_repeat_char '═' $width)╣${RESET}"

    for opt in "${options[@]}"; do
        if [ "$opt" = "DIVIDER" ]; then
            echo -e "  ${YELLOW}╠$(_repeat_char '═' $width)╣${RESET}"
        else
            local opt_pad=$(_pad_str " $opt" $width)
            echo -e "  ${YELLOW}║${RESET}${opt_pad}${YELLOW}║${RESET}"
        fi
    done
    echo -e "  ${YELLOW}╚$(_repeat_char '═' $width)╝${RESET}"
}

# ==========================================
# SPLIT-PANE DRAWING HELPERS (Enhanced)
# ==========================================
# Status dot: on/warn/off with semantic colors
_draw_status_dot() {
    local state="$1"
    local size="${2:-normal}"
    local on_char="●"
    local off_char="○"
    local warn_char="●"
    # Use same chars for both sizes — avoids ambiguous-width rendering
    :
    case "$state" in
        on)   echo -e "${GREEN}${on_char}${RESET}" ;;
        warn) echo -e "${YELLOW}${warn_char}${RESET}" ;;
        off)  echo -e "${RED}${off_char}${RESET}" ;;
    esac
}

# Status badge: colored pill label
_draw_status_badge() {
    local label="$1"
    local state="$2"
    local color
    case "$state" in
        on)    color="$GREEN" ;;
        warn)  color="$YELLOW" ;;
        off)   color="$RED" ;;
        info)  color="$CYAN" ;;
        brand) color="$YELLOW" ;;
        *)     color="$GRAY" ;;
    esac
    echo -e "${DIM}[${RESET}${color}${label}${RESET}${DIM}]${RESET}"
}

# Split-pane frame characters — resolved via function so they reflect the
# current value of YELLOW/DIM/WHITE after _setup_colors() is called.
_ZDT_BORDER_PRIMARY=""  # placeholder, reassigned in _setup_colors
_ZDT_BORDER_SECONDARY=""  # placeholder, reassigned in _setup_colors

_draw_split_top() {
    local lw=$1 rw=$2
    echo -e "  ${_ZDT_BORDER_PRIMARY}╔$(_repeat_char '═' $lw)╦$(_repeat_char '═' $rw)╗${RESET}"
}

_draw_split_row() {
    local ltxt="$1" rtxt="$2" lw=$3 rw=$4
    local lp rp
    lp=$(_pad_str "$ltxt" "$lw")
    rp=$(_pad_str "$rtxt" "$rw")
    echo -e "  ${_ZDT_BORDER_PRIMARY}║${RESET}${lp}${_ZDT_BORDER_PRIMARY}║${RESET}${rp}${_ZDT_BORDER_PRIMARY}║${RESET}"
}

_draw_split_sep() {
    local lw=$1 rw=$2
    echo -e "  ${_ZDT_BORDER_PRIMARY}╠$(_repeat_char '═' $lw)╬$(_repeat_char '═' $rw)╣${RESET}"
}

_draw_split_bottom() {
    local lw=$1 rw=$2
    echo -e "  ${_ZDT_BORDER_PRIMARY}╚$(_repeat_char '═' $lw)╩$(_repeat_char '═' $rw)╝${RESET}"
}

# ==========================================
# SINGLE BOX DRAWING HELPERS
# ==========================================
_draw_box_top() {
    local width=$1
    echo -e "  ${_ZDT_BORDER_PRIMARY}╔$(_repeat_char '═' $width)╗${RESET}"
}

_draw_box_row() {
    local text="$1" width=$2
    local pad=$(_pad_str "$text" "$width")
    echo -e "  ${_ZDT_BORDER_PRIMARY}║${RESET}${pad}${_ZDT_BORDER_PRIMARY}║${RESET}"
}

_draw_box_sep() {
    local width=$1
    echo -e "  ${_ZDT_BORDER_PRIMARY}╠$(_repeat_char '═' $width)╣${RESET}"
}

_draw_box_bottom() {
    local width=$1
    echo -e "  ${_ZDT_BORDER_PRIMARY}╚$(_repeat_char '═' $width)╝${RESET}"
}

# ==========================================
# HELP OVERLAY
# ==========================================
# Draw a contextual help overlay (triggered by ? key)
_draw_help_overlay() {
    local cols=$(tput cols 2>/dev/null || echo 80)
    local lines=$(tput lines 2>/dev/null || echo 24)
    local width=$(( cols - 8 ))
    [ "$width" -lt 50 ] && width=50
    [ "$width" -gt 70 ] && width=70
    local height=16
    local top_pad=$(( (lines - height) / 2 ))
    
    # Clear area and position overlay in center
    local i
    for ((i=0; i<top_pad; i++)); do echo ""; done
    
    _draw_box_top $width
    _draw_box_row " ${BOLD}${YELLOW}◈${RESET} ${BOLD}ZDT Help${RESET} ${DIM}— Keyboard Shortcuts${RESET}" $width
    _draw_box_sep $width
    
    local keys=(
        "${CYAN}[1-9]${RESET} Main menu actions"
        "${CYAN}[A]${RESET}    Zaki AI assistant"
        "${CYAN}[S]${RESET}    Storage setup"
        "${CYAN}[W]${RESET}    Watch daemon"
        "${CYAN}[T]${RESET}    Telegram bot"
        "${CYAN}[V]${RESET}    Web dashboard"
        "${CYAN}[P]${RESET}    Playlist manager"
        "${CYAN}[M]${RESET}    Metadata editor"
        "${CYAN}[O]${RESET}    Clean file names"
        "${CYAN}[R]${RESET}    Uninstall"
        "${CYAN}[U]${RESET}    Update"
        "${CYAN}[X]${RESET}    Delete all"
        "${CYAN}[0]${RESET}    Exit / Quit"
        "${CYAN}[?]${RESET}    This help overlay"
    )
    for key_entry in "${keys[@]}"; do
        _draw_box_row "  ${key_entry}" $width
    done
    
    _draw_box_sep $width
    _draw_box_row " ${DIM}Press any key to close${RESET}" $width
    _draw_box_bottom $width
    
    read -s -r -n 1 2>/dev/null || read -r -n 1 2>/dev/null || true
}

# ==========================================
# FOOTER DRAWING (Context-sensitive)
# ==========================================
# Draw a compact footer bar showing available shortcuts
# Usage: _draw_footer <inner_width> [shortcut pairs...]
# Example: _draw_footer 50 "0" "Exit" "?" "Help"
_draw_footer() {
    local width=$1
    shift
    local shortcuts=("$@")
    local items=()
    local total_len=0
    
    for ((i=0; i<${#shortcuts[@]}; i+=2)); do
        local key="${shortcuts[i]}"
        local label="${shortcuts[i+1]}"
        local item=" ${CYAN}[${key}]${RESET} ${label} "
        items+=("$item")
    done
    
    echo -e "  ${_ZDT_BORDER_PRIMARY}╠$(_repeat_char '═' $width)╣${RESET}"
    local footer_line=""
    for item in "${items[@]}"; do
        footer_line="${footer_line}${item}"
    done
    local pad=$(_pad_str "$footer_line" "$width")
    echo -e "  ${_ZDT_BORDER_PRIMARY}║${RESET}${pad}${_ZDT_BORDER_PRIMARY}║${RESET}"
    echo -e "  ${_ZDT_BORDER_PRIMARY}╚$(_repeat_char '═' $width)╝${RESET}"
}



# ==========================================
# OUTPUT WRAPPER — frame output menu, suppress clear biar ga kehapus
# ==========================================
wrap_output() {
    local _fake_dir
    _fake_dir=$(mktemp -d /tmp/zdt_clear_XXXXXX 2>/dev/null || echo "/tmp/zdt_clear_$$")
    printf '#!/bin/sh\nexit 0\n' > "$_fake_dir/clear"
    chmod +x "$_fake_dir/clear" 2>/dev/null || true

    PATH="$_fake_dir:$PATH" "$@"
    local _exit=$?

    rm -rf "$_fake_dir" 2>/dev/null || true
    return $_exit
}

# ==========================================
# HELPER: PAUSE BEFORE RETURN TO MENU
# ==========================================
_pause() {
    echo ""
    while read -s -r -t 0.01 -n 1000 2>/dev/null; do :; done
    local _pw=$(( $(tput cols 2>/dev/null || echo 50) - 8 ))
    [ "$_pw" -gt 60 ] && _pw=60
    [ "$_pw" -lt 30 ] && _pw=30
    local _pm="${DIM}Press any key to return...${RESET}"
    local _pp=$(_pad_str " ${_pm}" "$_pw")
    echo -e "  ${_ZDT_BORDER_PRIMARY}╭$(_repeat_char '─' $_pw)╮${RESET}"
    echo -e "  ${_ZDT_BORDER_PRIMARY}│${RESET}${_pp}${_ZDT_BORDER_PRIMARY}│${RESET}"
    echo -e "  ${_ZDT_BORDER_PRIMARY}╰$(_repeat_char '─' $_pw)╯${RESET}"
    read -s -r -n 1 2>/dev/null || read -r -n 1 2>/dev/null || true
    echo ""
}
