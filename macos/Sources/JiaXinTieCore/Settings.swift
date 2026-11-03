import AppKit
import Carbon.HIToolbox

public enum AppError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

public enum ShortcutAction: String, CaseIterable {
    case capture, quickCapture, pin, togglePins, copy, save, cancel, undo, redo, resetZoom
    public var title: String {
        switch self {
        case .capture: return "开始截图（全局）"
        case .quickCapture: return "框选即复制（全局）"
        case .pin: return "贴图（全局）"
        case .togglePins: return "显隐贴图（全局）"
        case .copy: return "完成并复制"
        case .save: return "保存截图"
        case .cancel: return "取消 / 删除贴图"
        case .undo: return "撤销标注"
        case .redo: return "重做标注"
        case .resetZoom: return "贴图原始大小"
        }
    }
    public static let global: [Self] = [.capture, .quickCapture, .pin, .togglePins]
    public static let editor: [Self] = [.copy, .save, .pin, .cancel, .undo, .redo]
}

public struct Shortcut: Codable, Equatable, Hashable {
    public var keyCode: UInt32
    public var modifiers: UInt
    public static let modifierMask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
    public init(_ key: Int, _ flags: NSEvent.ModifierFlags = []) {
        keyCode = UInt32(key); modifiers = flags.intersection(Self.modifierMask).rawValue
    }
    public init(event: NSEvent) { self.init(Int(event.keyCode), event.modifierFlags) }
    public func matches(_ event: NSEvent) -> Bool { self == Shortcut(event: event) }
    public var carbonModifiers: UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        return (flags.contains(.command) ? UInt32(cmdKey) : 0)
            | (flags.contains(.control) ? UInt32(controlKey) : 0)
            | (flags.contains(.option) ? UInt32(optionKey) : 0)
            | (flags.contains(.shift) ? UInt32(shiftKey) : 0)
    }
    public var isUsable: Bool { keyCode < 128 && ![48, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode) }
    public var isGlobalUsable: Bool {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        return isUsable && (!flags.intersection([.command, .control, .option]).isEmpty || Self.functionKeys[keyCode] != nil)
    }
    private static let functionKeys: [UInt32: String] = [122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12",105:"F13",107:"F14",113:"F15"]
    public var label: String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        let letters: [UInt32: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"−",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",36:"↩",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",49:"空格",50:"`",51:"⌫",53:"Esc",76:"⌤",123:"←",124:"→",125:"↓",126:"↑"]
        return (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "")
            + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
            + (Self.functionKeys[keyCode] ?? letters[keyCode] ?? "按键 \(keyCode)")
    }
}

public struct Settings: Codable {
    public var saveDirectory: String
    public var shortcuts: [String: Shortcut]
    public var hasCompletedSetup: Bool
    public init(saveDirectory: String? = nil) {
        self.saveDirectory = saveDirectory ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/夹心贴").path
        shortcuts = Self.defaults; hasCompletedSetup = false
    }
    public static var defaults: [String: Shortcut] {
        ["capture": Shortcut(kVK_F1),
         "quickCapture": Shortcut(kVK_F1, .command),
         "pin": Shortcut(kVK_F3),
         "togglePins": Shortcut(kVK_F3, .shift),
         "copy": Shortcut(kVK_F1), "save": Shortcut(kVK_ANSI_S),
         "cancel": Shortcut(kVK_Escape), "undo": Shortcut(kVK_ANSI_Z, .command),
         "redo": Shortcut(kVK_ANSI_Y, .command), "resetZoom": Shortcut(kVK_ANSI_0)]
    }
    public func shortcut(_ action: ShortcutAction) -> Shortcut { shortcuts[action.rawValue] ?? Self.defaults[action.rawValue]! }
    public func validate() throws {
        guard (saveDirectory as NSString).isAbsolutePath else { throw AppError.message("请选择完整的截图保存路径。") }
        for action in ShortcutAction.allCases where !shortcut(action).isUsable { throw AppError.message("\(action.title)的按键无效。") }
        for action in ShortcutAction.global where !shortcut(action).isGlobalUsable { throw AppError.message("全局快捷键请包含 ⌘、⌃、⌥，或使用 F1–F15。") }
        for group in [ShortcutAction.global, ShortcutAction.editor, [.copy, .save, .cancel, .resetZoom]] {
            let keys = group.map { shortcut($0) }
            if Set(keys).count != keys.count { throw AppError.message("同一场景的快捷键不能重复。") }
        }
    }
    private enum CodingKeys: CodingKey { case saveDirectory, shortcuts, hasCompletedSetup }
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        self.init(saveDirectory: try box.decodeIfPresent(String.self, forKey: .saveDirectory))
        shortcuts.merge(try box.decodeIfPresent([String: Shortcut].self, forKey: .shortcuts) ?? [:]) { _, new in new }
        hasCompletedSetup = try box.decodeIfPresent(Bool.self, forKey: .hasCompletedSetup) ?? false
    }
}

public struct SettingsStore {
    public let directory: URL
    public var file: URL { directory.appendingPathComponent("settings.json") }
    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("JiaXinTie", isDirectory: true)
    }
    public func load() throws -> Settings {
        guard FileManager.default.fileExists(atPath: file.path) else { return Settings() }
        let result = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: file))
        try result.validate(); return result
    }
    public func save(_ settings: Settings) throws {
        try settings.validate()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: file, options: .atomic)
    }
}
