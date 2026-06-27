#!/usr/bin/env bash

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}   ${YELLOW}Zaki Downloader Tools (ZDT) Installer${NC}          ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo ""

# Detect Prefix
PREFIX="/usr/local"
if [ -n "${TERMUX_VERSION:-}" ] || [ -n "${PREFIX_TERMUX:-}" ]; then
    PREFIX="/data/data/com.termux/files/usr"
elif [ "$(id -u)" -ne 0 ]; then
    PREFIX="$HOME/.local"
    mkdir -p "$PREFIX/bin"
    echo -e "${YELLOW}Notice:${NC} Running without root. Installing to $PREFIX/bin"
fi

BINDIR="$PREFIX/bin"
SHAREDIR="$PREFIX/share/zdt"

echo -e "Installing ZDT to ${GREEN}$BINDIR${NC}..."

# Create dirs
mkdir -p "$BINDIR" || {
    echo -e "${RED}Error: Cannot create directory $BINDIR. Run with sudo?${NC}"
    exit 1
}
mkdir -p "$SHAREDIR"

# Copy main script
if [ ! -f "zdt.sh" ]; then
    echo -e "${RED}Error: zdt.sh not found in current directory!${NC}"
    exit 1
fi

cp zdt.sh "$BINDIR/zdt"
chmod +x "$BINDIR/zdt"

if [ -f "zdt-telegram.py" ]; then
    cp zdt-telegram.py "$SHAREDIR/"
    chmod +x "$SHAREDIR/zdt-telegram.py"
fi

if [ -f "zdt-web.py" ]; then
    cp zdt-web.py "$SHAREDIR/"
    chmod +x "$SHAREDIR/zdt-web.py"
fi

# Copy web dashboard templates
if [ -d "templates" ] && [ -n "$(ls -A templates/ 2>/dev/null)" ]; then
    mkdir -p "$SHAREDIR/templates"
    cp -r templates/* "$SHAREDIR/templates/"
    echo -e "${GREEN}Templates:${NC} Web dashboard templates installed."
fi

if [ -f "zdt-watch.py" ]; then
    cp zdt-watch.py "$SHAREDIR/"
    chmod +x "$SHAREDIR/zdt-watch.py"
fi

if [ -f "zdt-scheduler.py" ]; then
    cp zdt-scheduler.py "$SHAREDIR/"
    chmod +x "$SHAREDIR/zdt-scheduler.py"
fi

# Copy AI prompt template
if [ -f "zdt-ai-prompt.txt" ]; then
    cp zdt-ai-prompt.txt "$SHAREDIR/"
    echo -e "${GREEN}AI Prompt:${NC} ZDT AI prompt template installed."
fi

# Copy module files
if [ -d "zdt-modules" ]; then
    mkdir -p "$SHAREDIR/zdt-modules"
    for mod in "zdt-modules/"*.sh; do
        [ -f "$mod" ] && cp "$mod" "$SHAREDIR/zdt-modules/"
    done
    echo -e "${GREEN}Modules:${NC} ZDT module files installed."
fi

echo -e "${GREEN}Success!${NC} ZDT has been installed."
echo -e "You can now run the toolkit by typing: ${YELLOW}zdt${NC}"

if [[ ":$PATH:" != *":$BINDIR:"* ]]; then
    echo -e "${YELLOW}Warning:${NC} $BINDIR is not in your PATH."
    echo "Please add it to your ~/.bashrc or ~/.zshrc:"
    echo "  export PATH=\"\$PATH:$BINDIR\""
fi
