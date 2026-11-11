#!/bin/bash
# MoleBar.app paketini üretir (SwiftPM release + Info.plist + ad-hoc imza).
set -euo pipefail

cd "$(dirname "$0")"
APP="MoleBar.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/MoleBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MoleBar"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Arayüz çevirileri. Türkçe geliştirme dilidir, İngilizce en.lproj içindedir.
for lproj in Resources/*.lproj; do cp -R "$lproj" "$APP/Contents/Resources/"; done

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>tr</string>
    <key>CFBundleLocalizations</key><array><string>tr</string><string>en</string></array>
    <key>CFBundleExecutable</key><string>MoleBar</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>local.molebar</string>
    <key>CFBundleName</key><string>MoleBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.3.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSAppleEventsUsageDescription</key><string>MoleBar, Çöp Kutusu'nu boşaltmak için Finder'a komut gönderir.</string>
    <key>NSLocationUsageDescription</key><string>MoleBar, bağlı Wi-Fi ağının adını (SSID) göstermek için konum iznini kullanır. Konum verisi okunmaz.</string>
    <key>NSLocationWhenInUseUsageDescription</key><string>MoleBar, bağlı Wi-Fi ağının adını (SSID) göstermek için konum iznini kullanır. Konum verisi okunmaz.</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# MOLEBAR_VERSION ile sürüm geçersiz kılınır (release iş akışı etiketten verir).
if [ -n "${MOLEBAR_VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MOLEBAR_VERSION" "$APP/Contents/Info.plist"
fi

# Sabit imza, Tam Disk Erişimi ve Finder izninin kurulumlar arasında kalmasını sağlar.
# SIGN_IDENTITY ile geçersiz kılınır. Sertifika yoksa ad-hoc imza kullanılır.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -1)}"
if [[ "$IDENTITY" == "Developer ID Application:"* ]]; then
  # Noter onayı hardened runtime ve güvenilir zaman damgası ister.
  echo "İmza (Developer ID, hardened runtime): $IDENTITY"
  codesign --force --options runtime --timestamp \
    --entitlements Resources/MoleBar.entitlements --sign "$IDENTITY" "$APP"
elif [ -n "$IDENTITY" ]; then
  echo "İmza: $IDENTITY"
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "Sertifika bulunamadı. Ad-hoc imza kullanılıyor (izinler her kurulumda sıfırlanabilir)."
  codesign --force --sign - "$APP"
fi
echo "Hazır: $(pwd)/$APP"
