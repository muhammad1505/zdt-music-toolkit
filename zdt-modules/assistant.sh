# ==========================================
# ZDT Zaki AI Assistant Module v4.0
# ==========================================
# Professional AI interface with conversation
# memory, multi-tier model fallback, and
# structured intent recognition
# ==========================================

# Conversation history (kept in memory)
declare -a ZDT_CHAT_HISTORY=()

_zaki_add_history() {
    local role="$1" content="$2"
    ZDT_CHAT_HISTORY+=("{\"role\": \"$role\", \"content\": \"$content\"}")
    # Keep only last 10 entries (5 user + 5 assistant)
    if [ ${#ZDT_CHAT_HISTORY[@]} -gt 10 ]; then
        ZDT_CHAT_HISTORY=("${ZDT_CHAT_HISTORY[@]:2}")
    fi
}

_zaki_build_messages() {
    local system_prompt="$1"
    local result="{\"role\": \"system\", \"content\": \"$system_prompt\"}"
    for msg in "${ZDT_CHAT_HISTORY[@]}"; do
        result="$result, $msg"
    done
    echo "[$result]"
}

_zaki_spinner() {
    local pid=$1
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    echo -ne "  ${MAGENTA}"
    while kill -0 "$pid" 2>/dev/null; do
        echo -ne "\r  ${MAGENTA}${frames[$i]} Zaki-Bot sedang mikir...${RESET}  "
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.12
    done
    echo -ne "\r                                      \r"
}

# ==========================================
# ZAKI AI ASSISTANT
# ==========================================
zaki_assistant() {
    local gemini_key=""
    local gemini_key_file="$HOME/.config/zdt/gemini_key"

    if [ -f "$gemini_key_file" ]; then
        gemini_key=$(cat "$gemini_key_file" | tr -d '[:space:]')
    fi

    while true; do
        if [ -z "${NO_COLOR:-}" ]; then
            echo -ne "\033[?25h"
            clear 2>/dev/null || printf "\033c"
        fi
        echo ""
        local jam
        jam=$(date +%H 2>/dev/null || echo "12")
        local salam="Selamat datang"
        if [ "$jam" -lt 12 ]; then
            salam="Selamat pagi"
        elif [ "$jam" -lt 18 ]; then
            salam="Selamat siang"
        else
            salam="Selamat malam"
        fi

        local total_kapasitas="N/A"
        local sisa="N/A"
        if command -v df >/dev/null 2>&1; then
            total_kapasitas=$(df -h . 2>/dev/null | awk 'NR==2{print $2}')
            sisa=$(df -h . 2>/dev/null | awk 'NR==2{print $4}')
        fi

        local ai_status="${RED}Belum Dikonfigurasi${RESET}"
        if [ -n "$gemini_key" ]; then
            if [[ "$gemini_key" == sk-or-* ]]; then
                ai_status="${GREEN}OpenRouter Connected${RESET}"
            else
                ai_status="${GREEN}Gemini Connected${RESET}"
            fi
        fi

        local ai_opts=(
            " ${MAGENTA}${BOLD}■ ZAKI AI ASSISTANT v4.0${RESET}"
            " ${WHITE}${salam} Bos! Aku siap bantu automasi tugasmu.${RESET}"
            "DIVIDER"
            " ${CYAN}Storage :${RESET} ${sisa} free of ${total_kapasitas}"
            " ${CYAN}AI API  :${RESET} $ai_status"
            " ${CYAN}Memori  :${RESET} ${#ZDT_CHAT_HISTORY[@]} pesan tersimpan"
            "DIVIDER"
            " ${GREEN}Ketik apa saja dengan bahasa sehari-hari, atau:${RESET}"
            "  ${YELLOW}[?]${RESET} Bantuan Cepat       ${YELLOW}[!]${RESET} Reset Memori"
            "  ${RED}[0]${RESET} Kembali ke Menu Utama"
        )
        _print_menu_box "ZAKI AI" "${ai_opts[@]}"
        echo ""

        # Handle auto-actions dari bot
        if [ -n "$ZDT_AUTO_KOMPRES" ]; then
            echo -e "  ${CYAN}${ICO_ARROW} Eksekusi: Kompres Media Batch${RESET}"
            ZDT_AUTO_KOMPRES=""
            _kompres_audio_batch
            echo ""
            continue
        fi

        if [ -n "$ZDT_AUTO_VOKAL" ]; then
            echo -e "  ${CYAN}${ICO_ARROW} Eksekusi: Ekstrak Vokal Batch${RESET}"
            local vokal_mode="$ZDT_AUTO_VOKAL"
            ZDT_AUTO_VOKAL=""
            AUTO_HAPUS_VOKAL_MODE="$vokal_mode"
            hapus_vokal
            echo ""
            continue
        fi

        if [ -n "$AUTO_SYNC_LIRIK" ]; then
            echo -e "  ${CYAN}${ICO_ARROW} Eksekusi: Auto Sync Lirik${RESET}"
            auto_sync_lirik
            echo ""
            continue
        fi

        if [ -n "$ZDT_AUTO_BERSIH" ]; then
            echo -e "  ${CYAN}${ICO_ARROW} Eksekusi: Bersih Nama File${RESET}"
            ZDT_AUTO_BERSIH=""
            bersih_nama_otomatis "."
            echo ""
            continue
        fi

        if [ -n "$ZDT_AUTO_PLAYLIST" ]; then
            echo -e "  ${CYAN}${ICO_ARROW} Eksekusi: Buat Playlist${RESET}"
            ZDT_AUTO_PLAYLIST=""
            bikin_playlist
            echo ""
            continue
        fi

        if [ -n "$AUTO_DOWNLOAD_URL" ]; then
            local url="$AUTO_DOWNLOAD_URL"
            AUTO_DOWNLOAD_URL=""
            if [[ "$url" =~ (youtube|youtu\\.be|tiktok|instagram|facebook) ]]; then
                echo -e "  ${CYAN}${ICO_ARROW} Deteksi link YouTube/Social - Download Audio${RESET}"
                download_ytdlp
            elif [[ "$url" =~ spotify ]]; then
                echo -e "  ${CYAN}${ICO_ARROW} Deteksi link Spotify - Download${RESET}"
                download_spotdl
            else
                echo -e "  ${CYAN}${ICO_ARROW} Download Audio dari link${RESET}"
                download_ytdlp
            fi
            echo ""
            continue
        fi

        # Tampilkan prompt
        echo -e "  ${MAGENTA}${ICO_PLAY} ${BOLD}Tanya Zaki-Bot:${RESET}"
        
        # Wrap input dengan line continuation
        local bot_prompt=""
        while true; do
            echo -e -n "  ${MAGENTA}► ${RESET}"
            local current_input
            read -r current_input
            if [ -z "$current_input" ]; then
                break
            fi
            if [ -n "$bot_prompt" ]; then
                bot_prompt="$bot_prompt $current_input"
            else
                bot_prompt="$current_input"
            fi
            if [[ "$current_input" != *"\\" ]]; then
                break
            fi
            bot_prompt="${bot_prompt%\\}"
        done

        local input="${bot_prompt,,}"
        input="${input//\"/}"
        input="${input//\'/}"

        [ -z "$input" ] && continue

        # Handle exit
        if [ "$input" = "0" ] || [ "$input" = "exit" ] || [ "$input" = "quit" ] || [ "$input" = "keluar" ] || [ "$input" = "back" ] || [ "$input" = "menu" ] || [ "$input" = "kembali" ]; then
            echo -e "  ${YELLOW}${ICO_ARROW} Kembali ke menu utama...${RESET}"
            _release_lock
            return 0
        fi

        # Reset memory
        if [ "$input" = "!" ] || [ "$input" = "reset" ] || [ "$input" = "clear" ]; then
            ZDT_CHAT_HISTORY=()
            echo -e "  ${GREEN}${ICO_OK} Memori percakapan direset!${RESET}"
            sleep 1
            continue
        fi

        # Help
        if [ "$input" = "?" ] || [ "$input" = "help" ] || [ "$input" = "bantuan" ]; then
            echo ""
            local help_opts=(
                " ${WHITE}${BOLD}BANTUAN PINTAR ZAKI-BOT${RESET}"
                " Ngobrol aja pakai bahasa santai, contohnya:"
                "DIVIDER"
                " ${CYAN}▶ Download${RESET}"
                "   'download lagu Tulus Hati-Hati'"
                "   'sedot video youtube https://...'"
                "   'download playlist spotify https://...'"
                "DIVIDER"
                " ${CYAN}▶ Editing & Tools${RESET}"
                "   'kompres semua audio' / 'kompres video'"
                "   'pisahin vokal lagu ini'"
                "   'cariin lirik semua lagu'"
                "   'bersihin nama file yang berantakan'"
                "DIVIDER"
                " ${CYAN}▶ Sistem & Utilitas${RESET}"
                "   'info sistem' / 'cek status'"
                "   'buat playlist M3U'"
                "   'jalankan web ui' / 'update tools'"
                "DIVIDER"
                " ${CYAN}▶ Kontrol Bot${RESET}"
                "   ${YELLOW}[!]${RESET} Reset memori percakapan"
                "   ${RED}[0]${RESET} Kembali ke menu utama"
            )
            _print_menu_box "BANTUAN" "${help_opts[@]}"
            _pause
            continue
        fi

        # ==========================================
        # PROSES INPUT MENGGUNAKAN AI ATAU MANUAL
        # ==========================================
        local ai_used=false
        local reply_text=""

        # Escape for JSON safety
        local input_escaped
        input_escaped=$(echo "$bot_prompt" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' ')

        # Coba pakai AI jika ada key
        if [ -n "$gemini_key" ]; then
            local abs_path="${STORAGE_DIR:-$HOME/Music/ZDT}"
            local dir_contents=""
            if [ -d "$abs_path" ]; then
                dir_contents=$(ls "$abs_path" 2>/dev/null | head -15 | tr '\n' ', ')
            fi

            # File count stats
            local file_count=0
            if [ -d "$abs_path" ]; then
                file_count=$(find "$abs_path" -maxdepth 2 -type f \( -iname "*.mp3" -o -iname "*.m4a" -o -iname "*.flac" -o -iname "*.mp4" \) 2>/dev/null | wc -l)
            fi

            local ai_prompt="IDENTITAS: Kamu Zaki-Bot, asisten cerdas untuk ZDT (Zaki Downloader Tools) v${APP_VERSION}.
ATURAN WAJIB:
1. HARUS 100% Bahasa Indonesia santai/gaul. DILARANG bahasa Inggris.
2. DILARANG KERAS menampilkan proses berpikir (reasoning), rencana, atau analisis internal. JAWAB LANGSUNG!
3. Jawab singkat, jelas. Maksimal 3 kalimat. Boleh pakai emoji.
4. Jika user minta JALANKAN fitur, WAJIB sertakan tag [AUTO_ACTION: <aksi>] di akhir jawaban.
5. Jika user tanya/ngobrol biasa (bukan minta jalankan), jawab biasa TANPA AUTO_ACTION.
6. PROAKTIF! Jika user minta dicarikan 1 lagu, jalankan [AUTO_ACTION: gas download audio ytsearch1:<kata kunci>]. Jika minta PLAYLIST/MIX tanpa link, JANGAN gunakan AUTO_ACTION! Beritahu user untuk mengirimkan LINK PLAYLIST agar bot bisa mengunduh ratusan lagu dengan akurat.
7. LINK MENTAH! Jika user HANYA mengirimkan link tanpa perintah apa-apa (YouTube/TikTok/dll), langsung jalankan [AUTO_ACTION: gas download smart <url>]. Jika link Spotify, jalankan [AUTO_ACTION: gas spotify <url>].

DAFTAR LENGKAP 18 FITUR ZDT:
[1] Setup — Instal dependensi (ffmpeg, yt-dlp, spotdl, demucs) → aksi: gas setup
[2] Spotify DL — Download lagu/album/playlist dari Spotify → aksi: gas spotify <url>
[3] YT Audio — Download audio dari YouTube/TikTok/SoundCloud → aksi: gas download audio ytsearch1:<judul> (hanya untuk 1 lagu) atau gas download audio <url> (untuk link tunggal atau playlist)
[4] Video DL — Download video dari YouTube/TikTok → aksi: gas download video ytsearch1:<judul> atau gas download video <url>
[5] Kompres Audio — Perkecil ukuran file audio → aksi: kompres media
[5b] Kompres Video — Perkecil ukuran file video → aksi: kompres video
[6] Hapus Vokal — Pisahkan vokal dan instrumen pakai AI Demucs → aksi: hapus vokal
[7] Sync Lirik — Cari dan download file .lrc otomatis → aksi: sync lirik
[8] Playlist Sync — Sinkronisasi playlist Spotify (hanya download yang belum ada) → aksi: gas playlist sync <url>
[9] Info Sistem — Cek spesifikasi dan status dependensi → aksi: gas info sistem
[S] Storage — Ubah folder target download → aksi: gas storage
[W] Watch Daemon — Jalankan daemon otomatis bersih nama file → aksi: gas daemon
[P] Playlist M3U — Buat file playlist .m3u dari semua lagu → aksi: bikin playlist
[M] Metadata — Edit tag ID3 (judul/artis) file audio → aksi: gas metadata
[O] Bersih Nama — Hapus karakter aneh dari nama file → aksi: bersih nama
[T] Telegram Bot — Kendali ZDT jarak jauh via Telegram → aksi: gas telegram
[V] Web UI — Buka dashboard ZDT di browser → aksi: gas web ui
[U] Update — Update ZDT ke versi terbaru via OTA → aksi: gas update
[X] Hapus Semua — Hapus semua file media di folder target → aksi: gas hapus semua

CONTOH PENGGUNAAN:
- User: 'download lagu Tulus Hati-Hati' → 'Siap Bos, langsung gas download! 🎵 [AUTO_ACTION: gas download audio ytsearch1:Tulus Hati-Hati]'
- User: 'download spotify https://open.spotify.com/track/abc' → 'Oke gas download dari Spotify! 🎧 [AUTO_ACTION: gas spotify https://open.spotify.com/track/abc]'
- User: 'bersihin nama file dong' → 'Gas, aku rapihin nama filenya ya! ✨ [AUTO_ACTION: bersih nama]'
- User: 'apa itu demucs?' → 'Demucs itu AI dari Meta buat misahin vokal dan instrumen dari lagu. Keren banget buat bikin karaoke! 🎤' (TANPA AUTO_ACTION karena cuma tanya)
- User: 'hapus semua file' → 'Oke Bos, aku hapus semua file media di folder target ya! ⚠️ [AUTO_ACTION: gas hapus semua]'

KONTEKS SAAT INI: Storage=$abs_path ($file_count file media). Isi folder: $dir_contents"

            # Add current message to history
            _zaki_add_history "user" "$input_escaped"

            # Build messages with history
            local messages
            messages=$(_zaki_build_messages "$ai_prompt")

            local ai_response=""
            local ai_tmpfile="/tmp/.zdt_ai_resp_$$"

            if [[ "$gemini_key" == sk-or-* ]]; then
                # OpenRouter — Multi-tier fallback (max 3 models per request)
                local or_url="https://openrouter.ai/api/v1/chat/completions"
                local or_tiers=(
                    '["nvidia/nemotron-3-ultra-550b-a55b:free","openai/gpt-oss-120b:free","nousresearch/hermes-3-llama-3.1-405b:free"]'
                    '["nvidia/nemotron-3-super-120b-a12b:free","qwen/qwen3-next-80b-a3b-instruct:free","qwen/qwen3-coder:free"]'
                    '["meta-llama/llama-3.3-70b-instruct:free","google/gemma-4-31b-it:free","poolside/laguna-m.1:free"]'
                    '["nex-agi/nex-n2-pro:free","openai/gpt-oss-20b:free","nvidia/nemotron-nano-9b-v2:free"]'
                )

                local or_parse='
import sys, json, re
try:
    d = json.load(sys.stdin)
    if "error" in d:
        sys.exit(1)
    txt = d.get("choices",[{}])[0].get("message",{}).get("content","")
    txt = re.sub(r"<think>.*?</think>", "", txt, flags=re.DOTALL)
    txt = re.sub(r"<reasoning>.*?</reasoning>", "", txt, flags=re.DOTALL)
    txt = re.sub(r"\*\*(?:Thinking|Reasoning|Analysis|Internal|Step)[:\*].*?(?=\n[A-Z]|\n\n|$)", "", txt, flags=re.DOTALL|re.IGNORECASE)
    txt = re.sub(r"^(?:Let me|I need to|I will|I should|The user|User wants|User is|Okay,? the user|Looking at|Wait,|So,? the|First,? I|Now,? I|Alright|Here,? the).*?\n", "", txt, flags=re.MULTILINE|re.IGNORECASE)
    # Strip any remaining full-English sentences (no Indonesian chars)
    lines = txt.strip().split("\n")
    clean = []
    for line in lines:
        l = line.strip()
        if not l:
            continue
        # Skip lines that look like internal reasoning
        if re.match(r"^(Okay|Wait|Hmm|So|Now|Let|Looking|The user|I need|I will|I should|First|Alright|Here|We need|We should|As an AI|According|But|However|Because|Since|In YouTube|The link|If the user)", l, re.IGNORECASE):
            continue
        clean.append(line)
    txt = "\n".join(clean).strip()
    if txt:
        print(txt)
except:
    pass
'

                for tier_models in "${or_tiers[@]}"; do
                    local payload="{\"models\": $tier_models, \"messages\": $messages, \"max_tokens\": 500}"
                    
                    # Run curl in background with spinner
                    curl -s --max-time 20 -H "Authorization: Bearer $gemini_key" -H "Content-Type: application/json" -d "$payload" "$or_url" 2>/dev/null > "$ai_tmpfile" &
                    local curl_pid=$!
                    _zaki_spinner $curl_pid
                    wait $curl_pid 2>/dev/null

                    ai_response=$(cat "$ai_tmpfile" 2>/dev/null | python3 -c "$or_parse" 2>/dev/null)
                    [ -n "$ai_response" ] && break
                done
            else
                # Gemini
                local gemini_url="https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$gemini_key"
                local gemini_contents=""
                for msg in "${ZDT_CHAT_HISTORY[@]}"; do
                    local msg_role=$(echo "$msg" | python3 -c "import sys,json; m=json.loads(sys.stdin.read()); r=m['role']; print('user' if r=='user' else 'model')" 2>/dev/null)
                    local msg_content=$(echo "$msg" | python3 -c "import sys,json; m=json.loads(sys.stdin.read()); print(m['content'])" 2>/dev/null)
                    if [ -n "$gemini_contents" ]; then
                        gemini_contents="$gemini_contents, "
                    fi
                    gemini_contents="$gemini_contents{\"role\": \"$msg_role\", \"parts\": [{\"text\": \"$msg_content\"}]}"
                done
                local payload="{\"system_instruction\": {\"parts\": [{\"text\": \"$ai_prompt\"}]}, \"contents\": [$gemini_contents], \"generationConfig\": {\"maxOutputTokens\": 500}}"
                
                curl -s --max-time 20 -H "Content-Type: application/json" -d "$payload" "$gemini_url" 2>/dev/null > "$ai_tmpfile" &
                local curl_pid=$!
                _zaki_spinner $curl_pid
                wait $curl_pid 2>/dev/null

                ai_response=$(cat "$ai_tmpfile" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('candidates',[{}])[0].get('content',{}).get('parts',[{}])[0].get('text',''))" 2>/dev/null)
            fi

            rm -f "$ai_tmpfile" 2>/dev/null

            if [ -n "$ai_response" ]; then
                ai_used=true
                reply_text="$ai_response"
                
                # Save AI response to history
                local resp_escaped
                resp_escaped=$(echo "$ai_response" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' ')
                _zaki_add_history "assistant" "$resp_escaped"
                
                # Proses AUTO_ACTION (Case-Insensitive)
                local upper_response="${ai_response^^}"
                if [[ "$upper_response" == *"[AUTO_ACTION:"* ]]; then
                    local action_match
                    action_match=$(echo "$ai_response" | grep -ioP '\[AUTO_ACTION:\s*\K[^\]]+')
                    local action_match_lower="${action_match,,}"
                    
                    case "$action_match_lower" in
                        "gas download smart"*)
                            local smart_url=$(echo "$action_match" | sed 's/^gas download smart //I')
                            echo -e "  ${CYAN}${ICO_ARROW} Link terdeteksi: $smart_url${RESET}"
                            if [[ "$smart_url" =~ spotify ]]; then
                                AUTO_DOWNLOAD_URL="$smart_url"
                                download_spotdl
                            else
                                _print_menu_box "SMART DOWNLOAD" \
                                    "${GREEN}[1]${RESET} Download Audio (MP3/M4A/dll)" \
                                    "${GREEN}[2]${RESET} Download Video (MP4/MKV/dll)" \
                                    "DIVIDER" \
                                    "${RED}[0]${RESET} BATAL"
                                echo -e -n "  ${BOLD}[?] Download sebagai [0-2]: ${RESET}"
                                read -r -n 1 smart_choice
                                echo ""
                                if [ "$smart_choice" = "1" ]; then
                                    AUTO_DOWNLOAD_URL="$smart_url"
                                    download_ytdlp
                                elif [ "$smart_choice" = "2" ]; then
                                    AUTO_DOWNLOAD_URL="$smart_url"
                                    download_video
                                else
                                    echo -e "  ${YELLOW}${ICO_WARN} Dibatalkan.${RESET}"
                                fi
                            fi
                            ;;
                        "gas download audio"*)
                            local dl_url=$(echo "$action_match" | sed 's/^gas download audio //I')
                            AUTO_DOWNLOAD_URL="$dl_url"
                            echo -e "  ${CYAN}${ICO_ARROW} Mendownload audio: $dl_url${RESET}"
                            if [[ "$dl_url" =~ spotify ]]; then
                                download_spotdl
                            else
                                download_ytdlp
                            fi
                            ;;
                        "gas download video"*)
                            local dl_url=$(echo "$action_match" | sed 's/^gas download video //I')
                            AUTO_DOWNLOAD_URL="$dl_url"
                            echo -e "  ${CYAN}${ICO_ARROW} Mendownload video: $dl_url${RESET}"
                            download_video
                            ;;
                        "gas spotify"*)
                            local sp_url=$(echo "$action_match" | sed 's/^gas spotify //I')
                            AUTO_DOWNLOAD_URL="$sp_url"
                            echo -e "  ${CYAN}${ICO_ARROW} Download Spotify: $sp_url${RESET}"
                            download_spotdl
                            ;;
                        "gas playlist sync"*)
                            local ps_url=$(echo "$action_match" | sed 's/^gas playlist sync //I')
                            echo -e "  ${CYAN}${ICO_ARROW} Sinkronisasi playlist Spotify: $ps_url${RESET}"
                            sync_spotify_playlist
                            ;;
                        "hapus vokal")
                            echo -e "  ${CYAN}${ICO_ARROW} Memisahkan vokal...${RESET}"
                            AUTO_HAPUS_VOKAL_MODE="1"
                            AUTO_HAPUS_VOKAL_PATH=""
                            hapus_vokal
                            ;;
                        "kompres media")
                            echo -e "  ${CYAN}${ICO_ARROW} Kompres audio...${RESET}"
                            _kompres_audio_batch
                            ;;
                        "kompres video")
                            echo -e "  ${CYAN}${ICO_ARROW} Kompres video...${RESET}"
                            _kompres_video_batch
                            ;;
                        "sync lirik")
                            echo -e "  ${CYAN}${ICO_ARROW} Sinkronisasi lirik...${RESET}"
                            AUTO_SYNC_LIRIK="1"
                            auto_sync_lirik
                            ;;
                        "bersih nama")
                            echo -e "  ${CYAN}${ICO_ARROW} Membersihkan nama file...${RESET}"
                            bersih_nama_otomatis "."
                            ;;
                        "bikin playlist")
                            echo -e "  ${CYAN}${ICO_ARROW} Membuat playlist M3U...${RESET}"
                            bikin_playlist
                            ;;
                        "gas web ui")
                            echo -e "  ${CYAN}${ICO_ARROW} Meluncurkan Web UI...${RESET}"
                            start_web_dashboard
                            ;;
                        "gas info sistem")
                            echo -e "  ${CYAN}${ICO_ARROW} Menampilkan Info Sistem...${RESET}"
                            system_info
                            ;;
                        "gas update")
                            echo -e "  ${CYAN}${ICO_ARROW} Melakukan OTA Update...${RESET}"
                            update_zdt_script
                            ;;
                        "gas setup")
                            echo -e "  ${CYAN}${ICO_ARROW} Menjalankan Setup...${RESET}"
                            install_missing_tools
                            ;;
                        "gas daemon")
                            echo -e "  ${CYAN}${ICO_ARROW} Menjalankan Watch Daemon...${RESET}"
                            start_watch_daemon
                            ;;
                        "gas telegram")
                            echo -e "  ${CYAN}${ICO_ARROW} Menjalankan Telegram Bot...${RESET}"
                            start_telegram_bot
                            ;;
                        "gas metadata")
                            echo -e "  ${CYAN}${ICO_ARROW} Membuka Metadata Editor...${RESET}"
                            edit_metadata_manual
                            ;;
                        "gas storage")
                            echo -e "  ${CYAN}${ICO_ARROW} Mengubah folder Storage...${RESET}"
                            setup_storage_dir
                            ;;
                        "gas hapus semua")
                            echo -e "  ${YELLOW}${ICO_WARN} Menghapus semua file media...${RESET}"
                            hapus_semua
                            ;;
                    esac
                    
                    # Bersihkan AUTO_ACTION dari reply
                    reply_text=$(echo "$reply_text" | sed 's/\[AUTO_ACTION:[^\]]*\]//g')
                fi
            fi
        fi

        # Fallback: proses manual jika AI tidak digunakan/gagal
        if [ "$ai_used" = false ]; then
            # Download intent
            if [[ "$input" =~ (download|sedot|download\ audio|download\ lagu|download\ youtube|download\ video) ]]; then
                if [[ "$input" =~ (https?://|www\.) ]]; then
                    local detected_url=$(echo "$bot_prompt" | grep -oP 'https?://[^\s]+' | head -1)
                    if [[ "$detected_url" =~ (youtube|youtu\\.be|tiktok|instagram|facebook) ]]; then
                        if [[ "$input" =~ video ]]; then
                            echo -e "  ${CYAN}${ICO_ARROW} Download video dari: $detected_url${RESET}"
                            AUTO_DOWNLOAD_URL="$detected_url"
                            download_video
                        else
                            echo -e "  ${CYAN}${ICO_ARROW} Download audio dari: $detected_url${RESET}"
                            AUTO_DOWNLOAD_URL="$detected_url"
                            download_ytdlp
                        fi
                    elif [[ "$detected_url" =~ spotify ]]; then
                        echo -e "  ${CYAN}${ICO_ARROW} Download Spotify: $detected_url${RESET}"
                        AUTO_DOWNLOAD_URL="$detected_url"
                        download_spotdl
                    else
                        echo -e "  ${CYAN}${ICO_ARROW} Download dari: $detected_url${RESET}"
                        AUTO_DOWNLOAD_URL="$detected_url"
                        download_ytdlp
                    fi
                elif [[ "$input" =~ (youtube|yt|video) ]]; then
                    echo -e "  ${YELLOW}${ICO_WARN} Kirim link YouTube-nya juga dong!${RESET}"
                    echo -e "  ${GRAY}  Contoh: download youtube https://youtube.com/watch?v=...${RESET}"
                elif [[ "$input" =~ (spotify|lagu|musik) ]]; then
                    echo -e "  ${YELLOW}${ICO_WARN} Kirim link Spotify-nya juga dong!${RESET}"
                    echo -e "  ${GRAY}  Contoh: download spotify https://open.spotify.com/track/...${RESET}"
                fi

            # Kompres
            elif [[ "$input" =~ (kompres|compress|kecilin|kecilkan|perkecil) ]]; then
                if [[ "$input" =~ video ]]; then
                    _kompres_video_batch
                else
                    _kompres_audio_batch
                fi

            # Vokal
            elif [[ "$input" =~ (vokal|pisah|pisahin|karaoke|separate|demucs|suara|instrumen|instrument) ]]; then
                AUTO_HAPUS_VOKAL_MODE="1"
                AUTO_HAPUS_VOKAL_PATH=""
                hapus_vokal

            # Lirik
            elif [[ "$input" =~ (lirik|lyric|lyrics|teks|kata|kata2) ]]; then
                AUTO_SYNC_LIRIK="1"
                auto_sync_lirik

            # Bersih nama
            elif [[ "$input" =~ (bersih|bersihin|rapih|rapihin|clean|rename|rapikan|beresin) ]]; then
                bersih_nama_otomatis "."

            # Playlist
            elif [[ "$input" =~ (playlist|daftar\ lagu|m3u) ]]; then
                bikin_playlist

            # Info sistem
            elif [[ "$input" =~ (info|status|sistem|system|diagnostic|health|cek) ]]; then
                system_info

            # Update tools
            elif [[ "$input" =~ (update|upgrade|perbarui) ]]; then
                update_zdt_script

            # Setup/install
            elif [[ "$input" =~ (install|setup) ]]; then
                install_missing_tools

            # Storage
            elif [[ "$input" =~ (storage|folder|direktori|directory|path|save|simpan) ]]; then
                setup_storage_dir

            # Web UI
            elif [[ "$input" =~ (web|dashboard|browser) ]]; then
                start_web_dashboard

            # Telegram
            elif [[ "$input" =~ (telegram|bot) ]]; then
                start_telegram_bot

            # Watch daemon
            elif [[ "$input" =~ (watch|daemon|pantau|monitor) ]]; then
                start_watch_daemon

            # Halo / greetings
            elif [[ "$input" =~ (halo|hai|hi|hey|selamat|pagi|siang|sore|malam|bro|boss|bang|kak|woi) ]]; then
                echo ""
                echo -e "  ${MAGENTA}${ICO_ROCKET} ${BOLD}Zaki-Bot:${RESET} ${WHITE}Halo juga Bos! Ada yang bisa saya bantu hari ini? 😎${RESET}"
                _pause

            # Thanks
            elif [[ "$input" =~ (makasih|terima\ kasih|thanks|thank\ you|thx|tq|mantap|keren|gokil) ]]; then
                echo ""
                echo -e "  ${MAGENTA}${ICO_ROCKET} ${BOLD}Zaki-Bot:${RESET} ${WHITE}Sama-sama Bos! Senang bisa bantu! 🙏${RESET}"
                _pause

            # Sisanya
            else
                echo ""
                if [ -n "$gemini_key" ]; then
                    echo -e "  ${YELLOW}${ICO_WARN} Wah, AI lagi sibuk atau koneksi lambat. Coba lagi ya!${RESET}"
                    echo -e "  ${GRAY}  Ketik ${BOLD}?${RESET}${GRAY} untuk lihat daftar perintah yang bisa langsung dijalankan.${RESET}"
                else
                    echo -e "  ${YELLOW}${ICO_WARN} Hmm, aku belum bisa jawab itu. Ketik '?' buat lihat daftar perintah!${RESET}"
                    echo -e "  ${GRAY}  Tips: Isi file ~/.config/zdt/gemini_key dengan API Key untuk${RESET}"
                    echo -e "  ${GRAY}  mengaktifkan AI (Google Gemini atau OpenRouter).${RESET}"
                fi
                _pause
            fi
        else
            # Tampilkan reply AI
            local clean_reply=$(echo "$reply_text" | sed 's/\[AUTO_ACTION:[^\]]*\]//g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
            if [ -n "$clean_reply" ]; then
                echo ""
                echo -e "  ${MAGENTA}${ICO_ROCKET} ${BOLD}Zaki-Bot:${RESET} ${WHITE}$clean_reply${RESET}"
                _pause
            fi
        fi

        echo ""
    done
}
# Auto-version hook installed
