import AppKit
import JiaXinTieCore

final class CaptureWindow: NSWindow {
    let canvas: CaptureCanvas
    init(screen: NSScreen, image: CGImage, settings: Settings, quick: Bool) {
        canvas = CaptureCanvas(image:image,size:screen.frame.size,settings:settings,quick:quick)
        // Call NSWindow's designated initializer. Its screen convenience initializer
        // redispatches to init(contentRect:styleMask:backing:defer:) on this subclass.
        super.init(contentRect:screen.frame,styleMask:.borderless,backing:.buffered,defer:false)
        setFrame(screen.frame,display:false); title = "夹心贴 · 截图编辑器"
        isReleasedWhenClosed = false; level = .screenSaver; isOpaque = true; hasShadow = false
        collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.stationary]
        contentView = canvas; makeFirstResponder(canvas)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class ActionButton: NSButton {
    private let handler: () -> Void
    init(symbol: String, title: String, handler: @escaping () -> Void) {
        self.handler = handler; super.init(frame:.zero)
        image = NSImage(systemSymbolName:symbol,accessibilityDescription:title)
        imagePosition = .imageOnly; toolTip = title; setAccessibilityLabel(title)
        bezelStyle = .regularSquare; isBordered = false; wantsLayer = true; layer?.cornerRadius = 5
        target = self; action = #selector(runAction)
        widthAnchor.constraint(equalToConstant:30).isActive = true; heightAnchor.constraint(equalToConstant:28).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func runAction() { handler() }
    func select(_ selected: Bool) { layer?.backgroundColor = (selected ? NSColor.controlAccentColor.withAlphaComponent(0.18) : .clear).cgColor; contentTintColor = selected ? .controlAccentColor : .labelColor }
}

final class CaptureCanvas: NSView, NSTextFieldDelegate {
    private let source: CGImage
    private let backdrop: NSImage
    private let settings: Settings
    private let quick: Bool
    private var selection = CGRect.zero
    private var history = AnnotationHistory()
    private var current: Mark?
    private var tool: DrawTool = .move
    private var color = NSColor.systemPink
    private var lineWidth: CGFloat = 3
    private var origin = CGPoint.zero
    private enum Drag { case none, select, move(CGRect), resize(Int,CGRect), draw, erase }
    private var drag: Drag = .none
    private let toolbar = NSStackView()
    private var tools: [DrawTool:ActionButton] = [:]
    private var undoButton: ActionButton!
    private var redoButton: ActionButton!
    private var textInput: NSTextField?
    private var textAnchor = CGPoint.zero
    private var pixelated: NSImage?
    var onComplete: ((NSImage,CaptureAction) throws -> Void)?
    var onCancel: (() -> Void)?
    var onBeginSelection: (() -> Void)?
    init(image: CGImage, size: CGSize, settings: Settings, quick: Bool) {
        source = image; backdrop = NSImage(cgImage:image,size:size); self.settings = settings; self.quick = quick
        super.init(frame:CGRect(origin:.zero,size:size)); buildToolbar(); setAccessibilityLabel("截图选区与标注画布")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds,cursor:.crosshair) }
    private func buildToolbar() {
        toolbar.orientation = .vertical; toolbar.alignment = .leading; toolbar.spacing = 5
        toolbar.edgeInsets = NSEdgeInsets(top:7,left:8,bottom:7,right:8)
        toolbar.wantsLayer = true; toolbar.layer?.backgroundColor = NSColor.white.cgColor; toolbar.layer?.cornerRadius = 9
        toolbar.layer?.borderWidth = 1; toolbar.layer?.borderColor = NSColor(calibratedWhite:0.78,alpha:1).cgColor
        toolbar.appearance = NSAppearance(named:.aqua)
        let row = NSStackView(); row.orientation = .horizontal; row.spacing = 3
        for tool in DrawTool.allCases where tool != .move {
            let button = ActionButton(symbol:tool.symbol,title:tool.title) { [weak self] in self?.choose(tool) }
            tools[tool] = button; row.addArrangedSubview(button)
        }
        func divider() { let line = NSBox(); line.boxType = .separator; line.widthAnchor.constraint(equalToConstant:1).isActive = true; line.heightAnchor.constraint(equalToConstant:22).isActive = true; row.addArrangedSubview(line) }
        divider()
        undoButton = ActionButton(symbol:"arrow.uturn.backward",title:"撤销 · \(settings.shortcut(.undo).label)") { [weak self] in self?.undo() }
        redoButton = ActionButton(symbol:"arrow.uturn.forward",title:"重做 · \(settings.shortcut(.redo).label)") { [weak self] in self?.redo() }
        row.addArrangedSubview(undoButton); row.addArrangedSubview(redoButton); divider()
        for (symbol,title,action) in [("square.and.arrow.down","保存 · \(settings.shortcut(.save).label)",CaptureAction.save),("pin","贴图 · \(settings.shortcut(.pin).label)",.pin)] {
            row.addArrangedSubview(ActionButton(symbol:symbol,title:title) { [weak self] in self?.finish(action) })
        }
        row.addArrangedSubview(ActionButton(symbol:"xmark",title:"取消 · \(settings.shortcut(.cancel).label)") { [weak self] in self?.onCancel?() })
        row.addArrangedSubview(ActionButton(symbol:"checkmark",title:"复制 · \(settings.shortcut(.copy).label) / ⌘C") { [weak self] in self?.finish(.copy) })
        toolbar.addArrangedSubview(row)
        let options = NSStackView(); options.orientation = .horizontal; options.spacing = 7
        for (index,value) in [NSColor.systemPink,.systemRed,.systemOrange,.systemYellow,.systemGreen,.systemBlue,.black,.white].enumerated() {
            let swatch = NSButton(title:"",target:self,action:#selector(pickColor(_:))); swatch.tag = index
            swatch.bezelStyle = .circular; swatch.wantsLayer = true; swatch.isBordered = false
            swatch.layer?.backgroundColor = value.cgColor; swatch.layer?.cornerRadius = 8; swatch.layer?.borderWidth = 1; swatch.layer?.borderColor = NSColor.lightGray.cgColor
            swatch.widthAnchor.constraint(equalToConstant:17).isActive = true; swatch.heightAnchor.constraint(equalToConstant:17).isActive = true
            swatch.setAccessibilityLabel(["粉色","红色","橙色","黄色","绿色","蓝色","黑色","白色"][index]); options.addArrangedSubview(swatch)
        }
        let width = NSPopUpButton(frame:.zero,pullsDown:false); width.addItems(withTitles:["2 pt","3 pt","5 pt","8 pt"]); width.selectItem(at:1)
        width.target = self; width.action = #selector(pickWidth(_:)); width.setAccessibilityLabel("标注粗细"); options.addArrangedSubview(width)
        toolbar.addArrangedSubview(options); addSubview(toolbar); toolbar.isHidden = true
    }
    private func choose(_ next: DrawTool) {
        commitText(); tool = tool == next ? .move : next
        if tool == .mosaic { prepareMosaic() }
        for (key,button) in tools { button.select(key == tool) }; window?.makeFirstResponder(self)
    }
    @objc private func pickColor(_ sender: NSButton) {
        color = [NSColor.systemPink,.systemRed,.systemOrange,.systemYellow,.systemGreen,.systemBlue,.black,.white][sender.tag]
        textInput?.textColor = color; window?.makeFirstResponder(textInput ?? self)
    }
    @objc private func pickWidth(_ sender: NSPopUpButton) { lineWidth = [2,3,5,8][sender.indexOfSelectedItem]; window?.makeFirstResponder(textInput ?? self) }
    private func updateToolbar() {
        toolbar.isHidden = quick || selection.width < 2 || selection.height < 2
        guard !toolbar.isHidden else { return }
        toolbar.layoutSubtreeIfNeeded(); let size = toolbar.fittingSize
        let x = min(max(8,selection.maxX-size.width),max(8,bounds.width-size.width-8))
        var y = selection.minY-size.height-10
        if y < 8 { y = min(bounds.height-size.height-8,selection.maxY+10) }
        toolbar.frame = CGRect(x:x,y:max(8,y),width:size.width,height:size.height)
        undoButton.isEnabled = history.canUndo; redoButton.isEnabled = history.canRedo
    }
    func clearSelection() { textInput?.removeFromSuperview(); textInput = nil; selection = .zero; history.clear(); current = nil; pixelated = nil; toolbar.isHidden = true; needsDisplay = true }
    func setDemoSelection(_ rect: CGRect) { selection = rect.intersection(bounds); updateToolbar(); needsDisplay = true }
    private func local(_ point: CGPoint) -> CGPoint { CGPoint(x:point.x-selection.minX,y:point.y-selection.minY) }
    private func clamped(_ point: CGPoint) -> CGPoint { CGPoint(x:max(0,min(bounds.width,point.x)),y:max(0,min(bounds.height,point.y))) }
    private func handles() -> [Int:CGPoint] {
        var result: [Int:CGPoint] = [:]
        for row in 0...2 { for col in 0...2 where row != 1 || col != 1 { result[row*3+col] = CGPoint(x:[selection.minX,selection.midX,selection.maxX][col],y:[selection.minY,selection.midY,selection.maxY][row]) } }; return result
    }
    override func mouseDown(with event: NSEvent) {
        commitText(); window?.makeFirstResponder(self)
        origin = clamped(convert(event.locationInWindow,from:nil))
        if tool == .move, history.marks.isEmpty, selection.width > 1, let handle = handles().first(where:{hypot($0.value.x-origin.x,$0.value.y-origin.y) <= 8}) {
            drag = .resize(handle.key,selection); toolbar.isHidden = true; return
        }
        guard selection.contains(origin) else {
            onBeginSelection?(); clearSelection(); selection = CGRect(origin:origin,size:.zero); drag = .select; return
        }
        switch tool {
        case .move: drag = .move(selection); toolbar.isHidden = true
        case .text: beginText(at:origin); drag = .none
        case .eraser: drag = .erase; erase(at:origin)
        default: current = Mark(tool:tool,start:local(origin),color:color,width:lineWidth); drag = .draw
        }
    }
    override func mouseDragged(with event: NSEvent) {
        let point = clamped(convert(event.locationInWindow,from:nil))
        switch drag {
        case .select: selection = normalizedRect(origin,point).intersection(bounds); needsDisplay = true
        case .move(let initial):
            selection.origin = CGPoint(x:max(0,min(bounds.width-initial.width,initial.minX+point.x-origin.x)),y:max(0,min(bounds.height-initial.height,initial.minY+point.y-origin.y)))
            pixelated = nil; needsDisplay = true
        case .resize(let handle,let initial):
            let col = handle%3, row = handle/3
            let a = CGPoint(x:col == 0 ? point.x : initial.minX,y:row == 0 ? point.y : initial.minY)
            let b = CGPoint(x:col == 2 ? point.x : initial.maxX,y:row == 2 ? point.y : initial.maxY)
            selection = normalizedRect(a,b).intersection(bounds); pixelated = nil; needsDisplay = true
        case .draw:
            let previous = current?.visualBounds ?? .zero
            if tool == .pen || tool == .highlighter { current?.points.append(local(point)) } else if current != nil { current!.points[1] = local(point) }
            let dirty = previous.union(current?.visualBounds ?? .zero).offsetBy(dx:selection.minX,dy:selection.minY)
            setNeedsDisplay(dirty.intersection(selection))
        case .erase: erase(at:point)
        case .none: break
        }
    }
    override func mouseUp(with event: NSEvent) {
        if case .draw = drag, let mark = current { history.append(mark); current = nil }
        drag = .none; updateToolbar(); needsDisplay = true
        if quick, selection.width >= 2, selection.height >= 2 { finish(.copy) }
    }
    override func rightMouseDown(with event: NSEvent) {
        if textInput != nil { commitText(); return }
        if tool == .move { onCancel?() } else { choose(tool) }
    }
    private func erase(at point: CGPoint) { if history.erase(at:local(point)) { needsDisplay = true; updateToolbar() } }
    private func undo() { commitText(); history.undo(); needsDisplay = true; updateToolbar(); window?.makeFirstResponder(self) }
    private func redo() { commitText(); history.redo(); needsDisplay = true; updateToolbar(); window?.makeFirstResponder(self) }
    @objc func copy(_ sender: Any?) { guard textInput == nil else { return }; finish(.copy) }
    @objc func undo(_ sender: Any?) { guard textInput == nil else { return }; undo() }
    @objc func redo(_ sender: Any?) { guard textInput == nil else { return }; redo() }
    private func prepareMosaic() {
        guard pixelated == nil, let crop = try? ImageRenderer.crop(source,screenSize:bounds.size,selection:selection) else { return }
        pixelated = ImageRenderer.mosaic(crop,size:selection.size)
    }
    override func draw(_ dirtyRect: NSRect) {
        backdrop.draw(in:bounds); NSColor.black.withAlphaComponent(0.42).setFill(); bounds.fill()
        guard selection.width > 0, selection.height > 0 else {
            let hint = "拖动鼠标框选截图区域 · Esc 取消" as NSString
            hint.draw(at:CGPoint(x:bounds.midX-145,y:bounds.midY),withAttributes:[.font:NSFont.systemFont(ofSize:16,weight:.medium),.foregroundColor:NSColor.white]); return
        }
        NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect:selection).addClip(); backdrop.draw(in:bounds)
        let translation = AffineTransform(translationByX:selection.minX,byY:selection.minY); (translation as NSAffineTransform).concat()
        if history.marks.contains(where:{$0.tool == .mosaic}) || current?.tool == .mosaic { prepareMosaic() }
        for mark in history.marks { mark.draw(mosaic:pixelated) }; current?.draw(mosaic:pixelated)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.controlAccentColor.setStroke(); let outline = NSBezierPath(rect:selection); outline.lineWidth = 1; outline.stroke()
        if history.marks.isEmpty, tool == .move {
            for point in handles().values { NSColor.white.setFill(); NSRect(x:point.x-3,y:point.y-3,width:6,height:6).fill(); NSColor.controlAccentColor.setStroke(); NSBezierPath(rect:NSRect(x:point.x-3,y:point.y-3,width:6,height:6)).stroke() }
        }
        let pixels = ImageRenderer.pixelRect(selection:selection,screenSize:bounds.size,pixels:CGSize(width:source.width,height:source.height))
        let label = "\(Int(pixels.width)) × \(Int(pixels.height))" as NSString
        let attributes: [NSAttributedString.Key:Any] = [.font:NSFont.monospacedDigitSystemFont(ofSize:12,weight:.medium),.foregroundColor:NSColor.white,.backgroundColor:NSColor.black.withAlphaComponent(0.7)]
        label.draw(at:CGPoint(x:selection.minX+4,y:min(bounds.maxY-22,selection.maxY+6)),withAttributes:attributes)
    }
    private func beginText(at point: CGPoint) {
        let width = min(260,selection.width), height = min(32,selection.height)
        guard width > 20, height > 15 else { return }
        let x = min(point.x,selection.maxX-width), y = min(point.y,selection.maxY-height)
        let field = NSTextField(frame:CGRect(x:x,y:y,width:width,height:height))
        field.identifier = NSUserInterfaceItemIdentifier("annotation-text-input")
        field.font = .systemFont(ofSize:max(18,lineWidth*5),weight:.medium); field.textColor = color
        field.backgroundColor = .white; field.focusRingType = .none; field.delegate = self; field.setAccessibilityLabel("标注文字")
        textAnchor = local(field.frame.origin); textInput = field; addSubview(field); window?.makeFirstResponder(field)
    }
    private func commitText() {
        guard let field = textInput else { return }
        // Read the active field editor: older macOS versions do not synchronize
        // NSTextField.stringValue until editing ends, and endEditing can discard it.
        let editor = field.currentEditor() as? NSTextView
        editor?.unmarkText()
        let text = editor?.string ?? field.stringValue
        window?.endEditing(for:field)
        if !text.isEmpty { history.append(Mark(tool:.text,start:textAnchor,color:color,width:lineWidth,text:text)) }
        field.removeFromSuperview(); textInput = nil; window?.makeFirstResponder(self); needsDisplay = true; updateToolbar()
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)), !textView.hasMarkedText() { commitText(); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)), !textView.hasMarkedText() { textInput?.removeFromSuperview(); textInput = nil; window?.makeFirstResponder(self); return true }
        return false
    }
    override func keyDown(with event: NSEvent) {
        guard textInput == nil else { return }
        func matches(_ action: ShortcutAction) -> Bool { settings.shortcut(action).matches(event) }
        if matches(.cancel) || event.keyCode == 53 { onCancel?() }
        else if matches(.undo) { undo() }
        else if matches(.redo) { redo() }
        else if matches(.save) { finish(.save) }
        else if matches(.pin) { finish(.pin) }
        else if matches(.copy) || matches(.capture) || Shortcut(36).matches(event) || Shortcut(8,.command).matches(event) { finish(.copy) }
        else { super.keyDown(with:event) }
    }
    private func finish(_ action: CaptureAction) {
        commitText()
        guard selection.width >= 2, selection.height >= 2 else { NSSound.beep(); return }
        do { let image = try ImageRenderer.render(source,screenSize:bounds.size,selection:selection,marks:history.marks); try onComplete?(image,action) }
        catch { let alert = NSAlert(); alert.messageText = "截图尚未完成"; alert.informativeText = error.localizedDescription; alert.beginSheetModal(for:window!) }
    }
}
