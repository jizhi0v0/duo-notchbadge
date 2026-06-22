#!/bin/bash
# 把 main.swift 编成 universal(arm64 + x86_64)二进制,装进 NotchBadge.app
set -euo pipefail
cd "$(dirname "$0")"

APP=NotchBadge
BUNDLE="$APP.app"
MIN=14.0                       # 最低 macOS;keyframeAnimator 要 14+
SPARKLE=".sparkle"             # 解包好的 Sparkle.framework 所在

[ -d "$SPARKLE/Sparkle.framework" ] || { echo "缺 $SPARKLE/Sparkle.framework"; exit 1; }

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources" "$BUNDLE/Contents/Frameworks"
cp Info.plist "$BUNDLE/Contents/Info.plist"

# 嵌入 Sparkle.framework(保留符号链接)
ditto "$SPARKLE/Sparkle.framework" "$BUNDLE/Contents/Frameworks/Sparkle.framework"

# 链接 Sparkle + 运行时从 Contents/Frameworks 找
SPK=(-F "$SPARKLE" -framework Sparkle -Xlinker -rpath -Xlinker "@executable_path/../Frameworks")

echo "编译 arm64 ..."
swiftc -O "${SPK[@]}" -target "arm64-apple-macosx$MIN"  main.swift -o "/tmp/$APP.arm64"
echo "编译 x86_64 ..."
swiftc -O "${SPK[@]}" -target "x86_64-apple-macosx$MIN" main.swift -o "/tmp/$APP.x86_64"

echo "合并 universal ..."
lipo -create -output "$BUNDLE/Contents/MacOS/$APP" "/tmp/$APP.arm64" "/tmp/$APP.x86_64"
rm -f "/tmp/$APP.arm64" "/tmp/$APP.x86_64"

# 图标:有 AppIcon.icns 就放进去(可选)
[ -f AppIcon.icns ] && cp AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns" && \
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$BUNDLE/Contents/Info.plist" 2>/dev/null || true

lipo -info "$BUNDLE/Contents/MacOS/$APP"
echo "✅ 构建完成: $BUNDLE"
