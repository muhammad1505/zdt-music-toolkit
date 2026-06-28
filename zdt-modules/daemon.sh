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
    
    local watch_script
    watch_script=$(_find_script "zdt-watch.py")

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
    
    local tele_script
    tele_script=$(_find_script "zdt-telegram.py")

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
    
    local web_script
    web_script=$(_find_script "zdt-web.py")

    if [ -z "$web_script" ]; then
        echo -e "  ${RED}${ICO_FAIL} Script zdt-web.py tidak ditemukan!${RESET}"
        return 1
    fi

    echo -e "  ${YELLOW}${ICO_ARROW} Menyalakan Web Dashboard...${RESET}"

    # Baca credentials asli dari config.env (bukan hardcoded "admin")
    local _actual_user="" _actual_pass=""
    if [ -f "$ZDT_CONFIG_FILE" ]; then
        _actual_user=$(grep "^ZDT_WEB_USER=" "$ZDT_CONFIG_FILE" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        _actual_pass=$(grep "^ZDT_WEB_PASS=" "$ZDT_CONFIG_FILE" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    fi
    [ -z "$_actual_user" ] && _actual_user="admin"
    [ -z "$_actual_pass" ] && _actual_pass="(auto-generated on first run)"
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
    local tmp_file
    tmp_file=$(mktemp "${TMPDIR:-/tmp}/zdt_update_XXXXXX.sh" 2>/dev/null || echo "/tmp/zdt_update_$$.sh")
    # Get latest commit SHA to bypass GitHub CDN cache
    local latest_sha
    local base_url="https://raw.githubusercontent.com/muhammad1505/zdt-music-toolkit"
    latest_sha=$(curl -sL "https://api.github.com/repos/muhammad1505/zdt-music-toolkit/commits/main" 2>/dev/null | grep -oP '"sha":\s*"\K[^"]+' | head -1)
    local dl_ref="${latest_sha:-main}"
    local cache_bust="?v=$(date +%s)"
    local gh_url="${base_url}/${dl_ref}"

    # --- Fungsi helper built-in (fallback jika helpers.sh tidak tersedia) ---
    _sanitize_ver() {
        local v="$1"
        local clean
        clean=$(echo "$v" | grep -oP '^[0-9]+\.[0-9]+\.[0-9]+' || echo "")
        [ -n "$clean" ] && echo "$clean" || echo "unknown"
    }
    _get_zdt_bin_fb() {
        local _f _w
        for _f in "$HOME/.local/bin/zdt" "/usr/local/bin/zdt" "/data/data/com.termux/files/usr/bin/zdt"; do
            [ -f "$_f" ] && { echo "$_f"; return 0; }
        done
        _w=$(command -v zdt 2>/dev/null) && [ -n "$_w" ] && { echo "$_w"; return 0; }
        echo "zdt"
    }
    _get_share_dir_fb() {
        local _d
        for _d in "$HOME/.local/share/zdt" "/usr/local/share/zdt" "/data/data/com.termux/files/usr/share/zdt"; do
            [ -d "$_d" ] && { echo "$_d"; return 0; }
        done
        echo "$HOME/.local/share/zdt"
    }

    # Step 1: Download VERSION file FIRST — single source of truth
    local tmp_ver
    tmp_ver=$(mktemp "${TMPDIR:-/tmp}/zdt_version_XXXXXX" 2>/dev/null || echo "/tmp/zdt_version_$$")
    curl -sL "${gh_url}/VERSION${cache_bust}" -o "$tmp_ver" 2>/dev/null
    local new_version
    if [ -s "$tmp_ver" ]; then
        local raw_ver
        raw_ver=$(cat "$tmp_ver" | tr -d '[:space:]')
        new_version=$(_sanitize_ver "$raw_ver")
    fi
    rm -f "$tmp_ver"

    # Step 2: Download zdt.sh
    if curl -sL "${gh_url}/zdt.sh${cache_bust}" -o "$tmp_file"; then
        if [ -s "$tmp_file" ] && grep -qE "APP_VERSION|Version :" "$tmp_file"; then
            # Step 3: Parse version from VERSION file (primary) or zdt.sh (fallback)
            if [ -z "${new_version:-}" ] || [ "$new_version" = "unknown" ]; then
                # Fallback: parse dari zdt.sh (old format: APP_VERSION="x.y.z")
                local _raw_ver
                _raw_ver=$(grep -oP 'APP_VERSION="\K[^"]+' "$tmp_file" 2>/dev/null || true)
                if [ -z "$_raw_ver" ]; then
                    local raw_v
                    raw_v=$(grep -oP 'Version : \K[0-9.]+' "$tmp_file" 2>/dev/null || echo "unknown")
                    new_version=$(_sanitize_ver "$raw_v")
                elif [[ "$_raw_ver" == *":-"* ]]; then
                    # New format: APP_VERSION="${_APP_VERSION:-x.y.z}" — extract fallback value
                    local raw_v
                    raw_v=$(echo "$_raw_ver" | grep -oP '\K[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
                    new_version=$(_sanitize_ver "$raw_v")
                else
                    new_version=$(_sanitize_ver "$_raw_ver")
                fi
            fi
            # Fallback if version is still empty
            [ -z "${new_version:-}" ] && new_version="unknown"
            echo -e "  ${GREEN}${ICO_OK} Versi $new_version berhasil didownload!${RESET}"
            
            local target_bin
            # Fallback: coba fungsi helpers.sh dulu, lalu built-in
            if command -v _get_zdt_bin >/dev/null 2>&1; then
                target_bin=$(_get_zdt_bin)
            else
                target_bin=$(_get_zdt_bin_fb)
            fi
            if [ "$target_bin" = "zdt" ]; then
                target_bin="$0"
            fi
            
            # Detect dev mode: jika SCRIPT_DIR punya zdt-modules, update juga di situ
            local dev_mode=false
            if [ -n "${SCRIPT_DIR:-}" ] && [ -d "$SCRIPT_DIR/zdt-modules" ]; then
                dev_mode=true
                echo -e "  ${CYAN}${ICO_ARROW} Dev mode detected — also updating repo modules...${RESET}"
            fi
            
            if cp "$tmp_file" "$target_bin" 2>/dev/null; then
                chmod +x "$target_bin"
                echo -e "  ${GREEN}   ✓ Main binary updated${RESET}"
            else
                if command -v sudo >/dev/null 2>&1 && sudo cp "$tmp_file" "$target_bin" 2>/dev/null; then
                    sudo chmod +x "$target_bin"
                    echo -e "  ${GREEN}   ✓ Main binary updated (via sudo)${RESET}"
                else
                    echo -e "  ${YELLOW}   ⚠ Gagal update $target_bin (butuh root). Copy manual:${RESET}"
                    echo -e "  ${YELLOW}     sudo cp $tmp_file $target_bin${RESET}"
                    echo -e "  ${YELLOW}     sudo chmod +x $target_bin${RESET}"
                fi
            fi
            
            # Step 4: Backup existing version for rollback
    local share_dir
    # Fallback: coba fungsi helpers.sh dulu, lalu built-in
    if command -v _get_share_dir >/dev/null 2>&1; then
        share_dir=$(_get_share_dir)
    else
        share_dir=$(_get_share_dir_fb)
    fi
    local mod_dir="$share_dir/zdt-modules"
    local backup_dir="$share_dir/backup-$(date +%Y%m%d%H%M%S)"
    local old_version="${new_version:-unknown}"
    
    echo -e "  ${CYAN}${ICO_ARROW} Membuat backup versi lama di $backup_dir...${RESET}"
    mkdir -p "$backup_dir/zdt-modules" 2>/dev/null
    # Backup main binary
    if [ -f "$target_bin" ]; then
        cp "$target_bin" "$backup_dir/zdt.sh" 2>/dev/null || true
    fi
    # Backup modules
    for mod in core helpers download-spotify download-youtube media playlist daemon setup assistant; do
        if [ -f "$mod_dir/${mod}.sh" ]; then
            cp "$mod_dir/${mod}.sh" "$backup_dir/zdt-modules/" 2>/dev/null || true
        fi
    done
    # Backup Python scripts
    for pyfile in zdt-web.py zdt-watch.py zdt-telegram.py; do
        if [ -f "$share_dir/$pyfile" ]; then
            cp "$share_dir/$pyfile" "$backup_dir/" 2>/dev/null || true
        fi
    done
    if [ -f "$share_dir/VERSION" ]; then
        cp "$share_dir/VERSION" "$backup_dir/VERSION" 2>/dev/null || true
    fi
    echo -e "  ${GREEN}   ✓ Backup tersimpan di $backup_dir${RESET}"
    
    # Step 5: Clean up stale module from previous buggy OTA
    mkdir -p "$mod_dir"
    rm -f "$mod_dir/download.sh" 2>/dev/null || true
    
    echo -e "  ${CYAN}${ICO_ARROW} Mengupdate shell modules...${RESET}"
    for mod in core helpers download-spotify download-youtube media playlist daemon setup assistant; do
        curl -sL "${gh_url}/zdt-modules/${mod}.sh${cache_bust}" -o "${mod_dir}/${mod}.sh" 2>/dev/null
        # Verify download succeeded (file not empty)
        if [ ! -s "${mod_dir}/${mod}.sh" ]; then
            echo -e "  ${RED}   ✗ Gagal download ${mod}.sh! Mengembalikan dari backup...${RESET}"
            if [ -f "$backup_dir/zdt-modules/${mod}.sh" ]; then
                cp "$backup_dir/zdt-modules/${mod}.sh" "${mod_dir}/${mod}.sh" 2>/dev/null || true
            fi
        fi
        # If dev mode, also update repo modules
        if [ "$dev_mode" = true ]; then
            cp "${mod_dir}/${mod}.sh" "$SCRIPT_DIR/zdt-modules/${mod}.sh" 2>/dev/null || true
        fi
    done
    
    echo -e "  ${CYAN}${ICO_ARROW} Mengupdate Python scripts...${RESET}"
    for pyfile in zdt-web.py zdt-watch.py zdt-telegram.py; do
        curl -sL "${gh_url}/${pyfile}${cache_bust}" -o "${share_dir}/${pyfile}" 2>/dev/null
        if [ ! -s "${share_dir}/${pyfile}" ]; then
            echo -e "  ${RED}   ✗ Gagal download ${pyfile}! Mengembalikan dari backup...${RESET}"
            if [ -f "$backup_dir/$pyfile" ]; then
                cp "$backup_dir/$pyfile" "${share_dir}/${pyfile}" 2>/dev/null || true
            fi
        fi
        if [ "$dev_mode" = true ]; then
            cp "${share_dir}/${pyfile}" "$SCRIPT_DIR/${pyfile}" 2>/dev/null || true
        fi
    done
    
    echo -e "  ${CYAN}${ICO_ARROW} Mengupdate dashboard template...${RESET}"
    mkdir -p "$share_dir/templates"
    curl -sL "${gh_url}/templates/dashboard.html${cache_bust}" -o "$share_dir/templates/dashboard.html" 2>/dev/null
    if [ "$dev_mode" = true ] && [ -d "$SCRIPT_DIR/templates" ]; then
        cp "$share_dir/templates/dashboard.html" "$SCRIPT_DIR/templates/dashboard.html" 2>/dev/null || true
    fi
    
    echo -e "  ${CYAN}${ICO_ARROW} Mengupdate utility files...${RESET}"
    for util in install.sh Makefile README.md; do
        curl -sL "${gh_url}/${util}${cache_bust}" -o "${share_dir}/${util}" 2>/dev/null
        if [ "$dev_mode" = true ] && [ -f "$SCRIPT_DIR/${util}" ]; then
            cp "${share_dir}/${util}" "$SCRIPT_DIR/${util}" 2>/dev/null || true
        fi
    done
    curl -sL "${gh_url}/zdt-ai-prompt.txt${cache_bust}" -o "${share_dir}/zdt-ai-prompt.txt" 2>/dev/null
    curl -sL "${gh_url}/zdt-modules/zdt_db.py${cache_bust}" -o "${mod_dir}/zdt_db.py" 2>/dev/null
    if [ "$dev_mode" = true ] && [ -d "$SCRIPT_DIR/zdt-modules" ]; then
        cp "${mod_dir}/zdt_db.py" "$SCRIPT_DIR/zdt-modules/zdt_db.py" 2>/dev/null || true
    fi
    chmod +x "${share_dir}/install.sh" 2>/dev/null
    
    # Step 6: Write VERSION file everywhere
    echo -e "  ${CYAN}${ICO_ARROW} Mengupdate VERSION file...${RESET}"
    echo "$new_version" > "${share_dir}/VERSION"
    local _installed_bin_dir
    _installed_bin_dir=$(dirname "$target_bin" 2>/dev/null || true)
    if [ -n "$_installed_bin_dir" ] && [ -d "$_installed_bin_dir" ]; then
        cp "${share_dir}/VERSION" "$_installed_bin_dir/VERSION" 2>/dev/null || true
    fi
    if [ "$dev_mode" = true ]; then
        echo "$new_version" > "$SCRIPT_DIR/VERSION"
    fi
    
    rm -f "$tmp_file"
    echo -e "  ${GREEN}${ICO_OK} Update v${new_version} selesai! Semua komponen diperbarui.${RESET}"
    echo -e "  ${GREEN}   ✓ Backup otomatis: $backup_dir${RESET}"
    echo -e "  ${YELLOW}   Untuk rollback: jalankan 'zdt --rollback $backup_dir'${RESET}"
    echo -e "  ${GREEN}   ✓ zdt.sh (main script)${RESET}"
    echo -e "  ${GREEN}   ✓ 8 shell modules${RESET}"
    echo -e "  ${GREEN}   ✓ 3 Python scripts (web, watch, telegram)${RESET}"
    echo -e "  ${GREEN}   ✓ AI prompt template (zdt-ai-prompt.txt)${RESET}"
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
    
    if [ -f "$ZDT_DEMUCS_BIN" ]; then
        echo -e "  ${CYAN}${ICO_ARROW} Memperbarui komponen AI Demucs...${RESET}"
        if "$ZDT_DEMUCS_VENV_DIR/bin/pip" install -U pip setuptools demucs torchcodec >/dev/null 2>&1; then
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
    
    echo -e "  ${CYAN}${ICO_ARROW} Target direktori: ${YELLOW}$target${RESET}"
    echo -e "  ${CYAN}${ICO_ARROW} Direktori aktif saat ini: ${YELLOW}$(pwd)${RESET}"
    echo ""
    
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
