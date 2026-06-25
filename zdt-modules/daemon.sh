# ==========================================
# ZDT Daemon Module
# ==========================================
# Background services: Watch daemon, Telegram bot,
# Web dashboard, updates, clean all
# ==========================================

# ==========================================
# HELPER: SMART PYTHON LAUNCHER
# Coba python global, lalu venv python, lalu fail gracefully
# ==========================================
_run_python_script() {
    local script="$1"
    shift
    # Try VENV python first (has all required modules installed)
    if [ -f "$ZDT_VENV_DIR/bin/python" ]; then
        "$ZDT_VENV_DIR/bin/python" "$script" "$@"
        return $?
    elif command -v python3 >/dev/null 2>&1; then
        python3 "$script" "$@"
        return $?
    else
        echo "Python tidak ditemukan! Jalankan menu Setup & Install Tools."
        return 1
    fi
}

# ==========================================
# FUNGSI UTAMA: UPDATE TOOLS
# ==========================================
start_watch_daemon() {
    print_header "ZDT AUTO-WATCH DAEMON"
    if ! _ensure_python_tool "watchdog" "Watchdog" 1; then return 1; fi
    
    local watch_script=""
    for dir in "$HOME/.local/share/zdt" "/usr/local/share/zdt" "/data/data/com.termux/files/usr/share/zdt"; do
        if [ -f "$dir/zdt-watch.py" ]; then watch_script="$dir/zdt-watch.py"; break; fi
    done

    if pgrep -f "zdt-watch.py" > /dev/null; then
        echo -e "  ${RED}${ICO_FAIL} Watcher Daemon sudah berjalan di background!${RESET}"
        echo -e "  ${YELLOW}${ICO_ARROW} Matikan dulu via Web UI (Menu Daemons) atau jalankan:${RESET}"
        echo -e "  ${BOLD}  pkill -f zdt-watch.py${RESET}"
        return 1
    fi

    if [ -z "$watch_script" ]; then
        echo -e "  ${RED}${ICO_FAIL} Script zdt-watch.py tidak ditemukan!${RESET}"
        return 1
    fi

    local watch_dir="${TARGET_DIR:-${ROOT_DIR:-.}}"
    
    echo -e "  ${YELLOW}${ICO_ARROW} Menjalankan Watchdog Daemon...${RESET}"
    echo -e "  ${CYAN}${ICO_OK} Memantau folder: ${BOLD}$watch_dir${RESET}"
    echo -e "  ${GRAY}  (Tekan Ctrl+C untuk mematikan daemon)${RESET}"
    echo ""
    
    cd "$watch_dir" || return 1
    _run_python_script "$watch_script" "$watch_dir"
}

start_telegram_bot() {
    print_header "TELEGRAM REMOTE BOT"
    
    if ! _ensure_python_tool "telebot" "pyTelegramBotAPI" 0; then
        echo -e "  ${YELLOW}${ICO_WARN} Modul telebot belum terinstal. Menginstal otomatis...${RESET}"
        if ! _ensure_python_tool "telebot" "pyTelegramBotAPI" 1; then
            echo -e "  ${RED}${ICO_FAIL} Gagal menginstal telebot! Jalankan menu [1] Setup & Install Tools.${RESET}"
            return 1
        fi
    fi
    
    local tele_script=""
    for dir in "$HOME/.local/share/zdt" "/usr/local/share/zdt" "/data/data/com.termux/files/usr/share/zdt"; do
        if [ -f "$dir/zdt-telegram.py" ]; then tele_script="$dir/zdt-telegram.py"; break; fi
    done

    if pgrep -f "zdt-telegram.py" > /dev/null; then
        echo -e "  ${RED}${ICO_FAIL} Telegram Bot sudah berjalan di background!${RESET}"
        echo -e "  ${YELLOW}${ICO_ARROW} Matikan dulu via Web UI (Menu Daemons) atau jalankan:${RESET}"
        echo -e "  ${BOLD}  pkill -f zdt-telegram.py${RESET}"
        return 1
    fi

    if [ -z "$tele_script" ]; then
        echo -e "  ${RED}${ICO_FAIL} Script zdt-telegram.py tidak ditemukan!${RESET}"
        return 1
    fi

    if [ ! -f "$HOME/.config/zdt/telegram_token.txt" ]; then
        echo -e "  ${YELLOW}${ICO_ARROW} Token Telegram belum diset!${RESET}"
        setup_telegram_bot
        return 0
    fi

    echo -e "  ${YELLOW}${ICO_ARROW} Menjalankan Telegram Bot...${RESET}"
    echo -e "  ${GRAY}  (Tekan Ctrl+C untuk mematikan bot)${RESET}"
    echo ""
    
    _run_python_script "$tele_script"
}

setup_telegram_bot() {
    echo -e "  ${CYAN}${ICO_ARROW} SETUP TOKEN TELEGRAM${RESET}"
    echo -e "  ${GRAY}Dapatkan token dari @BotFather di Telegram.${RESET}"
    echo -e -n "  ${BOLD}[?] Masukkan token Bot Telegram: ${RESET}"
    local token
    read -r token
    
    if [ -z "$token" ]; then
        echo -e "  ${RED}${ICO_FAIL} Token tidak boleh kosong!${RESET}"
        return 1
    fi
    
    mkdir -p "$HOME/.config/zdt"
    echo "$token" > "$HOME/.config/zdt/telegram_token.txt"
    chmod 600 "$HOME/.config/zdt/telegram_token.txt"
    echo -e "  ${GREEN}${ICO_OK} Token berhasil disimpan!${RESET}"
    echo -e "  ${CYAN}${ICO_ARROW} Menjalankan bot...${RESET}"
    start_telegram_bot
}

start_web_dashboard() {
    print_header "WEB DASHBOARD"
    
    if ! _ensure_python_tool "flask" "Flask" 1; then return 1; fi
    
    local web_script=""
    for dir in "$HOME/.local/share/zdt" "/usr/local/share/zdt" "/data/data/com.termux/files/usr/share/zdt"; do
        if [ -f "$dir/zdt-web.py" ]; then web_script="$dir/zdt-web.py"; break; fi
    done

    if [ -z "$web_script" ]; then
        echo -e "  ${RED}${ICO_FAIL} Script zdt-web.py tidak ditemukan!${RESET}"
        return 1
    fi

    echo -e "  ${YELLOW}${ICO_ARROW} Menyalakan Web Dashboard...${RESET}"

    # Baca credentials asli dari config.env (bukan hardcoded "admin")
    local _actual_user _actual_pass
    if [ -f "$ZDT_CONFIG_FILE" ]; then
        _actual_user=$(grep "^ZDT_WEB_USER=" "$ZDT_CONFIG_FILE" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        _actual_pass=$(grep "^ZDT_WEB_PASS=" "$ZDT_CONFIG_FILE" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    fi
    if [ -z "$_actual_user" ]; then _actual_user="admin"; fi
    if [ -z "$_actual_pass" ]; then _actual_pass="(auto-generated on first run)"; fi
    echo -e "  ${CYAN}${ICO_WARN} INFO AUTH: Username = ${BOLD}$_actual_user${RESET} | Password = ${BOLD}$_actual_pass${RESET}"
    echo ""
    
    local port="${WEB_PORT:-5000}"
    local host="${WEB_BIND:-127.0.0.1}"
    local open_host="$host"
    [ "$open_host" = "0.0.0.0" ] && open_host="127.0.0.1"
    local url="http://$open_host:$port"
    
    # Auto-open browser (multi-platform)
    ( sleep 1.5
        if command -v termux-open-url >/dev/null 2>&1; then
            # Native Termux
            termux-open-url "$url" >/dev/null 2>&1
        elif [ -x "/host-rootfs/data/data/com.termux/files/usr/bin/termux-open-url" ]; then
            # Proot-distro → call host Termux
            /host-rootfs/data/data/com.termux/files/usr/bin/termux-open-url "$url" >/dev/null 2>&1
        elif command -v am >/dev/null 2>&1; then
            # Android via am (Activity Manager)
            am start -a android.intent.action.VIEW -d "$url" >/dev/null 2>&1
        elif command -v xdg-open >/dev/null 2>&1; then
            # Linux desktop
            xdg-open "$url" >/dev/null 2>&1
        elif command -v open >/dev/null 2>&1; then
            # macOS
            open "$url" >/dev/null 2>&1
        else
            python3 -m webbrowser "$url" >/dev/null 2>&1
        fi
    ) &
    
    echo -e "  ${GREEN}${ICO_OK} Dashboard: ${CYAN}${url}${RESET}"
    echo ""
    
    _run_python_script "$web_script" --bind "$WEB_BIND" --port "$port"
}

# ==========================================
# FUNGSI: UPDATE ZDT SCRIPT
# ==========================================
update_zdt_script() {
    print_header "UPDATE ZDT (OVER-THE-AIR)"
    
    echo -e "  ${CYAN}${ICO_ARROW} Mendownload versi terbaru dari GitHub...${RESET}"
    
    # mktemp: nama file acak untuk cegah symlink attack saat OTA update
    local tmp_file
    tmp_file=$(mktemp "${TMPDIR:-/tmp}/zdt_update_XXXXXX.sh" 2>/dev/null || echo "/tmp/zdt_update_$$.sh")
    # Get latest commit SHA to bypass GitHub CDN cache
    local latest_sha
    latest_sha=$(curl -sL "https://api.github.com/repos/muhammad1505/zdt-music-toolkit/commits/main" 2>/dev/null | grep -oP '"sha":\s*"\K[^"]+' | head -1)
    local dl_ref="${latest_sha:-main}"
    if curl -sL "https://raw.githubusercontent.com/muhammad1505/zdt-music-toolkit/${dl_ref}/zdt.sh" -o "$tmp_file"; then
        if [ -s "$tmp_file" ] && grep -qE "APP_VERSION|Version :" "$tmp_file"; then
            local new_version
            # Try APP_VERSION="x.y.z" first (monolithic), else fallback to comment # Version : x.y.z (modular)
            new_version=$(grep -oP 'APP_VERSION="\K[^"]+' "$tmp_file" 2>/dev/null || grep -oP 'Version : \K[0-9.]+' "$tmp_file" 2>/dev/null || echo "unknown")
            echo -e "  ${GREEN}${ICO_OK} Versi $new_version berhasil didownload!${RESET}"
            
            local target_bin
            if [ -f "$HOME/.local/bin/zdt" ]; then
                target_bin="$HOME/.local/bin/zdt"
            elif [ -f "/usr/local/bin/zdt" ]; then
                target_bin="/usr/local/bin/zdt"
            elif [ -f "/data/data/com.termux/files/usr/bin/zdt" ]; then
                target_bin="/data/data/com.termux/files/usr/bin/zdt"
            else
                target_bin="$0"
            fi
            
            cp "$tmp_file" "$target_bin"
            chmod +x "$target_bin"
            
            # Also update module files
            local share_dir
            if [[ "$target_bin" == *"local/bin"* ]]; then
                share_dir="$HOME/.local/share/zdt"
            elif [[ "$target_bin" == *"termux"* ]]; then
                share_dir="/data/data/com.termux/files/usr/share/zdt"
            else
                share_dir="/usr/local/share/zdt"
            fi
            # Use GitHub API (no CDN cache) instead of raw.githubusercontent (cached ~5min)
            local base_url="https://raw.githubusercontent.com/muhammad1505/zdt-music-toolkit/main"
            local api_url="https://api.github.com/repos/muhammad1505/zdt-music-toolkit/contents"
            
            # Get latest commit SHA for cache-busting
            local latest_sha
            latest_sha=$(curl -sL "https://api.github.com/repos/muhammad1505/zdt-music-toolkit/commits/main" 2>/dev/null | grep -oP '"sha":\s*"\K[^"]+' | head -1)
            if [ -n "$latest_sha" ]; then
                base_url="https://raw.githubusercontent.com/muhammad1505/zdt-music-toolkit/${latest_sha}"
            fi
            local cache_bust="?v=$(date +%s)"
            
            # Download ALL shell modules
            local mod_dir="$share_dir/zdt-modules"
            mkdir -p "$mod_dir"
            # Clean up stale module from previous buggy OTA
            rm -f "$mod_dir/download.sh"
            echo -e "  ${CYAN}${ICO_ARROW} Mengupdate shell modules...${RESET}"
            for mod in core helpers download-spotify download-youtube media playlist daemon setup assistant; do
                curl -sL "${base_url}/zdt-modules/${mod}.sh${cache_bust}" -o "${mod_dir}/${mod}.sh" 2>/dev/null
            done
            
            # Download ALL Python scripts
            echo -e "  ${CYAN}${ICO_ARROW} Mengupdate Python scripts...${RESET}"
            for pyfile in zdt-web.py zdt-watch.py zdt-telegram.py; do
                curl -sL "${base_url}/${pyfile}${cache_bust}" -o "${share_dir}/${pyfile}" 2>/dev/null
            done
            
            # Download templates
            echo -e "  ${CYAN}${ICO_ARROW} Mengupdate dashboard template...${RESET}"
            mkdir -p "$share_dir/templates"
            curl -sL "${base_url}/templates/dashboard.html${cache_bust}" -o "$share_dir/templates/dashboard.html" 2>/dev/null
            
            # Download utility scripts + database helper
            echo -e "  ${CYAN}${ICO_ARROW} Mengupdate utility files...${RESET}"
            for util in install.sh Makefile README.md; do
                curl -sL "${base_url}/${util}${cache_bust}" -o "${share_dir}/${util}" 2>/dev/null
            done
            # Download database helper
            curl -sL "${base_url}/zdt-modules/zdt_db.py${cache_bust}" -o "${mod_dir}/zdt_db.py" 2>/dev/null
            chmod +x "${share_dir}/install.sh" 2>/dev/null
            
            rm -f "$tmp_file"
            echo -e "  ${GREEN}${ICO_OK} Update v${new_version} selesai! Semua komponen diperbarui.${RESET}"
            echo -e "  ${GREEN}   ✓ zdt.sh (main script)${RESET}"
            echo -e "  ${GREEN}   ✓ 8 shell modules${RESET}"
            echo -e "  ${GREEN}   ✓ 3 Python scripts (web, watch, telegram)${RESET}"
            echo -e "  ${GREEN}   ✓ Utility files (installer, readme)${RESET}"
            echo -e "  ${YELLOW}   Silakan jalankan ulang ZDT.${RESET}"
            _log "INFO" "OTA Update completed to version $new_version (full update)"
            exit 0
        else
            echo -e "  ${RED}${ICO_FAIL} File download tidak valid!${RESET}"
            rm -f "$tmp_file"
        fi
    else
        echo -e "  ${RED}${ICO_FAIL} Gagal mendownload update! Cek koneksi internet.${RESET}"
    fi
    
    _pause
}

# ==========================================
# FUNGSI: UPDATE TOOLS (VENV)
# ==========================================
update_tools() {
    print_header "UPDATE TOOLS (VENV)"
    
    if [ ! -f "$ZDT_VENV_DIR/bin/python" ]; then
        echo -e "  ${YELLOW}${ICO_ARROW} VENV belum dibuat. Mengalihkan ke menu Setup...${RESET}"
        sleep 1
        install_missing_tools
        return 0
    fi
    
    echo -e "  ${CYAN}${ICO_ARROW} Memperbarui tools utama di VENV...${RESET}"
    if "$ZDT_VENV_DIR/bin/pip" install -U yt-dlp spotdl syncedlyrics mutagen flask pyTelegramBotAPI watchdog >/dev/null 2>&1; then
        echo -e "  ${GREEN}${ICO_OK} Tools utama berhasil diperbarui!${RESET}"
    else
        echo -e "  ${YELLOW}${ICO_WARN} Update tools selesai dengan peringatan.${RESET}"
    fi
    
    local demucs_venv="$HOME/.local/share/zdt/demucs_venv"
    if [ -f "$demucs_venv/bin/demucs" ]; then
        echo -e "  ${CYAN}${ICO_ARROW} Memperbarui komponen AI Demucs...${RESET}"
        if "$demucs_venv/bin/pip" install -U pip setuptools demucs torchcodec >/dev/null 2>&1; then
            echo -e "  ${GREEN}${ICO_OK} AI Demucs berhasil diperbarui!${RESET}"
        else
            echo -e "  ${YELLOW}${ICO_WARN} Update Demucs selesai dengan peringatan.${RESET}"
        fi
    fi
    
    echo ""
    echo -e "  ${GREEN}${ICO_OK} Proses Update selesai!${RESET}"
    _log "INFO" "Tools updated"
    _pause
}

# ==========================================
# FUNGSI: HAPUS SEMUA FILE
# ==========================================
hapus_semua() {
    print_header "HAPUS SEMUA FILE"
    
    local target="${STORAGE_DIR:-${TARGET_DIR:-${ROOT_DIR:-.}}}"
    
    # Safety: refuse to operate on dangerous paths
    if [ "$target" = "." ] || [ "$target" = "/" ] || [ "$target" = "$HOME" ] || [ "$target" = "/root" ] || [ "$target" = "/home" ]; then
        echo -e "  ${RED}${ICO_DANGER} DITOLAK! Target direktori tidak aman: $target${RESET}"
        echo -e "  ${YELLOW}Silakan atur direktori penyimpanan terlebih dahulu via menu [S] Storage.${RESET}"
        return 1
    fi
    # Additional safety: min path length 6 chars (e.g. /a/b/c is still too short)
    if [ ${#target} -lt 6 ]; then
        echo -e "  ${RED}${ICO_DANGER} DITOLAK! Path terlalu pendek: $target${RESET}"
        return 1
    fi
    
    if [ ! -d "$target" ]; then
        echo -e "  ${RED}${ICO_FAIL} Direktori tidak ditemukan: $target${RESET}"
        return 1
    fi
    
    echo -e "  ${RED}${ICO_DANGER} PERINGATAN!${RESET}"
    echo -e "  ${YELLOW}Anda akan menghapus SEMUA file media di:${RESET}"
    echo -e "  ${WHITE}  $target${RESET}"
    echo ""
    echo -e -n "  ${BOLD}[?] Yakin hapus semua file? (ketik 'yakin' untuk konfirmasi): ${RESET}"
    local confirm
    read -r confirm
    
    # Trim whitespace and convert to lowercase
    confirm=$(echo "$confirm" | xargs | tr '[:upper:]' '[:lower:]')
    
    if [ "$confirm" != "yakin" ]; then
        echo -e "  ${GREEN}${ICO_OK} Dibatalkan.${RESET}"
        return 0
    fi
    
    local count=$(find "$target" -mindepth 1 | wc -l)
    
    if [ "$count" -eq 0 ]; then
        echo -e "  ${GREEN}${ICO_OK} Direktori sudah kosong!${RESET}"
        return 0
    fi

    # Hapus semua isi direktori (termasuk folder, thumbnail, json, dll)
    # ${target:?} sebagai pengaman terakhir: cegah ekspansi ke /* jika target kosong
    rm -rf "${target:?}"/* 2>/dev/null || true
    # Hapus file hidden (jika ada, selain . dan ..)
    rm -rf "${target:?}"/.[!.]* 2>/dev/null || true
    
    echo -e "  ${GREEN}${ICO_OK} Berhasil mengosongkan direktori ($count item dihapus)!${RESET}"
    _log "INFO" "Cleared storage directory $target ($count items)"
}
