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

# Only strip tags that are INSIDE parentheses () or brackets []
name = re.sub(r'\s*\([^)]*(?:Official|Music Video|Video Klip|Video Clip|Lyric Video|Audio Only|Live Performance|MV|Cover|Acoustic|Lirik)[^)]*\)', '', name, flags=re.IGNORECASE)
name = re.sub(r'\s*\[[^\]]*(?:Official|Music Video|Video Klip|Video Clip|Lyric Video|Audio Only|Live Performance|MV|Cover|Acoustic|Lirik)[^\]]*\]', '', name, flags=re.IGNORECASE)
name = re.sub(r'\s*[\(\[][^\)\]]*(4K|8K|HD|HQ|1080p|720p)[^\)\]]*[\)\]]', '', name, flags=re.IGNORECASE)

# Cleanup whitespace
name = re.sub(r'  +', ' ', name).strip()
name = re.sub(r' \.', '.', name)

# Strip common Indonesian music channel suffixes at the end
name = re.sub(r'\s*-\s*(DC MUSIK|DC PRODUCTION|DC\. PRODUCTION|Aneka Safari Records|Aneka Safari|Ageng Music|Global Musik Era Digital|Global Musik|Mabos Channel|Khatulistiwa Record|TA PRO Music|ENY SAGA|Eny Saga|Perdana Record|Sakura Record|Wahanamusik|Adita Music|Bintara|Sandi Records|RC Music|Ngapak|MUARA BINTANG|Teta Record)[^a-zA-Z0-9]*$', '', name, flags=re.IGNORECASE)

name = re.sub(r'\s*-\s*$', '', name).strip()

# SAFETY: never produce empty name
if not name:
    name = os.path.splitext(base)[0]

print(name + ext)
" "$base" 2>/dev/null || echo "$base")

    # Safety: skip if result is empty or just extension
    local newname_only="${newbase%.*}"
    if [ -z "$newname_only" ] || [ "$newbase" = "$base" ]; then
        return 0
    fi

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
    local mode="${2:-recent}"
    echo -e "  ${CYAN}${ICO_ARROW} AUTO CLEAN NAMA FILE${RESET}"
    local time_filter=()
    if [ "$mode" != "all" ]; then
        time_filter=(-mmin -60)
    fi
    while IFS= read -r file; do
        _bersih_satu_nama "$file"
    done < <(find "$scan_dir" -type f \( -iname "*.m4a" -o -iname "*.mp3" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.ogg" -o -iname "*.opus" -o -iname "*.mp4" -o -iname "*.lrc" \) "${time_filter[@]}" 2>/dev/null)
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

# ==========================================
# INTERACTIVE PLAYLIST SELECTOR
# ==========================================
_playlist_selector() {
    local url="$1"
    SELECTED_PLAYLIST_ITEMS=""
    
    echo -e -n "  ${CYAN}${ICO_ARROW} Mengambil daftar lagu dari playlist...${RESET} "
    
    local tmp_playlist="meta_temp_$$.playlist"
    
    # Run yt-dlp in background to show spinner
    yt-dlp --flat-playlist --print "%(playlist_index)s|%(url)s|%(title)s" "$url" > "$tmp_playlist" 2>/dev/null &
    local yt_pid=$!
    _zaki_spinner $yt_pid
    
    if [ ! -s "$tmp_playlist" ]; then
        echo -e "  ${RED}${ICO_FAIL} Gagal mengambil daftar playlist atau playlist kosong.${RESET}"
        rm -f "$tmp_playlist"
        return 1
    fi
    
    # Read playlist items into array
    local playlist_items=()
    while IFS= read -r line; do
        playlist_items+=("$line")
    done < "$tmp_playlist"
    rm -f "$tmp_playlist"
    
    local total_items=${#playlist_items[@]}
    local page_size=10
    local total_pages=$(( (total_items + page_size - 1) / page_size ))
    local current_page=1
    
    while true; do
        local start_idx=$(( (current_page - 1) * page_size ))
        local end_idx=$(( start_idx + page_size - 1 ))
        if [ "$end_idx" -ge "$total_items" ]; then
            end_idx=$(( total_items - 1 ))
        fi
        
        echo -e "\n  ${MAGENTA}■ DAFTAR LAGU PLAYLIST (Halaman $current_page dari $total_pages)${RESET}"
        echo -e "  ${GRAY}──────────────────────────────────────────────────${RESET}"
        
        for i in $(seq $start_idx $end_idx); do
            local item="${playlist_items[$i]}"
            local idx="${item%%|*}"
            local rest="${item#*|}"
            local title="${rest#*|}"
            
            # Truncate title if too long
            if [ ${#title} -gt 50 ]; then
                title="${title:0:47}..."
            fi
            echo -e "  ${GREEN}[$idx]${RESET} $title"
        done
        
        echo -e "  ${GRAY}──────────────────────────────────────────────────${RESET}"
        echo -e "  ${YELLOW}Navigasi:${RESET} [n] Next Page | [p] Prev Page | [0] Batal"
        echo -e -n "  ${BOLD}[?] Masukkan nomor lagu (contoh: 2 atau 1,4,7): ${RESET}"
        
        local user_input
        read -r user_input
        
        if [ -z "$user_input" ]; then
            continue
        elif [ "$user_input" = "0" ]; then
            return 1
        elif [ "${user_input,,}" = "n" ]; then
            if [ "$current_page" -lt "$total_pages" ]; then
                current_page=$((current_page + 1))
            fi
        elif [ "${user_input,,}" = "p" ]; then
            if [ "$current_page" -gt 1 ]; then
                current_page=$((current_page - 1))
            fi
        else
            # Validasi input regex: format "angka,angka" atau "angka"
            if [[ "$user_input" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
                SELECTED_PLAYLIST_ITEMS="$user_input"
                
                SELECTED_PLAYLIST_URLS=()
                IFS=',' read -ra sel_indices <<< "$user_input"
                for sel_idx in "${sel_indices[@]}"; do
                    # Strip leading zeros safely
                    sel_idx=$((10#$sel_idx))
                    for item in "${playlist_items[@]}"; do
                        local idx="${item%%|*}"
                        local num_idx=$((10#$idx))
                        if [ "$num_idx" -eq "$sel_idx" ]; then
                            local rest="${item#*|}"
                            local item_url="${rest%%|*}"
                            SELECTED_PLAYLIST_URLS+=("$item_url")
                            break
                        fi
                    done
                done
                
                return 0
            else
                echo -e "  ${RED}${ICO_FAIL} Input tidak valid! Masukkan angka atau pisahkan dengan koma.${RESET}"
                sleep 1
            fi
        fi
    done
}
