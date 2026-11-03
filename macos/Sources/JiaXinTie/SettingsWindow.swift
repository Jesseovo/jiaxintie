import AppKit
import JiaXinTieCore

final class ShortcutRecorder: NSButton {
    var onChange: ((Shortcut,Shortcut) -> Void)?
    var shortcut: Shortcut { didSet { title = shortcut.label; onChange?(oldValue,shortcut) } }
    init(shortcut: Shortcut) {
        self.shortcut = shortcut; super.init(frame: .zero)
        title = shortcut.label; bezelStyle = .rounded; font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        setButtonType(.momentaryPushIn); widthAnchor.constraint(equalToConstant: 150).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override func becomeFirstResponder() -> Bool { title = "按下快捷键…"; return true }
    override func resignFirstResponder() -> Bool { title = shortcut.label; return true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 { window?.selectNextKeyView(self); return }
        let candidate = Shortcut(event: event)
        if candidate.isUsable { shortcut = candidate; window?.makeFirstResponder(nil) } else { NSSound.beep() }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event); return true
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let folder = NSTextField()
    private var recorders: [ShortcutAction: ShortcutRecorder] = [:]
    private let status = NSTextField(wrappingLabelWithString: "")
    private let root = NSStackView()
    private let extraKeys = NSStackView()
    private let summary = NSTextField(wrappingLabelWithString: "")
    private let current: Settings
    var onSave: ((Settings) throws -> Void)?
    var onDismiss: (() -> Void)?
    init(settings: Settings, hotkeyStatus: [String]) {
        current = settings
        let window = NSWindow(contentRect: NSRect(x:0,y:0,width:560,height:640), styleMask: [.titled,.closable,.miniaturizable], backing: .buffered, defer: false)
        window.title = "夹心贴 · 设置"; window.isReleasedWhenClosed = false
        super.init(window: window); window.delegate = self
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant:28), root.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-28), root.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:24)])
        let title = NSTextField(labelWithString: "夹心贴"); title.font = .systemFont(ofSize:26,weight:.semibold)
        let heading = NSStackView(); heading.orientation = .horizontal; heading.spacing = 14
        if let icon = NSImage(named: NSImage.Name("AppIcon")) {
            let view = NSImageView(image:icon); view.widthAnchor.constraint(equalToConstant:48).isActive = true; view.heightAnchor.constraint(equalToConstant:48).isActive = true; heading.addArrangedSubview(view)
        }
        heading.addArrangedSubview(title); root.addArrangedSubview(heading)
        root.addArrangedSubview(NSTextField(labelWithString:"保存位置"))
        folder.stringValue = settings.saveDirectory; folder.setAccessibilityLabel("截图保存文件夹")
        let browse = NSButton(title:"选择…",target:self,action:#selector(chooseFolder))
        let directoryRow = NSStackView(views:[folder,browse]); directoryRow.orientation = .horizontal
        directoryRow.widthAnchor.constraint(equalToConstant:504).isActive = true; folder.setContentHuggingPriority(.defaultLow,for:.horizontal)
        root.addArrangedSubview(directoryRow)
        let hint = NSTextField(wrappingLabelWithString:"保存操作写入此文件夹；“缓存”中仅保留最近 3 张。")
        hint.font = .systemFont(ofSize:12); hint.textColor = .secondaryLabelColor; root.addArrangedSubview(hint)
        root.addArrangedSubview(NSTextField(labelWithString:"常用快捷键"))
        extraKeys.orientation = .vertical; extraKeys.alignment = .leading; extraKeys.spacing = 12
        let common: [ShortcutAction] = [.capture,.pin,.save]
        for action in common + ShortcutAction.allCases.filter({ !common.contains($0) }) {
            let label = NSTextField(labelWithString: action.title)
            let recorder = ShortcutRecorder(shortcut:settings.shortcut(action)); recorder.setAccessibilityLabel(action.title + "快捷键"); recorders[action] = recorder
            let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow,for:.horizontal)
            let row = NSStackView(views:[label,spacer,recorder]); row.orientation = .horizontal
            row.widthAnchor.constraint(equalToConstant:504).isActive = true
            if common.contains(action) { root.addArrangedSubview(row) } else { extraKeys.addArrangedSubview(row) }
        }
        recorders[.capture]?.onChange = { [weak self] old, new in
            if self?.recorders[.copy]?.shortcut == old { self?.recorders[.copy]?.shortcut = new }
            self?.updateSummary()
        }
        for action in [ShortcutAction.pin,.save,.copy] { recorders[action]?.onChange = { [weak self] _,_ in self?.updateSummary() } }
        summary.font = .systemFont(ofSize:12); summary.textColor = .secondaryLabelColor; summary.preferredMaxLayoutWidth = 504
        updateSummary(); root.addArrangedSubview(summary)
        let more = NSButton(title:"更多快捷键",target:self,action:#selector(toggleExtraKeys(_:)))
        more.setButtonType(.onOff); more.bezelStyle = .inline; more.isBordered = false
        more.title = "更多快捷键 ▸"; more.setAccessibilityLabel("展开或收起更多快捷键")
        root.addArrangedSubview(more); root.addArrangedSubview(extraKeys); extraKeys.isHidden = true
        status.stringValue = hotkeyStatus.isEmpty ? "点击按键框后按下新快捷键。输入标注文字时，快捷键暂停。" : "快捷键注册失败：\n" + hotkeyStatus.joined(separator:"\n")
        status.font = .systemFont(ofSize:12); status.textColor = hotkeyStatus.isEmpty ? .secondaryLabelColor : .systemRed
        status.preferredMaxLayoutWidth = 504; root.addArrangedSubview(status)
        let permission = NSButton(title: "屏幕录制权限…", target:self, action:#selector(openPermissions))
        let reset = NSButton(title:"恢复默认按键",target:self,action:#selector(resetShortcuts))
        let save = NSButton(title:"保存",target:self,action:#selector(saveSettings)); save.bezelStyle = .rounded; save.keyEquivalent = "\r"
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow,for:.horizontal)
        let buttons = NSStackView(views:[permission,reset,spacer,save]); buttons.orientation = .horizontal
        buttons.widthAnchor.constraint(equalToConstant:504).isActive = true; root.addArrangedSubview(buttons)
        window.contentView!.layoutSubtreeIfNeeded()
        resizeToFit()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = "选择保存文件夹"; panel.directoryURL = URL(fileURLWithPath:folder.stringValue)
        panel.beginSheetModal(for:window!) { response in if response == .OK, let url = panel.url { self.folder.stringValue = url.path } }
    }
    @objc private func resetShortcuts() { for (action, recorder) in recorders { recorder.shortcut = Settings().shortcut(action) } }
    private func updateSummary() {
        let copy = recorders[.copy]?.shortcut.label ?? "F1", pin = recorders[.pin]?.shortcut.label ?? "F3", save = recorders[.save]?.shortcut.label ?? "S"
        summary.stringValue = "框选后按 \(copy) 复制，\(pin) 贴图，\(save) 保存；Esc 取消。\nF 键默认控制亮度、音量时，配合 Fn 使用。"
    }
    @objc private func toggleExtraKeys(_ sender: NSButton) {
        extraKeys.isHidden = sender.state != .on
        sender.title = extraKeys.isHidden ? "更多快捷键 ▸" : "收起更多快捷键 ▾"
        resizeToFit()
    }
    private func resizeToFit() {
        window?.contentView?.layoutSubtreeIfNeeded()
        window?.setContentSize(NSSize(width:560,height:root.fittingSize.height+48)); window?.center()
    }
    @objc private func openPermissions() {
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
    @objc private func saveSettings() {
        do {
            var candidate = current; candidate.saveDirectory = folder.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
            candidate.shortcuts = Dictionary(uniqueKeysWithValues: recorders.map { ($0.key.rawValue,$0.value.shortcut) }); candidate.hasCompletedSetup = true
            try candidate.validate(); try ShotStore.validateWritable(candidate.saveDirectory); try onSave?(candidate); close()
        } catch { status.stringValue = error.localizedDescription; status.textColor = .systemRed }
    }
    func windowWillClose(_ notification: Notification) { onDismiss?() }
}
