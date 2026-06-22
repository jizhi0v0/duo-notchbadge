#!/bin/bash
# Developer ID 签名 + 公证 + 装订 + 打 dmg。先跑 ./build.sh。
# 需要先设置(证书是你的,我不经手):
#   export DEV_ID="Developer ID Application: 你的名字 (TEAMID)"
#   一次性存好公证凭据(之后用 --keychain-profile 引用):
#     xcrun notarytool store-credentials notch-notary \
#        --apple-id "你的AppleID" --team-id "TEAMID" --password "App专用密码"
set -euo pipefail
cd "$(dirname "$0")"

APP=NotchBadge
BUNDLE="$APP.app"
PROFILE="${AC_PROFILE:-notch-notary}"   # notarytool keychain profile 名

: "${DEV_ID:?请先 export DEV_ID='Developer ID Application: ... (TEAMID)'}"
[ -d "$BUNDLE" ] || { echo "先跑 ./build.sh"; exit 1; }

echo "① 签名:先 Sparkle 内部组件(由内到外)再主 app,全部 hardened runtime ..."
SP="$BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B"
sign() { codesign --force --options runtime --timestamp --sign "$DEV_ID" "$@"; }
if [ -d "$SP" ]; then
  sign "$SP/XPCServices/Downloader.xpc"
  sign "$SP/XPCServices/Installer.xpc"
  sign "$SP/Updater.app"
  sign "$SP/Autoupdate"
  sign "$BUNDLE/Contents/Frameworks/Sparkle.framework"
fi
sign "$BUNDLE"                                  # 主 app 最后签
codesign --verify --strict --verbose=2 "$BUNDLE"

echo "② 打 zip 交公证..."
ditto -c -k --keepParent "$BUNDLE" "$APP.zip"
xcrun notarytool submit "$APP.zip" --keychain-profile "$PROFILE" --wait

echo "③ 装订票据..."
xcrun stapler staple "$BUNDLE"
xcrun stapler validate "$BUNDLE"

echo "④ 打 dmg..."
rm -f "$APP.dmg"
hdiutil create -volname "$APP" -srcfolder "$BUNDLE" -ov -format UDZO "$APP.dmg"
rm -f "$APP.zip"

echo "✅ 可分发: $APP.dmg(已签名+公证+装订,别人下载直接能开)"
