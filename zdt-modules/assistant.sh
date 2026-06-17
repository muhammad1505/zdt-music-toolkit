# ==========================================
# ZDT Zaki AI Assistant Module
# ==========================================
# Conversational AI interface with Gemini/OpenRouter integration
# ==========================================

# ==========================================
# ZAKI AI ASSISTANT
# ==========================================
zaki_assistant() {
    local gemini_key=""
    local gemini_key_file="$HOME/.config/zdt/gemini_key"

    if [ -f "$gemini_key_file" ]; then
        gemini_key=$(cat "$gemini_key_file")
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

        local ai_opts=(
            " ${MAGENTA}${BOLD}🤖 ZAKI AI ASSISTANT${RESET}"
            " ${WHITE}${salam} Bos! Aku siap bantu automasi tugasmu.${RESET}"
            "DIVIDER"
            " ${CYAN}Storage :${RESET} ${sisa} free of ${total_kapasitas}"
            " ${CYAN}AI API  :${RESET} $([ -n "$gemini_key" ] && echo "${GREEN}Connected${RESET}" || echo "${RED}Not Configured${RESET}")"
            "DIVIDER"
            " ${GREEN}Ketik apa saja dengan bahasa sehari-hari, atau:${RESET}"
            "  ${YELLOW}[?]${RESET} Bantuan Cepat"
            "  ${RED}[0]${RESET} Kembali ke Menu Utama"
        )
        _print_menu_box "${ai_opts[@]}"
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
            echo -e -n "  ${MAGENTA}► Ketik pesan:${RESET} "
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

        # Help
        if [ "$input" = "?" ] || [ "$input" = "help" ] || [ "$input" = "bantuan" ]; then
            echo ""
            local help_opts=(
                " ${WHITE}${BOLD}BANTUAN PINTAR ZAKI-BOT${RESET}"
                " Ngobrol aja pakai bahasa santai, contohnya:"
                "DIVIDER"
                " ${CYAN}▶ Download${RESET}"
                "   'download spotify https://...'"
                "   'sedot video youtube https://...'"
                "DIVIDER"
                " ${CYAN}▶ Editing & Kompresi${RESET}"
                "   'kompres audio' / 'kompres video'"
                "   'pisahin vokal' / 'hapus vokal'"
                "DIVIDER"
                " ${CYAN}▶ Utilitas Lainnya${RESET}"
                "   'cari lirik' / 'sync lirik'"
                "   'bersihin nama file'"
                "   'buat playlist'"
                "   'info sistem' / 'status'"
            )
            _print_menu_box "${help_opts[@]}"
            _pause
            continue
        fi

        # ==========================================
        # PROSES INPUT MENGGUNAKAN AI ATAU MANUAL
        # ==========================================
        local ai_used=false
        local reply_text=""

        # Coba pakai AI jika ada key
        if [ -n "$gemini_key" ]; then
            local abs_path="${STORAGE_DIR:-$HOME/Music/ZDT}"
            local dir_contents=""
            if [ -d "$abs_path" ]; then
                dir_contents=$(ls "$abs_path" 2>/dev/null | head -20 | tr '\n' ', ')
            fi

            local ai_prompt="Kamu adalah Zaki-Bot, asisten gaul, cerdas, dan to-the-point untuk ZDT (Zaki Downloader Tools). ZDT punya 18 fitur: [1] Setup (instal ffmpeg, yt-dlp, spotdl, demucs), [2] Spotify DL (download spotify), [3] YT Audio (download audio ytdlp), [4] Video DL (download video tiktok/yt), [5] Compress (perkecil ukuran file ffmpeg), [6] Vocal Remover (pisahin vokal pakai Demucs AI), [7] Sync Lyrics (cari file .lrc otomatis), [8] Playlist Sync (sinkronisasi playlist spotify bertahap), [9] System Info (cek spek & dependensi), [S] Storage (ganti target folder download), [W] Watch (daemon pantau folder otomatis bersih nama), [T] Telegram (bot remote terminal), [P] Playlist (buat file .m3u), [M] Metadata (edit tag mp3/flac mutagen), [O] Clean (bersihkan karakter aneh di nama file), [V] Web UI (akses ZDT via web browser server lokal), [U] Update (update script ZDT OTA), [X] Delete All (hapus isi folder). ATURAN: Jawab max 4 kalimat, asik, bahasa Indonesia gaul. Jika user minta penjelasan fitur, jelaskan. Jika user minta dieksekusi, kamu wajib membalas dengan [AUTO_ACTION: <aksi>]. Aksi AUTO_ACTION yang didukung HANYA: 'gas download audio ytsearch1:<judul>', 'gas download video ytsearch1:<judul>', 'hapus vokal', 'kompres media', 'sync lirik', 'bersih nama', 'bikin playlist'. Storage saat ini: $abs_path. Isi file (cuplikan): $dir_contents."

            local ai_response=""
            if [[ "$gemini_key" == sk-or-* ]]; then
                # OpenRouter
                local or_url="https://openrouter.ai/api/v1/chat/completions"
                local or_models='["meta-llama/llama-3.3-70b-instruct:free","google/gemma-4-31b-it:free","nousresearch/hermes-3-llama-3.1-405b:free"]'
                local payload="{\"models\": $or_models, \"messages\": [{\"role\": \"system\", \"content\": \"$ai_prompt\"}, {\"role\": \"user\", \"content\": \"$input\"}], \"max_tokens\": 100}"
                
                ai_response=$(curl -s -H "Authorization: Bearer $gemini_key" -H "Content-Type: application/json" -d "$payload" "$or_url" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('choices',[{}])[0].get('message',{}).get('content',''))" 2>/dev/null)
            else
                # Gemini
                local gemini_url="https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$gemini_key"
                local payload="{\"system_instruction\": {\"parts\": [{\"text\": \"$ai_prompt\"}]}, \"contents\": [{\"role\": \"user\", \"parts\": [{\"text\": \"$input\"}]}], \"generationConfig\": {\"maxOutputTokens\": 100}}"
                
                ai_response=$(curl -s -H "Content-Type: application/json" -d "$payload" "$gemini_url" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('candidates',[{}])[0].get('content',{}).get('parts',[{}])[0].get('text',''))" 2>/dev/null)
            fi

            if [ -n "$ai_response" ]; then
                ai_used=true
                reply_text="$ai_response"
                
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
            elif [[ "$input" =~ (update|upgrade|perbarui|install|setup) ]]; then
                update_tools

            # Storage
            elif [[ "$input" =~ (storage|folder|direktori|directory|path|save|simpan) ]]; then
                setup_storage_dir

            # Halo / greetings
            elif [[ "$input" =~ (halo|hai|hi|hey|selamat|pagi|siang|sore|malam|bro|boss|bang|kak) ]]; then
                echo ""
                echo -e "  ${MAGENTA}${ICO_ROCKET} ${BOLD}Zaki-Bot:${RESET} ${WHITE}Halo juga Bos! Ada yang bisa saya bantu?${RESET}"
                _pause

            # Thanks
            elif [[ "$input" =~ (makasih|terima\ kasih|thanks|thank\ you|thx|tq) ]]; then
                echo ""
                echo -e "  ${MAGENTA}${ICO_ROCKET} ${BOLD}Zaki-Bot:${RESET} ${WHITE}Sama-sama Bos! Kalo butuh bantuan lagi, bilang aja ya!${RESET}"
                _pause

            # Sisanya
            else
                echo ""
                if [ -n "$gemini_key" ]; then
                    echo -e "  ${YELLOW}${ICO_WARN} Maaf, AI lagi error. Coba ulangi atau ketik '?' untuk bantuan.${RESET}"
                else
                    echo -e "  ${YELLOW}${ICO_WARN} Hmm, maksudnya apa ya? Coba ketik '?' buat lihat contoh perintah!${RESET}"
                    echo -e "  ${GRAY}  Tips: Belum ada key AI. Isi file ~/.config/zdt/gemini_key dengan${RESET}"
                    echo -e "  ${GRAY}  Google Gemini / OpenRouter API Key biar Zaki-Bot makin pintar!${RESET}"
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
