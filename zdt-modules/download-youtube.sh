# ==========================================
# ZDT Download YouTube Module
# ==========================================
# YouTube/YT-DLP and Video downloads
# ==========================================

# ==========================================
download_ytdlp() {
    print_header "SEDOT AUDIO (YOUTUBE/TIKTOK/IG/DLL)"

    local link file
    local links=()
    local step=1

    if ! _ensure_python_tool "yt-dlp" "yt-dlp" 0; then
        return 1
    fi

    local original_dir
    original_dir=$(pwd)

    local folder_mode="" folder_manual_name="" format_pilih="" yt_ext=""
    local pilih_archive="" pilih_chapter="" pilih_lirik="" pilih_kompres="n"
    if [ -n "$AUTO_DOWNLOAD_URL" ]; then
        links=("$AUTO_DOWNLOAD_URL")
        AUTO_DOWNLOAD_URL=""
        step=2
    fi

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
                _print_menu_box "MANAJEMEN FOLDER OUTPUT" \
                    "${GREEN}[1]${RESET} Auto-Folder per Artis/Channel Utama" \
                    "${GREEN}[2]${RESET} Bikin 1 Folder Manual" \
                    "${GREEN}[3]${RESET} Tanpa folder baru" \
                    "DIVIDER" \
                    "${RED}[0]${RESET} KEMBALI"
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
                _print_menu_box "FORMAT OUTPUT" \
                    "${GREEN}[1]${RESET} M4A  (Default, paling kompatibel, kualitas bagus)" \
                    "${GREEN}[2]${RESET} MP3  (Universal, didukung semua perangkat lama)" \
                    "${GREEN}[3]${RESET} FLAC (Lossless, kualitas tertinggi, ukuran besar)" \
                    "${GREEN}[4]${RESET} WAV  (Uncompressed, untuk studio/editing)" \
                    "${GREEN}[5]${RESET} OPUS (Modern, ukuran kecil, suara jernih)" \
                    "${GREEN}[6]${RESET} OGG  (Open source, bagus untuk streaming/game)" \
                    "DIVIDER" \
                    "${RED}[0]${RESET} KEMBALI"
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
                
                local has_playlist=0
                for l in "${links[@]}"; do
                    if [[ "$l" == *"list="* ]]; then has_playlist=1; break; fi
                done
                
                if [ "$has_playlist" -eq 1 ]; then
                    step=65
                else
                    pilih_playlist="n"
                    step=7
                fi
            elif [ "$step" -eq 65 ]; then
                _print_menu_box "DOWNLOAD PLAYLIST" \
                    "${GREEN}[1]${RESET} Download seluruh isi playlist" \
                    "${GREEN}[2]${RESET} Pilih lagu spesifik dari daftar" \
                    "DIVIDER" \
                    "${RED}[0]${RESET} KEMBALI"
                echo -e -n "  ${BOLD}[?] Pilihan [0-2]: ${RESET}"
                read -r -n 1 opsi_playlist
                echo ""
                if [ "$opsi_playlist" = "0" ]; then step=6; continue; fi
                if [ "$opsi_playlist" = "2" ]; then
                    local playlist_url=""
                    for l in "${links[@]}"; do
                        if [[ "$l" == *"list="* || "$l" == *"playlist"* ]]; then
                            playlist_url="$l"
                            break
                        fi
                    done
                    if [ -n "$playlist_url" ]; then
                        if ! _playlist_selector "$playlist_url"; then
                            # Canceled or failed
                            step=65
                            continue
                        fi
                        
                        local new_links=()
                        for l in "${links[@]}"; do
                            if [[ "$l" == *"list="* || "$l" == *"playlist"* ]]; then
                                new_links+=("${SELECTED_PLAYLIST_URLS[@]}")
                            else
                                new_links+=("$l")
                            fi
                        done
                        links=("${new_links[@]}")
                        pilih_playlist="n"
                    else
                        pilih_playlist="y"
                    fi
                else
                    pilih_playlist="y"
                fi
                step=7
            elif [ "$step" -eq 7 ]; then
            echo -e -n "  ${BOLD}[?] Auto-lirik via SyncedLyrics? (y/n/0=Kembali): ${RESET}"
            read -r -n 1 pilih_lirik
            echo ""
            if [ "$pilih_lirik" = "0" ]; then step=6; continue; fi
            if [[ "$yt_ext" == "m4a" || "$yt_ext" == "mp3" ]]; then step=8; else step=9; fi
        elif [ "$step" -eq 8 ]; then
            echo -e -n "  ${BOLD}[?] Kompres otomatis 128kbps? (y/n/0=Kembali): ${RESET}"
            read -r -n 1 pilih_kompres
            echo ""
            if [ "$pilih_kompres" = "0" ]; then step=7; continue; fi
            step=9
        elif [ "$step" -eq 9 ]; then
            break
        fi
    done

    if [ -n "$folder_manual_name" ]; then
        mkdir -p "$folder_manual_name"
    fi

    echo -e "  ${CYAN}${ICO_ARROW} Mengeksekusi ${#links[@]} antrean YouTube...${RESET}"
    _log "INFO" "YouTube download started: ${#links[@]} links"

    for link in "${links[@]}"; do
        echo -e "  ${GRAY}──────────────────────────────────────────────────${RESET}"
        echo -e "  ${YELLOW}${ICO_ARROW} Memproses:${RESET} $link"

        # Duplicate Detector
        local db_script="$_MODULES_DIR/zdt_db.py"
        local db_path="$HOME/.config/zdt/zdt.db"
        if [ -f "$db_script" ]; then
            local is_dup=$(python3 "$db_script" "$db_path" "check_duplicate" "$link" 2>/dev/null)
            if [ "$is_dup" = "True" ]; then
                echo -e "  ${YELLOW}${ICO_WARN} Peringatan: Tautan ini sudah ada di Database Statistik!${RESET}"
                echo -n -e "  ${CYAN}Apakah Anda yakin ingin mengunduh ulang? (y/N) ${RESET}"
                read -r dup_confirm
                if [[ ! "$dup_confirm" =~ ^[Yy]$ ]]; then
                    echo -e "  ${GREEN}Dilewati.${RESET}"
                    continue
                fi
            fi
        fi

        local output_template
        local auto_folder_name=""
        case "$folder_mode" in
            1)
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
                output_template="${auto_folder_name}/%(title)s.%(ext)s"
                echo -e "  ${GREEN}${ICO_OK} Auto-Folder:${RESET} $auto_folder_name/"
                ;;
            2)
                if [ -n "$folder_manual_name" ]; then
                    output_template="${folder_manual_name}/%(title)s.%(ext)s"
                else
                    output_template="%(title)s.%(ext)s"
                fi
                ;;
            *)
                output_template="%(title)s.%(ext)s"
                ;;
        esac

        echo -e "  ${CYAN}${ICO_ARROW} Mendownload Media...${RESET}"
        local dl_status=0
        local archive_arg=()
        if [[ "$pilih_archive" =~ ^[Yy]$ ]]; then
            archive_arg=("--download-archive" "$TARGET_DIR/.zdt_ytdlp_archive.txt")
        fi
        
        local chapter_arg=()
        if [[ "$pilih_chapter" =~ ^[Yy]$ ]]; then
            chapter_arg=("--split-chapters")
        fi

        local playlist_arg=()
        if [[ ! "$pilih_playlist" =~ ^[Yy]$ ]]; then
            playlist_arg=("--no-playlist")
        fi

        local bitrate_arg=()
        if [ -n "${AUTO_BITRATE:-}" ]; then
            bitrate_arg=("--audio-quality" "${AUTO_BITRATE}K")
        fi

        local dl_cmd=()
        case "$format_pilih" in
            1) 
                if [ -n "${AUTO_BITRATE:-}" ]; then
                    dl_cmd=(yt-dlp --no-warnings --no-mtime -x --audio-format m4a "${bitrate_arg[@]}" --embed-metadata --embed-thumbnail -o "$output_template" "${archive_arg[@]}" "${chapter_arg[@]}" "${playlist_arg[@]}" "$link")
                else
                    dl_cmd=(yt-dlp --no-warnings --no-mtime -f "ba[ext=m4a]/ba" --embed-metadata --embed-thumbnail -o "$output_template" "${archive_arg[@]}" "${chapter_arg[@]}" "${playlist_arg[@]}" "$link")
                fi
                ;;
            2) dl_cmd=(yt-dlp --no-warnings --no-mtime -x --audio-format mp3 "${bitrate_arg[@]}" --embed-metadata --embed-thumbnail -o "$output_template" "${archive_arg[@]}" "${chapter_arg[@]}" "${playlist_arg[@]}" "$link") ;;
            3) dl_cmd=(yt-dlp --no-warnings --no-mtime -x --audio-format flac "${bitrate_arg[@]}" --embed-metadata --embed-thumbnail -o "$output_template" "${archive_arg[@]}" "${chapter_arg[@]}" "${playlist_arg[@]}" "$link") ;;
            4) dl_cmd=(yt-dlp --no-warnings --no-mtime -x --audio-format wav "${bitrate_arg[@]}" -o "$output_template" "${archive_arg[@]}" "${chapter_arg[@]}" "${playlist_arg[@]}" "$link") ;;
            5) dl_cmd=(yt-dlp --no-warnings --no-mtime -x --audio-format opus "${bitrate_arg[@]}" --embed-metadata --embed-thumbnail -o "$output_template" "${archive_arg[@]}" "${chapter_arg[@]}" "${playlist_arg[@]}" "$link") ;;
            6) dl_cmd=(yt-dlp --no-warnings --no-mtime -x --audio-format ogg "${bitrate_arg[@]}" --embed-metadata --embed-thumbnail -o "$output_template" "${archive_arg[@]}" "${chapter_arg[@]}" "${playlist_arg[@]}" "$link") ;;
        esac

        _download_with_retry "${dl_cmd[@]}"
        dl_status=$?

        if [ "$dl_status" -ne 0 ]; then
            echo -e "  ${YELLOW}${ICO_WARN} Peringatan: Ada file yang gagal diunduh! Melanjutkan proses file yang berhasil...${RESET}"
            _log "WARN" "yt-dlp reported errors for: $link (exit: $dl_status)"
        fi

        local scan_dir="."
        if [ "$folder_mode" = "1" ] && [ -n "$auto_folder_name" ]; then
            scan_dir="./$auto_folder_name"
        elif [ "$folder_mode" = "2" ] && [ -n "$folder_manual_name" ]; then
            scan_dir="./$folder_manual_name"
        fi

        # Record successful downloads to database
        local source_name="youtube"
        if [[ "$link" == *"tiktok.com"* ]]; then source_name="tiktok"; fi
        if [[ "$link" == *"soundcloud.com"* ]]; then source_name="soundcloud"; fi
        if [[ "$link" == *"spotify.com"* ]]; then source_name="spotify"; fi
        _record_downloads "$scan_dir" "$source_name" "$link"

        if [[ "$pilih_lirik" =~ ^[Yy]$ && "$yt_ext" != "mp4" ]]; then
            echo -e "  ${CYAN}${ICO_ARROW} MENCARI LIRIK${RESET}"
            if _ensure_python_tool "syncedlyrics" "syncedlyrics" 0; then
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

        if [[ "$pilih_kompres" =~ ^[Yy]$ && "$yt_ext" != "mp4" ]]; then
            echo -e "  ${CYAN}${ICO_ARROW} AUTO COMPRESS AUDIO${RESET}"
            
            local c_codec="aac"
            local c_ext="m4a"
            if [ "$yt_ext" = "mp3" ]; then
                c_codec="libmp3lame"
                c_ext="mp3"
            fi
            
            while IFS= read -r file; do
                _kompres_audio_file "$file" "$c_codec" "128k" "$c_ext"
            done < <(find "$scan_dir" -type f -iname "*.$yt_ext" ! -name "*_temp.*" -mmin -60 2>/dev/null)
        fi

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

    if ! _ensure_python_tool "yt-dlp" "yt-dlp" 0; then
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
        step=2
    fi
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
                _print_menu_box "KUALITAS VIDEO" \
                    "${GREEN}[1]${RESET} Best Quality (Up to 4K/1080p)" \
                    "${GREEN}[2]${RESET} 1080p" \
                    "${GREEN}[3]${RESET} 720p" \
                    "${GREEN}[4]${RESET} 480p" \
                    "${GREEN}[5]${RESET} 360p" \
                    "DIVIDER" \
                    "${RED}[0]${RESET} KEMBALI"
                echo -e -n "  ${BOLD}[?] Pilihan [0-5]: ${RESET}"
                read -r -n 1 kualitas_pilih
                echo ""
                if [ "$kualitas_pilih" = "0" ]; then step=1; continue; fi
                step=3
            elif [ "$step" -eq 3 ]; then
                _print_menu_box "FORMAT VIDEO OUTPUT" \
                    "${GREEN}[1]${RESET} MP4  (Paling Kompatibel)" \
                    "${GREEN}[2]${RESET} MKV  (Multi-Track, Multi-Sub)" \
                    "${GREEN}[3]${RESET} WebM (Ringan, VP9/AV1)" \
                    "${GREEN}[4]${RESET} AVI  (Legacy / Kompatibel Lama)" \
                    "${GREEN}[5]${RESET} MOV  (Apple / Final Cut Pro)" \
                    "${GREEN}[6]${RESET} TS   (MPEG Transport Stream)" \
                    "DIVIDER" \
                    "${RED}[0]${RESET} KEMBALI"
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
            _print_menu_box "CODEC VIDEO" \
                "${GREEN}[1]${RESET} Copy     (Tanpa Re-encode, Cepat)" \
                "${GREEN}[2]${RESET} x264/H264 (Kompatibel, Cepat)" \
                "${GREEN}[3]${RESET} x265/HEVC (Ukuran Kecil, Lambat)" \
                "DIVIDER" \
                "${RED}[0]${RESET} KEMBALI"
            echo -e -n "  ${BOLD}[?] Pilih Codec [0-3]: ${RESET}"
            read -r -n 1 codec_pilih
            echo ""
            if [ "$codec_pilih" = "0" ]; then step=3; continue; fi
            step=5
        elif [ "$step" -eq 5 ]; then
            _print_menu_box "SUBTITLE" \
                "${GREEN}[1]${RESET} Embed Subtitle ke Video (jika ada)" \
                "${GREEN}[2]${RESET} Download Subtitle Terpisah (.srt)" \
                "${GREEN}[3]${RESET} Embed + Terpisah" \
                "${GREEN}[4]${RESET} Tanpa Subtitle" \
                "DIVIDER" \
                "${RED}[0]${RESET} KEMBALI"
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
            _print_menu_box "MANAJEMEN FOLDER OUTPUT" \
                "${GREEN}[1]${RESET} Auto-Folder per Channel/Playlist" \
                "${GREEN}[2]${RESET} Bikin 1 Folder Manual" \
                "${GREEN}[3]${RESET} Tanpa folder baru" \
                "DIVIDER" \
                "${RED}[0]${RESET} KEMBALI"
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
            
            local has_playlist=0
            for l in "${links[@]}"; do
                if [[ "$l" == *"list="* ]]; then has_playlist=1; break; fi
            done
            
            if [ "$has_playlist" -eq 1 ]; then
                step=95
            else
                pilih_playlist="n"
                step=10
            fi
        elif [ "$step" -eq 95 ]; then
            _print_menu_box "DOWNLOAD PLAYLIST" \
                "${GREEN}[1]${RESET} Download seluruh isi playlist" \
                "${GREEN}[2]${RESET} Pilih video spesifik dari daftar" \
                "DIVIDER" \
                "${RED}[0]${RESET} KEMBALI"
            echo -e -n "  ${BOLD}[?] Pilihan [0-2]: ${RESET}"
            read -r -n 1 opsi_playlist
            echo ""
            if [ "$opsi_playlist" = "0" ]; then step=9; continue; fi
            if [ "$opsi_playlist" = "2" ]; then
                local playlist_url=""
                for l in "${links[@]}"; do
                    if [[ "$l" == *"list="* || "$l" == *"playlist"* ]]; then
                        playlist_url="$l"
                        break
                    fi
                done
                if [ -n "$playlist_url" ]; then
                    if ! _playlist_selector "$playlist_url"; then
                        step=95
                        continue
                    fi
                    
                    local new_links=()
                    for l in "${links[@]}"; do
                        if [[ "$l" == *"list="* || "$l" == *"playlist"* ]]; then
                            new_links+=("${SELECTED_PLAYLIST_URLS[@]}")
                        else
                            new_links+=("$l")
                        fi
                    done
                    links=("${new_links[@]}")
                    pilih_playlist="n"
                else
                    pilih_playlist="y"
                fi
            else
                pilih_playlist="y"
            fi
            step=10
        elif [ "$step" -eq 10 ]; then
            break
        fi
    done

    if [ -n "$folder_manual_name" ]; then
        mkdir -p "$folder_manual_name"
    fi


    echo -e "  ${GREEN}${ICO_OK} Mengeksekusi ${#links[@]} antrean Video...${RESET}"

    for link in "${links[@]}"; do
        echo -e "  ${GRAY}──────────────────────────────────────────────────${RESET}"
        echo -e "  ${YELLOW}${ICO_ARROW} Memproses:${RESET} $link"

        # Duplicate Detector
        local db_script="$_MODULES_DIR/zdt_db.py"
        local db_path="$HOME/.config/zdt/zdt.db"
        if [ -f "$db_script" ]; then
            local is_dup=$(python3 "$db_script" "$db_path" "check_duplicate" "$link" 2>/dev/null)
            if [ "$is_dup" = "True" ]; then
                echo -e "  ${YELLOW}${ICO_WARN} Peringatan: Tautan ini sudah ada di Database Statistik!${RESET}"
                echo -n -e "  ${CYAN}Apakah Anda yakin ingin mengunduh ulang? (y/N) ${RESET}"
                read -r dup_confirm
                if [[ ! "$dup_confirm" =~ ^[Yy]$ ]]; then
                    echo -e "  ${GREEN}Dilewati.${RESET}"
                    continue
                fi
            fi
        fi

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
            archive_arg=("--download-archive" "$TARGET_DIR/.zdt_ytdlp_video_archive.txt")
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

        local playlist_arg=()
        if [[ ! "$pilih_playlist" =~ ^[Yy]$ ]]; then
            playlist_arg=("--no-playlist")
        fi

        local dl_cmd=(yt-dlp --no-warnings --no-mtime -f "$format_str" --embed-metadata --merge-output-format "$merge_format" -o "$output_template" "${archive_arg[@]}" "${chapter_arg[@]}" "${sub_args[@]}" "${playlist_arg[@]}" "$link")
        
        _download_with_retry "${dl_cmd[@]}"
        dl_status=$?
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
                local enc_exit=$?
                if [ "$enc_exit" -eq 0 ] && [ -f "$tmpfile" ]; then
                    mv "$tmpfile" "$file"
                    echo -e "\b${GREEN}${ICO_OK}${RESET}"
                else
                    rm -f "$tmpfile"
                    echo -e "\b${RED}${ICO_FAIL}${RESET}"
                fi
            done < <(find "$scan_dir" -type f -iname "*.$ext_video" ! -name "*_temp.*" -mmin -60 2>/dev/null)
        fi

        echo -e "  ${CYAN}${ICO_ARROW} AUTO CLEAN NAMA FILE${RESET}"
        while IFS= read -r file; do
            _bersih_satu_nama "$file"
        done < <(find "$scan_dir" -type f -iname "*.$ext_video" -mmin -60 2>/dev/null)
    done

    cd "$original_dir" || true
    _log "INFO" "Video download batch complete"
}
