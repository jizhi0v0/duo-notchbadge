#!/bin/bash
# 画图标 → 生成 AppIcon.icns(各尺寸)。build.sh 会自动把 AppIcon.icns 放进 bundle。
set -euo pipefail
cd "$(dirname "$0")"

swift make-icon.swift /tmp/icon1024.png

ICONSET=/tmp/AppIcon.iconset
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
gen() { sips -z "$2" "$2" /tmp/icon1024.png --out "$ICONSET/icon_$1.png" >/dev/null; }
gen 16x16        16
gen 16x16@2x     32
gen 32x32        32
gen 32x32@2x     64
gen 128x128     128
gen 128x128@2x  256
gen 256x256     256
gen 256x256@2x  512
gen 512x512     512
gen 512x512@2x 1024
iconutil -c icns "$ICONSET" -o AppIcon.icns
echo "✅ AppIcon.icns 生成完成"
