#!/bin/bash
# MoleBar.app dosyasından DMG üretir. Önce ./make-app.sh çalıştırın.
# Çıktı: dist/MoleBar-<sürüm>.dmg ve .sha256 dosyası.
# Uygulama Developer ID ile imzalıysa imza korunur ve DMG de aynı kimlikle imzalanır.
# Noter onayı için sonra scripts/notarize.sh çalıştırın.
# Diğer durumda uygulama ad-hoc imzalanır. İlk açılışta sağ tık > Aç gerekir.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="MoleBar.app"
[ -d "$APP" ] || { echo "Hata: $APP yok. Önce ./make-app.sh çalıştırın." >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
OUT_DIR="dist"
DMG="$OUT_DIR/MoleBar-$VERSION.dmg"
mkdir -p "$OUT_DIR"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

# Kaynak uygulama değişmez. İmza kopya üzerinde atılır.
ditto "$APP" "$STAGE/$APP"
AUTHORITY=$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=\(Developer ID Application: .*\)/\1/p' | head -1)
if [ -z "$AUTHORITY" ]; then
  codesign --force --deep -s - "$STAGE/$APP"
fi
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "MoleBar $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
if [ -n "$AUTHORITY" ]; then
  codesign --force --timestamp --sign "$AUTHORITY" "$DMG"
fi

(cd "$OUT_DIR" && shasum -a 256 "$(basename "$DMG")" | tee "$(basename "$DMG").sha256")
echo "Hazır: $DMG"
