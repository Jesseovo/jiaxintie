// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JiaXinTie",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "JiaXinTie", targets: ["JiaXinTie"])],
    targets: [
        .target(name: "JiaXinTieCore"),
        .executableTarget(name: "JiaXinTie", dependencies: ["JiaXinTieCore"]),
        // A standalone regression runner also works with Command Line Tools, without full Xcode/XCTest.
        .executableTarget(name: "JiaXinTieRegression", dependencies: ["JiaXinTieCore"], path: "Tests/JiaXinTieCoreTests")
    ]
)
