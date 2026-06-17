# ==========================================
# ZDT Helpers Module
# ==========================================
# Shared utility functions: dependency checks,
# folder selection, file cleaning, media scanning
# ==========================================

# ==========================================
# HELPER: VALIDASI DEPENDENCY
# ==========================================
_check_dependency() {
    local tool="$1"
    local required="${2:-false}"

    if command -v "$tool" >/dev/null 2>&1; then
        return 0
    fi

    if [ "$required" = "true" ]; then
        echo -e "  ${YELLOW}${ICO_ARROW} Alat '$tool' belum terinstal! Mengalihkan ke menu Setup...${RESET}"
        sleep 1
        install_missing_tools
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo -e "  ${RED}${ICO_FAIL} Alat '$tool' masih tidak ditemukan. Batal memproses!${RESET}"
            return 1
        fi
        return 0
    fi
    return 1
}

# ==========================================
# HELPER: SELECT TARGET FOLDER
# ==========================================
pilih_folder_target() {
    local folder_list=()
    local search_dir="${ROOT_DIR:-.}"
    _safe_find_dirs folder_list "$search_dir"

    local count=${#folder_list[@]}
    local options=()
    options+=("${RED}[0]${RESET} BATAL / KEMBALI")
    options+=("${GREEN}[1]${RESET} Semua ($search_dir)")
    
    if [ "$count" -gt 0 ]; then
        for ((i = 0; i < count; i++)); do
            local nama_f
            nama_f=$(basename "${folder_list[$i]}")
            options+=("[$((i + 2))] $nama_f")
        done
    else
        options+=("${GRAY}(Tidak ada sub-folder terdeteksi)${RESET}")
    fi

    local max_idx=$((count + 1))
    
    _print_menu_box "PILIH TARGET FOLDER" "${options[@]}"
    
    echo -e -n "  ${BOLD}[?] Pilihan [0-$max_idx] (Enter = 1): ${RESET}"
    local target_idx
    read -r target_idx
    echo ""

    if [ "$target_idx" = "0" ]; then
        echo -e "  ${YELLOW}${ICO_ARROW} Dibatalkan! Kembali ke menu utama...${RESET}"
        return 1
    elif [ -z "$target_idx" ] || [ "$target_idx" = "1" ]; then
        TARGET_DIR="$search_dir"
        echo -e "  ${GREEN}${ICO_OK} Target disetel ke: Semua ($search_dir)${RESET}"
        return 0
    elif [[ "$target_idx" =~ ^[0-9]+$ ]] && [ "$target_idx" -le "$max_idx" ] && [ "$target_idx" -gt 1 ]; then
        local subfolder
        subfolder=$(basename "${folder_list[$((target_idx - 2))]}")
        TARGET_DIR="$search_dir/$subfolder"
        echo -e "  ${GREEN}${ICO_OK} Target disetel ke: $TARGET_DIR${RESET}"
        return 0
    else
        echo -e "  ${RED}${ICO_FAIL} Pilihan tidak valid! Otomatis disetel ke Semua ($search_dir).${RESET}"
        TARGET_DIR="$search_dir"
        return 0
    fi
}

# ==========================================
# HELPER: PEMBERSIH NAMA FILE
# ==========================================
_bersih_satu_nama() {
    local file="$1"

    if [ ! -f "$file" ]; then
        return 0
    fi

    local dir base
    dir=$(dirname "$file")
    base=$(basename "$file")

    if ! command -v python3 >/dev/null 2>&1; then
        _log "WARN" "python3 tidak tersedia, skip pembersihan nama: $base"
        return 0
    fi

    local newbase
    newbase=$(python3 -c "
import re, sys, os
base = sys.argv[1]
name, ext = os.path.splitext(base)

name = re.sub(r'\s*[\(\[\s]*(?:Official|Live|Music|Video|Lyric|Audio|Performance|Acoustic|Cover|Lirik)[^\)\]]*[\)\]]?', '', name, flags=re.IGNORECASE)
name = re.sub(r'\s*[\(\[\s]*(?:4K|8K|HD|HQ|1080p|720p)[^\)\]]*[\)\]]?', '', name, flags=re.IGNORECASE)

name = re.sub(r'  +', ' ', name).strip()
name = re.sub(r' \.', '.', name)

print(name + ext)
" "$base" 2>/dev/null || echo "$base")

    if [ "$base" != "$newbase" ] && [ -n "$newbase" ]; then
        if [ -e "$dir/$newbase" ]; then
            local filename extension
            if [[ "$newbase" == *.* ]]; then
                filename="${newbase%.*}"
                extension="${newbase##*.}"
            else
                filename="$newbase"
                extension=""
            fi

            local counter=1
            if [ -n "$extension" ]; then
                while [ -e "$dir/${filename} (${counter}).${extension}" ]; do
                    ((counter++))
                done
                newbase="${filename} (${counter}).${extension}"
            else
                while [ -e "$dir/${filename} (${counter})" ]; do
                    ((counter++))
                done
                newbase="${filename} (${counter})"
            fi
        fi
        mv -- "$file" "$dir/$newbase" && echo -e "    ${GREEN}${ICO_OK} Dirapikan:${RESET} $newbase"
        _log "INFO" "Renamed: $base -> $newbase"
        
        # AUTO-TAGGER METADATA
        local final_file="$dir/$newbase"
        if [[ -f "$ZDT_VENV_DIR/bin/python" ]]; then
            "$ZDT_VENV_DIR/bin/python" -c "
import sys, os
try:
    import mutagen
    from mutagen.easyid3 import EasyID3
    from mutagen.mp4 import MP4
    from mutagen.flac import FLAC
    file_path = sys.argv[1]
    name_noext = os.path.splitext(os.path.basename(file_path))[0]
    artist = 'Unknown Artist'
    title = name_noext
    if ' - ' in name_noext:
        parts = name_noext.split(' - ', 1)
        artist = parts[0].strip()
        title = parts[1].strip()
    
    if file_path.lower().endswith('.mp3'):
        try:
            audio = EasyID3(file_path)
        except mutagen.id3.ID3NoHeaderError:
            audio = mutagen.File(file_path, easy=True)
            audio.add_tags()
        audio['title'] = title
        audio['artist'] = artist
        audio.save()
    elif file_path.lower().endswith('.m4a'):
        audio = MP4(file_path)
        audio['\xa9nam'] = title
        audio['\xa9ART'] = artist
        audio.save()
    elif file_path.lower().endswith('.flac'):
        audio = FLAC(file_path)
        audio['title'] = title
        audio['artist'] = artist
        audio.save()
except Exception:
    pass
" "$final_file" 2>/dev/null
        fi
    else
        echo -e "    ${GRAY}${ICO_CHECK_OK} Sudah rapi:${RESET} $base"
    fi
}

bersih_nama_otomatis() {
    local scan_dir="${1:-.}"
    echo -e "  ${CYAN}${ICO_ARROW} AUTO CLEAN NAMA FILE${RESET}"
    while IFS= read -r file; do
        _bersih_satu_nama "$file"
    done < <(find "$scan_dir" -type f \( -iname "*.m4a" -o -iname "*.mp3" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.ogg" -o -iname "*.opus" -o -iname "*.mp4" -o -iname "*.lrc" \) -mmin -60 2>/dev/null)
}

# ==========================================
# HELPER: SCAN MEDIA FILES (DRY)
# ==========================================
# _find_media_files <target_dir> <type> [extra_find_args...]
# type: "audio" | "video" | "all" | "lyrics"
_find_media_files() {
    local search_dir="$1"
    local media_type="$2"
    shift 2
    local extra_args=("$@")

    local find_args=("$search_dir" -type f)
    local ext_args=()

    case "$media_type" in
        audio)
            ext_args=("(" -iname "*.m4a" -o -iname "*.mp3" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.ogg" -o -iname "*.opus" ")")
            ;;
        video)
            ext_args=("(" -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.webm" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.ts" ")")
            ;;
        all)
            ext_args=("(" -iname "*.m4a" -o -iname "*.mp3" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.ogg" -o -iname "*.opus" -o -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.webm" ")")
            ;;
        lyrics)
            ext_args=(-iname "*.lrc")
            ;;
        media_with_lyrics)
            ext_args=("(" -iname "*.m4a" -o -iname "*.mp3" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.ogg" -o -iname "*.opus" -o -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.webm" -o -iname "*.lrc" ")")
            ;;
    esac

    find_args+=("${ext_args[@]}" "${extra_args[@]}")
    find "${find_args[@]}" 2>/dev/null
}

# ==========================================
# HELPER: KOMPRES AUDIO TUNGGAL
# ==========================================
_kompres_audio_file() {
    local file="$1"
    local codec="${2:-aac}"
    local bitrate="${3:-128k}"
    local target_ext="${4:-m4a}"

    if [ ! -f "$file" ]; then
        return 0
    fi

    if ! command -v ffmpeg >/dev/null 2>&1; then
        echo -e "    ${RED}${ICO_FAIL} ffmpeg tidak tersedia!${RESET}"
        return 1
    fi

    local dir base filename_noext ext_original
    dir=$(dirname "$file")
    base=$(basename "$file")
    filename_noext="${base%.*}"
    ext_original="${base##*.}"

    local temp_file="$dir/${filename_noext}_temp.${target_ext}"

    if ffmpeg -y -nostdin -v quiet -threads 2 -i "$file" -c:v copy -c:a "$codec" -b:a "$bitrate" "$temp_file"; then
        if [ "$file" != "$dir/${filename_noext}.${target_ext}" ]; then
            rm -f "$file"
        fi
        mv -- "$temp_file" "$dir/${filename_noext}.${target_ext}"
        if [ "$ext_original" != "$target_ext" ]; then
            echo -e "    ${GREEN}${ICO_OK} SUKSES KOMPRES:${RESET} $base ${GRAY}→ .${target_ext} ($codec $bitrate)${RESET}"
        else
            echo -e "    ${GREEN}${ICO_OK} SUKSES KOMPRES:${RESET} $base"
        fi
        _log "INFO" "Compressed: $base -> ${filename_noext}.${target_ext}"
    else
        rm -f "$temp_file"
        echo -e "    ${RED}${ICO_FAIL} GAGAL KOMPRES:${RESET} $base"
        _log "ERROR" "Compression failed: $base"
    fi
}

# ==========================================
# HELPER: KOMPRES VIDEO TUNGGAL
# ==========================================
_kompres_video_file() {
    local file="$1"
    local codec="${2:-libx265}"
    local v_qual="${3:--crf 28}"
    local target_ext="${4:-mp4}"

    if [ ! -f "$file" ]; then
        return 0
    fi

    if ! command -v ffmpeg >/dev/null 2>&1; then
        echo -e "    ${RED}${ICO_FAIL} ffmpeg tidak tersedia!${RESET}"
        return 1
    fi

    local dir base filename_noext ext_original
    dir=$(dirname "$file")
    base=$(basename "$file")
    filename_noext="${base%.*}"
    ext_original="${base##*.}"

    local temp_file="$dir/${filename_noext}_temp.${target_ext}"

    echo -e -n "    ${CYAN}${ICO_ARROW} Mengompresi ke $codec... Harap sabar! "
    local qual_arr=()
    read -r -a qual_arr <<< "$v_qual"

    ffmpeg -y -nostdin -v quiet -threads 2 -i "$file" -c:v "$codec" "${qual_arr[@]}" -preset fast -c:a aac -b:a 128k "$temp_file" &
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

    if [ "$f_exit" -eq 0 ] && [ -f "$temp_file" ]; then
        if [ "$file" != "$dir/${filename_noext}.${target_ext}" ]; then
            rm -f "$file"
        fi
        mv -- "$temp_file" "$dir/${filename_noext}.${target_ext}"
        echo -e "    ${GREEN}${ICO_OK} SUKSES KOMPRES VIDEO:${RESET} $base ${GRAY}→ .${target_ext} ($codec)${RESET}"
        _log "INFO" "Video compressed to $codec: $base"
    else
        rm -f "$temp_file"
        echo -e "    ${RED}${ICO_FAIL} GAGAL KOMPRES VIDEO:${RESET} $base"
        _log "ERROR" "Video compression failed: $base"
    fi
}
