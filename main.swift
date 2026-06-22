import Cocoa
import SwiftUI
import ApplicationServices
import ServiceManagement   // 开机自启(SMAppService)
#if canImport(Sparkle)
import Sparkle      // 带 -F .sparkle 编译时启用;swift main.swift 直接跑会自动跳过
#endif

// DEBUG:持续左右摆给你观察动画。开法:NOTCH_DEBUG=1 swift main.swift  或  swift main.swift --debug
let DEBUG = ProcessInfo.processInfo.environment["NOTCH_DEBUG"] == "1" || CommandLine.arguments.contains("--debug")

// MARK: - AX 读取 Dock 角标
func axAttr(_ el: AXUIElement, _ a: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, a as CFString, &v) == .success ? v : nil
}

struct RawBadge { let name: String; let path: String; let badge: String }

func readDockBadges() -> [RawBadge] {
    guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [] }
    let app = AXUIElementCreateApplication(dock.processIdentifier)
    let lists = axAttr(app, kAXChildrenAttribute as String) as? [AXUIElement] ?? []
    var out: [RawBadge] = []
    var seen = Set<String>()
    for list in lists {
        let items = axAttr(list, kAXChildrenAttribute as String) as? [AXUIElement] ?? []
        for it in items {
            // 只认真正的 Dock 应用图标项,挡掉 ⌘-Tab 切换器等其它 list
            guard axAttr(it, kAXSubroleAttribute as String) as? String == "AXApplicationDockItem" else { continue }
            guard let badge = axAttr(it, "AXStatusLabel") as? String, !badge.isEmpty else { continue }
            let path = (axAttr(it, "AXURL") as? URL)?.path ?? ""   // 直接拿 app 路径,不靠名字匹配
            guard !path.isEmpty, !seen.contains(path) else { continue } // 无路径(幽灵项)/重复 → 滤掉
            seen.insert(path)
            let name = axAttr(it, kAXTitleAttribute as String) as? String ?? "?"
            out.append(RawBadge(name: name, path: path, badge: badge))
        }
    }
    return out
}

// MARK: - 数据模型
struct BadgeApp: Identifiable {
    let id: String
    let name: String
    let path: String         // app 路径,下拉时用来打开
    let icon: NSImage
    var badge: String
    var bounceToken: Int
}

final class Model: ObservableObject {
    @Published var apps: [BadgeApp] = []
    @Published var debugTick = 0                 // debug 模式心跳,每跳一次全体摆一下
    @Published var hovering = false              // 悬停刘海 → 展开
    @Published var peeking = false               // 来消息临时探头
    @Published var retractedIds: Set<String> = []  // 被手动收起的 app(只剩小角标钮)
    var dragging = false                          // 正在拖某个图标(拖动期间保持可交互,非 @Published 免重渲染)
    private var peekWork: DispatchWorkItem?
    private var prevBadge: [String: Int] = [:]
    private var prevToken: [String: Int] = [:]
    private var iconCache: [String: NSImage] = [:]   // 图标缓存,避免每次刷新 new 一个导致闪烁
    private var lastSig = ""                          // 内容签名,没变就不重发 apps

    var iconsVisible: Bool { UI.alwaysShow || hovering || peeking || DEBUG }

    func show(_ on: Bool) {                       // 悬停展开/收起
        guard hovering != on else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.74)) { hovering = on }
    }

    func toggleRetract(_ id: String) {            // 下拉收起 / 挂回
        if retractedIds.contains(id) { retractedIds.remove(id) } else { retractedIds.insert(id) }
    }

    var allRetracted: Bool { !apps.isEmpty && apps.allSatisfy { retractedIds.contains($0.id) } }
    func toggleSuspendAll() {                     // 一键全部挂起 / 全部恢复
        withAnimation(.spring(response: 0.42, dampingFraction: 0.6)) {
            if allRetracted { retractedIds.removeAll() } else { retractedIds = Set(apps.map { $0.id }) }
        }
    }

    func peek() {                                // 来消息 → 探头几秒再自动收起
        if hovering { return }
        peeking = true
        peekWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            withAnimation(.spring(response: 0.34, dampingFraction: 0.74)) { self?.peeking = false }
        }
        peekWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + UI.peekSeconds, execute: w)
    }

    func icon(forPath path: String) -> NSImage {
        if let c = iconCache[path] { return c }
        let img: NSImage = (!path.isEmpty && FileManager.default.fileExists(atPath: path))
            ? NSWorkspace.shared.icon(forFile: path)        // 用 AXURL 路径直接取,最稳
            : NSWorkspace.shared.icon(for: .applicationBundle)
        iconCache[path] = img
        return img
    }

    func refresh() {
        let raw = readDockBadges()
        var next: [BadgeApp] = []
        var bumped = false
        for r in raw {
            let key = r.path.isEmpty ? r.name : r.path        // 路径优先当稳定 id
            let n = Int(r.badge.filter(\.isNumber)) ?? 0
            var token = prevToken[key] ?? 0
            if let old = prevBadge[key], n > old { token += 1; bumped = true }   // 角标变大
            else if prevBadge[key] == nil && n > 0 { token += 1; bumped = true } // 首次出现
            prevBadge[key] = n
            prevToken[key] = token
            next.append(BadgeApp(id: key, name: r.name, path: r.path, icon: icon(forPath: r.path), badge: r.badge, bounceToken: token))
        }
        // 清掉已消失的
        let live = Set(raw.map { $0.path.isEmpty ? $0.name : $0.path })
        prevBadge = prevBadge.filter { live.contains($0.key) }
        prevToken = prevToken.filter { live.contains($0.key) }
        let prunedRetract = retractedIds.intersection(live)        // app 消失就别留在收起集里
        if prunedRetract != retractedIds { retractedIds = prunedRetract }
        // debug 模式下若当前没有任何角标,注入一个占位图标,保证有东西可看
        if DEBUG && next.isEmpty {
            let p = "/Applications/Telegram.app"
            let pp = FileManager.default.fileExists(atPath: p) ? p : ""
            next.append(BadgeApp(id: "debug", name: "debug", path: pp,
                                 icon: icon(forPath: pp), badge: "9", bounceToken: 0))
        }
        let result = next.sorted { $0.name < $1.name }
        let sig = result.map { "\($0.id)|\($0.badge)|\($0.bounceToken)" }.joined(separator: ",")
        if sig == lastSig { return }             // 内容没变就不重发,避免打断摆动→闪烁
        lastSig = sig
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.74)) { self.apps = result }
            if bumped { self.peek() }            // 来消息 → 探头
        }
    }
}

// MARK: - 外观参数(想调改这里)
enum UI {
    static let alwaysShow = true           // 常驻模式:图标一直挂着。改 false = 平时收起、悬停/来消息才显示
    static let iconSize: CGFloat   = 20    // 图标边长
    static let spacing: CGFloat    = 14    // 图标间距(大点,摆动不撞)
    static let badgeFont: CGFloat  = 8     // 角标字号
    static let threadLen: CGFloat  = 32    // 挂着态吊线长度(越大图标垂得越低,垂到标签页下方)
    static let swingDeg: Double    = 16    // 单摆初始摆角(度)
    static let clearance: CGFloat  = 14    // 左右留白,防摆出窗口被裁
    static let gapBelowNotch: CGFloat = 2  // 离刘海底的余量(越小越贴顶,太小收起态会被刘海下沿切)
    static let peekSeconds: Double = 4.0   // 来消息探头停留秒数,然后自动收起
    static let pullMax: CGFloat    = 28    // 单个 app 最多能下拉多长
    static let pullThreshold: CGFloat = 16 // 下拉超过这距离 → 切换收起/挂回
    static let retractScale: CGFloat = 0.78 // 收起态图标缩到多大(不显角标,所以可以大一些)
}

// MARK: - 视图:一根线吊一个图标 = 一个可拖拽个体,两个停靠位(挂着 / 收起)。
// 图标一直显示;线长随手指连续变化;收起=线收到0+图标缩小贴刘海;来消息左右摆。
struct Dangler: View {
    let app: BadgeApp
    var extra: Int = 0          // debug 心跳,跟 bounceToken 合并成触发
    let retracted: Bool         // 当前停靠位:true=收起
    let onToggle: () -> Void
    var onDrag: (Bool) -> Void = { _ in }   // 拖动开始/结束,通知外层保持可交互
    @State private var pull: CGFloat = 0

    var body: some View {
        let rest: CGFloat = retracted ? 0 : UI.threadLen      // 停靠位的线长
        let dropY = rest + pull                               // 当前线长(含拖动)
        let t = min(1, dropY / UI.threadLen)                  // 0=收起 1=挂起
        let scale = UI.retractScale + (1 - UI.retractScale) * t
        VStack(spacing: 0) {
            Rectangle()
                .fill(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.03)],
                                     startPoint: .top, endPoint: .bottom))  // 上深下浅:出刘海看得见,进内容区渐隐
                .frame(width: 1, height: dropY)              // 线一直在,长度连续跟手
            Image(nsImage: app.icon)
                .resizable().interpolation(.high)
                .frame(width: UI.iconSize, height: UI.iconSize)
                .shadow(color: .black.opacity(0.30), radius: 3, y: 1)
                .overlay(alignment: .topTrailing) {
                    Text(app.badge)
                        .font(.system(size: UI.badgeFont, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 3.5).padding(.vertical, 0.5)
                        .background(Capsule().fill(.red))
                        .offset(x: 4, y: -3)
                        .opacity(t)                  // 收起(t→0)时角标淡出,只留图标
                }
                .scaleEffect(scale, anchor: .top)    // 收起时图标整体缩放
        }
        .frame(width: UI.iconSize, alignment: .top)
        .contentShape(Rectangle())
        // 绕「线顶」旋转 → 单摆(来消息)
        .keyframeAnimator(initialValue: 0.0, trigger: app.bounceToken &+ extra) { content, angle in
            content.rotationEffect(.degrees(angle), anchor: .top)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(UI.swingDeg,         duration: 0.16)
                CubicKeyframe(-UI.swingDeg * 0.65, duration: 0.28)
                CubicKeyframe(UI.swingDeg * 0.40,  duration: 0.26)
                CubicKeyframe(-UI.swingDeg * 0.22, duration: 0.24)
                CubicKeyframe(UI.swingDeg * 0.10,  duration: 0.22)
                CubicKeyframe(0,                   duration: 0.20)
            }
        }
        // 下拉松手过阈值 → 切到另一个停靠位,然后弹回贴位
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in onDrag(true); pull = max(0, min(v.translation.height, UI.pullMax)) }
                .onEnded { v in
                    let moved = abs(v.translation.height) > 6 || abs(v.translation.width) > 6
                    if !moved {
                        if !app.path.isEmpty {                       // 单击 → 打开/激活该 app
                            NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
                        }
                    } else if v.translation.height > UI.pullThreshold {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.55)) { onToggle() }  // 下拉 → 收起/挂回
                    }
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.5)) { pull = 0 }
                    onDrag(false)
                }
        )
    }
}

// 折叠态的小提示:刘海下一个低调小横条,悬停它就展开
struct Nub: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(.white.opacity(0.22))
            .frame(width: 24, height: 4)
            .padding(.top, 3)
    }
}

struct NotchDockView: View {
    @ObservedObject var model: Model
    var body: some View {
        ZStack(alignment: .top) {
            if model.iconsVisible {
                HStack(alignment: .top, spacing: UI.spacing) {
                    ForEach(model.apps) { a in
                        Dangler(app: a, extra: model.debugTick,
                                retracted: model.retractedIds.contains(a.id),
                                onToggle: { model.toggleRetract(a.id) },
                                onDrag: { model.dragging = $0 })
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))   // 从刘海里吊下来/缩回
            } else {
                Nub()
            }
        }
        .padding(.horizontal, UI.clearance)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)   // 居中挂在刘海下
        .animation(.spring(response: 0.34, dampingFraction: 0.74), value: model.iconsVisible)
    }
}

// MARK: - 窗口 / App
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {                          // 打开菜单时刷新状态
        refreshLoginState()
        suspendItem?.title = model.allRetracted ? "全部恢复" : "全部挂起"
    }
    let model = Model()
    var window: NSPanel!
    var timer: Timer?
    var hoverTimer: Timer?
    var statusItem: NSStatusItem!
    weak var loginItem: NSMenuItem?
    weak var suspendItem: NSMenuItem?
    #if canImport(Sparkle)
    var updater: SPUStandardUpdaterController!     // Sparkle 自动更新控制器
    #endif

    func applicationDidFinishLaunching(_ n: Notification) {
        ensureAccessibility()      // 没辅助功能权限就弹系统提示+开设置(分发后每台机首次都要授权)
        #if canImport(Sparkle)
        updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        #endif
        setupMenuBar()

        let panel = NSPanel(contentRect: .init(x: 0, y: 0, width: 80, height: 90),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true     // 默认穿透;只在 dock 区域临时打开交互
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: NotchDockView(model: model))
        self.window = panel

        if DEBUG { NSLog("NotchBadge DEBUG: 持续左右摆") }

        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in self?.tick() }
        tick()
        panel.orderFrontRegardless()

        // 12.5Hz 轮询光标:悬停刘海下方区域 → 展开 + 开放鼠标(可下拉),离开收起
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.updateInteractivity()
        }

        if DEBUG {
            Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                self?.model.debugTick &+= 1     // 每 1.5s 触发一次单摆
            }
        }
    }

    // 辅助功能权限:没有就弹系统提示并把本 app 加进列表、打开「隐私与安全 > 辅助功能」
    func ensureAccessibility() {
        if AXIsProcessTrusted() { return }
        let opt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([opt: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // 菜单栏状态项:查更新 / 开机自启 / 退出(app 没别的 UI 入口,靠这个)
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let img = NSImage(systemSymbolName: "bell.badge", accessibilityDescription: "NotchBadge") {
            img.isTemplate = true
            statusItem.button?.image = img
        }
        let menu = NSMenu()
        menu.delegate = self
        let susp = NSMenuItem(title: "全部挂起", action: #selector(toggleSuspendAll), keyEquivalent: "s")
        susp.target = self; menu.addItem(susp); suspendItem = susp
        menu.addItem(.separator())
        #if canImport(Sparkle)
        let upd = NSMenuItem(title: "检查更新…", action: #selector(checkForUpdates), keyEquivalent: "")
        upd.target = self; menu.addItem(upd)
        #endif
        let login = NSMenuItem(title: "开机自启", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self; menu.addItem(login); loginItem = login
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 NotchBadge", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        statusItem.menu = menu
        refreshLoginState()
    }

    func refreshLoginState() {
        loginItem?.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    @objc func toggleSuspendAll() { model.toggleSuspendAll() }

    @objc func checkForUpdates() {
        #if canImport(Sparkle)
        updater.checkForUpdates(nil)
        #endif
    }

    @objc func toggleLogin() {
        let svc = SMAppService.mainApp
        do { svc.status == .enabled ? try svc.unregister() : try svc.register() }
        catch { NSLog("login toggle: \(error)") }
        refreshLoginState()
    }

    @objc func quitApp() { NSApp.terminate(nil) }

    func tick() {
        model.refresh()
        DispatchQueue.main.async { [weak self] in self?.layout() }
    }

    func layout() {
        guard let screen = NSScreen.main, let panel = window else { return }
        let f = screen.frame
        let topInset = f.maxY - screen.visibleFrame.maxY                 // 菜单栏/刘海高度
        let n = max(model.apps.count, 1)
        let iconsW = CGFloat(n) * (UI.iconSize + UI.spacing)
        let w = UI.clearance * 2 + iconsW + UI.spacing                  // 预留展开宽度,探头不被裁
        let h = UI.threadLen + UI.pullMax + UI.iconSize + 24
        let x = f.midX - w / 2                                          // 居中挂在刘海下
        let y = f.maxY - topInset - h - UI.gapBelowNotch
        panel.setFrame(.init(x: x, y: y, width: w, height: h), display: true)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private var lastInside = Date.distantPast

    // 每个图标占的小竖条(屏幕坐标)。只有这些条才拦鼠标,其余透明区放行点击
    private func iconStrips() -> [CGRect] {
        guard let panel = window else { return [] }
        let f = panel.frame
        let n = model.apps.count
        guard n > 0 else { return [] }
        let contentW = CGFloat(n) * UI.iconSize + CGFloat(n - 1) * UI.spacing
        let left = f.minX + (f.width - contentW) / 2          // 居中
        let m: CGFloat = 3                                     // 一点点边距好抓
        return (0..<n).map { i in
            let cx = left + CGFloat(i) * (UI.iconSize + UI.spacing) + UI.iconSize / 2   // 图标中心x
            let retracted = model.retractedIds.contains(model.apps[i].id)
            let vis = retracted ? UI.iconSize * UI.retractScale : UI.iconSize           // 可见图标边长
            let topOffset = retracted ? 0 : UI.threadLen                                 // 图标顶距窗口顶(=线长)
            let iconTopY = f.maxY - topOffset                                            // 屏幕坐标:图标顶
            // 只盖「图标本身」那个小方块,不含上面的线 → 线穿过的标签栏照样能点
            return CGRect(x: cx - vis / 2 - m, y: iconTopY - vis - m, width: vis + 2 * m, height: vis + 2 * m)
        }
    }

    func updateInteractivity() {
        guard let panel = window, panel.isVisible else { return }
        let p = NSEvent.mouseLocation
        let f = panel.frame
        // 只有压在图标本身(贴尺寸)那一小块、或正在拖动时才拦鼠标,其余照样穿透
        let overIcon = (model.iconsVisible && iconStrips().contains { $0.contains(p) }) || model.dragging
        panel.ignoresMouseEvents = !overIcon

        // 仅 hover 模式才管展开/收起(用较宽的"在 dock 附近"判断,免得移出图标就缩)
        if !UI.alwaysShow {
            let nearW: CGFloat = model.iconsVisible ? f.width : 90
            let nearH: CGFloat = model.iconsVisible ? f.height : 26
            let near = CGRect(x: f.midX - nearW / 2, y: f.maxY - nearH, width: nearW, height: nearH).contains(p)
            if near {
                lastInside = Date()
                if !model.hovering { model.show(true) }
            } else if model.hovering, Date().timeIntervalSince(lastInside) > 0.35 {
                model.show(false)
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // 不占 Dock
let delegate = AppDelegate()
app.delegate = delegate
app.run()
