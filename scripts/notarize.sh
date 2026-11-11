#!/bin/bash
# DMG dosyasını Apple'a noter onayı için gönderir ve onayı DMG'ye zımbalar.
# Kullanım: scripts/notarize.sh dist/MoleBar-<sürüm>.dmg
# Gerekli ortam değişkenleri:
#   NOTARY_APPLE_ID   Apple hesabı e-postası
#   NOTARY_TEAM_ID    Takım kimliği (10 karakter)
#   NOTARY_PASSWORD   Uygulamaya özel parola (appleid.apple.com)
# DMG, Developer ID imzalı uygulama içermelidir. Ad-hoc imza reddedilir.
set -euo pipefail

DMG="${1:?Kullanım: $0 <dmg>}"
[ -f "$DMG" ] || { echo "Hata: $DMG yok." >&2; exit 1; }
: "${NOTARY_APPLE_ID:?NOTARY_APPLE_ID tanımlı değil}"
: "${NOTARY_TEAM_ID:?NOTARY_TEAM_ID tanımlı değil}"
: "${NOTARY_PASSWORD:?NOTARY_PASSWORD tanımlı değil}"

xcrun notarytool submit "$DMG" \
  --apple-id "$NOTARY_APPLE_ID" \
  --team-id "$NOTARY_TEAM_ID" \
  --password "$NOTARY_PASSWORD" \
  --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "Noter onayı tamam: $DMG"
