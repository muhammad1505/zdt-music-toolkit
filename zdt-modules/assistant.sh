# ==========================================
# ZDT Zaki AI Assistant Module
# ==========================================
# Professional AI interface with conversation
# memory, multi-tier model fallback, and
# structured intent recognition
# ==========================================
# Version: ${APP_VERSION}

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

# ==========================================
# LOAD SHARED AI PROMPT TEMPLATE
# ==========================================
_load_ai_base_prompt() {
    local prompt_file
    # Cari di berbagai lokasi via shared path resolver
    for _dir in "$SCRIPT_DIR" $(_get_share_dir); do
        if [ -f "$_dir/zdt-ai-prompt.txt" ]; then
            prompt_file="$_dir/zdt-ai-prompt.txt"
            break
        fi
    done
    # Also try Termux-specific path
    if [ -z "$prompt_file" ] && [ -n "${TERMUX_VERSION:-}" ]; then
        local _termux_prompt="/data/data/com.termux/files/usr/share/zdt/zdt-ai-prompt.txt"
        [ -f "$_termux_prompt" ] && prompt_file="$_termux_prompt"
    fi

    if [ -n "$prompt_file" ] && [ -f "$prompt_file" ]; then
        # Baca file dan substitusi placeholder
        sed "s/{APP_VERSION}/${APP_VERSION}/g" "$prompt_file"
    else
        # Fallback: base prompt minimal tanpa file
        echo "Kamu Zaki-Bot, asisten pintar ZDT Music Toolkit v${APP_VERSION}. Bahasa gaul Indonesia, jawab singkat dan to the point."
        echo ""
        echo "ZDT adalah toolkit musik/video all-in-one: CLI, Web Dashboard, Telegram Bot."
        echo ""
        echo "MENU: 1=Setup, 2=Spotify DL, 3=YT Audio, 4=Video DL, 5=Kompres,"
        echo "6=Hapus Vokal, 7=Sync Lirik, 8=Playlist Sync, 9=Info Sistem,"
        echo "S=Storage, W=Watch, P=Playlist, M=Metadata, O=Bersih Nama,"
        echo "T=Telegram, V=Web, U=Update, A=AI, X=Hapus Semua"
        echo ""
        echo "Download: YouTube (yt-dlp), Spotify (spotdl), Video (pilih quality/codec)"
        echo "Kompres Audio: AAC/MP3/FLAC/OPUS, bitrate 128k-320k"
        echo "Kompres Video: x264/x265/AV1/VP9, CRF28/23, 2M/5M"
        echo "Vokal: AI Demucs, 3 mode (semua/per-artis/per-lagu)"
        echo "Lirik: syncedlyrics, .lrc, timeout 30s"
        echo "Metadata: mutagen, edit title/artist/cover"
        echo "Web: Flask port 5000, Telegram: remote bot, Watch: auto-process"
        echo "Config: ~/.config/zdt/config.env, API keys: gemini_key/openrouter_key"
        echo ""
        echo "PERSONALITY:"
        echo "- Santai, gaul, pake bahasa sehari-hari Indonesia"
        echo "- Jawab SINGKAT, max 2-3 kalimat"
        echo "- Kalo user minta aksi → kasih tau sambil eksekusi"
        echo "- JANGAN pake markdown heading (###)"
        echo "- PAKAI emoji secukupnya aja"
        echo "- Paham menu nomor (5=kompres) dan huruf (V=web)"
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
            " ${MAGENTA}${BOLD}■ ZAKI AI ASSISTANT v${ZDT_VERSION:-${APP_VERSION:-unknown}}${RESET}"
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
                "   'set api key' / 'ganti key' — Atur API Key"
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

            # Runtime context
            local ctx_os="$(_get_os_name 2>/dev/null || echo 'Linux')"
            local ctx_env="$(_detect_environment 2>/dev/null || echo 'standard')"
            local ctx_storage=""
            if command -v df >/dev/null 2>&1 && [ -d "$abs_path" ]; then
                ctx_storage=$(df -h "$abs_path" 2>/dev/null | awk 'NR==2{print $4" free of "$2}')
            fi
            local ctx_dir_contents=""
            if [ -d "$abs_path" ]; then
                ctx_dir_contents=$(ls "$abs_path" 2>/dev/null | head -12 | tr '\n' ', ')
            fi
            local ctx_file_count=0
            if [ -d "$abs_path" ]; then
                ctx_file_count=$(find "$abs_path" -maxdepth 2 -type f \( -iname "*.mp3" -o -iname "*.m4a" -o -iname "*.flac" -o -iname "*.mp4" -o -iname "*.wav" -o -iname "*.ogg" -o -iname "*.opus" \) 2>/dev/null | wc -l)
            fi
            local ctx_has_ytdlp="false"
            command -v yt-dlp >/dev/null 2>&1 && ctx_has_ytdlp="true"
            local ctx_has_ffmpeg="false"
            command -v ffmpeg >/dev/null 2>&1 && ctx_has_ffmpeg="true"
            local ctx_has_spotdl="false"
            command -v spotdl >/dev/null 2>&1 && ctx_has_spotdl="true"
            local ctx_web_running="false"
            if [ -n "$(pgrep -f 'zdt-web.py' 2>/dev/null)" ]; then ctx_web_running="true"; fi
            local ctx_tg_running="false"
            if [ -n "$(pgrep -f 'zdt-telegram.py' 2>/dev/null)" ]; then ctx_tg_running="true"; fi
            local ctx_watch_running="false"
            if [ -n "$(pgrep -f 'zdt-watch.py' 2>/dev/null)" ]; then ctx_watch_running="true"; fi

            local ai_prompt
            ai_prompt=$(_load_ai_base_prompt)
            ai_prompt="$ai_prompt

FORMAT RESPON:
WAJIB balas HANYA JSON, tanpa markdown, tanpa penjelasan tambahan!
Format: {\"reply\":\"...\",\"intent\":\"...\",\"query\":\"...\"}

reply: natural dan santai (max 3 kalimat). KALO USER SALAM/SAPA, balas lalu TANYA \"ada yang bisa dibantu?\".
intent: KOSONG jika hanya ngobrol. Isi SALAH SATU dari: download audio, download video, download smart, cari lagu, spotify, kompres media, kompres video, hapus vokal, sync lirik, bersih nama, bikin playlist, playlist sync, info sistem, web ui, setup, update, telegram, daemon, metadata, storage, hapus semua
query: URL atau 'ytsearch1:kata kunci' (kosong jika tidak ada)

INSTRUKSI INTENT:
- JIKA user MINTA sesuatu (download, kompres, hapus, dll) → WAJIB isi intent! BAHKAN jika user belum kasih URL/judul!
- Intent \"download audio\" = download dari MANAPUN (YouTube, Spotify, SoundCloud, FB, Twitter, TikTok, IG, dll). Backend otomatis deteksi sumbernya.
- Intent \"download video\" = download video dari link mana pun.
- Intent \"spotify\" = khusus link Spotify (track/album/playlist).
- jika user minta download TANPA URL → isi intent, query KOSONG, user bakal ditanya setelahnya.

PENTING: Pahamin variasi bahasa user:
- download lagu/bantu download/sedot/unduh/ambil → download audio
- download video/sedot video → download video
- kompres/kecilin/compress file audio → kompres media
- kompres/kecilin video → kompres video
- pisah vokal/karaoke/demucs/vocal remover/pisahin → hapus vokal
- cari lirik/sync lyric/sync lirik → sync lirik
- bersih nama/beresin nama/rapiin file/bersihin file → bersih nama
- bikin playlist/buat playlist/m3u → bikin playlist
- download spotify/spotify link → spotify

Contoh:
User: halo bro
{\"reply\":\"Halo juga bro! 👋 Ada yang bisa gue bantu? Mau download lagu, kompres file, atau apa nih?\",\"intent\":\"\",\"query\":\"\"}

User: download lagu Tulus
{\"reply\":\"Gas download Tulus! 🎵\",\"intent\":\"download audio\",\"query\":\"ytsearch1:Tulus\"}

User: bisa gak bantu gw download audio?
{\"reply\":\"Bisa bang! Mau download dari YouTube, Spotify, SoundCloud, atau kirim link aja? 🎵\",\"intent\":\"download audio\",\"query\":\"\"}

User: tolong sedot video dari fb
{\"reply\":\"Oke, kirim link videonya bro! 💫\",\"intent\":\"download video\",\"query\":\"\"}

User: download spotify playlist
{\"reply\":\"Oke, kasih link Spotify-nya bro! 🎧\",\"intent\":\"spotify\",\"query\":\"\"}

User: menu 6
{\"reply\":\"Buka Hapus Vokal! Siapkan file audionya 🎤\",\"intent\":\"hapus vokal\",\"query\":\"\"}

User: jalanin web dashboard
{\"reply\":\"Meluncurkan Web Dashboard... 🌐\",\"intent\":\"web ui\",\"query\":\"\"}

User: cek status
{\"reply\":\"Cek status! 📊\",\"intent\":\"info sistem\",\"query\":\"\"}

User: apa itu zdt
{\"reply\":\"ZDT itu toolkit lengkap buat kelola musik/video. Ada download, kompres, pisah vokal, lirik, dan banyak lagi!\",\"intent\":\"\",\"query\":\"\"}

User: lu bisa apa
{\"reply\":\"Gue bisa download lagu/video dari YouTube, Spotify, SoundCloud, FB, TikTok, dll! Juga kompres file, pisahin vokal pake AI, sync lirik, bersihin nama file, dan kontrol server dari web/telegram! Ada yang mau dicoba? 😎\",\"intent\":\"\",\"query\":\"\"}

User: V
{\"reply\":\"Oke buka Web Dashboard! 🚀\",\"intent\":\"web ui\",\"query\":\"\"}

User: kompres semua video
{\"reply\":\"Siap, kompres video semua file! 🎬\",\"intent\":\"kompres video\",\"query\":\"\"}

User: tolong dong bersihin nama file yang kotor
{\"reply\":\"Siap, gue bersihin semua nama file! ✨\",\"intent\":\"bersih nama\",\"query\":\"\"}

User: update tools dong
{\"reply\":\"Update VENV tools... 🔄\",\"intent\":\"update\",\"query\":\"\"}

User: buatin playlist
{\"reply\":\"Bikin playlist M3U! 📋\",\"intent\":\"bikin playlist\",\"query\":\"\"}

User: minta tolong pisahin vokal lagu
{\"reply\":\"Siap, gue pisahin vokalnya! 🎤\",\"intent\":\"hapus vokal\",\"query\":\"\"}

KONTEKS:
Storage=$abs_path ($ctx_file_count file, $ctx_storage)
Isi folder: $ctx_dir_contents
OS: $ctx_os ($ctx_env)
Tools: yt-dlp=$ctx_has_ytdlp ffmpeg=$ctx_has_ffmpeg spotdl=$ctx_has_spotdl
Services: Web=$ctx_web_running Telegram=$ctx_tg_running Watch=$ctx_watch_running"
            # Add current message to history
            _zaki_add_history "user" "$input_escaped"

            # Build messages with history
            local messages
            messages=$(_zaki_build_messages "$ai_prompt")

            local ai_response=""
            # mktemp: nama file acak untuk cegah symlink attack pada /tmp
            local ai_tmpfile
            ai_tmpfile=$(mktemp "${TMPDIR:-/tmp}/zdt_ai_resp_XXXXXX" 2>/dev/null || echo "/tmp/.zdt_ai_resp_$$")

            # Resolve OR key (explicit OR key or backward-compat sk-or- gemini key)
            local effective_or_key="${openrouter_key:-}"
            if [ -z "$effective_or_key" ] && [[ "$gemini_key" == sk-or-* ]]; then
                effective_or_key="$gemini_key"
            fi
            local or_fallback_key="${openrouter_key:-$gemini_key}"

            # Shared JSON extractor: handles markdown code blocks AND raw JSON
            # Priority: ```json block > flat JSON > whole text fallback
            local ai_json_parse='
import sys, json, re
def extract(txt):
    # Try markdown code block first
    m = re.search(r"```(?:json)?\s*\n?(.*?)```", txt, re.DOTALL)
    if m:
        try:
            p = json.loads(m.group(1))
            if isinstance(p, dict): return json.dumps(p)
        except: pass
    # Try non-greedy flat JSON (no nested braces)
    for m in re.finditer(r"\{[^{}]*\}", txt):
        try:
            p = json.loads(m.group(0))
            if isinstance(p, dict):
                return json.dumps(p)
        except: pass
    # Greedy fallback
    m = re.search(r"\{.*\}", txt, re.DOTALL)
    if m:
        try:
            p = json.loads(m.group(0))
            if isinstance(p, dict): return json.dumps(p)
        except: pass
    # Plain text fallback
    return json.dumps({"reply": txt.strip()[:600], "intent": "", "query": ""})
try:
    d = json.load(sys.stdin)
    txt = d.get("choices",[{}])[0].get("message",{}).get("content","")
    if txt:
        print(extract(txt))
    else:
        sys.exit(1)
except: sys.exit(1)
'

            # ==============================================
            # PRIORITY 1: Gemini (lebih pintar, lebih cepat)
            # ==============================================
            if [ -z "$ai_response" ] && [ -n "$gemini_key" ] && [[ "$gemini_key" != sk-or-* ]]; then
                local gemini_url="https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$gemini_key"
                local gemini_contents=""
                if command -v python3 >/dev/null 2>&1; then
                    gemini_contents=$(python3 "$ZDT_DB_HELPER" "$ZDT_DB_FILE" "get_gemini_json" 2>/dev/null)
                fi
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
        'generationConfig': {'maxOutputTokens': 2000}
    }
    print(json.dumps(payload))
except:
    print(json.dumps({'system_instruction': {'parts': [{'text': sys.argv[2]}]}, 'contents': [], 'generationConfig': {'maxOutputTokens': 2000}}))
" "$gemini_contents" "$ai_prompt" 2>/dev/null)

                curl -s --max-time 45 -H "Content-Type: application/json" -d "$payload" "$gemini_url" 2>/dev/null > "$ai_tmpfile" &
                local g_pid=$!
                _zaki_spinner $g_pid
                wait $g_pid 2>/dev/null

                local g_parse="
import sys, json, re
def extract(txt):
    m = re.search(r\"'''json'''\s*\n?(.*?)''''''\", txt, re.DOTALL)
    if m:
        try:
            p = json.loads(m.group(1))
            if isinstance(p, dict): return json.dumps(p)
        except: pass
    for m in re.finditer(r'\{[^{}]*\}', txt):
        try:
            p = json.loads(m.group(0))
            if isinstance(p, dict): return json.dumps(p)
        except: pass
    m = re.search(r'\{.*\}', txt, re.DOTALL)
    if m:
        try:
            p = json.loads(m.group(0))
            if isinstance(p, dict): return json.dumps(p)
        except: pass
    return json.dumps({'reply': txt.strip()[:600], 'intent': '', 'query': ''})
try:
    d = json.load(sys.stdin)
    txt = d.get('candidates',[{}])[0].get('content',{}).get('parts',[{}])[0].get('text','')
    if txt:
        print(extract(txt))
    else:
        sys.exit(1)
except: sys.exit(1)
"
                ai_response=$(cat "$ai_tmpfile" 2>/dev/null | python3 -c "$g_parse" 2>/dev/null)

                if [ -z "$ai_response" ]; then
                    # Gemini gagal — fallback ke OpenRouter jika ada
                    if [ -n "$or_fallback_key" ]; then
                        echo -e "\n  ${YELLOW}${ICO_WARN} Gemini sibuk, alihkan ke OpenRouter...${RESET}"
                    fi
                fi
            fi

            # ==============================================
            # PRIORITY 2: OpenRouter (fallback jika Gemini gagal)
            # ==============================================
            if [ -z "$ai_response" ] && [ -n "$effective_or_key" ]; then
                local or_url="https://openrouter.ai/api/v1/chat/completions"
                local or_tiers=(
                    '["meta-llama/llama-3.3-70b-instruct:free","qwen/qwen2.5-72b-instruct:free"]'
                    '["google/gemma-4-31b-it:free","mistralai/mistral-small-3.1-24b-instruct:free"]'
                )
                for tier_models in "${or_tiers[@]}"; do
                    local tmp_payload
                    tmp_payload=$(python3 -c "
import sys, json
try:
    models = json.loads(sys.argv[1])
    msgs = json.loads(sys.argv[2])
    payload = {'models': models, 'messages': msgs, 'max_tokens': 1500}
    print(json.dumps(payload))
except:
    print(json.dumps({'models': [], 'messages': [], 'max_tokens': 1500}))
" "$tier_models" "$messages" 2>/dev/null)

                    curl -s --max-time 30 -H "Authorization: Bearer $effective_or_key" -H "Content-Type: application/json" -d "$tmp_payload" "$or_url" 2>/dev/null > "$ai_tmpfile" &
                    local curl_pid=$!
                    _zaki_spinner $curl_pid
                    wait $curl_pid 2>/dev/null

                    ai_response=$(cat "$ai_tmpfile" 2>/dev/null | python3 -c "$ai_json_parse" 2>/dev/null)
                    [ -n "$ai_response" ] && break
                done
            fi

            # ==============================================
            # PRIORITY 3: Simple OR fallback (tanpa JSON, tanpa history)
            # ==============================================
            if [ -z "$ai_response" ] && [ -n "$or_fallback_key" ]; then
                local simple_payload
                simple_payload=$(python3 -c "
import sys, json
payload = {
    'model': 'meta-llama/llama-3.3-70b-instruct:free',
    'messages': [{'role': 'system', 'content': sys.argv[1]}, {'role': 'user', 'content': sys.argv[2]}],
    'max_tokens': 1000
}
print(json.dumps(payload))
" "$ai_prompt" "$bot_prompt" 2>/dev/null)
                curl -s --max-time 30 -H "Authorization: Bearer $or_fallback_key" -H "Content-Type: application/json" -d "$simple_payload" "$or_url" 2>/dev/null > "$ai_tmpfile" &
                local s_pid=$!
                _zaki_spinner $s_pid
                wait $s_pid 2>/dev/null
                local simple_parse="import sys,json; d=json.load(sys.stdin); t=d.get('choices',[{}])[0].get('message',{}).get('content',''); print(json.dumps({'reply':t.strip()[:600],'intent':'','query':''}))"
                ai_response=$(cat "$ai_tmpfile" 2>/dev/null | python3 -c "$simple_parse" 2>/dev/null)
            fi

            rm -f "$ai_tmpfile" 2>/dev/null

            if [ -n "$ai_response" ]; then
                ai_used=true
                
                # Save raw AI response to history
                local resp_escaped
                resp_escaped=$(echo "$ai_response" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' ')
                _zaki_add_history "assistant" "$resp_escaped"
                
                if command -v python3 >/dev/null 2>&1; then
                    clean_reply=$(echo "$ai_response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('reply',''))" 2>/dev/null)
                    action_intent=$(echo "$ai_response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('intent',''))" 2>/dev/null)
                    action_query=$(echo "$ai_response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('query',''))" 2>/dev/null)
                else
                    clean_reply="$ai_response"
                fi
                
                if [ -n "$action_intent" ]; then
                    is_auto_action=true
                fi
            fi

            # === KEYWORD INTENT FALLBACK (jalan meskipun AI gagal) ===
            if [ -z "$action_intent" ] && [ -n "$input_lower" ]; then
                local ki="$input_lower"
                local kw_intent=""
                local kw_query=""

                # Salam/sapa — tanpa intent, balas natural
                if echo "$ki" | grep -qE '^(halo|hai|hey|hi|hallo|helo|selamat|siang|pagi|sore|malam|testing)'; then
                    if [ -z "$clean_reply" ] || [[ "$clean_reply" == "Siap. Ada yang bisa saya bantu?" ]]; then
                        local hr
                        hr=$(date +%H 2>/dev/null || echo "12")
                        if [ "$hr" -lt 11 ]; then
                            clean_reply="Pagi bro! ☀️ Ada yang bisa gue bantu?"
                        elif [ "$hr" -lt 15 ]; then
                            clean_reply="Siang bro! 🌤️ Ada yang bisa gue bantu?"
                        elif [ "$hr" -lt 19 ]; then
                            clean_reply="Sore bro! 🌅 Ada yang bisa gue bantu?"
                        else
                            clean_reply="Malam bro! 🌙 Ada yang bisa gue bantu?"
                        fi
                        ai_used=true
                    fi
                fi

                # Download — cocok di mana pun dalam kalimat
                if echo "$ki" | grep -qE '(download|sedot|ambil|unduh|downloadin|downloadkan)'; then
                    local dl_match=""
                    dl_match=$(echo "$ki" | grep -oE '(download|sedot|ambil|unduh|downloadin|downloadkan)' | head -1)
                    # Ambil teks setelah kata kunci download
                    local after_dl
                    after_dl=$(echo "$bot_prompt" | sed "s/.*${dl_match}//I" | xargs)
                    # Bersihin kata-kata perintah/artikel di depan
                    after_dl=$(echo "$after_dl" | sed 's/^\(bantu\|tolong\|dung\|in\|kan\|dong\|yah\|ya\|bro\|bang\|kak\|boss\|sih\|deh\|ah\|nih\|dari\|dgn\|dan\|atau\)[ ]*//I' | xargs)
                    # Deteksi tipe: video atau audio?
                    if echo "$ki" | grep -qE '(video|mp4|film|klip)'; then
                        kw_intent="download video"
                        after_dl=$(echo "$after_dl" | sed 's/^\(video\|mp4\|film\|klip\)[ ]*//I' | xargs)
                    else
                        kw_intent="download audio"
                        after_dl=$(echo "$after_dl" | sed 's/^\(audio\|lagu\|musik\|mp3\)[ ]*//I' | xargs)
                    fi
                    # Cek hasil akhir
                    if echo "$after_dl" | grep -qE '^https?://'; then
                        kw_query="$after_dl"
                    elif [ -n "$after_dl" ]; then
                        kw_query="ytsearch1:$after_dl"
                    else
                        kw_query=""
                    fi
                fi

                if [ -z "$kw_intent" ] && echo "$ki" | grep -qE '(spotify|spot)'; then
                    kw_intent="spotify"
                    if echo "$ki" | grep -qE 'https?://'; then
                        kw_query=$(echo "$bot_prompt" | grep -oE 'https?://[^ ]+' | head -1)
                    fi
                fi

                if [ -z "$kw_intent" ] && echo "$ki" | grep -qE '(pisah.*vokal|vokal.*pisah|karaoke|demucs|vocal.?remov|pisahin)'; then
                    kw_intent="hapus vokal"
                fi

                if [ -z "$kw_intent" ] && echo "$ki" | grep -qE '(kompres|kecilin|compress|kecilkan)'; then
                    if echo "$ki" | grep -qE '(video|mp4)'; then
                        kw_intent="kompres video"
                    else
                        kw_intent="kompres media"
                    fi
                fi

                if [ -z "$kw_intent" ] && echo "$ki" | grep -qE '(lirik|sync.*lirik|lyric|cari.*lirik)'; then
                    kw_intent="sync lirik"
                fi

                if [ -z "$kw_intent" ] && echo "$ki" | grep -qE '(bersih.*nama|beresin.*nama|rapihin.*nama|rename.*file|rapiin)'; then
                    kw_intent="bersih nama"
                fi

                if [ -z "$kw_intent" ] && echo "$ki" | grep -qE '(playlist|m3u|buat.*playlist|bikin.*playlist)'; then
                    kw_intent="bikin playlist"
                fi

                if [ -z "$kw_intent" ] && echo "$ki" | grep -qE '(status|info.*sistem|cek.*server|storage|kapasitas)'; then
                    kw_intent="info sistem"
                fi

                if [ -z "$kw_intent" ] && echo "$ki" | grep -qE '(web.*ui|dashboard|webui)'; then
                    kw_intent="web ui"
                fi

                if [ -z "$kw_intent" ] && echo "$ki" | grep -qE '(update|upgrade|perbarui)'; then
                    kw_intent="update"
                fi

                if [ -z "$kw_intent" ] && echo "$ki" | grep -qE '(telegram|bot.*tg)'; then
                    kw_intent="telegram"
                fi

                if [ -z "$kw_intent" ] && echo "$ki" | grep -qE '(watch|daemon|pantau|pemantau)'; then
                    kw_intent="daemon"
                fi

                if [ -z "$kw_intent" ] && echo "$ki" | grep -qE '(setup|konfigurasi|config|setting)'; then
                    kw_intent="setup"
                fi

                if [ -n "$kw_intent" ]; then
                    action_intent="$kw_intent"
                    action_query="$kw_query"
                    is_auto_action=true
                    ai_used=true
                    if [ -z "$clean_reply" ] || [[ "$clean_reply" == "Siap. Ada yang bisa saya bantu?" ]]; then
                        case "$kw_intent" in
                            "download audio") clean_reply="Mau download dari YouTube, Spotify, SoundCloud, atau kirim link aja? 🎵" ;;
                            "download video") clean_reply="Kirim link videonya bro! 💫" ;;
                            "spotify") clean_reply="Kirim link Spotify-nya bro! 🎧" ;;
                            "hapus vokal") clean_reply="Siap, gue pisahin vokalnya! 🎤" ;;
                            "kompres media") clean_reply="Kompres file audio! 🔧" ;;
                            "kompres video") clean_reply="Kompres video! 🎬" ;;
                            "sync lirik") clean_reply="Cari & sync lirik! 📝" ;;
                            "bersih nama") clean_reply="Bersihin nama file! ✨" ;;
                            "bikin playlist") clean_reply="Bikin playlist M3U! 📋" ;;
                            "info sistem") clean_reply="Cek status sistem! 📊" ;;
                            "web ui") clean_reply="Buka Web Dashboard! 🚀" ;;
                            "update") clean_reply="Update tools... 🔄" ;;
                            "telegram") clean_reply="Atur Bot Telegram! 🤖" ;;
                            "daemon") clean_reply="Atur Watch Daemon! 👀" ;;
                            "setup") clean_reply="Buka setup! ⚙️" ;;
                        esac
                    fi
                fi
            fi

            # Anti-empty response fallback
            if [ -z "$clean_reply" ] && [ "$is_auto_action" = false ]; then
                echo -e "  ${YELLOW}${ICO_WARN} Zaki-Bot belum ngerti maksud Bos. Ketik '?' buat bantuan.${RESET}"
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
            
            # Proses Intent (Case-Insensitive)
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

            # Set API Key
            elif [[ "$input" =~ (set (api )?key|api.?key|ganti (api )?key|key (gemini|openrouter)|atur (api )?key|configure key) ]]; then
                echo ""
                echo -e "  ${CYAN}${ICO_ARROW} Pilih API yang mau di-set:${RESET}"
                echo -e "  ${GREEN}[1]${RESET} Gemini API Key"
                echo -e "  ${GREEN}[2]${RESET} OpenRouter API Key"
                echo -e "  ${RED}[0]${RESET} Batal"
                echo -e -n "  ${BOLD}[?] Pilihan [0-2]: ${RESET}"
                local _api_choice
                read -r -n 1 _api_choice; echo ""
                local _key_file=""
                local _key_name=""
                case "$_api_choice" in
                    1) _key_file="$HOME/.config/zdt/gemini_key"; _key_name="Gemini";;
                    2) _key_file="$HOME/.config/zdt/openrouter_key"; _key_name="OpenRouter";;
                    *) echo -e "  ${YELLOW}${ICO_WARN} Dibatalkan.${RESET}"; echo ""; continue;;
                esac
                echo -e -n "  ${BOLD}[?] Masukkan ${_key_name} API Key: ${RESET}"
                local _new_key
                read -r _new_key
                _new_key="${_new_key//\"/}"
                _new_key="${_new_key//\'/}"
                _new_key="$(echo "$_new_key" | tr -d '[:space:]')"
                if [ -z "$_new_key" ]; then
                    echo -e "  ${RED}${ICO_FAIL} Key kosong!${RESET}"
                    echo ""; continue
                fi
                mkdir -p "$(dirname "$_key_file")" 2>/dev/null
                echo "$_new_key" > "$_key_file"
                chmod 600 "$_key_file" 2>/dev/null
                echo -e "  ${GREEN}${ICO_OK} ${_key_name} API Key berhasil disimpan!${RESET}"
                # Verify dengan test call singkat
                if [ "$_api_choice" = "1" ]; then
                    local _test
                    _test=$(curl -sL "https://generativelanguage.googleapis.com/v1beta/models?key=$_new_key" 2>/dev/null | head -c 200)
                    if echo "$_test" | grep -q "models"; then
                        echo -e "  ${GREEN}   ✓ Key valid!${RESET}"
                    else
                        echo -e "  ${YELLOW}   ⚠ Key tersimpan, tapi verifikasi gagal (mungkin butuh waktu propagasi).${RESET}"
                    fi
                else
                    local _test
                    _test=$(curl -sL -o /dev/null -w "%{http_code}" "https://openrouter.ai/api/v1/auth/key" -H "Authorization: Bearer $_new_key" 2>/dev/null)
                    if [ "$_test" = "200" ]; then
                        echo -e "  ${GREEN}   ✓ Key valid!${RESET}"
                    else
                        echo -e "  ${YELLOW}   ⚠ Key tersimpan, tapi verifikasi gagal (HTTP $_test). Cek key di openrouter.ai/keys${RESET}"
                    fi
                fi
                echo ""

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
