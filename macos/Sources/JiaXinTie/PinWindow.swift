import AppKit
import JiaXinTieCore

final class PinWindow: NSPanel, NSWindowDelegate {
    let image: NSImage
    let settings: Settings
    private var zoom: CGFloat = 1
    var onClose: (() -> Void)?
    var onSave: ((NSImage) throws -> Void)?
    init(image: NSImage, settings: Settings) {
        self.image = image; self.settings = settings
        let screen = NSScreen.screens.first(where:{$0.frame.contains(NSEvent.mouseLocation)}) ?? NSScreen.main!
        let area = screen.visibleFrame
        let initial = min(1,area.width*0.7/max(image.size.width,1),area.height*0.7/max(image.size.height,1))
        zoom = initial
        let size = NSSize(width:max(16,image.size.width*initial),height:max(16,image.size.height*initial))
        super.init(contentRect:NSRect(origin:CGPoint(x:area.midX-size.width/2,y:area.midY-size.height/2),size:size),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        title = "夹心贴 · 桌面贴图"; isReleasedWhenClosed = false; level = .floating; hasShadow = true
        isOpaque = false; backgroundColor = .clear; hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]; delegate = self
        let view = PinView(frame:NSRect(origin:.zero,size:size)); contentView = view; makeFirstResponder(view)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    func windowWillClose(_ notification: Notification) { onClose?() }
    func windowDidBecomeKey(_ notification: Notification) { contentView?.needsDisplay = true }
    func windowDidResignKey(_ notification: Notification) { contentView?.needsDisplay = true }
    func scale(by factor: CGFloat, anchor: CGPoint) {
        let next = max(0.05,min(8,zoom*factor))
        let size = CGSize(width:max(16,min(16000,image.size.width*next)),height:max(16,min(16000,image.size.height*next)))
        let origin = CGPoint(x:frame.minX+anchor.x-(anchor.x/frame.width)*size.width,y:frame.minY+anchor.y-(anchor.y/frame.height)*size.height)
        zoom = next; setFrame(CGRect(origin:origin,size:size),display:true)
    }
    @objc func resetZoom() { scale(by:1/zoom,anchor:CGPoint(x:frame.width/2,y:frame.height/2)) }
    @objc func copyImage() { do { try ImageIO.copy(image) } catch { showError(error) } }
    @objc func saveImage() { do { try onSave?(image) } catch { showError(error) } }
    @objc func deletePin() { close() }
    private func showError(_ error: Error) { let alert = NSAlert(); alert.messageText = "贴图操作未完成"; alert.informativeText = error.localizedDescription; alert.beginSheetModal(for:self) }
}

final class PinView: NSView {
    private var pin: PinWindow? { window as? PinWindow }
    override var acceptsFirstResponder: Bool { true }
    @objc func copy(_ sender: Any?) { pin?.copyImage() }
    override func draw(_ dirtyRect: NSRect) {
        guard let pin else { return }
        NSGraphicsContext.current?.imageInterpolation = .high
        pin.image.draw(in:bounds,from:.zero,operation:.sourceOver,fraction:1)
        if pin.isKeyWindow { NSColor.controlAccentColor.setStroke(); let border = NSBezierPath(rect:bounds.insetBy(dx:0.5,dy:0.5)); border.lineWidth = 1; border.stroke() }
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey(); window?.makeFirstResponder(self)
        if event.clickCount == 2 { pin?.resetZoom() } else { window?.performDrag(with:event) }
    }
    override func scrollWheel(with event: NSEvent) {
        guard let pin else { return }
        if !event.modifierFlags.intersection([.control,.command]).isEmpty { pin.alphaValue = max(0.15,min(1,pin.alphaValue+event.scrollingDeltaY*0.015)) }
        else {
            let delta = max(-20,min(20,event.scrollingDeltaY))
            pin.scale(by:exp(delta*(event.hasPreciseScrollingDeltas ? 0.012 : 0.08)),anchor:convert(event.locationInWindow,from:nil))
        }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let pin else { return nil }
        let menu = NSMenu()
        for (title,selector) in [("复制",#selector(PinWindow.copyImage)),("保存",#selector(PinWindow.saveImage)),("原始大小",#selector(PinWindow.resetZoom)),("删除贴图",#selector(PinWindow.deletePin))] {
            let item = NSMenuItem(title:title,action:selector,keyEquivalent:""); item.target = pin; menu.addItem(item)
        }; return menu
    }
    override func keyDown(with event: NSEvent) {
        guard let pin else { return }
        let settings = pin.settings
        if settings.shortcut(.cancel).matches(event) || event.keyCode == 53 { pin.deletePin() }
        else if settings.shortcut(.copy).matches(event) || Shortcut(8,.command).matches(event) { pin.copyImage() }
        else if settings.shortcut(.save).matches(event) { pin.saveImage() }
        else if settings.shortcut(.resetZoom).matches(event) { pin.resetZoom() }
        else { super.keyDown(with:event) }
    }
}
