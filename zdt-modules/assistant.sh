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
            " ${MAGENTA}${BOLD}🤖 ZAKI AI ASSISTANT v4.0${RESET}"
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
        input_escaped=$(echo "$input" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' ')

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

            local ai_prompt="IDENTITAS: Kamu Zaki-Bot, asisten pintar untuk ZDT (Zaki Downloader Tools) v${APP_VERSION}.
BAHASA: WAJIB 100% Bahasa Indonesia santai. DILARANG bahasa Inggris. DILARANG tampilkan proses berpikir/reasoning.
FORMAT: Jawab LANGSUNG, singkat, dan jelas. Maksimal 3 kalimat. Pakai emoji jika perlu.
FITUR ZDT:
- Download: Spotify[2], YouTube Audio[3], Video[4] — support link langsung atau cari judul
- Editing: Kompres Audio/Video[5], Hapus Vokal AI Demucs[6], Edit Metadata[M], Bersih Nama File[O]
- Utilitas: Sync Lirik[7], Playlist Sync Spotify[8], Buat Playlist M3U[P], Watch Daemon[W]
- Sistem: Setup[1], Info Sistem[9], Storage[S], Web UI[V], Update OTA[U], Telegram Bot[T], Hapus File[X]
AKSI OTOMATIS: Jika user minta jalankan fitur, WAJIB tambahkan [AUTO_ACTION: <aksi>] di akhir jawaban.
Daftar aksi: gas download audio ytsearch1:<judul>, gas download video ytsearch1:<judul>, hapus vokal, kompres media, sync lirik, bersih nama, bikin playlist, gas web ui, gas info sistem, gas update, gas setup, gas daemon, gas telegram.
Contoh: User bilang 'download lagu Tulus Hati-Hati' -> jawab 'Siap Bos, gas download! [AUTO_ACTION: gas download audio ytsearch1:Tulus Hati-Hati]'
KONTEKS: Storage=$abs_path ($file_count file). File: $dir_contents"

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
    txt = re.sub(r"^(?:Let me|I need to|The user|User wants).*?\n", "", txt, flags=re.MULTILINE|re.IGNORECASE)
    txt = txt.strip()
    if txt:
        print(txt)
except:
    pass
'

                for tier_models in "${or_tiers[@]}"; do
                    local payload="{\"models\": $tier_models, \"messages\": $messages, \"max_tokens\": 180}"
                    
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
                local payload="{\"system_instruction\": {\"parts\": [{\"text\": \"$ai_prompt\"}]}, \"contents\": [$gemini_contents], \"generationConfig\": {\"maxOutputTokens\": 180}}"
                
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
                
                # Proses AUTO_ACTION
                if [[ "$ai_response" == *"[AUTO_ACTION:"* ]]; then
                    local action_match
                    action_match=$(echo "$ai_response" | grep -oP '\[AUTO_ACTION:\s*\K[^\]]+')
                    
                    case "$action_match" in
                        "gas download audio"*)
                            local dl_url=$(echo "$action_match" | sed 's/^gas download audio //')
                            AUTO_DOWNLOAD_URL="$dl_url"
                            echo -e "  ${CYAN}${ICO_ARROW} Mendownload audio: $dl_url${RESET}"
                            if [[ "$dl_url" =~ ytsearch1: ]]; then
                                download_ytdlp
                            else
                                download_spotdl
                            fi
                            ;;
                        "gas download video"*)
                            local dl_url=$(echo "$action_match" | sed 's/^gas download video //')
                            AUTO_DOWNLOAD_URL="$dl_url"
                            echo -e "  ${CYAN}${ICO_ARROW} Mendownload video: $dl_url${RESET}"
                            download_video
                            ;;
                        "hapus vokal")
                            echo -e "  ${CYAN}${ICO_ARROW} Memisahkan vokal...${RESET}"
                            AUTO_HAPUS_VOKAL_MODE="1"
                            AUTO_HAPUS_VOKAL_PATH=""
                            hapus_vokal
                            ;;
                        "kompres media")
                            echo -e "  ${CYAN}${ICO_ARROW} Kompres media...${RESET}"
                            _kompres_audio_batch
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
                            echo -e "  ${CYAN}${ICO_ARROW} Membuat playlist...${RESET}"
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
                            echo -e "  ${CYAN}${ICO_ARROW} Menjalankan Setup Menu...${RESET}"
                            install_missing_tools
                            ;;
                        "gas daemon")
                            echo -e "  ${CYAN}${ICO_ARROW} Menjalankan Watchdog Daemon...${RESET}"
                            start_watch_daemon
                            ;;
                        "gas telegram")
                            echo -e "  ${CYAN}${ICO_ARROW} Menjalankan Telegram Bot...${RESET}"
                            start_telegram_bot
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
            local clean_reply=$(echo "$reply_text" | sed 's/\[AUTO_ACTION:[^\]]*\]//g' | xargs)
            if [ -n "$clean_reply" ]; then
                echo ""
                echo -e "  ${MAGENTA}${ICO_ROCKET} ${BOLD}Zaki-Bot:${RESET} ${WHITE}$clean_reply${RESET}"
                _pause
            fi
        fi

        echo ""
    done
}
