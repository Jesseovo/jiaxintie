import AppKit
import ScreenCaptureKit
import JiaXinTieCore

enum CaptureAction { case copy, save, pin }

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let recentMenu = NSMenu()
    private let hotkeys = HotKeyManager()
    private var hotkeyFailures: [String] = []
    private var settings = Settings()
    private let settingsStore: SettingsStore
    private var store: ShotStore?
    private var preferences: SettingsWindowController?
    private var overlays: [CaptureWindow] = []
    private var pins: [PinWindow] = []
    private var hiddenPins = false
    private var capturePending = false
    private var lastImage: NSImage?
    private let demo = CommandLine.arguments.contains("--demo")
    override init() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of:"--profile"), index+1 < args.count {
            settingsStore = SettingsStore(directory:URL(fileURLWithPath:args[index+1]))
        } else if args.contains("--demo") {
            settingsStore = SettingsStore(directory:FileManager.default.temporaryDirectory.appendingPathComponent("JiaXinTie-demo-\(UUID().uuidString)"))
        } else { settingsStore = SettingsStore() }
        super.init()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--smoke-test") {
            do { try AppSmokeTest.run(); NSApp.terminate(nil) }
            catch { fputs("FAIL: \(error.localizedDescription)\n",stderr); exit(1) }
            return
        }
        // Reopening the installed app brings up its settings instead of creating another menu item.
        let bundleID = Bundle.main.bundleIdentifier ?? "com.jesseovo.jiaxintie"
        if !demo, let running = NSRunningApplication.runningApplications(withBundleIdentifier:bundleID).first(where:{$0.processIdentifier != ProcessInfo.processInfo.processIdentifier}) {
            running.activate(options:[]); NSApp.terminate(nil); return
        }
        do {
            settings = try settingsStore.load()
            if demo { settings.saveDirectory = settingsStore.directory.appendingPathComponent("截图").path; settings.hasCompletedSetup = true }
            store = try ShotStore(directory:settings.saveDirectory); try store?.trim()
        } catch { showError(error) }
        setupMenu()
        hotkeys.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .capture, .quickCapture: self.startCapture(quick:action == .quickCapture)
            case .pin: self.pasteImage()
            case .togglePins: self.togglePins()
            default: break
            }
        }
        resumeHotkeys()
        if demo { startDemo() }
        else if !settings.hasCompletedSetup || store == nil { showSettings() }
        else if CommandLine.arguments.contains("--capture") { startCapture(quick:false) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return false }
    func applicationWillTerminate(_ notification: Notification) { hotkeys.pause() }
    private func setupMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        let quitItem = NSMenuItem(title:"退出夹心贴",action:#selector(quit),keyEquivalent:"q"); quitItem.target = self
        appMenu.addItem(quitItem); appItem.submenu = appMenu; mainMenu.addItem(appItem)
        let editItem = NSMenuItem(title:"编辑",action:nil,keyEquivalent:""); let editMenu = NSMenu(title:"编辑")
        for (title,action,key,flags) in [
            ("撤销","undo:","z",NSEvent.ModifierFlags.command),
            ("重做","redo:","y",.command),
            ("剪切","cut:","x",.command),("复制","copy:","c",.command),
            ("粘贴","paste:","v",.command),("全选","selectAll:","a",.command)
        ] {
            let item = NSMenuItem(title:title,action:Selector(action),keyEquivalent:key); item.keyEquivalentModifierMask = flags; editMenu.addItem(item)
        }
        editItem.submenu = editMenu; mainMenu.addItem(editItem); NSApp.mainMenu = mainMenu
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        if let button = statusItem.button {
            let icon = NSImage(systemSymbolName:"pin.square",accessibilityDescription:"夹心贴")
            icon?.isTemplate = true; button.image = icon; button.toolTip = "夹心贴 · 截图与贴图"
        }
        menu.delegate = self
        add("截图",#selector(captureFromMenu)); add("贴图",#selector(pasteImage)); add("隐藏 / 显示贴图",#selector(togglePins))
        menu.addItem(.separator())
        let recent = NSMenuItem(title:"最近截图",action:nil,keyEquivalent:""); recent.submenu = recentMenu; menu.addItem(recent)
        add("打开保存文件夹",#selector(openFolder)); menu.addItem(.separator())
        add("设置…",#selector(showSettings)); add("退出夹心贴",#selector(quit),key:"q")
        statusItem.menu = menu
    }
    private func add(_ title: String, _ selector: Selector, key: String = "") {
        let item = NSMenuItem(title:title,action:selector,keyEquivalent:key); item.target = self; menu.addItem(item)
    }
    func menuWillOpen(_ menu: NSMenu) {
        recentMenu.removeAllItems()
        do {
            for url in try store?.recent() ?? [] {
                let date = try url.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate ?? .now
                let formatter = DateFormatter(); formatter.dateFormat = "MM-dd HH:mm:ss"
                let item = NSMenuItem(title:formatter.string(from:date) + " · 点击贴图",action:#selector(pinRecent(_:)),keyEquivalent:"")
                item.target = self; item.representedObject = url
                if let image = NSImage(contentsOf:url) { image.size = NSSize(width:32,height:24); item.image = image }
                recentMenu.addItem(item)
            }
        } catch { showError(error) }
        if recentMenu.items.isEmpty { let item = NSMenuItem(title:"还没有截图",action:nil,keyEquivalent:""); item.isEnabled = false; recentMenu.addItem(item) }
        for (index, action) in [ShortcutAction.capture,.pin,.togglePins].enumerated() {
            let title = ["截图","贴图","隐藏 / 显示贴图"][index]
            menu.items[index].title = title + "    " + settings.shortcut(action).label
        }
    }
    private func resumeHotkeys() {
        guard !demo, overlays.isEmpty, !capturePending, preferences == nil else { return }
        hotkeyFailures = hotkeys.register(settings)
        statusItem?.button?.toolTip = hotkeyFailures.isEmpty ? "夹心贴 · 截图与贴图" : "夹心贴 · 有快捷键被占用，请打开设置"
    }
    @objc private func captureFromMenu() {
        DispatchQueue.main.asyncAfter(deadline:.now()+0.15) { self.startCapture(quick:false) }
    }
    private func startCapture(quick: Bool) {
        guard overlays.isEmpty, !capturePending else { return }
        if demo { startDemo(); return }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            let alert = NSAlert(); alert.messageText = "需要屏幕录制权限"
            alert.informativeText = "请在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”中允许夹心贴，然后重新打开应用。"; alert.addButton(withTitle:"打开系统设置"); alert.addButton(withTitle:"稍后")
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) }; return
        }
        capturePending = true; hotkeys.pause()
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
                var captured: [(NSScreen,CGImage)] = []
                let ownApp = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                // Capture every display before showing any editor, preserving each display's Retina scale.
                for screen in NSScreen.screens {
                    let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
                    guard let display = content.displays.first(where:{$0.displayID == number?.uint32Value}) else { continue }
                    let configuration = SCStreamConfiguration()
                    configuration.width = Int(screen.frame.width * screen.backingScaleFactor)
                    configuration.height = Int(screen.frame.height * screen.backingScaleFactor)
                    configuration.showsCursor = false; configuration.captureResolution = .best
                    let filter = SCContentFilter(display:display,excludingApplications:ownApp,exceptingWindows:[])
                    let image = try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:configuration)
                    captured.append((screen,image))
                }
                guard !captured.isEmpty else { throw AppError.message("没有找到可截图的显示器。") }
                capturePending = false; showOverlays(captured,quick:quick)
            } catch { capturePending = false; resumeHotkeys(); showError(error) }
        }
    }
    private func showOverlays(_ screens: [(NSScreen,CGImage)], quick: Bool) {
        hotkeys.pause()
        for (screen, image) in screens {
            let window = CaptureWindow(screen:screen,image:image,settings:settings,quick:quick)
            window.canvas.onCancel = { [weak self] in self?.closeOverlays() }
            window.canvas.onBeginSelection = { [weak self, weak window] in
                for other in self?.overlays ?? [] where other !== window { other.canvas.clearSelection() }
                window?.makeKeyAndOrderFront(nil)
            }
            window.canvas.onComplete = { [weak self] image, action in try self?.complete(image,action:action) }
            overlays.append(window)
        }
        NSApp.activate(ignoringOtherApps:true)
        for window in overlays { window.orderFrontRegardless() }
        let mouse = NSEvent.mouseLocation
        (overlays.first(where:{$0.frame.contains(mouse)}) ?? overlays.first)?.makeKeyAndOrderFront(nil)
    }
    private func closeOverlays() {
        for window in overlays { window.orderOut(nil); window.close() }; overlays.removeAll(); resumeHotkeys()
    }
    private func complete(_ image: NSImage, action: CaptureAction) throws {
        guard let store else { throw AppError.message("请先在设置中选择可写入的保存文件夹。") }
        let png = try ImageIO.png(image)
        try store.record(png:png,permanent:action == .save)
        if action == .copy { try ImageIO.copy(image) }
        lastImage = image; closeOverlays()
        if action == .pin { createPin(image) }
    }
    @objc private func pasteImage() {
        guard overlays.isEmpty, !capturePending else { return }
        if let image = NSImage(pasteboard:NSPasteboard.general) { createPin(image); return }
        if let lastImage { createPin(lastImage); return }
        do {
            if let url = try store?.recent().first, let image = NSImage(contentsOf:url) { createPin(image) }
            else { throw AppError.message("先截图并复制，或复制一张图片，再使用贴图。") }
        } catch { showError(error) }
    }
    private func createPin(_ image: NSImage) {
        let window = PinWindow(image:image,settings:settings)
        window.onClose = { [weak self, weak window] in self?.pins.removeAll(where:{$0 === window}) }
        window.onSave = { [weak self] image in
            guard let store = self?.store else { throw AppError.message("保存目录不可用。") }
            try store.record(png:ImageIO.png(image),permanent:true)
        }
        if hiddenPins { for pin in pins { pin.orderFrontRegardless() }; hiddenPins = false }
        pins.append(window); window.makeKeyAndOrderFront(nil)
    }
    @objc private func pinRecent(_ item: NSMenuItem) {
        guard let url = item.representedObject as? URL, let image = NSImage(contentsOf:url) else { return }; createPin(image)
    }
    @objc private func togglePins() {
        hiddenPins.toggle(); for pin in pins { if hiddenPins { pin.orderOut(nil) } else { pin.orderFrontRegardless() } }
    }
    @objc private func openFolder() {
        if let store { NSWorkspace.shared.open(store.root) } else { showSettings() }
    }
    @objc private func showSettings() {
        guard overlays.isEmpty, !capturePending else { return }
        if let preferences { preferences.showWindow(nil); NSApp.activate(ignoringOtherApps:true); return }
        hotkeys.pause()
        let controller = SettingsWindowController(settings:settings,hotkeyStatus:hotkeyFailures); preferences = controller
        controller.onSave = { [weak self] candidate in
            guard let self else { return }
            let failures = demo ? [] : hotkeys.register(candidate); hotkeys.pause()
            guard failures.isEmpty else { throw AppError.message("快捷键被占用：\n" + failures.joined(separator:"\n")) }
            let newStore = try ShotStore(directory:candidate.saveDirectory); try newStore.trim()
            try settingsStore.save(candidate); settings = candidate; store = newStore
        }
        controller.onDismiss = { [weak self] in self?.preferences = nil; self?.resumeHotkeys() }
        controller.showWindow(nil); NSApp.activate(ignoringOtherApps:true)
    }
    @objc private func quit() { NSApp.terminate(nil) }
    private func startDemo() {
        guard overlays.isEmpty, let screen = NSScreen.main else { return }
        let size = screen.frame.size, image = NSImage(size:size)
        image.lockFocus()
        NSColor(calibratedRed:0.94,green:0.93,blue:0.98,alpha:1).setFill(); NSRect(origin:.zero,size:size).fill()
        let card = NSRect(x:size.width*0.18,y:size.height*0.25,width:size.width*0.64,height:size.height*0.5)
        NSColor.white.setFill(); NSBezierPath(roundedRect:card,xRadius:24,yRadius:24).fill()
        ("留住这一刻的灵感" as NSString).draw(at:NSPoint(x:card.minX+48,y:card.maxY-110),withAttributes:[.font:NSFont.systemFont(ofSize:36,weight:.semibold),.foregroundColor:NSColor(calibratedWhite:0.16,alpha:1)])
        ("夹心贴 for Mac\n截图 · 标注 · 桌面贴图" as NSString).draw(at:NSPoint(x:card.minX+50,y:card.midY-30),withAttributes:[.font:NSFont.systemFont(ofSize:20),.foregroundColor:NSColor(calibratedWhite:0.4,alpha:1)])
        if let logo = NSImage(contentsOf:Bundle.main.resourceURL!.appendingPathComponent("logo.png")) { logo.draw(in:NSRect(x:card.maxX-220,y:card.minY+28,width:160,height:160)) }
        image.unlockFocus()
        if let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil) {
            showOverlays([(screen,cg)],quick:false); overlays.first?.canvas.setDemoSelection(card.insetBy(dx:-12,dy:-12))
        }
    }
    private func showError(_ error: Error) {
        NSApp.activate(ignoringOtherApps:true)
        let alert = NSAlert(); alert.messageText = "夹心贴 · 操作未完成"; alert.informativeText = error.localizedDescription; alert.runModal()
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = AppDelegate()
application.delegate = delegate
application.run()
