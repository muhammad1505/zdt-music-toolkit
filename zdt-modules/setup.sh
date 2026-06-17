# ==========================================
# ZDT Setup Module
# ==========================================
# Dependency management, system info,
# documentation, storage setup, CLI args
# ==========================================

# ==========================================
# ENSURE PYTHON TOOL
# ==========================================
_ensure_python_tool() {
    local tool_name="$1"
    local display_name="$2"
    local required="${3:-0}"

    if command -v "$tool_name" >/dev/null 2>&1; then
        return 0
    fi

    if [ -f "$ZDT_VENV_DIR/bin/$tool_name" ]; then
        PATH="$ZDT_VENV_DIR/bin:$PATH"
        return 0
    fi

    # Cek via python module
    if [ -f "$ZDT_VENV_DIR/bin/python" ]; then
        if "$ZDT_VENV_DIR/bin/python" -c "import $tool_name" 2>/dev/null; then
            return 0
        fi
    fi

    if [ "$required" = "1" ]; then
        echo -e "  ${YELLOW}${ICO_WARN} $display_name belum terinstal!${RESET}"
        echo -e -n "  ${BOLD}[?] Instal sekarang? (Y/n): ${RESET}"
        local ans
        read -r -n 1 ans; echo ""
        if [[ "$ans" =~ ^[Yy]$ ]] || [ -z "$ans" ]; then
            install_missing_tools
            if command -v "$tool_name" >/dev/null 2>&1 || [ -f "$ZDT_VENV_DIR/bin/$tool_name" ]; then
                return 0
            fi
        fi
        return 1
    fi

    return 1
}

# ==========================================
# INSTALL MISSING TOOLS
# ==========================================
install_missing_tools() {
    print_header "AUTO INSTALL TOOLS"

    echo -e "  ${CYAN}${ICO_ARROW} Mendeteksi package manager...${RESET}"
    local mgr
    mgr=$(_get_pkg_manager)
    echo -e "  ${GREEN}${ICO_OK} Menggunakan: $mgr${RESET}"

    # 1. Install base system packages
    echo -e "  ${CYAN}${ICO_ARROW} Memasang dependensi sistem...${RESET}"
    local base_pkgs="python3 ffmpeg"
    
    # Cek apakah perlu python3-venv
    if command -v apt-get >/dev/null 2>&1 || command -v apt >/dev/null 2>&1; then
        base_pkgs="$base_pkgs python3-venv python3-pip"
    fi

    for pkg in $base_pkgs; do
        if ! command -v "$pkg" >/dev/null 2>&1 && [ "$pkg" != "python3-venv" ] && [ "$pkg" != "python3-pip" ]; then
            _pkg_install "$pkg"
        elif [ "$pkg" = "python3-venv" ] || [ "$pkg" = "python3-pip" ]; then
            # Cek via dpkg untuk paket python
            if ! dpkg -s "$pkg" 2>/dev/null | grep -q "Status.*installed"; then
                _pkg_install "$pkg" 2>/dev/null || true
            fi
        else
            echo -e "  ${GRAY}  ${ICO_CHECK_OK} $pkg sudah terinstal${RESET}"
        fi
    done

    # 2. Setup VENV
    echo -e "  ${CYAN}${ICO_ARROW} Menyiapkan Python Virtual Environment...${RESET}"
    if [ ! -f "$ZDT_VENV_DIR/bin/python" ]; then
        mkdir -p "$(dirname "$ZDT_VENV_DIR")"
        python3 -m venv "$ZDT_VENV_DIR" 2>/dev/null || {
            echo -e "  ${RED}${ICO_FAIL} Gagal membuat VENV. Coba instal python3-venv manual.${RESET}"
            _log "ERROR" "VENV creation failed"
            sleep 2
            return 1
        }
    fi

    # 3. Aktifkan VENV dan install tools
    echo -e "  ${CYAN}${ICO_ARROW} Menginstal Python tools (yt-dlp, spotdl, mutagen, dll)...${RESET}"
    local pip_cmd="$ZDT_VENV_DIR/bin/pip"
    $pip_cmd install -U pip setuptools wheel >/dev/null 2>&1

    if $pip_cmd install yt-dlp spotdl syncedlyrics mutagen flask pyTelegramBotAPI watchdog >/dev/null 2>&1; then
        echo -e "  ${GREEN}${ICO_OK} Semua modul dasar berhasil terinstal!${RESET}"
    else
        echo -e "  ${YELLOW}${ICO_WARN} Instalasi modul dasar selesai dengan peringatan.${RESET}"
    fi

    # 4. Setup Demucs VENV (Opsional)
    echo -e "  ${CYAN}${ICO_ARROW} Mengecek komponen AI (Demucs Vocal Remover)...${RESET}"
    local demucs_venv="$HOME/.local/share/zdt/demucs_venv"
    if [ ! -f "$demucs_venv/bin/demucs" ]; then
        echo -e -n "  ${BOLD}[?] Komponen Demucs sangat besar (PyTorch ~2GB+). Instal sekarang? (y/N): ${RESET}"
        local ans
        read -r -n 1 ans; echo ""
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            echo -e "  ${YELLOW}Sedang mengunduh & menginstal Demucs... (Harap bersabar)${RESET}"
            python3 -m venv "$demucs_venv" >/dev/null 2>&1
            if "$demucs_venv/bin/pip" install -U pip setuptools demucs torchcodec >/dev/null 2>&1; then
                echo -e "  ${GREEN}${ICO_OK} Demucs berhasil diinstal!${RESET}"
            else
                echo -e "  ${RED}${ICO_FAIL} Gagal menginstal Demucs.${RESET}"
            fi
        else
            echo -e "  ${GRAY}Instalasi Demucs dilewati (Bisa diinstal otomatis nanti di menu [6]).${RESET}"
        fi
    else
        echo -e "  ${GRAY}  ${ICO_CHECK_OK} Demucs sudah terinstal${RESET}"
    fi

    echo ""
    echo -e "  ${GREEN}${ICO_OK} Proses Auto Install selesai!${RESET}"
    _log "INFO" "Tools installation completed"
    sleep 1
}

# ==========================================
# SYSTEM INFO
# ==========================================
system_info() {
    if [ -z "${NO_COLOR:-}" ]; then
        echo -ne "\033[?25h"
        clear
    fi
    echo ""

    local os_name=$(_get_os_name)
    local env=$(_detect_environment)
    local ram=$(_get_ram_percent)
    local storage=$(_get_storage_percent)
    local uptime_val=$(_get_uptime)
    local python_ver=$(python3 --version 2>/dev/null || echo "Missing")
    local bash_ver=$(bash --version | head -n1 | awk '{print $4}')

    local cols=$(tput cols 2>/dev/null || echo 80)
    local width=$(( cols - 4 ))
    [ "$width" -lt 50 ] && width=50
    [ "$width" -gt 76 ] && width=76

    local title=" SISTEM DIAGNOSTIK "
    local title_pad=$(_pad_str "$title" $width)
    
    echo -e "  ${CYAN}╭$(_repeat_char '─' $width)╮${RESET}"
    echo -e "  ${CYAN}│${RESET}${MAGENTA}${BOLD}${title_pad}${RESET}${CYAN}│${RESET}"
    echo -e "  ${CYAN}├$(_repeat_char '─' $width)┤${RESET}"

    local lines=(
        " ${GRAY}OS      :${RESET} $os_name"
        " ${GRAY}Env     :${RESET} $env"
        " ${GRAY}RAM     :${RESET} ${YELLOW}${ram}% USED${RESET}"
        " ${GRAY}Storage :${RESET} ${YELLOW}${storage}% FULL${RESET}"
        " ${GRAY}Uptime  :${RESET} $uptime_val"
        " ${GRAY}Python  :${RESET} $python_ver"
        " ${GRAY}Bash    :${RESET} $bash_ver"
        "DIVIDER"
        " ${MAGENTA}${BOLD}■ STATUS DEPENDENSI${RESET}"
    )

    for tool in ffmpeg python3 yt-dlp spotdl syncedlyrics mutagen flask demucs; do
        local stat=""
        if command -v "$tool" >/dev/null 2>&1; then
            local ver=$("$tool" --version 2>/dev/null | head -1 | awk '{print $1" "$2}' | tr -d '\r')
            if [ -z "$ver" ]; then ver="OK"; fi
            ver=${ver:0:25}
            stat="${GREEN}Installed${RESET} (${GRAY}${ver}${RESET})"
        elif [ -f "$ZDT_VENV_DIR/bin/$tool" ]; then
            stat="${GREEN}Installed${RESET} (VENV)"
        else
            stat="${RED}Missing${RESET}"
        fi
        
        local tool_disp="   ${CYAN}${tool}${RESET} $(_repeat_char '.' $(( 16 - ${#tool} )))"
        lines+=("${tool_disp} $stat")
    done

    for l_text in "${lines[@]}"; do
        if [ "$l_text" = "DIVIDER" ]; then
            echo -e "  ${CYAN}├$(_repeat_char '─' $width)┤${RESET}"
        else
            local l_pad=$(_pad_str "$l_text" $width)
            echo -e "  ${CYAN}│${RESET}${l_pad}${CYAN}│${RESET}"
        fi
    done

    echo -e "  ${CYAN}╰$(_repeat_char '─' $width)╯${RESET}"
    _pause
}

# ==========================================
# DOKUMENTASI
# ==========================================
tampilkan_dokumentasi() {
    print_header "DOKUMENTASI ZDT"
    
    local doc_text="
ZAKI DOWNLOADER TOOLS (ZDT) v$APP_VERSION
============================================

DAFTAR MENU:
  1. Setup & Install Tools   - Install/update dependencies & VENV
  2. Download Spotify         - Download lagu/playlist dari Spotify
  3. Download YouTube Audio   - Download audio dari YouTube/TikTok/dll
  4. Download Video           - Download video resolusi tinggi
  5. Kompres Media            - Kompres audio/video (multi-processing)
  6. Hapus Vokal (Demucs)     - Pisahkan vokal & instrumen pakai AI
  7. Auto Sync Lirik          - Cari & download lirik .lrc otomatis
  8. Generator Playlist       - Buat file .m3u dari folder
  9. Info Sistem              - Cek RAM, storage, versi tools
  S. Setup Storage            - Atur direktori penyimpanan
  W. Auto-Watch Daemon        - Pantau folder untuk auto-process
  P. Generator Playlist       - Buat playlist (.m3u)
  M. Metadata Editor          - Edit judul, artis, cover art
  O. Bersih Nama File         - Rapikan nama file kotor
  T. Telegram Bot             - Kontrol ZDT dari HP via Telegram
  V. Web Dashboard            - Akses ZDT dari browser
  U. Update Tools (VENV)      - Update tools Python
  A. Zaki AI Assistant        - Chat dengan AI untuk kontrol ZDT
  X. Hapus Semua File         - Bersihkan semua file media

ARGUMEN CLI:
  zdt --help                  - Tampilkan bantuan ini
  zdt --version               - Tampilkan versi
  zdt --no-color              - Nonaktifkan warna
  zdt --no-unicode            - Nonaktifkan emoji/unicode
  zdt --debug                 - Mode debug (error tracing)
  zdt --web                   - Jalankan Web Dashboard
  zdt --web-bind 0.0.0.0     - Web Dashboard untuk semua interface
  zdt --update                - Update ZDT via OTA
  zdt --download-audio <url>  - Download audio langsung
  zdt --download-video <url>  - Download video langsung
  zdt --spotify-sync <url>    - Sinkronisasi playlist Spotify
  zdt --kompres-media-all     - Kompres semua media
  zdt --extract-vocal-all     - Ekstrak vokal semua file
  zdt --sync-lirik-all        - Sinkronisasi lirik semua file
  zdt --bersih-nama-all       - Bersihkan nama semua file
  zdt --bikin-playlist-all    - Buat playlist dari semua file
  zdt --clean-file <path>     - Bersihkan 1 file spesifik

TROUBLESHOOTING:
  - Error 'command not found': Jalankan menu [1] Setup & Install Tools
  - Download gagal: Cek koneksi internet, atau update tools via [U]
  - Lirik tidak ditemukan: Coba manual dengan judul yang lebih spesifik
  - Demucs error: Pastikan RAM minimal 4GB dan ruang disk cukup
"

    if command -v less >/dev/null 2>&1; then
        echo "$doc_text" | less
    else
        echo "$doc_text"
        _pause
    fi
}

# ==========================================
# SETUP STORAGE DIR
# ==========================================
setup_storage_dir() {
    print_header "SETUP DIREKTORI PENYIMPANAN"
    
    local current_dir="${STORAGE_DIR:-$(pwd)}"
    echo -e "  ${CYAN}${ICO_ARROW} Direktori saat ini: ${YELLOW}$current_dir${RESET}"
    echo ""
    _print_menu_box "SETUP DIREKTORI" \
        "${GREEN}[1]${RESET} Gunakan direktori saat ini" \
        "${GREEN}[2]${RESET} Pilih folder spesifik" \
        "DIVIDER" \
        "${RED}[0]${RESET} KEMBALI"
    echo -e -n "  ${BOLD}[?] Pilihan [0-2]: ${RESET}"
    local pilihan
    read -r -n 1 pilihan; echo ""
    
    case "$pilihan" in
        1)
            STORAGE_DIR="$(pwd)"
            _config_set "storage_dir" "$STORAGE_DIR"
            ROOT_DIR="$STORAGE_DIR"
            echo -e "  ${GREEN}${ICO_OK} Storage diset ke: $STORAGE_DIR${RESET}"
            ;;
        2)
            echo -e -n "  ${BOLD}[?] Masukkan path lengkap: ${RESET}"
            local custom_path
            read -r -e custom_path
            custom_path="${custom_path//\'/}"
            custom_path="${custom_path//\"/}"
            custom_path="${custom_path#"${custom_path%%[![:space:]]*}"}"
            custom_path="${custom_path%"${custom_path##*[![:space:]]}"}"
            
            if [ -z "$custom_path" ]; then
                echo -e "  ${RED}${ICO_FAIL} Path kosong!${RESET}"
                return 0
            fi
            
            if [ ! -d "$custom_path" ]; then
                echo -e -n "  ${BOLD}[?] Direktori belum ada. Buat sekarang? (Y/n): ${RESET}"
                local buat
                read -r -n 1 buat; echo ""
                if [[ "$buat" =~ ^[Yy]$ ]] || [ -z "$buat" ]; then
                    mkdir -p "$custom_path"
                else
                    echo -e "  ${YELLOW}${ICO_ARROW} Dibatalkan.${RESET}"
                    return 0
                fi
            fi
            
            STORAGE_DIR="$custom_path"
            _config_set "storage_dir" "$STORAGE_DIR"
            ROOT_DIR="$STORAGE_DIR"
            echo -e "  ${GREEN}${ICO_OK} Storage diset ke: $STORAGE_DIR${RESET}"
            ;;
        *)
            return 0
            ;;
    esac
    
    _log "INFO" "Storage directory set to: $STORAGE_DIR"
    _pause
}

# ==========================================
# INSTALL GLOBAL
# ==========================================
install_global() {
    print_header "INSTALASI GLOBAL"

    local target_bin=""
    local target_share=""

    # Deteksi lokasi instalasi
    if [ -n "${TERMUX_VERSION:-}" ]; then
        target_bin="/data/data/com.termux/files/usr/bin/zdt"
        target_share="/data/data/com.termux/files/usr/share/zdt"
    elif [ "$(id -u)" -eq 0 ]; then
        target_bin="/usr/local/bin/zdt"
        target_share="/usr/local/share/zdt"
    else
        target_bin="$HOME/.local/bin/zdt"
        target_share="$HOME/.local/share/zdt"
    fi

    echo -e "  ${CYAN}${ICO_ARROW} Menginstal ZDT ke: ${YELLOW}$target_bin${RESET}"

    # Buat direktori
    mkdir -p "$(dirname "$target_bin")" 2>/dev/null || {
        echo -e "  ${RED}${ICO_FAIL} Tidak bisa membuat direktori. Coba dengan sudo?${RESET}"
        return 1
    }
    mkdir -p "$target_share" "$target_share/zdt-modules"

    # Copy main script & modules
    local script_dir
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    
    cp "$script_dir/zdt.sh" "$target_bin" 2>/dev/null || {
        echo -e "  ${RED}${ICO_FAIL} Gagal mengkopi script!${RESET}"
        return 1
    }
    chmod +x "$target_bin"

    # Copy modules
    for mod in "$script_dir/zdt-modules/"*.sh; do
        [ -f "$mod" ] && cp "$mod" "$target_share/zdt-modules/"
    done

    # Copy Python scripts
    for py_script in zdt-web.py zdt-telegram.py zdt-watch.py; do
        [ -f "$script_dir/$py_script" ] && cp "$script_dir/$py_script" "$target_share/"
    done

    # Buat desktop entry (jika ada)
    if [ -d "$HOME/.local/share/applications" ] && [ -z "${TERMUX_VERSION:-}" ]; then
        cat > "$HOME/.local/share/applications/zdt.desktop" <<DESKEOF
[Desktop Entry]
Name=ZDT Music Toolkit
Comment=Universal Music Downloader & Manager
Exec=$target_bin
Terminal=true
Type=Application
Categories=Audio;Video;Utility;
DESKEOF
        echo -e "  ${GREEN}${ICO_OK} Desktop entry dibuat!${RESET}"
    fi

    echo -e "  ${GREEN}${ICO_OK} Instalasi selesai! Jalankan dengan: ${BOLD}zdt${RESET}"
    
    if [[ ":$PATH:" != *":$(dirname "$target_bin"):"* ]]; then
        echo -e "  ${YELLOW}${ICO_WARN} Tambahkan $(dirname "$target_bin") ke PATH Anda:${RESET}"
        echo "    export PATH=\"\$PATH:$(dirname "$target_bin")\""
    fi
    
    _log "INFO" "Global installation completed at $target_bin"
}

# ==========================================
# PARSE CLI ARGUMENTS
# ==========================================
_parse_args() {
    ORIGINAL_ARGS=("$@")
    
    while [ $# -gt 0 ]; do
        case "$1" in
            --debug)
                ZDT_DEBUG=1
                set -o errtrace
                trap '_trap_err $LINENO $?' ERR
                shift
                ;;
            --no-color)
                NO_COLOR=1
                shift
                ;;
            --no-unicode)
                NO_UNICODE=1
                shift
                ;;
            --log-file)
                LOG_FILE="$2"
                shift 2
                ;;
            --version|-v)
                echo "$APP_NAME v$APP_VERSION"
                exit 0
                ;;
            --help|-h)
                tampilkan_dokumentasi
                exit 0
                ;;
            --install|install)
                install_global
                exit $?
                ;;
            --web|web)
                _setup_colors
                _setup_unicode
                _init_logging
                start_web_dashboard
                exit 0
                ;;
            --web-bind)
                WEB_BIND="$2"
                shift 2
                ;;
            --update|update)
                update_zdt_script
                exit 0
                ;;
            --download-audio)
                AUTO_DOWNLOAD_URL="$2"
                shift 2
                MAIN_MODE="download_audio"
                ;;
            --download-video)
                AUTO_DOWNLOAD_URL="$2"
                shift 2
                MAIN_MODE="download_video"
                ;;
            --spotify-sync)
                AUTO_DOWNLOAD_URL="$2"
                shift 2
                MAIN_MODE="spotify_sync"
                ;;
            --clean-file)
                CLEAN_FILE="$2"
                _setup_colors
                _setup_unicode
                _init_logging
                _load_config
                _load_storage_dir
                _bersih_satu_nama "$CLEAN_FILE"
                exit 0
                ;;
            --kompres-media-all)
                MAIN_MODE="kompres_media"
                ;;
            --extract-vocal-all)
                MAIN_MODE="extract_vocal"
                ;;
            --sync-lirik-all)
                MAIN_MODE="sync_lirik"
                ;;
            --bersih-nama-all)
                MAIN_MODE="bersih_nama"
                ;;
            --bikin-playlist-all)
                MAIN_MODE="bikin_playlist"
                ;;
            *)
                echo -e "Argumen tidak dikenal: $1"
                echo "Gunakan --help untuk melihat daftar argumen."
                exit 1
                ;;
        esac
    done
}
