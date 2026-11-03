import Foundation
import AppKit
import JiaXinTieCore

final class CoreTests {
    private var directory: URL!
    func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("夹心贴 测试-\(UUID().uuidString)",isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    }
    func tearDownWithError() throws { try FileManager.default.removeItem(at:directory) }
    private func image(width: Int = 100, height: Int = 80) -> CGImage {
        var bytes = [UInt8](repeating:255,count:width*height*4)
        for y in 0..<height { for x in 0..<width {
            let i = (y*width+x)*4
            bytes[i] = y < height/2 ? 255 : 0; bytes[i+1] = UInt8(x%255); bytes[i+2] = y < height/2 ? 0 : 255
        } }
        return CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:CGDataProvider(data:Data(bytes) as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
    }
    func testSettingsRoundTripAndMissingNewKeys() throws {
        let storage = SettingsStore(directory:directory)
        var settings = Settings(saveDirectory:directory.appendingPathComponent("截图").path)
        settings.shortcuts["capture"] = Shortcut(18,[.command,.option]); settings.hasCompletedSetup = true
        try storage.save(settings)
        let loaded = try storage.load()
        XCTAssertEqual(loaded.shortcut(.capture),settings.shortcut(.capture)); XCTAssertTrue(loaded.hasCompletedSetup)
        let old = "{\"saveDirectory\":\"/tmp/screenshots\",\"shortcuts\":{}}"
        try Data(old.utf8).write(to:storage.file)
        XCTAssertEqual(try storage.load().shortcut(.redo),Settings().shortcut(.redo))
    }
    func testCorruptSettingsAreNotOverwritten() throws {
        let storage = SettingsStore(directory:directory), bad = Data("broken settings".utf8)
        try bad.write(to:storage.file); XCTAssertThrowsError(try storage.load())
        XCTAssertEqual(try Data(contentsOf:storage.file),bad)
    }
    func testShortcutValidation() throws {
        var settings = Settings(); XCTAssertNoThrow(try settings.validate())
        settings.shortcuts["pin"] = settings.shortcut(.capture); XCTAssertThrowsError(try settings.validate())
        settings = Settings(); settings.shortcuts["capture"] = Shortcut(0); XCTAssertThrowsError(try settings.validate())
        settings.shortcuts["capture"] = Shortcut(122); XCTAssertNoThrow(try settings.validate())
        settings.shortcuts["save"] = settings.shortcut(.copy); XCTAssertThrowsError(try settings.validate())
        settings = Settings(); settings.shortcuts["cancel"] = Shortcut(900); XCTAssertThrowsError(try settings.validate())
    }
    func testShortcutLabelsAndModifierConversion() {
        let key = Shortcut(0,[.control,.option])
        XCTAssertEqual(key.label,"⌃⌥A"); XCTAssertEqual(key.carbonModifiers,UInt32(4096+2048))
        XCTAssertEqual(Shortcut(6,[.command,.shift]).label,"⇧⌘Z")
        XCTAssertFalse(Shortcut(55).isUsable)
    }
    func testCacheRotationPreservesPermanentAndUnrelatedFiles() throws {
        let store = try ShotStore(directory:directory.path)
        let unrelated = store.cache.appendingPathComponent("jxt-cache-user.png")
        try Data("keep".utf8).write(to:unrelated)
        let png = try ImageIO.png(NSImage(cgImage:image(),size:CGSize(width:50,height:40)))
        let permanent = try store.record(png:png,permanent:true)
        var newest: URL!
        for _ in 0..<5 { Thread.sleep(forTimeInterval:0.003); newest = try store.record(png:png,permanent:false) }
        XCTAssertEqual(try store.recent().count,3); XCTAssertEqual(try store.recent().first?.resolvingSymlinksInPath(),newest.resolvingSymlinksInPath())
        XCTAssertTrue(FileManager.default.fileExists(atPath:permanent.path)); XCTAssertEqual(try Data(contentsOf:permanent),png)
        XCTAssertEqual(try Data(contentsOf:unrelated),Data("keep".utf8))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:store.root.path).contains(where:{$0.hasSuffix(".part")}))
    }
    func testCacheNeverFollowsSymlinksOrTreatsDirectoriesAsImages() throws {
        let store = try ShotStore(directory:directory.path)
        let name = "jxt-cache-20261101-123456789-abcdef123456.png"
        let outside = directory.appendingPathComponent("保留的图片.png"); try Data([1,2,3]).write(to:outside)
        try FileManager.default.createSymbolicLink(at:store.cache.appendingPathComponent(name),withDestinationURL:outside)
        try FileManager.default.createDirectory(at:store.cache.appendingPathComponent("jxt-cache-20261101-123456780-abcdef123456.png"),withIntermediateDirectories:true)
        XCTAssertTrue(try store.recent().isEmpty); try store.trim(); XCTAssertEqual(try Data(contentsOf:outside),Data([1,2,3]))
        XCTAssertFalse(ShotStore.isOwnedCache("jxt-cache-20261101-123456789-abcdef123456.png.backup"))
    }
    func testRetinaCoordinateConversionAndClipping() {
        let rect = ImageRenderer.pixelRect(selection:CGRect(x:5,y:4,width:10,height:6),screenSize:CGSize(width:50,height:40),pixels:CGSize(width:100,height:80))
        XCTAssertEqual(rect,CGRect(x:10,y:60,width:20,height:12))
        XCTAssertEqual(ImageRenderer.pixelRect(selection:CGRect(x:-4,y:-2,width:9,height:7),screenSize:CGSize(width:50,height:40),pixels:CGSize(width:100,height:80)),CGRect(x:0,y:70,width:10,height:10))
    }
    func testCropAndPNGKeepNativePixelsAndOrientation() throws {
        let source = image(), selection = CGRect(x:4,y:3,width:20,height:15)
        let rendered = try ImageRenderer.render(source,screenSize:CGSize(width:50,height:40),selection:selection,marks:[])
        let png = try ImageIO.png(rendered), decoded = NSBitmapImageRep(data:png)!
        XCTAssertEqual(decoded.pixelsWide,40); XCTAssertEqual(decoded.pixelsHigh,30)
        XCTAssertEqual(rendered.size,selection.size)
        let expected = NSBitmapImageRep(cgImage:try ImageRenderer.crop(source,screenSize:CGSize(width:50,height:40),selection:selection))
        for point in [(0,0),(10,10),(39,29)] {
            let a = expected.colorAt(x:point.0,y:point.1)!.usingColorSpace(.sRGB)!, b = decoded.colorAt(x:point.0,y:point.1)!.usingColorSpace(.sRGB)!
            XCTAssertEqual(a.redComponent,b.redComponent,accuracy:0.01); XCTAssertEqual(a.blueComponent,b.blueComponent,accuracy:0.01)
        }
    }
    func testAnnotationUsesBottomLeftCoordinates() throws {
        let source = image(width:100,height:100)
        var mark = Mark(tool:.line,start:CGPoint(x:5,y:5),color:.green,width:3); mark.points[1] = CGPoint(x:40,y:5)
        let result = try ImageRenderer.render(source,screenSize:CGSize(width:50,height:50),selection:CGRect(x:0,y:0,width:50,height:50),marks:[mark])
        let bitmap = NSBitmapImageRep(data:try ImageIO.png(result))!
        let color = bitmap.colorAt(x:40,y:90)!.usingColorSpace(.sRGB)!
        XCTAssertGreaterThan(color.greenComponent,0.8); XCTAssertLessThan(color.redComponent,0.2); XCTAssertLessThan(color.blueComponent,0.2)
    }
    func testEmptySelectionFailsWithoutCreatingImage() {
        XCTAssertThrowsError(try ImageRenderer.render(image(),screenSize:CGSize(width:50,height:40),selection:.zero,marks:[]))
    }
    func testEraserHitsStrokesAndUndoRestoresLayerOrder() {
        var history = AnnotationHistory()
        var rectangle = Mark(tool:.rectangle,start:CGPoint(x:10,y:10)); rectangle.points[1] = CGPoint(x:100,y:100)
        XCTAssertFalse(rectangle.hitTest(CGPoint(x:50,y:50))); XCTAssertTrue(rectangle.hitTest(CGPoint(x:10,y:50)))
        history.append(rectangle)
        var line = Mark(tool:.line,start:CGPoint(x:10,y:50)); line.points[1] = CGPoint(x:100,y:50); history.append(line)
        XCTAssertTrue(history.erase(at:CGPoint(x:50,y:50))); XCTAssertEqual(history.marks.count,1)
        history.undo(); XCTAssertEqual(history.marks.map(\.tool),[.rectangle,.line])
        history.redo(); XCTAssertEqual(history.marks.map(\.tool),[.rectangle])
        history.undo(); history.append(Mark(tool:.text,start:.zero,text:"中文 s")); XCTAssertFalse(history.canRedo)
    }
    func testMosaicChangesOnlyAnnotatedRegion() throws {
        let source = image()
        var mark = Mark(tool:.mosaic,start:CGPoint(x:10,y:10)); mark.points[1] = CGPoint(x:20,y:20)
        let size = CGSize(width:50,height:40), selection = CGRect(origin:.zero,size:size)
        let original = NSBitmapImageRep(data:try ImageIO.png(ImageRenderer.render(source,screenSize:size,selection:selection,marks:[])))!
        let edited = NSBitmapImageRep(data:try ImageIO.png(ImageRenderer.render(source,screenSize:size,selection:selection,marks:[mark])))!
        XCTAssertEqual(original.colorAt(x:2,y:2),edited.colorAt(x:2,y:2))
        XCTAssertNotEqual(original.colorAt(x:23,y:47),edited.colorAt(x:23,y:47))
    }
}
