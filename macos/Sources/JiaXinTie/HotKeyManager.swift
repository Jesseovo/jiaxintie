import AppKit
import Carbon.HIToolbox
import JiaXinTieCore

final class HotKeyManager {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    var onAction: ((ShortcutAction) -> Void)?
    init() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.id > 0, id.id <= ShortcutAction.global.count else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
            manager.onAction?(ShortcutAction.global[Int(id.id)-1]); return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    @discardableResult func register(_ settings: Settings) -> [String] {
        pause(); var failed: [String] = []
        for (index, action) in ShortcutAction.global.enumerated() {
            let key = settings.shortcut(action)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(key.keyCode, key.carbonModifiers, EventHotKeyID(signature: 0x4A58544D, id: UInt32(index+1)), GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs.append(ref) }
            else { failed.append("\(action.title)：\(key.label)（\(status)）") }
        }
        return failed
    }
    func pause() { for ref in refs { UnregisterEventHotKey(ref) }; refs.removeAll() }
    deinit { pause(); if let handler { RemoveEventHandler(handler) } }
}
