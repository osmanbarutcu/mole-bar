#!/bin/bash
# MoleBar'ı derler ve /Applications altına kurar.
# Mevcut kurulum varsa önce çalışan uygulamayı kapatır, sonra değiştirir.
set -euo pipefail

cd "$(dirname "$0")"
TARGET="/Applications/MoleBar.app"

./make-app.sh

if pgrep -x MoleBar > /dev/null; then
    osascript -e 'tell application "MoleBar" to quit' > /dev/null 2>&1 || pkill -x MoleBar || true
    sleep 2
fi

if [ -d "$TARGET" ]; then
    echo "Mevcut kurulum değiştiriliyor: $TARGET"
    rm -rf "$TARGET"
fi

cp -R MoleBar.app "$TARGET"
codesign --verify --deep "$TARGET"
echo "Kuruldu: $TARGET"
open "$TARGET"
