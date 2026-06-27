# ==========================================
# ZDT Download Spotify Module
# ==========================================
# Spotify download via spotdl
# ==========================================


# ==========================================
# FUNGSI UTAMA: DOWNLOAD SPOTIFY
# ==========================================
download_spotdl() {
    print_header "DOWNLOAD DARI SPOTIFY"

    local link file
    local links=()
    local step=1

    if ! _ensure_python_tool "spotdl" "spotdl" 0; then
        return 1
    fi

    local original_dir
    original_dir=$(pwd)

    local folder_mode="" folder_manual_name="" format_pilih="" spotdl_ext=""
    local pilih_archive="" pilih_lirik="" lirik_args=() pilih_kompres="n"

    if [ -n "$AUTO_DOWNLOAD_URL" ] || [ -n "$AUTO_MODE" ]; then
        links=("$AUTO_DOWNLOAD_URL")
        AUTO_DOWNLOAD_URL=""
        # Auto mode: skip semua interactive prompts, pakai default
        folder_mode="3"
        format_pilih="${AUTO_FORMAT_SPEC:-1}"
        case $format_pilih in
            2) spotdl_ext="mp3" ;;
            3) spotdl_ext="flac" ;;
            4) spotdl_ext="wav" ;;
            5) spotdl_ext="opus" ;;
            6) spotdl_ext="ogg" ;;
            *) spotdl_ext="m4a" ;;
        esac
        pilih_archive="n"
        pilih_lirik="n"
        lirik_args=()
        pilih_kompres="n"
        if [ -z "$links" ] || [ -z "${links[*]}" ]; then
            echo -e "  ${RED}${ICO_FAIL} URL kosong! Batal.${RESET}"
            return 0
        fi
    else
        links=()
    fi

    while true; do
        if [ -n "$AUTO_MODE" ]; then
            break
        fi
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
                if ! _ask_folder_mode; then step=1; continue; fi
                folder_mode="$ZDT_FOLDER_MODE"
                folder_manual_name="$ZDT_FOLDER_MANUAL_NAME"
                step=4
            elif [ "$step" -eq 4 ]; then
                if ! _ask_format_audio; then step=2; continue; fi
                format_pilih="$ZDT_FORMAT_PILIH"
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
                echo -e -n "  ${BOLD}[?] Kompres otomatis 128kbps? (y/n/0=Kembali): ${RESET}"
                read -r -n 1 pilih_kompres
                echo ""
                if [ "$pilih_kompres" = "0" ]; then step=6; continue; fi
                step=8
            elif [ "$step" -eq 8 ]; then
                break
            fi
        done

    if [ -n "$folder_manual_name" ]; then
        mkdir -p "$folder_manual_name"
    fi

    echo -e "  ${CYAN}${ICO_ARROW} Mengeksekusi ${#links[@]} antrean Spotify...${RESET}"
    _log "INFO" "Spotify download started: ${#links[@]} links"

    for link in "${links[@]}"; do
        echo -e "  ${GRAY}──────────────────────────────────────────────────${RESET}"
        echo -e "  ${YELLOW}${ICO_ARROW} Memproses:${RESET} $link"

        # Duplicate Detector — cek DB apakah link ini sudah pernah didownload
        local db_script="$_MODULES_DIR/zdt_db.py"
        local db_path="$HOME/.config/zdt/zdt.db"
        if [ -f "$db_script" ] && [ -n "$link" ]; then
            local is_dup=$(python3 "$db_script" "$db_path" "check_duplicate" "$link" 2>/dev/null)
            if [ "$is_dup" = "True" ]; then
                if [ "${AUTO_MODE:-0}" = "1" ]; then
                    # Auto/web mode: skip tanpa prompt
                    echo -e "  ${YELLOW}${ICO_WARN} Tautan sudah ada di Database Statistik. Dilewati (auto mode).${RESET}"
                    continue
                fi
                echo -e "  ${YELLOW}${ICO_WARN} Peringatan: Tautan ini sudah ada di Database Statistik!${RESET}"
                echo -n -e "  ${CYAN}Apakah Anda yakin ingin mengunduh ulang? (y/N) ${RESET}"
                read -r dup_confirm
                if [[ ! "$dup_confirm" =~ ^[Yy]$ ]]; then
                    echo -e "  ${GREEN}Dilewati.${RESET}"
                    continue
                fi
            fi
        fi

        local output_tpl
        local auto_folder_name=""
        case "$folder_mode" in
            1)
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
                output_tpl="${auto_folder_name}/{artists}-{title}"
                echo -e "  ${GREEN}${ICO_OK} Auto-Folder:${RESET} $auto_folder_name/"
                ;;
            2)
                if [ -n "$folder_manual_name" ]; then
                    output_tpl="${folder_manual_name}/{artists}-{title}"
                else
                    output_tpl="{artists} - {title}"
                fi
                ;;
            *)
                output_tpl="{artists}-{title}"
                ;;
        esac

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

        local scan_dir
        scan_dir=$(_resolve_scan_dir "$folder_mode" "$auto_folder_name" "$folder_manual_name")

        # Record successful downloads to database immediately after download
        _record_downloads "$scan_dir" "spotify" "$link"

        _post_download_audio "$scan_dir" "$spotdl_ext" "$pilih_kompres"
    done

    _log "INFO" "Spotify download batch complete"
}

# ==========================================
# FUNGSI UTAMA: DOWNLOAD YOUTUBE
