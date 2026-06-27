#!/bin/bash
# release.sh - Script otomatis untuk merilis versi baru ZDT
# Usage: ./release.sh [patch|minor|major]

BUMP_TYPE=${1:-patch}

# Ambil versi saat ini dari zdt.sh
CURRENT_VERSION=$(grep '^readonly APP_VERSION=' zdt.sh | cut -d'"' -f2)

if [ -z "$CURRENT_VERSION" ]; then
    echo "Gagal menemukan APP_VERSION di zdt.sh!"
    exit 1
fi

IFS='.' read -ra VER <<< "$CURRENT_VERSION"

MAJOR=${VER[0]}
MINOR=${VER[1]}
PATCH=${VER[2]}

if [ "$BUMP_TYPE" = "patch" ]; then
    if [ "$PATCH" -ge 99 ]; then
        MINOR=$((MINOR + 1))
        PATCH=0
    else
        PATCH=$((PATCH + 1))
    fi
elif [ "$BUMP_TYPE" = "minor" ]; then
    MINOR=$((MINOR + 1))
    PATCH=0
elif [ "$BUMP_TYPE" = "major" ]; then
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
else
    echo "Tipe bump tidak valid. Gunakan: patch, minor, atau major"
    exit 1
fi

NEW_VERSION="$MAJOR.$MINOR.$PATCH"

echo "🚀 Bumping version: v$CURRENT_VERSION -> v$NEW_VERSION"

# Update VERSION file (single source of truth)
echo "$NEW_VERSION" > VERSION

# Update fallback di zdt.sh (VERSION file is primary, fallback stays in sync)
sed -i "s/readonly APP_VERSION=\"$CURRENT_VERSION\"/readonly APP_VERSION=\"$NEW_VERSION\"/" zdt.sh

# Replace di README.md (khusus baris instalasi)
sed -i "s/ZDT (v$CURRENT_VERSION+)/ZDT (v$NEW_VERSION+)/" README.md

# Terapkan juga ke instalasi lokal (binary + VERSION file share dir)
if [ -f "$HOME/.local/bin/zdt" ]; then
    sed -i "s/readonly APP_VERSION=\"$CURRENT_VERSION\"/readonly APP_VERSION=\"$NEW_VERSION\"/" "$HOME/.local/bin/zdt"
fi
if command -v zdt >/dev/null 2>&1; then
    _share=$(dirname "$(dirname "$(command -v zdt)")")/share/zdt
    cp VERSION "$_share/VERSION" 2>/dev/null || true
fi

# Push ke GitHub
git add VERSION zdt.sh README.md
git commit -m "Release: Version $NEW_VERSION"
git push

echo "✅ Berhasil merilis v$NEW_VERSION ke GitHub!"
