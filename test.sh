test_match() {
    local raw="$1"
    if [[ "$raw" =~ ^(.*)[[:space:]]+([^[:space:]]+)$ ]]; then
        cmd="${BASH_REMATCH[1],,}"
        arg="${BASH_REMATCH[2]}"
    else
        cmd="${raw,,}"
        arg=""
    fi
    echo "CMD: '$cmd' ARG: '$arg'"
}
test_match "Gas Download Smart https://www.youtube.com/watch?v=lHFOzj1_suE"
test_match "Gas Download Audio ytsearch1:tulus hati-hati"
test_match "Gas Setup"
test_match "Hapus Vokal"
