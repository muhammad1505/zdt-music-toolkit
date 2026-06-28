# ==========================================
# ZDT Media Module
# ==========================================
# Media compression, Demucs AI vocal removal,
# metadata editor, manual name cleaning
# ==========================================

# ==========================================
# FUNGSI UTAMA: KOMPRES MEDIA (WRAPPER)
# ==========================================
kompres_media() {
    while true; do
        print_header "SMART MEDIA COMPRESSOR"

        _print_menu_box "TIPE MEDIA" \
            "${GREEN}[1]${RESET} Audio" \
            "${GREEN}[2]${RESET} Video" \
            "DIVIDER" \
            "${RED}[0]${RESET} KEMBALI KE MENU UTAMA"
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
            _print_menu_box "CODEC AUDIO" \
                "${GREEN}[1]${RESET} AAC (Default, sangat kompatibel, .m4a)" \
                "${GREEN}[2]${RESET} MP3 (Libmp3lame, universal, .mp3)" \
                "${GREEN}[3]${RESET} FLAC (Lossless, ukuran besar, .flac)" \
                "${GREEN}[4]${RESET} OPUS (Ukuran kecil, suara jernih, .opus)" \
                "DIVIDER" \
                "${RED}[0]${RESET} KEMBALI"
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
            _print_menu_box "BITRATE AUDIO" \
                "${GREEN}[1]${RESET} 128k (Standar, ukuran kecil)" \
                "${GREEN}[2]${RESET} 192k (Menengah, bagus)" \
                "${GREEN}[3]${RESET} 256k (Tinggi, sangat bagus)" \
                "${GREEN}[4]${RESET} 320k (Maksimal, HQ)" \
                "DIVIDER" \
                "${RED}[0]${RESET} KEMBALI"
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
            _print_menu_box "JANGKAUAN SCAN" \
                "${GREEN}[1]${RESET} Semua file di target folder" \
                "${GREEN}[2]${RESET} File baru saja (60 menit terakhir)" \
                "DIVIDER" \
                "${RED}[0]${RESET} KEMBALI"
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

    find "$target_dir" -type f -name "*_temp.*" -delete 2>/dev/null

    local find_args=("$target_dir" -type f)
    # Always scan ALL audio formats, not just target extension.
    # This allows cross-format conversion (e.g. flac to m4a).
    find_args+=("(" -iname "*.m4a" -o -iname "*.mp3" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.ogg" -o -iname "*.opus" ")")
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
    local max_jobs
    max_jobs=$(nproc 2>/dev/null || echo 4)
    [ "$max_jobs" -gt 4 ] && max_jobs=4

    while IFS= read -r file; do
        ((current++))
        local percent=$((current * 100 / total_files))
        printf "  [%3d%%] %s ...\n" "$percent" "$(basename "$file")"
        
        _kompres_audio_file "$file" "$codec" "$bitrate" "$ext_pilih" >/dev/null 2>&1 &
        bg_pids+=($!)
        
        if [ ${#bg_pids[@]} -ge "$max_jobs" ]; then
            wait 2>/dev/null
            bg_pids=()
        fi
    done < <(find "${find_args[@]}" 2>/dev/null)
    
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
            _print_menu_box "CODEC VIDEO" \
                "${GREEN}[1]${RESET} x264/AVC (Kompatibel, cepat)" \
                "${GREEN}[2]${RESET} x265/HEVC (Default, ukuran sangat kecil)" \
                "${GREEN}[3]${RESET} AV1 (Ukuran terkecil, sangat lambat)" \
                "${GREEN}[4]${RESET} VP9 (Ringan, cocok untuk WebM)" \
                "DIVIDER" \
                "${RED}[0]${RESET} KEMBALI"
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
            _print_menu_box "KUALITAS (CRF / BITRATE)" \
                "${GREEN}[1]${RESET} CRF 28 (Default, ukuran kecil)" \
                "${GREEN}[2]${RESET} CRF 23 (Kualitas bagus, ukuran sedang)" \
                "${GREEN}[3]${RESET} Bitrate 2M (Kualitas stabil menengah)" \
                "${GREEN}[4]${RESET} Bitrate 5M (Kualitas tinggi)" \
                "DIVIDER" \
                "${RED}[0]${RESET} KEMBALI"
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
            _print_menu_box "FORMAT OUTPUT" \
                "${GREEN}[1]${RESET} MP4 (Paling Kompatibel)" \
                "${GREEN}[2]${RESET} MKV (Support banyak fitur/subtitle)" \
                "${GREEN}[3]${RESET} WebM (Khusus VP9/AV1)" \
                "${GREEN}[4]${RESET} Ikuti Codec (Default, .${default_ext})" \
                "DIVIDER" \
                "${RED}[0]${RESET} KEMBALI"
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
            _print_menu_box "JANGKAUAN SCAN" \
                "${GREEN}[1]${RESET} Semua file di target folder" \
                "${GREEN}[2]${RESET} File baru saja (60 menit terakhir)" \
                "DIVIDER" \
                "${RED}[0]${RESET} KEMBALI"
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

    find "$target_dir" -type f -name "*_temp.*" -delete 2>/dev/null

    local find_args=("$target_dir" -type f)
    find_args+=("(" -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.webm" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.ts" ")")
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
    local max_jobs
    max_jobs=$(nproc 2>/dev/null || echo 2)
    [ "$max_jobs" -gt 2 ] && max_jobs=2

    while IFS= read -r file; do
        ((current++))
        local percent=$((current * 100 / total_files))
        printf "  [%3d%%] %s ...\n" "$percent" "$(basename "$file")"
        
        _kompres_video_file "$file" "$codec" "$v_qual" "$target_ext" >/dev/null 2>&1 &
        bg_pids+=($!)
        
        if [ ${#bg_pids[@]} -ge "$max_jobs" ]; then
            wait 2>/dev/null
            bg_pids=()
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

    # Daftar temp directories yang perlu dibersihkan jika di-interupsi
    _DEMUCS_CLEANUP_DIRS=()
    _ZDT_ORIG_SIGINT=$(trap -p SIGINT 2>/dev/null || true)
    trap '_cleanup_demucs_temp' SIGINT SIGTERM
    
    local demucs_bin="${ZDT_DEMUCS_BIN:-$HOME/.local/share/zdt/demucs_venv/bin/demucs}"

    if [ ! -f "$demucs_bin" ]; then
        echo -e "  ${YELLOW}${ICO_WARN} Demucs AI belum terinstal.${RESET}"
        echo -e "  ${GRAY}Proses instalasi akan membuat virtual environment dan mendownload${RESET}"
        echo -e "  ${GRAY}library PyTorch & Demucs (total sekitar 2-3 GB).${RESET}"
        echo -e "  ${GRAY}  ⚠ Pastikan ada ruang disk minimal 4GB sebelum instalasi.${RESET}"
        echo -e -n "  ${BOLD}[?] Lanjutkan instalasi sekarang? [Y/n]: ${RESET}"
        local confirm
        read -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]] && [ -n "$confirm" ]; then
            echo -e "  ${RED}${ICO_FAIL} Instalasi dibatalkan.${RESET}"
            sleep 2
            return 0
        fi

        echo -e "\n  ${CYAN}${ICO_ARROW} Membuat Python Virtual Environment...${RESET}"
        if !        python3 -m venv "${ZDT_DEMUCS_VENV_DIR:-$HOME/.local/share/zdt/demucs_venv}"; then
            echo -e "  ${RED}${ICO_FAIL} Gagal membuat virtual environment. Pastikan paket python3-venv terinstal.${RESET}"
            sleep 2
            return 1
        fi

        echo -e "  ${CYAN}${ICO_ARROW} Mendownload & Menginstal Demucs (Ini butuh waktu cukup lama)...${RESET}"
        if ! "${ZDT_DEMUCS_VENV_DIR:-$HOME/.local/share/zdt/demucs_venv}/bin/pip" install -U pip setuptools demucs torchcodec; then
            echo -e "  ${RED}${ICO_FAIL} Gagal menginstal Demucs!${RESET}"
            rm -rf "${ZDT_DEMUCS_VENV_DIR:-$HOME/.local/share/zdt/demucs_venv}"
            sleep 2
            return 1
        fi
        echo -e "  ${GREEN}${ICO_OK} Demucs berhasil diinstal!${RESET}\n"
    fi

    # Auto-mode: jika AUTO_HAPUS_VOKAL_MODE di-set, proses semua file di storage dir tanpa interaktif
    local auto_mode=${AUTO_HAPUS_VOKAL_MODE:-0}
    AUTO_HAPUS_VOKAL_MODE=""

    local step=1
    local mode_proses=""
    local files_to_process=()

    local target_dir="${AUTO_HAPUS_VOKAL_PATH:-${STORAGE_DIR:-${TARGET_DIR:-${ROOT_DIR:-.}}}}"
    AUTO_HAPUS_VOKAL_PATH=""
    
    while true; do
        if [ "$step" -eq 1 ]; then
            if [ "$auto_mode" = "1" ]; then
                # Auto mode: proses semua file baru di storage dir
                mode_proses="1"
                step=2
                continue
            fi
            _print_menu_box "MODE PROSES" \
                "${GREEN}[1]${RESET} Semua File di Storage (Baru Didownload)" \
                "${GREEN}[2]${RESET} Per Folder Artis" \
                "${GREEN}[3]${RESET} Per Lagu Spesifik" \
                "DIVIDER" \
                "${RED}[0]${RESET} KEMBALI"
            echo -e -n "  ${BOLD}[?] Pilih Mode [0-3]: ${RESET}"
            read -r -n 1 mode_proses
            echo ""
            [ "$mode_proses" = "0" ] && return 0
            if [[ ! "$mode_proses" =~ ^[1-3]$ ]]; then
                echo -e "  ${RED}${ICO_FAIL} Pilihan tidak valid!${RESET}"
                continue
            fi
            step=2
        elif [ "$step" -eq 2 ]; then
            files_to_process=()
            if [ "$mode_proses" = "1" ]; then
                while IFS= read -r f; do
                    files_to_process+=("$f")
                done < <(_find_media_files "$target_dir" "all" "!" -name "*_karaoke.*" -mmin -60)
                step=4
                continue
            fi

            # Mode 2 & 3: Pilih Folder Artis
            echo -e "  ${CYAN}${ICO_ARROW} Menampilkan daftar folder artis di: ${YELLOW}$target_dir${RESET}"
            
            local fcount=0
            local folders=()
            folders+=("$target_dir")
            echo -e "    ${GREEN}[1]${RESET} [Root Folder / Tidak di dalam sub-folder]"
            fcount=1
            
            while IFS= read -r d; do
                if [ -n "$d" ]; then
                    ((fcount++))
                    folders+=("$d")
                    printf "    ${GREEN}[%d]${RESET} %s\n" "$fcount" "$(basename "$d")"
                fi
            done < <(find "$target_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
            
            if [ "$fcount" -eq 1 ]; then
                echo -e "  ${YELLOW}Tidak ada folder artis ditemukan.${RESET}"
            fi
            
            echo -e -n "\n  ${BOLD}[?] Pilih Folder [1-$fcount, 0=Kembali]: ${RESET}"
            local pilih_folder
            read -r pilih_folder
            if [ -z "$pilih_folder" ] || [ "$pilih_folder" = "0" ] || [ "$pilih_folder" -gt "$fcount" ]; then
                step=1; continue
            fi
            
            selected_folder="${folders[$((pilih_folder-1))]}"
            
            if [ "$mode_proses" = "2" ]; then
                local find_args=( -iname "*.mp3" -o -iname "*.m4a" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.ogg" -o -iname "*.opus" )
                while IFS= read -r f; do
                    files_to_process+=("$f")
                done < <(find "$selected_folder" -maxdepth 1 -type f \( "${find_args[@]}" \) ! -name "*_karaoke.*" 2>/dev/null)
                step=4
            else
                step=3
            fi
        elif [ "$step" -eq 3 ]; then
            # Mode 3: Per Lagu Spesifik
            local folder_display
            [ "$selected_folder" = "$target_dir" ] && folder_display="Root Storage" || folder_display="$(basename "$selected_folder")"
            echo -e "  ${CYAN}${ICO_ARROW} Menampilkan daftar lagu di: ${YELLOW}$folder_display${RESET}"
            local lcount=0
            local lagus=()
            local find_args=( -iname "*.mp3" -o -iname "*.m4a" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.ogg" -o -iname "*.opus" )
            
            while IFS= read -r f; do
                if [ -n "$f" ]; then
                    ((lcount++))
                    lagus+=("$f")
                    printf "    ${GREEN}[%d]${RESET} %s\n" "$lcount" "$(basename "$f")"
                fi
            done < <(find "$selected_folder" -maxdepth 1 -type f \( "${find_args[@]}" \) ! -name "*_karaoke.*" 2>/dev/null | sort)
            
            if [ "$lcount" -eq 0 ]; then
                echo -e "  ${RED}${ICO_FAIL} Tidak ada file media di folder ini!${RESET}"
                sleep 2
                step=2; continue
            fi
            
            echo -e -n "\n  ${BOLD}[?] Pilih Lagu [1-$lcount, 0=Kembali]: ${RESET}"
            local pilih_lagu
            read -r pilih_lagu
            if [ -z "$pilih_lagu" ] || [ "$pilih_lagu" = "0" ] || [ "$pilih_lagu" -gt "$lcount" ]; then
                step=2; continue
            fi
            
            files_to_process+=("${lagus[$((pilih_lagu-1))]}")
            step=4
        elif [ "$step" -eq 4 ]; then
            break
        fi
    done

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
        # Register cleanup directory (for Ctrl+C handling)
        _DEMUCS_CLEANUP_DIRS+=("$tmp_out_dir")

        local demucs_log="$tmp_out_dir/demucs.log"
        echo -e -n "    ${CYAN}${ICO_ARROW} [AI Demucs] Membedah vokal & instrumen... [0%]"
        OMP_NUM_THREADS=2 "$demucs_bin" -n htdemucs --two-stems=vocals "$file" -o "$tmp_out_dir" >"$demucs_log" 2>&1 &
        local fpid=$!
        local last_pct="0%"

        while kill -0 $fpid 2>/dev/null; do
            if [ -f "$demucs_log" ]; then
                local current_pct
                current_pct=$(tr '\r' '\n' < "$demucs_log" 2>/dev/null | grep -o '[0-9]\+%' | tail -n 1)
                if [ -n "$current_pct" ] && [ "$current_pct" != "$last_pct" ]; then
                    printf "\r    ${CYAN}${ICO_ARROW} [AI Demucs] Membedah vokal & instrumen... [%s]    " "$current_pct"
                    last_pct="$current_pct"
                fi
            fi
            sleep 0.2
        done
        wait $fpid
        local f_exit=$?
        printf "\r    ${CYAN}${ICO_ARROW} [AI Demucs] Membedah vokal & instrumen... [100%%]   \n"

        local novocals_file
        novocals_file=$(find "$tmp_out_dir" -name "no_vocals.wav" -type f 2>/dev/null | head -n 1)
        local final_output="$dir/${filename_noext}_karaoke.$ext_original"

        if [ "$f_exit" -eq 0 ] && [ -n "$novocals_file" ] && [ -f "$novocals_file" ]; then
            echo -e -n "    ${CYAN}${ICO_ARROW} Mengonversi ke format asli... "
            
            local src_bitrate
            src_bitrate=$(ffprobe -v error -select_streams a:0 -show_entries stream=bit_rate -of default=nw=1:nk=1 "$file" 2>/dev/null)
            if [[ "$src_bitrate" =~ ^[0-9]+$ ]] && [ "$src_bitrate" -gt 0 ] 2>/dev/null; then
                src_bitrate="$(( src_bitrate / 1000 ))k"
            else
                src_bitrate="128k"
            fi

            local has_video=0
            if ffprobe -v error -select_streams v:0 -show_entries stream=codec_type -of default=nw=1:nk=1 "$file" 2>/dev/null | grep -q "video"; then
                has_video=1
            fi

            local ext_lower
            ext_lower=$(echo "$ext_original" | tr '[:upper:]' '[:lower:]')

            if [ "$has_video" -eq 1 ]; then
                local a_codec="aac"
                [ "$ext_lower" = "mp3" ] && a_codec="libmp3lame"
                [ "$ext_lower" = "ogg" ] && a_codec="libvorbis"
                [ "$ext_lower" = "flac" ] && a_codec="flac"
                
                ffmpeg -y -nostdin -v quiet -threads 2 -i "$file" -i "$novocals_file" -map 0:v:0 -map 1:a:0 -c:v copy -c:a "$a_codec" -b:a "$src_bitrate" "$final_output" &
            elif [ "$ext_lower" = "wav" ]; then
                cp "$novocals_file" "$final_output" &
            elif [ "$ext_lower" = "flac" ]; then
                ffmpeg -y -nostdin -v quiet -threads 2 -i "$novocals_file" -c:a flac "$final_output" &
            elif [ "$ext_lower" = "mp3" ]; then
                ffmpeg -y -nostdin -v quiet -threads 2 -i "$novocals_file" -c:a libmp3lame -b:a "$src_bitrate" "$final_output" &
            else
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
            local f2_exit=$?
            echo -e "\b "

            if [ "$f2_exit" -eq 0 ] && [ -s "$final_output" ]; then
                rm -rf "$tmp_out_dir"
                echo -e "    ${GREEN}${ICO_OK} SUKSES:${RESET} ${filename_noext}_karaoke.$ext_original"
            else
                rm -f "$final_output" 2>/dev/null
                echo -e "    ${RED}${ICO_FAIL} GAGAL KONVERSI:${RESET} Ext: $ext_original. Data vokal mentah tersimpan di: $tmp_out_dir"
            fi
        else
            rm -rf "$tmp_out_dir"
            echo -e "    ${RED}${ICO_FAIL} GAGAL PROSES:${RESET} Pastikan RAM cukup & file tidak corrupt."
        fi
        echo -e "  ──────────────────────────────────────────────────"
    done

    # Bersihkan trap setelah selesai
    if [ -n "$_ZDT_ORIG_SIGINT" ]; then
        eval "$_ZDT_ORIG_SIGINT"
    else
        trap - SIGINT
    fi
    trap - SIGTERM
    _ZDT_ORIG_SIGINT=""
    echo -e "  ${GREEN}${ICO_OK} 100% Selesai!${RESET}"
    _log "INFO" "Demucs vocal removal complete: $current files"
}

# Cleanup handler untuk Demucs temp files — dipanggil saat Ctrl+C
_cleanup_demucs_temp() {
    local dir
    echo ""
    echo -e "  ${YELLOW}${ICO_WARN} Membersihkan file temporary Demucs...${RESET}"
    for dir in "${_DEMUCS_CLEANUP_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            rm -rf "$dir" 2>/dev/null
            echo -e "  ${GREEN}${ICO_OK} Dihapus: $dir${RESET}"
        fi
    done
    _DEMUCS_CLEANUP_DIRS=()
    if [ -n "$_ZDT_ORIG_SIGINT" ]; then
        eval "$_ZDT_ORIG_SIGINT"
    else
        trap - SIGINT
    fi
    trap - SIGTERM
    _ZDT_ORIG_SIGINT=""
}

# ==========================================
# FUNGSI UTAMA: BERSIH NAMA FILE MANUAL
# ==========================================
edit_metadata_manual() {
    print_header "METADATA & COVER ART EDITOR"
    if [ ! -f "$ZDT_VENV_DIR/bin/python" ]; then
        echo -e "  ${YELLOW}${ICO_ARROW} VENV Python belum siap! Mengalihkan ke menu Setup...${RESET}"
        sleep 1
        install_missing_tools
        if [ ! -f "$ZDT_VENV_DIR/bin/python" ]; then
            echo -e "  ${RED}${ICO_FAIL} VENV Python masih gagal diakses. Batal!${RESET}"
            sleep 2
            return 1
        fi
    fi

    echo -e "  ${CYAN}${ICO_ARROW} Menampilkan daftar file audio di folder saat ini...${RESET}"
    local count=0
    local files=()
    
    local search_dir="${TARGET_DIR:-${ROOT_DIR:-.}}"
    while IFS= read -r f; do
        if [ -n "$f" ]; then
            ((count++))
            files+=("$f")
            printf "    %2d. %s\n" "$count" "$(basename "$f")"
        fi
    done < <(find "$search_dir" -maxdepth 1 -type f \( -iname "*.mp3" -o -iname "*.m4a" -o -iname "*.flac" \) -exec stat -c "%Y %n" {} + 2>/dev/null | sort -nr | cut -d' ' -f2- | head -n 20)

    if [ "$count" -eq 0 ]; then
        echo -e "  ${RED}${ICO_FAIL} Tidak ada file audio di direktori ini!${RESET}"
        sleep 2
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
    
    new_cover=$(echo "$new_cover" | tr -d '"' | tr -d "'")

    echo -e "  ${YELLOW}${ICO_ARROW} Menyuntikkan metadata...${RESET}"
    local meta_output
    meta_output=$("$ZDT_VENV_DIR/bin/python" -c "
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
" "$selected_file" "$new_title" "$new_artist" "$new_cover" 2>&1)

    # Check Python output for SUCCESS
    if echo "$meta_output" | grep -q "SUCCESS"; then
        echo -e "  ${GREEN}${ICO_OK} Metadata berhasil diperbarui!${RESET}"
    else
        local err_msg=$(echo "$meta_output" | grep -oP 'ERROR:\s*\K.+' || echo "Unknown error")
        echo -e "  ${RED}${ICO_FAIL} Gagal memperbarui metadata: $err_msg${RESET}"
    fi
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
            _print_menu_box "JANGKAUAN SCAN" \
                "${GREEN}[1]${RESET} Semua file di folder tersebut" \
                "${GREEN}[2]${RESET} File baru saja (60 menit terakhir)" \
                "DIVIDER" \
                "${RED}[0]${RESET} KEMBALI"
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
    done < <(_find_media_files "$target_dir" "media_with_lyrics" "${time_arg[@]}")
    echo -e "  ${GREEN}${ICO_OK} Proses perapian nama selesai! ($count file diproses)${RESET}"
    _log "INFO" "Name cleaning done: $count files scanned"
}
