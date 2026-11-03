import AppKit
import CoreImage

public enum DrawTool: String, CaseIterable {
    case move, rectangle, ellipse, line, arrow, pen, highlighter, mosaic, text, eraser
    public var title: String {
        switch self {
        case .move: return "移动选区"
        case .rectangle: return "矩形"
        case .ellipse: return "圆形"
        case .line: return "直线"
        case .arrow: return "箭头"
        case .pen: return "画笔"
        case .highlighter: return "荧光笔"
        case .mosaic: return "马赛克"
        case .text: return "文字"
        case .eraser: return "橡皮擦"
        }
    }
    public var symbol: String {
        switch self {
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .mosaic: return "square.grid.3x3.fill"
        case .text: return "textformat"
        case .eraser: return "eraser"
        }
    }
}

public func normalizedRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
    CGRect(x: min(a.x,b.x), y: min(a.y,b.y), width: abs(a.x-b.x), height: abs(a.y-b.y))
}

public struct Mark {
    public var tool: DrawTool
    public var points: [CGPoint]
    public var color: NSColor
    public var width: CGFloat
    public var text: String
    public init(tool: DrawTool, start: CGPoint, color: NSColor = .systemPink, width: CGFloat = 3, text: String = "") {
        self.tool = tool; points = [start, start]; self.color = color; self.width = width; self.text = text
    }
    public var bounds: CGRect { normalizedRect(points.first ?? .zero, points.last ?? .zero) }
    public var textAttributes: [NSAttributedString.Key: Any] { [.font: NSFont.systemFont(ofSize: max(18, width * 5), weight: .medium), .foregroundColor: color] }
    public var visualBounds: CGRect {
        if tool == .text { return CGRect(origin: points[0], size: (text as NSString).size(withAttributes: textAttributes)).insetBy(dx: -4, dy: -4) }
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0, width: (xs.max() ?? 0) - (xs.min() ?? 0), height: (ys.max() ?? 0) - (ys.min() ?? 0)).insetBy(dx: -(width + 20), dy: -(width + 20))
    }
    private func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x-a.x, dy = b.y-a.y, length = dx*dx+dy*dy
        let t = length == 0 ? 0 : max(0, min(1, ((p.x-a.x)*dx+(p.y-a.y)*dy)/length))
        return hypot(p.x-a.x-t*dx, p.y-a.y-t*dy)
    }
    public func hitTest(_ point: CGPoint, radius: CGFloat = 8) -> Bool {
        guard visualBounds.insetBy(dx: -radius, dy: -radius).contains(point) else { return false }
        let tolerance = radius + width/2, r = bounds
        switch tool {
        case .text: return visualBounds.contains(point)
        case .mosaic: return r.insetBy(dx: -radius, dy: -radius).contains(point)
        case .ellipse:
            guard r.width > 0, r.height > 0 else { return false }
            return abs(hypot((point.x-r.midX)/(r.width/2), (point.y-r.midY)/(r.height/2))-1) * min(r.width,r.height)/2 <= tolerance
        case .rectangle:
            let corners = [CGPoint(x:r.minX,y:r.minY),CGPoint(x:r.maxX,y:r.minY),CGPoint(x:r.maxX,y:r.maxY),CGPoint(x:r.minX,y:r.maxY),CGPoint(x:r.minX,y:r.minY)]
            return zip(corners, corners.dropFirst()).contains { distance(point,$0,$1) <= tolerance }
        default: return zip(points, points.dropFirst()).contains { distance(point,$0,$1) <= tolerance }
        }
    }
    public func draw(mosaic: NSImage?) {
        guard let first = points.first, let last = points.last else { return }
        let path = NSBezierPath(); path.lineWidth = width; path.lineCapStyle = .round; path.lineJoinStyle = .round
        (tool == .highlighter ? color.withAlphaComponent(0.35) : color).setStroke()
        switch tool {
        case .rectangle: path.appendRect(bounds)
        case .ellipse: path.appendOval(in: bounds)
        case .pen, .highlighter:
            path.lineWidth = tool == .highlighter ? max(14,width * 5) : width
            path.move(to: first); for point in points.dropFirst() { path.line(to: point) }
        case .line, .arrow:
            path.move(to: first); path.line(to: last)
            if tool == .arrow {
                let angle = atan2(last.y-first.y,last.x-first.x), size = max(12, width * 4)
                for offset in [-CGFloat.pi/6, CGFloat.pi/6] { path.move(to: last); path.line(to: CGPoint(x:last.x-size*cos(angle+offset),y:last.y-size*sin(angle+offset))) }
            }
        case .text: (text as NSString).draw(at: first, withAttributes: textAttributes); return
        case .mosaic:
            NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: bounds).addClip()
            mosaic?.draw(at: .zero, from: .zero, operation: .copy, fraction: 1)
            NSGraphicsContext.restoreGraphicsState(); return
        default: return
        }
        path.stroke()
    }
}

public struct AnnotationHistory {
    public private(set) var marks: [Mark] = []
    private var past: [[Mark]] = [], future: [[Mark]] = []
    public init() {}
    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public mutating func append(_ mark: Mark) { past.append(marks); marks.append(mark); future.removeAll() }
    @discardableResult public mutating func erase(at point: CGPoint) -> Bool {
        guard let index = marks.lastIndex(where: { $0.hitTest(point) }) else { return false }
        past.append(marks); marks.remove(at: index); future.removeAll(); return true
    }
    public mutating func undo() { guard let previous = past.popLast() else { return }; future.append(marks); marks = previous }
    public mutating func redo() { guard let next = future.popLast() else { return }; past.append(marks); marks = next }
    public mutating func clear() { self = Self() }
}

public enum ImageRenderer {
    // AppKit's origin is bottom-left; CGImage crop rectangles start at the top-left.
    public static func pixelRect(selection: CGRect, screenSize: CGSize, pixels: CGSize) -> CGRect {
        let r = selection.intersection(CGRect(origin: .zero, size: screenSize))
        guard !r.isNull, screenSize.width > 0, screenSize.height > 0 else { return .zero }
        return CGRect(x: r.minX * pixels.width / screenSize.width,
                      y: (screenSize.height-r.maxY) * pixels.height / screenSize.height,
                      width: r.width * pixels.width / screenSize.width,
                      height: r.height * pixels.height / screenSize.height).integral
            .intersection(CGRect(origin: .zero, size: pixels))
    }
    public static func crop(_ image: CGImage, screenSize: CGSize, selection: CGRect) throws -> CGImage {
        let rect = pixelRect(selection: selection, screenSize: screenSize, pixels: CGSize(width:image.width,height:image.height))
        guard rect.width >= 1, rect.height >= 1, let crop = image.cropping(to: rect) else { throw AppError.message("请先框选截图区域。") }
        return crop
    }
    public static func mosaic(_ image: CGImage, size: CGSize) -> NSImage? {
        let input = CIImage(cgImage: image)
        let filtered = input.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: max(12,CGFloat(image.width)/size.width * 10)])
        guard let cg = CIContext(options: [.cacheIntermediates: false]).createCGImage(filtered, from: input.extent) else { return nil }
        return NSImage(cgImage: cg, size: size)
    }
    public static func render(_ source: CGImage, screenSize: CGSize, selection: CGRect, marks: [Mark]) throws -> NSImage {
        let cropped = try crop(source, screenSize: screenSize, selection: selection)
        let size = selection.intersection(CGRect(origin:.zero,size:screenSize)).size
        guard let context = CGContext(data: nil, width: cropped.width, height: cropped.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw AppError.message("无法分配截图缓冲区。") }
        context.draw(cropped, in: CGRect(x:0,y:0,width:cropped.width,height:cropped.height))
        context.scaleBy(x: CGFloat(cropped.width)/size.width, y: CGFloat(cropped.height)/size.height)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let pixelated = marks.contains(where: {$0.tool == .mosaic}) ? mosaic(cropped, size: size) : nil
        for mark in marks { mark.draw(mosaic: pixelated) }
        NSGraphicsContext.restoreGraphicsState()
        guard let output = context.makeImage() else { throw AppError.message("截图合成失败。") }
        return NSImage(cgImage: output, size: size)
    }
}
