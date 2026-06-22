# duo-notchbadge

刘海下方的角标 dock:自动收集所有挂 Dock 角标的 app,吊在刘海下;来消息左右摆,
单击打开,下拉收起/挂回。读 Dock 角标走辅助功能 AX(`AXStatusLabel` / `AXURL`)。
内置 Sparkle 自动更新。

## 本地跑(开发)
```bash
swift main.swift            # 直接解释执行(蹭终端的辅助功能授权;Sparkle 自动跳过)
NOTCH_DEBUG=1 swift main.swift --debug   # 持续左右摆,看动画
```
外观/手感参数都在 `main.swift` 顶部 `enum UI`。

## 打包成 .app
```bash
./fetch-sparkle.sh         # 首次:拉 Sparkle 框架/工具到 .sparkle/(不入库)
./build.sh                 # 编 universal(arm64+x86_64)+ 嵌 Sparkle → NotchBadge.app
```

## 公开分发(签名 + 公证)
> 上不了 App Store(沙盒读不到 Dock 的 AX)。只能自分发 dmg/zip,且必须签名+公证,
> 否则别人下载会被 Gatekeeper 拦。需要 Apple 开发者账号($99/年)。

1. 一次性存好公证凭据:
   ```bash
   xcrun notarytool store-credentials notch-notary \
     --apple-id "你的AppleID" --team-id "TEAMID" --password "App专用密码"
   ```
2. 出包:
   ```bash
   export DEV_ID="Developer ID Application: 你的名字 (TEAMID)"
   ./fetch-sparkle.sh && ./build.sh && ./release.sh   # → NotchBadge.dmg(签名+公证+装订)
   ```

## 仓库结构
- **本仓 `duo-notchbadge`(私有)**:源码、构建/发布脚本。
- **`duo-notchbadge-releases`(公开)**:只放 release(dmg + appcast)给用户下载/自动更新。
  `SUFeedURL` 指向它的 `releases/latest/download/appcast.xml`。

## 发新版(Sparkle 自动更新)
更新签名公钥 `SUPublicEDKey` 已在 Info.plist;私钥在你的钥匙串(`generate_keys` 生成)。
1. 改 `Info.plist` 的 `CFBundleVersion`(+1)和 `CFBundleShortVersionString`,`./build.sh && ./release.sh`。
2. 在**发布仓**建 release(tag 如 `v1.1`)传 dmg,再生成并上传签名 appcast:
   ```bash
   REL=jizhi0v0/duo-notchbadge-releases
   gh release create v1.1 NotchBadge.dmg --repo "$REL" -t "NotchBadge 1.1" -n "更新说明"
   d=$(mktemp -d); cp NotchBadge.dmg "$d"/
   ./.sparkle/bin/generate_appcast --download-url-prefix \
     "https://github.com/$REL/releases/download/v1.1/" "$d"
   gh release upload v1.1 "$d/appcast.xml" --repo "$REL"
   ```
   旧用户的 app 后台轮询到新 appcast → 弹更新。

## 每台机首次要做(给用户说明)
1. 打开 NotchBadge.app(签名公证过的版本直接双击即可)。
2. 系统会提示授权「辅助功能」→ 系统设置 > 隐私与安全 > 辅助功能 → 勾上 NotchBadge。
   - 这是读 Dock 角标必须的;不给权限就只是空着不显示。
3. 想开机自启:系统设置 > 通用 > 登录项 里加 NotchBadge(或后续做成 LaunchAgent)。

## 注意
- **签名要稳定**:辅助功能授权绑在代码签名上。每次更新都用同一 Developer ID 签,
  授权才会跨版本保留;换签名/ad-hoc 会让用户得重新勾。
- **最低系统 macOS 14**(`keyframeAnimator` 需要)。
- 读 `AXStatusLabel`/`AXURL` 是 Dock 的非公开行为,跨大版本 macOS 可能变,按目标系统测一下。
