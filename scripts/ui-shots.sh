#!/bin/bash
# Tüm sayfaların ve panel sekmelerinin ekran görüntüsünü alır. Tasarım gerilemelerini yakalamak içindir.
# Kullanım: scripts/ui-shots.sh [çıktı klasörü] [system|light|dark]
# Gereksinim: Terminal için Erişilebilirlik izni (menü ve düğme tıklamaları için).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/ui-shots}"
MODE="${2:-system}"
APP=/Applications/MoleBar.app
BIN="$APP/Contents/MacOS/MoleBar"
TOOL="$(mktemp -d)/windowlist"
mkdir -p "$OUT"
swiftc -o "$TOOL" "$ROOT/scripts/windowlist.swift" 2>/dev/null

SECTIONS=("Genel" "Diskler" "Analiz" "Büyük dosyalar" "Yinelenenler" "Önbellek" "Uygulamalar" "Süreçler" "Araçlar" "Ayarlar")
TABS=("Genel" "Diskler" "Süreçler" "Araçlar")

onscreen_window() { "$TOOL" | awk '$3==1{print $1}' | head -1; }
click_menu() {
  osascript -e "tell application \"System Events\" to tell process \"MoleBar\" to click menu item \"$1\" of menu 1 of menu bar item \"Sayfa\" of menu bar 1" >/dev/null 2>&1 || true
}
place_window() {
  osascript -e 'tell application "System Events" to tell process "MoleBar" to set position of window 1 to {60, 60}' >/dev/null 2>&1 || true
}

pkill -x MoleBar 2>/dev/null || true; sleep 1
defaults write local.molebar appearance "$MODE"

echo "Ana pencere sayfaları ($MODE)"
open -a "$APP"; sleep 5; place_window
for name in "${SECTIONS[@]}"; do
  click_menu "$name"; sleep 3
  screencapture -x -o -l "$(onscreen_window)" "$OUT/main-${MODE}-${name// /_}.png"
  echo "  $name"
done

pkill -x MoleBar 2>/dev/null || true; sleep 1
echo "Panel sekmeleri ($MODE)"
MOLEBAR_PANEL_PREVIEW=1 "$BIN" >/dev/null 2>&1 &
sleep 6; place_window
index=1
for name in "${TABS[@]}"; do
  osascript -e "tell application \"System Events\" to tell process \"MoleBar\" to click radio button $index of radio group 1 of group 1 of window 1" >/dev/null 2>&1 || true
  sleep 2
  screencapture -x -o -l "$(onscreen_window)" "$OUT/panel-${MODE}-${name}.png"
  echo "  $name"
  index=$((index + 1))
done

pkill -x MoleBar 2>/dev/null || true
defaults write local.molebar appearance system
echo "Bitti: $OUT"
