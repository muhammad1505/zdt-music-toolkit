# ==========================================
# ZDT Daemon Module
# ==========================================
# Background services: Watch daemon, Telegram bot,
# Web dashboard, updates, clean all
# ==========================================

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
    "$ZDT_VENV_DIR/bin/python" "$watch_script" "$watch_dir"
}

start_telegram_bot() {
    print_header "TELEGRAM REMOTE BOT"
    
    local tele_script=""
    for dir in "$HOME/.local/share/zdt" "/usr/local/share/zdt" "/data/data/com.termux/files/usr/share/zdt"; do
        if [ -f "$dir/zdt-telegram.py" ]; then tele_script="$dir/zdt-telegram.py"; break; fi
    done

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
    
    "$ZDT_VENV_DIR/bin/python" "$tele_script"
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
    echo ""
    
    local port="${WEB_PORT:-5000}"
    local host="${WEB_BIND:-127.0.0.1}"
    local open_host="$host"
    [ "$open_host" = "0.0.0.0" ] && open_host="127.0.0.1"
    
    # Auto-open browser
    ( sleep 1.5; command -v xdg-open >/dev/null 2>&1 && xdg-open "http://$open_host:$port" >/dev/null 2>&1 || python3 -m webbrowser "http://$open_host:$port" >/dev/null 2>&1 ) &
    
    "$ZDT_VENV_DIR/bin/python" "$web_script" --bind "$WEB_BIND" --port "$port"
}

# ==========================================
# FUNGSI: UPDATE ZDT SCRIPT
# ==========================================
update_zdt_script() {
    print_header "UPDATE ZDT (OVER-THE-AIR)"
    
    echo -e "  ${CYAN}${ICO_ARROW} Mendownload versi terbaru dari GitHub...${RESET}"
    
    local tmp_file="/tmp/zdt_update_$$.sh"
    if curl -sL "https://raw.githubusercontent.com/muhammad1505/zdt-music-toolkit/main/zdt.sh?v=$(date +%s)" -o "$tmp_file"; then
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
            
            # Download module files
            local mod_dir="$share_dir/zdt-modules"
            mkdir -p "$mod_dir"
            for mod in core helpers download media playlist daemon setup assistant; do
                curl -sL "https://raw.githubusercontent.com/muhammad1505/zdt-music-toolkit/main/zdt-modules/${mod}.sh?v=$(date +%s)" -o "${mod_dir}/${mod}.sh" 2>/dev/null
            done
            
            rm -f "$tmp_file"
            echo -e "  ${GREEN}${ICO_OK} Update selesai! Silakan jalankan ulang ZDT.${RESET}"
            _log "INFO" "OTA Update completed to version $new_version"
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
    
    local target="${TARGET_DIR:-${ROOT_DIR:-.}}"
    echo -e "  ${RED}${ICO_DANGER} PERINGATAN!${RESET}"
    echo -e "  ${YELLOW}Anda akan menghapus SEMUA file di:${RESET}"
    echo -e "  ${WHITE}  $target${RESET}"
    echo ""
    echo -e -n "  ${BOLD}[?] Yakin hapus semua file? (ketik 'yakin' untuk konfirmasi): ${RESET}"
    local confirm
    read -r confirm
    
    if [ "$confirm" != "yakin" ]; then
        echo -e "  ${GREEN}${ICO_OK} Dibatalkan.${RESET}"
        return 0
    fi
    
    local count=0
    while IFS= read -r f; do
        rm -f "$f"
        ((count++))
    done < <(_find_media_files "$target" "media_with_lyrics")
    
    echo -e "  ${GREEN}${ICO_OK} Berhasil menghapus $count file!${RESET}"
    _log "INFO" "Deleted $count files from $target"
    _pause
}
