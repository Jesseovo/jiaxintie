import AppKit

public struct ShotStore {
    public let root: URL
    public var cache: URL { root.appendingPathComponent("缓存", isDirectory: true) }
    public init(directory: String) throws {
        guard (directory as NSString).isAbsolutePath else { throw AppError.message("请选择完整的截图保存路径。") }
        root = URL(fileURLWithPath: directory, isDirectory: true).standardizedFileURL
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    }
    public static func validateWritable(_ directory: String) throws {
        let store = try ShotStore(directory: directory)
        let probe = store.root.appendingPathComponent(".jiaxintie-write-\(UUID().uuidString)")
        try Data([0]).write(to: probe, options: .withoutOverwriting)
        try FileManager.default.removeItem(at: probe)
    }
    public static func isOwnedCache(_ name: String) -> Bool {
        name.range(of: #"^jxt-cache-\d{8}-\d{9}-[a-f0-9]{12}\.png$"#, options: .regularExpression) != nil
    }
    public func recent() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .isSymbolicLinkKey])
            .filter { url in
                guard Self.isOwnedCache(url.lastPathComponent), let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
                return values.isRegularFile == true && values.isSymbolicLink != true
            }.sorted { a, b in
                let first = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let second = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return first == second ? a.lastPathComponent > b.lastPathComponent : first > second
            }
    }
    public func trim() throws {
        for url in try recent().dropFirst(3) { try FileManager.default.removeItem(at: url) }
    }
    @discardableResult public func record(png: Data, permanent: Bool) throws -> URL {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyyMMdd-HHmmssSSS"
        let stamp = formatter.string(from: Date()) + "-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
        let cached = cache.appendingPathComponent("jxt-cache-\(stamp).png")
        let saved = root.appendingPathComponent("夹心贴-\(stamp).png")
        if permanent { try png.write(to: saved, options: .atomic) }
        try png.write(to: cached, options: .atomic)
        try trim(); return permanent ? saved : cached
    }
}

public enum ImageIO {
    public static func png(_ image: NSImage) throws -> Data {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { throw AppError.message("图片无法转换为 PNG。") }
        return data
    }
    public static func copy(_ image: NSImage) throws {
        let png = try png(image)
        let item = NSPasteboardItem(); item.setData(png, forType: .png)
        if let tiff = image.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects([item]) else { throw AppError.message("无法写入剪贴板，请重试。") }
    }
}
