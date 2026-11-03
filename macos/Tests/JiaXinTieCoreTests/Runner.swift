import Foundation

// No external packages or XCTest runtime: the same checks run on a clean CLT-only Mac.
private var failures = 0
private func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
    failures += 1; fputs("FAIL \(file):\(line): \(message)\n",stderr)
}
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { if a != b { fail("\(a) != \(b)",file:file,line:line) } }
func XCTAssertNotEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { if a == b { fail("values unexpectedly equal: \(a)",file:file,line:line) } }
func XCTAssertEqual<T: BinaryFloatingPoint>(_ a: T, _ b: T, accuracy: T, file: StaticString = #filePath, line: UInt = #line) { if abs(a-b) > accuracy { fail("\(a) != \(b) ± \(accuracy)",file:file,line:line) } }
func XCTAssertTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { if !value { fail("expected true",file:file,line:line) } }
func XCTAssertFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { if value { fail("expected false",file:file,line:line) } }
func XCTAssertGreaterThan<T: Comparable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { if !(a > b) { fail("\(a) is not greater than \(b)",file:file,line:line) } }
func XCTAssertLessThan<T: Comparable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { if !(a < b) { fail("\(a) is not less than \(b)",file:file,line:line) } }
func XCTAssertNoThrow<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) { do { _ = try expression() } catch { fail("unexpected error: \(error)",file:file,line:line) } }
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) { do { _ = try expression(); fail("expected error",file:file,line:line) } catch {} }

@main struct RegressionRunner {
    static func main() {
        let tests = CoreTests()
        let cases: [(String,() throws -> Void)] = [
            ("设置持久化与默认值补齐",tests.testSettingsRoundTripAndMissingNewKeys),
            ("损坏配置不被静默覆盖",tests.testCorruptSettingsAreNotOverwritten),
            ("快捷键冲突及无效按键",tests.testShortcutValidation),
            ("Mac 按键标签及系统修饰键",tests.testShortcutLabelsAndModifierConversion),
            ("仅轮换三张缓存并保留手动文件",tests.testCacheRotationPreservesPermanentAndUnrelatedFiles),
            ("缓存忽略符号链接与目录",tests.testCacheNeverFollowsSymlinksOrTreatsDirectoriesAsImages),
            ("Retina 坐标转换及边界裁剪",tests.testRetinaCoordinateConversionAndClipping),
            ("PNG 原生分辨率和图像方向",tests.testCropAndPNGKeepNativePixelsAndOrientation),
            ("标注坐标与输出方向",tests.testAnnotationUsesBottomLeftCoordinates),
            ("拒绝空选区",tests.testEmptySelectionFailsWithoutCreatingImage),
            ("橡皮擦命中与撤销重做图层顺序",tests.testEraserHitsStrokesAndUndoRestoresLayerOrder),
            ("马赛克仅作用于标注范围",tests.testMosaicChangesOnlyAnnotatedRegion)
        ]
        for (name,body) in cases {
            let before = failures
            do { try tests.setUpWithError(); try body() } catch { fail("\(name): \(error)") }
            do { try tests.tearDownWithError() } catch { fail("清理测试目录：\(error)") }
            print("\(failures == before ? "PASS" : "FAIL") \(name)")
        }
        print("\(cases.count) 项回归检查，\(failures) 处失败")
        exit(failures == 0 ? 0 : 1)
    }
}
