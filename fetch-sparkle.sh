#!/bin/bash
# 拉取官方 Sparkle 二进制包到 .sparkle/(框架+工具,克隆后构建前先跑一次)。不入库。
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .sparkle && cd .sparkle
TAG=$(gh release view --repo sparkle-project/Sparkle --json tagName -q .tagName)
echo "下载 Sparkle $TAG ..."
gh release download "$TAG" --repo sparkle-project/Sparkle --pattern "Sparkle-*.tar.xz" --dir . --clobber
tar xf Sparkle-*.tar.xz
echo "✅ .sparkle/ 就绪(Sparkle.framework + bin/{generate_keys,generate_appcast,sign_update})"
