# ==========================================
# ZDT Zaki AI Assistant Module v4.0
# ==========================================
# Professional AI interface with conversation
# memory, multi-tier model fallback, and
# structured intent recognition
# ==========================================

# Conversation history (Database)
readonly ZDT_DB_FILE="$HOME/.config/zdt/zdt_history.db"
readonly ZDT_DB_HELPER="$_MODULES_DIR/zdt_db.py"

_zaki_add_history() {
    local role="$1" content="$2"
    if command -v python3 >/dev/null 2>&1; then
        python3 "$ZDT_DB_HELPER" "$ZDT_DB_FILE" "add" "$role" "$content" 2>/dev/null || true
    fi
}

_zaki_build_messages() {
    local system_prompt="$1"
    local history_json=""
    
    if command -v python3 >/dev/null 2>&1; then
        history_json=$(python3 "$ZDT_DB_HELPER" "$ZDT_DB_FILE" "get_openai_json" 2>/dev/null)
    fi
    
    # Build JSON safely using Python to avoid broken JSON from special chars in prompt
    if [ -n "$history_json" ]; then
        python3 -c "
import sys, json
try:
    sys_prompt = sys.argv[1]
    sys_msg = {'role': 'system', 'content': sys_prompt}
    history = json.loads(sys.argv[2])
    result = [sys_msg] + (history if isinstance(history, list) else [history])
    print(json.dumps(result))
except Exception:
    # Fallback: minimal valid JSON
    import html
    print(json.dumps([{'role': 'system', 'content': 'Assistant ZDT. Balas singkat dalam Bahasa Indonesia.'}]))
" "$system_prompt" "$history_json" 2>/dev/null || echo "[{\"role\": \"system\", \"content\": \"Assistant ZDT. Balas singkat dalam Bahasa Indonesia.\"}]"
    else
        python3 -c "
import sys, json
print(json.dumps([{'role': 'system', 'content': sys.argv[1]}]))
" "$system_prompt" 2>/dev/null || echo "[{\"role\": \"system\", \"content\": \"Assistant ZDT. Balas singkat dalam Bahasa Indonesia.\"}]"
    fi
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
    local openrouter_key=""
    local gemini_key_file="$HOME/.config/zdt/gemini_key"
    local openrouter_key_file="$HOME/.config/zdt/openrouter_key"

    if [ -f "$gemini_key_file" ]; then
        gemini_key=$(cat "$gemini_key_file" | tr -d '[:space:]')
    fi
    if [ -f "$openrouter_key_file" ]; then
        openrouter_key=$(cat "$openrouter_key_file" | tr -d '[:space:]')
    fi
    
    # Dual-key logic:
    # - Jika gemini_key starts with "sk-or-" → itu sebenarnya OR key (backward compat)
    # - Jika openrouter_key eksplisit → prioritas untuk OR
    # - Jika keduanya ada: gemini_key → Gemini, openrouter_key → OpenRouter
    if [ -z "$openrouter_key" ] && [[ "$gemini_key" == sk-or-* ]]; then
        # Backward compat: gemini_key yg sk-or- digunakan sebagai OR key
        openrouter_key="$gemini_key"
        gemini_key=""
    fi

    local _zaki_first_run=true
    while true; do
        # Reset state variables setiap iterasi (local di bash punya function-wide scope)
        local ai_used=false
        local reply_text=""
        local clean_reply=""
        local action_intent=""
        local action_query=""
        local input=""
        local input_lower=""
        local is_auto_action=false
        
        if [ "$_zaki_first_run" = true ]; then
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
        if [ -n "$gemini_key" ] && [ -n "$openrouter_key" ]; then
            ai_status="${GREEN}Gemini + OpenRouter Connected${RESET}"
        elif [ -n "$gemini_key" ]; then
            ai_status="${GREEN}Gemini Connected${RESET}"
        elif [ -n "$openrouter_key" ]; then
            ai_status="${GREEN}OpenRouter Connected${RESET}"
        fi

        local db_count=0
        if command -v python3 >/dev/null 2>&1; then
            db_count=$(python3 "$ZDT_DB_HELPER" "$ZDT_DB_FILE" "get_count" 2>/dev/null || echo "0")
        fi

        local ai_opts=(
            " ${MAGENTA}${BOLD}■ ZAKI AI ASSISTANT v${ZDT_VERSION:-4.0}${RESET}"
            " ${WHITE}${salam} Bos! Aku siap bantu automasi tugasmu.${RESET}"
            "DIVIDER"
            " ${CYAN}Storage :${RESET} ${sisa} free of ${total_kapasitas}"
            " ${CYAN}AI API  :${RESET} $ai_status"
            " ${CYAN}Memori  :${RESET} $db_count pesan tersimpan di SQLite"
            "DIVIDER"
            " ${GREEN}Ketik apa saja dengan bahasa sehari-hari, atau:${RESET}"
            "  ${YELLOW}[?]${RESET} Bantuan Cepat       ${YELLOW}[!]${RESET} Reset Memori"
            "  ${RED}[0]${RESET} Kembali ke Menu Utama"
        )
        _print_menu_box "ZAKI AI" "${ai_opts[@]}"
        echo ""
        _zaki_first_run=false
        fi

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
        local input_lower="$input"

        [ -z "$input" ] && continue

        # Handle exit
        if [ "$input" = "0" ] || [ "$input" = "exit" ] || [ "$input" = "quit" ] || [ "$input" = "keluar" ] || [ "$input" = "back" ] || [ "$input" = "menu" ] || [ "$input" = "kembali" ]; then
            echo -e "  ${YELLOW}${ICO_ARROW} Kembali ke menu utama...${RESET}"
            _release_lock
            return 0
        fi

        # Reset memory
        if [ "$input" = "!" ] || [ "$input_lower" = "reset" ] || [ "$input_lower" = "clear" ] || [ "$input_lower" = "/clear" ]; then
            if command -v python3 >/dev/null 2>&1; then
                python3 "$ZDT_DB_HELPER" "$ZDT_DB_FILE" "clear" 2>/dev/null || true
            fi
            echo -e "  ${YELLOW}${ICO_ARROW} Zaki-Bot:${RESET} Memori percakapan telah dikosongkan! Aku siap memulai dari nol."
            continue
        fi

        # Help / Capability Intercept (HANYA trigger literal — pertanyaan
        # kapabilitas natural seperti "bisa apa aja" sengaja dibiarkan ke AI)
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
            echo ""
            continue
        fi

        # ==========================================
        # PROSES INPUT MENGGUNAKAN AI ATAU MANUAL
        # ==========================================

        # Escape for JSON safety
        local input_escaped
        input_escaped=$(echo "$bot_prompt" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' ')

        # Coba pakai AI jika ada key (Gemini atau OpenRouter)
        if [ -n "$gemini_key" ] || [ -n "$openrouter_key" ]; then
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

            local ai_prompt="Kamu Zaki-Bot, asisten cerdas ZDT Music Toolkit v${APP_VERSION}.

## PENGETAHUAN APLIKASI LENGKAP
ZDT adalah toolkit manajemen musik/video berbasis CLI + Web + Telegram.

### CLI MENU UTAMA (18 menu):
1. Download YouTube — download audio/video dari YT
2. Download Spotify — download lagu/playlist dari Spotify
3. Kompres Audio — kompres file audio pakai FFmpeg
4. Kompres Video — kompres file video pakai FFmpeg
5. Pisah Vokal — ekstrak vokal/instrumen pakai Demucs AI
6. Sync Lirik — cari dan sync lirik otomatis
7. Bersih Nama File — rapikan nama file berantakan
8. Buat Playlist M3U — bikin playlist dari file media
9. Info Sistem — cek disk, RAM, CPU, uptime
10. Metadata Editor — edit metadata file
11. Setup Tools — install dependencies
12. Watch Daemon — monitor folder download
13. Web Dashboard — antarmuka web (port 5678)
14. Zaki AI — asisten AI pintar (ini!)
15. Telegram Bot — kontrol via Telegram
16. Update ZDT — update skrip ke versi terbaru
17. Storage Setup — ubah folder penyimpanan
18. Keluar

### CLI ARGUMENTS:
--help, --download-audio URL, --download-video URL
--sync-lirik-all, --bersih-nama-all, --bikin-playlist-all
--setup, --update, --watch, --web, --telegram

### WEB DASHBOARD:
Monitoring real-time: Disk, RAM, CPU + uptime (Chart.js)
AI API: status Gemini/OpenRouter
Watch daemon: start/stop/status
Notifikasi: konfigurasi Telegram (token + chat ID)
Scheduler: playlist terjadwal + start/stop daemon
Auto-refresh tiap 1.5 detik

### AI BACKEND:
OpenRouter: 3-tier fallback (Qwen3, DeepSeek, Gemma, Nemotron, MiniMax, Llama)
Gemini: gemini-1.5-flash (secondary)
Dual-key: prefers OR, falls back to Gemini
Config: ~/.config/zdt/{gemini_key,openrouter_key}
History: SQLite di ~/.config/zdt/zdt_history.db

### DAEMONS:
1. Watch Daemon: monitor folder download, kompres otomatis
2. Scheduler Daemon: download playlist terjadwal (baca scheduler.json)
   Kirim notif Telegram via webhook kalau selesai

### CONFIG FILES:
~/.config/zdt/config.env - main config
~/.config/zdt/gemini_key - Gemini API key
~/.config/zdt/openrouter_key - OpenRouter API key
~/.config/zdt/telegram_token.txt - Telegram Bot token
~/.config/zdt/scheduler.json - scheduler config
~/.config/zdt/zdt_history.db - chat history

### SISTEMD:
zdt-scheduler.service + zdt-scheduler.timer

HARUS: Balas HANYA JSON TANPA markdown!
Format: {\"reply\":\"...\",\"intent\":\"...\",\"query\":\"...\"}

intent: download audio, download video, cari lagu, spotify, kompres media, hapus vokal, sync lirik, bersih nama, bikin playlist, playlist sync, info sistem, web ui, setup, update, telegram, daemon, metadata, storage, hapus semua, scheduler, notifikasi
query: URL atau kata kunci pencarian

Contoh:
User: download lagu Tulus
JSON: {\"reply\":\"Download Tulus! 🎵\",\"intent\":\"download audio\",\"query\":\"ytsearch1:Tulus\"}

User: cek status server
JSON: {\"reply\":\"Cek status bentar! 📊\",\"intent\":\"info sistem\",\"query\":\"\"}

User: gimana cara pake scheduler
JSON: {\"reply\":\"Buka Web Dashboard -> Scheduler panel. Tambah URL playlist Spotify, atur interval, start daemon. Download otomatis + notif Telegram!\",\"intent\":\"\",\"query\":\"\"}

User: apa itu zdt
JSON: {\"reply\":\"ZDT adalah toolkit manajemen musik/video dengan CLI, Web Dashboard, dan Telegram Bot. Ada 18 menu CLI, monitoring server, download otomatis, kompresi, pisah vokal AI, scheduler playlist, dan banyak lagi!\",\"intent\":\"\",\"query\":\"\"}

User: daemon apa aja yang jalan
JSON: {\"reply\":\"Ada 2 daemon: Watch Daemon (pantau folder download) dan Scheduler Daemon (download playlist terjadwal). Status bisa dicek di Web Dashboard atau lewat CLI.\",\"intent\":\"\",\"query\":\"\"}

KONTEKS: Storage=$abs_path ($file_count file). Isi: $dir_contents"
            # Add current message to history
            _zaki_add_history "user" "$input_escaped"

            # Build messages with history
            local messages
            messages=$(_zaki_build_messages "$ai_prompt")

            local ai_response=""
            # mktemp: nama file acak untuk cegah symlink attack pada /tmp
            local ai_tmpfile
            ai_tmpfile=$(mktemp "${TMPDIR:-/tmp}/zdt_ai_resp_XXXXXX" 2>/dev/null || echo "/tmp/.zdt_ai_resp_$$")

            # Use openrouter_key if available, otherwise check if gemini_key is an OR key
            local effective_or_key="${openrouter_key:-}"
            if [ -z "$effective_or_key" ] && [[ "$gemini_key" == sk-or-* ]]; then
                effective_or_key="$gemini_key"
            fi
            
            if [ -n "$effective_or_key" ]; then
                # OpenRouter — Multi-tier fallback (max 3 models per request)
                local or_url="https://openrouter.ai/api/v1/chat/completions"
                local or_tiers=(
                    '["google/gemma-4-31b-it:free","google/gemma-4-26b-a4b-it:free"]'
                    '["nvidia/nemotron-3-super-120b-a12b:free","meta-llama/llama-3.3-70b-instruct:free"]'
                    '["nousresearch/hermes-3-llama-3.1-405b:free","meta-llama/llama-3.2-3b-instruct:free"]'
                )

                local or_parse='
import sys, json, re
try:
    d = json.load(sys.stdin)
    if "error" in d:
        sys.exit(1)
    txt = d.get("choices",[{}])[0].get("message",{}).get("content","")
    
    match = re.search(r"\{.*\}", txt, re.DOTALL)
    if match:
        parsed = json.loads(match.group(0))
        print(json.dumps(parsed))
    else:
        print(json.dumps({"reply": txt.strip(), "intent": "", "query": ""}))
except Exception:
    pass
'
                for tier_models in "${or_tiers[@]}"; do
                    # Build payload safely via Python to avoid JSON injection from messages content
                    local tmp_payload
                    tmp_payload=$(python3 -c "
import sys, json
try:
    models = json.loads(sys.argv[1])
    msgs = json.loads(sys.argv[2])
    payload = {'models': models, 'messages': msgs, 'max_tokens': 1000}
    print(json.dumps(payload))
except:
    print(json.dumps({'models': [], 'messages': [], 'max_tokens': 1000}))
" "$tier_models" "$messages" 2>/dev/null)
                    
                    curl -s --max-time 20 -H "Authorization: Bearer $effective_or_key" -H "Content-Type: application/json" -d "$tmp_payload" "$or_url" 2>/dev/null > "$ai_tmpfile" &
                    local curl_pid=$!
                    _zaki_spinner $curl_pid
                    wait $curl_pid 2>/dev/null

                    ai_response=$(cat "$ai_tmpfile" 2>/dev/null | python3 -c "$or_parse" 2>/dev/null)
                    [ -n "$ai_response" ] && break
                done
            fi
            
            if [ -z "$ai_response" ] && [ -n "$gemini_key" ] && [[ "$gemini_key" != sk-or-* ]]; then
                # Gemini (only if OR didn't produce an answer AND we have a real Gemini key)
                local gemini_url="https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$gemini_key"
                local gemini_contents=""
                
                if command -v python3 >/dev/null 2>&1; then
                    gemini_contents=$(python3 "$ZDT_DB_HELPER" "$ZDT_DB_FILE" "get_gemini_json" 2>/dev/null)
                fi
                # Build payload safely via Python to avoid JSON injection from prompt content
                local payload
                payload=$(python3 -c "
import sys, json
try:
    contents_json = sys.argv[1]
    contents = json.loads(contents_json) if contents_json.strip() else []
    if not isinstance(contents, list): contents = [contents]
    payload = {
        'system_instruction': {'parts': [{'text': sys.argv[2]}]},
        'contents': contents,
        'generationConfig': {'maxOutputTokens': 1000}
    }
    print(json.dumps(payload))
except:
    print(json.dumps({'system_instruction': {'parts': [{'text': sys.argv[2]}]}, 'contents': [], 'generationConfig': {'maxOutputTokens': 1000}}))
" "$gemini_contents" "$ai_prompt" 2>/dev/null)
                
                curl -s --max-time 20 -H "Content-Type: application/json" -d "$payload" "$gemini_url" 2>/dev/null > "$ai_tmpfile" &
                local curl_pid=$!
                _zaki_spinner $curl_pid
                wait $curl_pid 2>/dev/null

                local gemini_parse='
import sys, json, re
try:
    d = json.load(sys.stdin)
    txt = d.get("candidates",[{}])[0].get("content",{}).get("parts",[{}])[0].get("text","")
    match = re.search(r"\{.*\}", txt, re.DOTALL)
    if match:
        parsed = json.loads(match.group(0))
        print(json.dumps(parsed))
    else:
        print(json.dumps({"reply": txt.strip(), "intent": "", "query": ""}))
except Exception:
    pass
'
                ai_response=$(cat "$ai_tmpfile" 2>/dev/null | python3 -c "$gemini_parse" 2>/dev/null)
                
                # Graceful Fallback to OpenRouter if Gemini fails or hits quota
                # Use openrouter_key if available, otherwise fall back to gemini_key for OR
                local or_fallback_key="${openrouter_key:-$gemini_key}"
                if [ -z "$ai_response" ] || [[ "$ai_response" == *"error"* ]]; then
                    if [ -n "$or_fallback_key" ]; then
                        echo -e "\n  ${YELLOW}${ICO_WARN} Gemini API sibuk (429). Mengalihkan ke OpenRouter (Graceful Fallback)...${RESET}"
                        local or_url="https://openrouter.ai/api/v1/chat/completions"
                        local or_parse="import sys,json; d=json.load(sys.stdin); print(d.get('choices',[{}])[0].get('message',{}).get('content',''))"
                        # Build payload safely via Python
                        local fallback_payload
                        fallback_payload=$(python3 -c "
import sys, json
try:
    payload = {
        'models': ['google/gemma-4-31b-it:free', 'google/gemma-4-26b-a4b-it:free'],
        'messages': [{'role': 'system', 'content': sys.argv[1]}, {'role': 'user', 'content': sys.argv[2]}],
        'max_tokens': 1000
    }
    print(json.dumps(payload))
except:
    print('{}')
" "$ai_prompt" "$bot_prompt" 2>/dev/null)
                        curl -s --max-time 20 -H "Authorization: Bearer $or_fallback_key" -H "Content-Type: application/json" -d "$fallback_payload" "$or_url" 2>/dev/null > "$ai_tmpfile" &
                        local or_pid=$!
                        _zaki_spinner $or_pid
                        wait $or_pid 2>/dev/null
                        ai_response=$(cat "$ai_tmpfile" 2>/dev/null | python3 -c "$or_parse" 2>/dev/null)
                    fi
                fi
            fi

            rm -f "$ai_tmpfile" 2>/dev/null

            if [ -n "$ai_response" ]; then
                ai_used=true
                
                # Save raw AI response to history
                local resp_escaped
                resp_escaped=$(echo "$ai_response" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' ')
                _zaki_add_history "assistant" "$resp_escaped"
                
                if command -v python3 >/dev/null 2>&1; then
                    # We expect ai_response to be a valid JSON string
                    clean_reply=$(echo "$ai_response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('reply',''))" 2>/dev/null)
                    action_intent=$(echo "$ai_response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('intent',''))" 2>/dev/null)
                    action_query=$(echo "$ai_response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('query',''))" 2>/dev/null)
                else
                    clean_reply="$ai_response"
                fi
                
                if [ -n "$action_intent" ]; then
                    is_auto_action=true
                fi

                # Anti-empty response fallback
                if [ ${#clean_reply} -lt 15 ] && [ "$is_auto_action" = false ]; then
                    echo -e "  ${YELLOW}${ICO_WARN} Zaki-Bot belum mengerti maksud Bos. Ketik '?' untuk menu bantuan.${RESET}"
                    continue
                fi

                if [ -n "$clean_reply" ]; then
                    echo ""
                    echo -e "  ${MAGENTA}${ICO_ROCKET} ${BOLD}Zaki-Bot:${RESET} ${WHITE}$clean_reply${RESET}"
                    if [ "$is_auto_action" = false ]; then
                        echo ""
                    else
                        echo ""
                        sleep 1
                    fi
                fi
                
                # Proses Intent JSON (Case-Insensitive)
                if [ "$is_auto_action" = true ]; then
                    local intent_lower="${action_intent,,}"
                    
                    case "$intent_lower" in
                        "download smart")
                            local smart_url="$action_query"
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
                        "download audio")
                            local dl_url="$action_query"
                            AUTO_DOWNLOAD_URL="$dl_url"
                            echo -e "  ${CYAN}${ICO_ARROW} Mendownload audio: $dl_url${RESET}"
                            if [[ "$dl_url" =~ spotify ]]; then
                                download_spotdl
                            else
                                download_ytdlp
                            fi
                            ;;
                        "download video")
                            local dl_url="$action_query"
                            AUTO_DOWNLOAD_URL="$dl_url"
                            echo -e "  ${CYAN}${ICO_ARROW} Mendownload video: $dl_url${RESET}"
                            download_video
                            ;;
                        "spotify")
                            local sp_url="$action_query"
                            AUTO_DOWNLOAD_URL="$sp_url"
                            echo -e "  ${CYAN}${ICO_ARROW} Download Spotify: $sp_url${RESET}"
                            download_spotdl
                            ;;
                        "cari lagu")
                            local search_q="$action_query"
                            echo -e "  ${CYAN}${ICO_ARROW} Mencari '$search_q' di YouTube...${RESET}"
                            echo -e "  ${YELLOW}Sedang mengambil 5 hasil teratas, mohon tunggu...${RESET}"
                            
                            local search_output=""
                            search_output=$(yt-dlp --print "%(title)s (ID: %(id)s)" "ytsearch5:$search_q" 2>/dev/null)
                            
                            if [ -z "$search_output" ]; then
                                echo -e "  ${RED}${ICO_FAIL} Pencarian gagal atau tidak ditemukan.${RESET}"
                            else
                                local options=()
                                local ids=()
                                local i=1
                                while IFS= read -r line; do
                                    if [ -n "$line" ]; then
                                        # Parse title and ID safely
                                        local title="${line% (ID:*}"
                                        local vid_id="${line##* (ID: }"
                                        vid_id="${vid_id%)}"
                                        options+=(" ${GREEN}[$i]${RESET} $title")
                                        ids+=("$vid_id")
                                        ((i++))
                                    fi
                                done <<< "$search_output"
                                
                                options+=("DIVIDER")
                                options+=(" ${RED}[0]${RESET} Batal")
                                _print_menu_box "HASIL PENCARIAN" "${options[@]}"
                                
                                echo -e -n "  ${BOLD}[?] Pilih lagu yang ingin didownload [0-$((i-1))]: ${RESET}"
                                read -r choice
                                echo ""
                                
                                if [[ "$choice" =~ ^[1-5]$ ]] && [ "$choice" -lt "$i" ]; then
                                    local selected_id="${ids[$((choice-1))]}"
                                    echo -e "  ${CYAN}${ICO_ARROW} Memproses ID: $selected_id${RESET}"
                                    AUTO_DOWNLOAD_URL="https://youtube.com/watch?v=$selected_id"
                                    download_ytdlp
                                else
                                    echo -e "  ${YELLOW}${ICO_WARN} Dibatalkan.${RESET}"
                                fi
                            fi
                            ;;
                        "playlist sync")
                            local ps_url="$action_query"
                            echo -e "  ${CYAN}${ICO_ARROW} Sinkronisasi playlist Spotify: $ps_url${RESET}"
                            sync_spotify_playlist
                            ;;
                        "hapus vokal")
                            echo -e "  ${CYAN}${ICO_ARROW} Memisahkan vokal...${RESET}"
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
                        "web ui")
                            echo -e "  ${CYAN}${ICO_ARROW} Meluncurkan Web UI...${RESET}"
                            start_web_dashboard
                            ;;
                        "info sistem")
                            echo -e "  ${CYAN}${ICO_ARROW} Menampilkan Info Sistem...${RESET}"
                            system_info
                            ;;
                        "update")
                            echo -e "  ${CYAN}${ICO_ARROW} Melakukan OTA Update...${RESET}"
                            update_zdt_script
                            ;;
                        "setup")
                            echo -e "  ${CYAN}${ICO_ARROW} Menjalankan Setup...${RESET}"
                            install_missing_tools
                            ;;
                        "daemon")
                            echo -e "  ${CYAN}${ICO_ARROW} Menjalankan Watch Daemon...${RESET}"
                            start_watch_daemon
                            ;;
                        "telegram")
                            echo -e "  ${CYAN}${ICO_ARROW} Menjalankan Telegram Bot...${RESET}"
                            start_telegram_bot
                            ;;
                        "metadata")
                            echo -e "  ${CYAN}${ICO_ARROW} Membuka Metadata Editor...${RESET}"
                            edit_metadata_manual
                            ;;
                        "storage")
                            echo -e "  ${CYAN}${ICO_ARROW} Mengubah folder Storage...${RESET}"
                            setup_storage_dir
                            ;;
                        "hapus semua")
                            echo -e "  ${YELLOW}${ICO_WARN} Menghapus semua file media...${RESET}"
                            hapus_semua
                            ;;
                    esac
                    
                    # Layar tidak di-clear lagi tiap turn, cukup beri spasi
                    echo ""
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
                echo ""

            # Thanks
            elif [[ "$input" =~ (makasih|terima\ kasih|thanks|thank\ you|thx|tq|mantap|keren|gokil) ]]; then
                echo ""
                echo -e "  ${MAGENTA}${ICO_ROCKET} ${BOLD}Zaki-Bot:${RESET} ${WHITE}Sama-sama Bos! Senang bisa bantu! 🙏${RESET}"
                echo ""

            # Sisanya
            else
                echo ""
                if [ -n "$gemini_key" ]; then
                    echo -e "  ${RED}${ICO_FAIL} Zaki-Bot: Maaf bos, API AI sedang gangguan atau limit kuota habis (HTTP 429).${RESET}"
                    echo -e "  ${GRAY}  Silakan coba lagi nanti, atau pastikan API key terisi di ~/.config/zdt/gemini_key (Gemini) atau ~/.config/zdt/openrouter_key (OpenRouter)!${RESET}"
                else
                    echo -e "  ${YELLOW}${ICO_WARN} Hmm, aku belum bisa jawab itu. Ketik '?' buat lihat daftar perintah!${RESET}"
                    echo -e "  ${GRAY}  Tips: Isi file ~/.config/zdt/gemini_key (Gemini API Key) atau${RESET}"
                    echo -e "  ${GRAY}  ~/.config/zdt/openrouter_key (OpenRouter API Key) untuk mengaktifkan AI!${RESET}"
                fi
                echo ""
            fi
        else
            # Jika AI tidak dipanggil (fallback mode): cukup beri spasi,
            # alur chat berlanjut tanpa memutus ke menu.
            if [ -z "${input:-}" ]; then
                echo ""
            fi
        fi

        echo ""
    done
}
# Auto-version hook installed
