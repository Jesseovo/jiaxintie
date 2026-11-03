import AppKit
import JiaXinTieCore

// Exercise invisible native views with fixture pixels. No screen capture, clipboard,
// global input injection, or user settings are involved in this test mode.
enum AppSmokeTest {
    static func run() throws {
        guard let screen = NSScreen.main else { throw AppError.message("No display available") }
        let size = screen.frame.size
        let context = CGContext(data:nil,width:Int(size.width),height:Int(size.height),bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray:0.95,alpha:1)); context.fill(CGRect(origin:.zero,size:size))
        let cg = context.makeImage()!, settings = Settings()
        let editor = CaptureWindow(screen:screen,image:cg,settings:settings,quick:false)
        let canvas = editor.canvas
        let sample = NSImage(cgImage:cg,size:NSSize(width:100,height:80))
        let pin = PinWindow(image:sample,settings:settings)
        let preferences = SettingsWindowController(settings:settings,hotkeyStatus:[])
        defer { editor.close(); pin.close(); preferences.close() }
        func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw AppError.message(message) }
            print("PASS: \(message)")
        }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func button(_ title: String) throws -> NSButton {
            guard let result = descendants(canvas).compactMap({$0 as? NSButton}).first(where:{$0.toolTip?.hasPrefix(title) == true}) else { throw AppError.message("Missing toolbar button: \(title)") }
            return result
        }
        func key(_ code: UInt16, _ modifiers: NSEvent.ModifierFlags = []) {
            canvas.keyDown(with:NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:modifiers,timestamp:0,windowNumber:editor.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:code)!)
        }
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with:type,location:canvas.convert(point,to:nil),modifierFlags:[],timestamp:0,windowNumber:editor.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
        }
        var outputs: [Data] = [], actions: [CaptureAction] = []
        canvas.onComplete = { image,action in outputs.append(try ImageIO.png(image)); actions.append(action) }
        try require(editor.canBecomeKey && pin.canBecomeKey && preferences.window != nil,"native windows initialize")
        canvas.setDemoSelection(CGRect(x:40,y:40,width:320,height:200))
        key(1) // S saves the selected fixture without needing a modifier.
        try require(outputs.count == 1 && actions.last == .save,"S exports selected pixels")
        let baseline = outputs.last!
        let decoded = NSBitmapImageRep(data:baseline)!
        try require(decoded.pixelsWide == 320 && decoded.pixelsHigh == 200,"editor exports exact selection dimensions")
        try button("矩形").performClick(nil)
        canvas.mouseDown(with:mouse(.leftMouseDown,CGPoint(x:80,y:80)))
        canvas.mouseDragged(with:mouse(.leftMouseDragged,CGPoint(x:200,y:160)))
        canvas.mouseUp(with:mouse(.leftMouseUp,CGPoint(x:200,y:160)))
        key(1); let annotated = outputs.last!
        try require(annotated != baseline,"drawing changes exported pixels")
        key(6,.command); key(1)
        try require(outputs.last == baseline,"Command-Z restores fixture pixels")
        key(16,.command); key(1)
        try require(outputs.last == annotated,"Command-Y restores annotation")
        try button("橡皮擦").performClick(nil)
        canvas.mouseDown(with:mouse(.leftMouseDown,CGPoint(x:80,y:120)))
        canvas.mouseUp(with:mouse(.leftMouseUp,CGPoint(x:80,y:120)))
        key(1); try require(outputs.last == baseline,"eraser removes the hit annotation")
        key(6,.command); key(1)
        try require(outputs.last == annotated,"erasing can be undone")
        try button("文字").performClick(nil)
        canvas.mouseDown(with:mouse(.leftMouseDown,CGPoint(x:100,y:100)))
        guard let field = descendants(canvas).compactMap({$0 as? NSTextField}).first(where:{$0.identifier?.rawValue == "annotation-text-input"}) else { throw AppError.message("Text input did not open") }
        let fieldEditor = field.currentEditor() as? NSTextView
        if let fieldEditor { fieldEditor.insertText("中文 s",replacementRange:NSRange(location:0,length:fieldEditor.string.utf16.count)) }
        else { field.stringValue = "中文 s" }
        let count = outputs.count; key(1); key(122)
        try require(outputs.count == count && (fieldEditor?.string ?? field.stringValue) == "中文 s","S and F1 leave active text input intact")
        let committed = canvas.control(field,textView:fieldEditor ?? NSTextView(),doCommandBy:#selector(NSResponder.insertNewline(_:)))
        key(1)
        if outputs.last == annotated { print("DETAIL: committed=\(committed), inputStillOpen=\(field.superview != nil), field=\(String(reflecting:field.stringValue)), editor=\(String(reflecting:fieldEditor?.string)), marked=\(fieldEditor?.hasMarkedText() ?? false)") }
        try require(outputs.last != annotated,"Chinese annotation is committed to the export")
        key(122); try require(actions.last == .copy,"F1 completes the selected capture")
        key(99); try require(actions.last == .pin,"F3 completes capture as a pin")
        var cancelled = false; canvas.onCancel = { cancelled = true }; key(53)
        try require(cancelled,"Escape cancels editing")
        pin.scale(by:2,anchor:CGPoint(x:50,y:40))
        try require(pin.frame.size == NSSize(width:200,height:160),"pin scales around its anchor")
        pin.resetZoom(); try require(pin.frame.size == NSSize(width:100,height:80),"pin resets to original size")
        guard let preferencesView = preferences.window?.contentView,
              let more = descendants(preferencesView).compactMap({$0 as? NSButton}).first(where:{$0.title == "更多快捷键 ▸"}) else { throw AppError.message("Missing shortcut disclosure") }
        let height = preferences.window!.frame.height; more.performClick(nil)
        try require(preferences.window!.frame.height > height,"advanced shortcuts expand")
        more.performClick(nil); try require(preferences.window!.frame.height == height,"common shortcut view collapses")
        print("Native UI regression passed")
    }
}
