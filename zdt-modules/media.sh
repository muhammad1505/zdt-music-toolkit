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

        echo -e "  ${CYAN}${ICO_ARROW} TIPE MEDIA${RESET}"
        echo "    1. Audio"
        echo "    2. Video"
        echo "    0. ${ICO_FAIL} KEMBALI KE MENU UTAMA"
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
            echo -e "  ${CYAN}${ICO_ARROW} CODEC AUDIO${RESET}"
            echo "    1. AAC (Default, sangat kompatibel, .m4a)"
            echo "    2. MP3 (Libmp3lame, universal, .mp3)"
            echo "    3. FLAC (Lossless, ukuran besar, .flac)"
            echo "    4. OPUS (Ukuran kecil, suara jernih, .opus)"
            echo "    0. ${ICO_FAIL} KEMBALI"
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
            echo -e "  ${CYAN}${ICO_ARROW} BITRATE AUDIO${RESET}"
            echo "    1. 128k (Standar, ukuran kecil)"
            echo "    2. 192k (Menengah, bagus)"
            echo "    3. 256k (Tinggi, sangat bagus)"
            echo "    4. 320k (Maksimal, HQ)"
            echo "    0. ${ICO_FAIL} KEMBALI"
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
            echo -e "  ${CYAN}${ICO_ARROW} JANGKAUAN SCAN${RESET}"
            echo "    1. Semua file di target folder"
            echo "    2. File baru saja (60 menit terakhir)"
            echo "    0. ${ICO_FAIL} KEMBALI"
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
    if [ -z "$ext_pilih" ]; then
        find_args+=("(" -iname "*.m4a" -o -iname "*.mp3" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.ogg" ")")
    else
        find_args+=(-iname "*.$ext_pilih")
    fi
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
    local max_jobs=$(nproc 2>/dev/null || echo 4)
    [ "$max_jobs" -gt 4 ] && max_jobs=4

    while IFS= read -r file; do
        ((current++))
        local percent=$((current * 100 / total_files))
        printf "  [%3d%%] %s ...\n" "$percent" "$(basename "$file")"
        
        _kompres_audio_file "$file" "$codec" "$bitrate" "$ext_pilih" >/dev/null 2>&1 &
        bg_pids+=($!)
        
        if [ ${#bg_pids[@]} -ge $max_jobs ]; then
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
            echo -e "  ${CYAN}${ICO_ARROW} CODEC VIDEO${RESET}"
            echo "    1. x264/AVC (Kompatibel, cepat)"
            echo "    2. x265/HEVC (Default, ukuran sangat kecil)"
            echo "    3. AV1 (Ukuran terkecil, sangat lambat)"
            echo "    4. VP9 (Ringan, cocok untuk WebM)"
            echo "    0. ${ICO_FAIL} KEMBALI"
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
            echo -e "  ${CYAN}${ICO_ARROW} KUALITAS (CRF / BITRATE)${RESET}"
            echo "    1. CRF 28 (Default, ukuran kecil)"
            echo "    2. CRF 23 (Kualitas bagus, ukuran sedang)"
            echo "    3. Bitrate 2M (Kualitas stabil menengah)"
            echo "    4. Bitrate 5M (Kualitas tinggi)"
            echo "    0. ${ICO_FAIL} KEMBALI"
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
            echo -e "  ${CYAN}${ICO_ARROW} FORMAT OUTPUT${RESET}"
            echo "    1. MP4 (Paling Kompatibel)"
            echo "    2. MKV (Support banyak fitur/subtitle)"
            echo "    3. WebM (Khusus VP9/AV1)"
            echo "    4. Ikuti Codec (Default, .${default_ext})"
            echo "    0. ${ICO_FAIL} KEMBALI"
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
            echo -e "  ${CYAN}${ICO_ARROW} JANGKAUAN SCAN${RESET}"
            echo "    1. Semua file di target folder"
            echo "    2. File baru saja (60 menit terakhir)"
            echo "    0. ${ICO_FAIL} KEMBALI"
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
    local max_jobs=$(nproc 2>/dev/null || echo 2)
    [ "$max_jobs" -gt 2 ] && max_jobs=2

    while IFS= read -r file; do
        ((current++))
        local percent=$((current * 100 / total_files))
        printf "  [%3d%%] %s ...\n" "$percent" "$(basename "$file")"
        
        _kompres_video_file "$file" "$codec" "$v_qual" "$target_ext" >/dev/null 2>&1 &
        bg_pids+=($!)
        
        if [ ${#bg_pids[@]} -ge $max_jobs ]; then
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

    local venv_dir="$HOME/.local/share/zdt/demucs_venv"
    local demucs_bin="$venv_dir/bin/demucs"

    if [ ! -f "$demucs_bin" ]; then
        echo -e "  ${YELLOW}${ICO_WARN} Demucs AI belum terinstal.${RESET}"
        echo -e "  ${GRAY}Proses instalasi akan membuat virtual environment dan mendownload${RESET}"
        echo -e "  ${GRAY}library PyTorch & Demucs (total sekitar 2-3 GB).${RESET}"
        echo -e -n "  ${BOLD}[?] Lanjutkan instalasi sekarang? [Y/n]: ${RESET}"
        local confirm
        read -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]] && [ -n "$confirm" ]; then
            echo -e "  ${RED}${ICO_FAIL} Instalasi dibatalkan.${RESET}"
            sleep 2
            return 0
        fi

        echo -e "\n  ${CYAN}${ICO_ARROW} Membuat Python Virtual Environment...${RESET}"
        if ! python3 -m venv "$venv_dir"; then
            echo -e "  ${RED}${ICO_FAIL} Gagal membuat virtual environment. Pastikan paket python3-venv terinstal.${RESET}"
            sleep 2
            return 1
        fi

        echo -e "  ${CYAN}${ICO_ARROW} Mendownload & Menginstal Demucs (Ini butuh waktu cukup lama)...${RESET}"
        if ! "$venv_dir/bin/pip" install -U pip setuptools demucs torchcodec; then
            echo -e "  ${RED}${ICO_FAIL} Gagal menginstal Demucs!${RESET}"
            rm -rf "$venv_dir"
            sleep 2
            return 1
        fi
        echo -e "  ${GREEN}${ICO_OK} Demucs berhasil diinstal!${RESET}\n"
    fi

    local step=1
    local mode_proses=""
    local files_to_process=()

    if [ -n "$AUTO_HAPUS_VOKAL_MODE" ]; then
        mode_proses="$AUTO_HAPUS_VOKAL_MODE"
        if [ "$mode_proses" = "1" ]; then
            local target_dir="${TARGET_DIR:-$(pwd)}"
            while IFS= read -r f; do
                files_to_process+=("$f")
            done < <(_find_media_files "$target_dir" "all" "!" -name "*_karaoke.*" -mmin -60)
        elif [ "$mode_proses" = "2" ]; then
            if [ -n "$AUTO_HAPUS_VOKAL_PATH" ] && [ -f "$AUTO_HAPUS_VOKAL_PATH" ]; then
                files_to_process+=("$AUTO_HAPUS_VOKAL_PATH")
            fi
        fi
        AUTO_HAPUS_VOKAL_MODE=""
        AUTO_HAPUS_VOKAL_PATH=""
    else
        while true; do
            if [ "$step" -eq 1 ]; then
                echo -e "  ${CYAN}${ICO_ARROW} MODE PROSES${RESET}"
                echo "    1. Batch (Satu Folder Penuh)"
                echo "    2. Satu File Spesifik"
                echo "    0. ${ICO_FAIL} KEMBALI"
                echo -e -n "  ${BOLD}[?] Pilih Mode [0-2]: ${RESET}"
                read -r -n 1 mode_proses
                echo ""
                [ "$mode_proses" = "0" ] && return 0
                if [[ ! "$mode_proses" =~ ^[1-2]$ ]]; then
                    echo -e "  ${RED}${ICO_FAIL} Pilihan tidak valid!${RESET}"
                    continue
                fi
                step=2
            elif [ "$step" -eq 2 ]; then
                files_to_process=()
                if [ "$mode_proses" = "1" ]; then
                    if ! pilih_folder_target; then step=1; continue; fi
                    local target_dir="$TARGET_DIR"

                    while IFS= read -r f; do
                        files_to_process+=("$f")
                    done < <(_find_media_files "$target_dir" "all" "!" -name "*_karaoke.*")

                elif [ "$mode_proses" = "2" ]; then
                    echo -e -n "  ${BOLD}[?] Masukkan path file lengkap (drag & drop, 0=Kembali): ${RESET}"
                    local file_input
                    read -r -e file_input
                    if [ "$file_input" = "0" ]; then step=1; continue; fi
                    
                    file_input="${file_input//\'/}"
                    file_input="${file_input//\"/}"
                    file_input="${file_input#"${file_input%%[![:space:]]*}"}"
                    file_input="${file_input%"${file_input##*[![:space:]]}"}"

                    if [ ! -f "$file_input" ]; then
                        echo -e "  ${RED}${ICO_FAIL} File tidak ditemukan!${RESET}"
                        continue
                    fi
                    files_to_process+=("$file_input")
                fi
                step=3
            elif [ "$step" -eq 3 ]; then
                break
            fi
        done
    fi

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

        echo -e -n "    ${CYAN}${ICO_ARROW} [AI Demucs] Membedah vokal & instrumen... "
        OMP_NUM_THREADS=2 "$demucs_bin" -n htdemucs --two-stems=vocals "$file" -o "$tmp_out_dir" >/dev/null 2>&1 &
        local fpid=$!
        local spin='-\|/'
        local i=0
        while kill -0 $fpid 2>/dev/null; do
            i=$(( (i+1) %4 ))
            printf "\b${spin:$i:1}"
            sleep 0.1
        done
        wait $fpid
        local f_exit=$?
        echo -e "\b "

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
                ffmpeg -y -nostdin -v quiet -threads 2 -i "$file" -i "$novocals_file" -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a "$src_bitrate" "$final_output" &
            elif [ "$ext_lower" = "wav" ] || [ "$ext_lower" = "flac" ]; then
                cp "$novocals_file" "$final_output" &
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
            echo -e "\b "

            rm -rf "$tmp_out_dir"
            echo -e "    ${GREEN}${ICO_OK} SUKSES:${RESET} ${filename_noext}_karaoke.$ext_original"
        else
            rm -rf "$tmp_out_dir"
            echo -e "    ${RED}${ICO_FAIL} GAGAL PROSES:${RESET} Pastikan RAM cukup & file tidak corrupt."
        fi
        echo -e "  ──────────────────────────────────────────────────"
    done

    echo -e "  ${GREEN}${ICO_OK} 100% Selesai!${RESET}"
    _log "INFO" "Demucs vocal removal complete: $current files"
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
    
    local search_dir="${TARGET_DIR:-$(pwd)}"
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
    "$ZDT_VENV_DIR/bin/python" -c "
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
" "$selected_file" "$new_title" "$new_artist" "$new_cover"

    echo -e "  ${GREEN}${ICO_OK} Metadata berhasil diperbarui!${RESET}"
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
            echo -e "  ${CYAN}${ICO_ARROW} JANGKAUAN SCAN${RESET}"
            echo "    1. Semua file di folder tersebut"
            echo "    2. File baru saja (60 menit terakhir)"
            echo "    0. ${ICO_FAIL} KEMBALI"
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
