# ==========================================
# ZDT Playlist Module
# ==========================================
# Lyrics sync, Spotify playlist sync, M3U playlist generator
# ==========================================

# ==========================================
# FUNGSI UTAMA: AUTO SYNC LIRIK
# ==========================================
auto_sync_lirik() {
    print_header "AUTO SYNC LIRIK (SCAN MISSING .LRC)"

    if ! _ensure_python_tool "syncedlyrics" "syncedlyrics" 0; then
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
        target_dir="${TARGET_DIR:-${ROOT_DIR:-.}}"
        AUTO_SYNC_LIRIK=""
        total_audio=$(_find_media_files "$target_dir" "all" | wc -l)
        total_missing=0
        while IFS= read -r af; do
            local fn="${af%.*}.lrc"
            [ ! -f "$fn" ] && ((total_missing++))
        done < <(_find_media_files "$target_dir" "all")
        if [ "$total_missing" -eq 0 ]; then
            return 0
        fi
    else
        while true; do
        if [ "$step" -eq 1 ]; then
            if ! pilih_folder_target; then return 0; fi
            target_dir="$TARGET_DIR"

            total_audio=$(_find_media_files "$target_dir" "all" | wc -l)
            total_missing=0
            while IFS= read -r af; do
                local fn="${af%.*}.lrc"
                [ ! -f "$fn" ] && ((total_missing++))
            done < <(_find_media_files "$target_dir" "all")

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
                query=$(echo "$LAST_DOWNLOAD_QUERY" | sed 's/.*ytsearch1://' | tr '+' ' ' | tr -d "\"'\\''")
            fi
            LAST_DOWNLOAD_QUERY=""
        fi

        if [ -z "$query" ]; then
            query=$(echo "$filename_noext" | sed -E 's/\([^)]*\)//g' | sed -E 's/\[[^]]*\]//g' | sed 's/-/ /g' | sed 's/  */ /g')
        fi

        echo -e "  ${YELLOW}${ICO_ARROW} Mendownload lirik:${RESET} $filename_noext"

        # Gunakan timeout untuk mencegah hang selamanya (max 30 detik per query)
        timeout 30 syncedlyrics "$query" -o "$lrc_file" >/dev/null 2>&1

        if [ -f "$lrc_file" ] && [ -s "$lrc_file" ]; then
            echo -e "    ${GREEN}${ICO_OK} Lirik Ditemukan!${RESET}"
            ((count_success++))
        else
            rm -f "$lrc_file" 2>/dev/null
            echo -e "    ${RED}${ICO_FAIL} Gagal menemukan lirik.${RESET}"
            ((count_failed++))
        fi
    done < <(_find_media_files "$target_dir" "all" | while IFS= read -r f; do stat -c "%Y %n" "$f" 2>/dev/null; done | sort -rn | cut -d' ' -f2-)

    echo -e "  ${CYAN}${ICO_ARROW} LAPORAN AUTO SYNC:${RESET}"
    echo -e "    ${GREEN}Sukses  :${RESET} $count_success lagu"
    echo -e "    ${RED}Gagal   :${RESET} $count_failed lagu"
    echo -e "    ${GRAY}Dilewati:${RESET} $count_skipped lagu (sudah punya lirik)"
    _log "INFO" "Lyric sync: success=$count_success failed=$count_failed skipped=$count_skipped"
}

# ==========================================
# FUNGSI UTAMA: SPOTIFY PLAYLIST SYNC
# ==========================================
sync_spotify_playlist() {
    print_header "SPOTIFY PLAYLIST SYNC"
    
    if ! _ensure_python_tool "spotdl" "spotdl" 0; then return 1; fi

    local target_dir
    if [ -n "$AUTO_MODE" ]; then
        target_dir="${STORAGE_DIR:-${TARGET_DIR:-${ROOT_DIR:-.}}}"
        echo -e "  ${CYAN}${ICO_ARROW} Auto-mode: menggunakan storage dir${RESET}"
    else
        if ! pilih_folder_target; then return 0; fi
        target_dir="$TARGET_DIR"
    fi

    local playlist_url=""
    if [ -n "$AUTO_DOWNLOAD_URL" ]; then
        playlist_url="$AUTO_DOWNLOAD_URL"
        AUTO_DOWNLOAD_URL=""
        echo -e "  ${CYAN}${ICO_ARROW} Sync playlist: ${YELLOW}$playlist_url${RESET}"
    elif [ -f "$HOME/.config/zdt/spotify_playlist.txt" ]; then
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

    # Duplicate Detector — cek DB apakah playlist ini sudah pernah di-sync
    local db_script="$_MODULES_DIR/zdt_db.py"
    local db_path="$ZDT_DB_PATH"
    if [ -f "$db_script" ] && [ -n "$playlist_url" ]; then
        local is_dup=$(python3 "$db_script" "$db_path" "check_duplicate" "$playlist_url" 2>/dev/null)
        if [ "$is_dup" = "True" ]; then
            if [ -n "$AUTO_MODE" ]; then
                echo -e "  ${YELLOW}${ICO_WARN} Playlist sudah pernah di-sync. Dilewati (auto mode).${RESET}"
                _log "INFO" "Spotify Sync skipped (duplicate, auto mode): $playlist_url"
                return 0
            fi
            echo -e "  ${YELLOW}${ICO_WARN} Playlist ini sudah pernah di-sinkronisasi sebelumnya!${RESET}"
            echo -n -e "  ${CYAN}Tetap lanjutkan sinkronisasi? (y/N) ${RESET}"
            local sync_confirm
            read -r sync_confirm
            if [[ ! "$sync_confirm" =~ ^[Yy]$ ]]; then
                echo -e "  ${GREEN}Dilewati.${RESET}"
                return 0
            fi
        fi
    fi

    echo -e "  ${YELLOW}${ICO_ARROW} Memulai sinkronisasi playlist (Mencari lagu baru)...${RESET}"
    cd "$target_dir" || return 1
    
    spotdl download "$playlist_url" --m3u "sync_playlist.m3u" --save-errors "sync_errors.txt" --format m4a --bitrate 128k
    
    # Record hasil download ke database
    _record_downloads "$target_dir" "spotify" "$playlist_url"
    
    # Juga record URL playlist secara eksplisit (tracking sync history)
    python3 "$db_script" "$db_path" add_download "__playlist_sync__" "$playlist_url" "spotify_sync" "0" 2>/dev/null || true
    
    echo -e "  ${GREEN}${ICO_OK} Sinkronisasi Selesai!${RESET}"
    _log "INFO" "Spotify Sync Completed: $playlist_url"
}

# ==========================================
# FUNGSI UTAMA: GENERATOR PLAYLIST
# ==========================================
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
