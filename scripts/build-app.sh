#!/bin/bash
# TokenCat.app 번들 + dmg 생성 (§6 M3).
#
# 사용법:
#   scripts/build-app.sh                          # ad-hoc 서명 (로컬 실행용)
#   CODESIGN_IDENTITY="Developer ID Application: ..." scripts/build-app.sh
#   NOTARY_PROFILE=<notarytool keychain profile> CODESIGN_IDENTITY=... scripts/build-app.sh
#
# notarize까지 하려면 사전에 1회:
#   xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <team> --password <app-pw>
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

echo "▸ release 빌드"
swift build -c release

APP=dist/TokenCat.app
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/TokenCat "$APP/Contents/MacOS/"
# SPM 리소스 번들 (스프라이트 Assets) — Bundle.module이 Contents/Resources에서 찾음
if [ -d .build/release/TokenCat_TokenCat.bundle ]; then
  cp -R .build/release/TokenCat_TokenCat.bundle "$APP/Contents/Resources/"
fi
cp scripts/Info.plist "$APP/Contents/Info.plist"

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  echo "▸ 서명: $CODESIGN_IDENTITY (hardened runtime)"
  codesign --force --deep --options runtime -s "$CODESIGN_IDENTITY" "$APP"
else
  echo "▸ ad-hoc 서명 (배포용은 CODESIGN_IDENTITY 필요)"
  codesign --force --deep -s - "$APP"
fi

echo "▸ dmg 생성"
hdiutil create -volname TokenCat -srcfolder "$APP" -ov -format UDZO dist/TokenCat.dmg > /dev/null

if [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "▸ notarize 제출"
  xcrun notarytool submit dist/TokenCat.dmg --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  xcrun stapler staple dist/TokenCat.dmg
fi

echo "✓ 완료: $APP, dist/TokenCat.dmg"
codesign -dv "$APP" 2>&1 | head -3
