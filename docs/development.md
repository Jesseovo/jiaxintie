# 开发与构建

夹心贴使用两个原生桌面实现：Windows 为 C# / WinForms / .NET Framework 4.8，macOS 为 Swift / AppKit / ScreenCaptureKit。运行不依赖 Snipaste 的程序、DLL、授权或安装目录，没有广告、遥测或应用联网逻辑。

## 代码结构

```text
src/                           Windows 界面、截图、标注及缓存
macos/Sources/JiaXinTie/        Mac 菜单栏、编辑器、贴图与设置
macos/Sources/JiaXinTieCore/    Mac 配置、缓存、标注及图像合成
macos/Tests/                   Mac 核心回归入口
tests/                         Windows 回归、演示及绘制基准
assets/                        应用图标及 README 素材
screenshots/                   不含真实桌面内容的演示截图
.github/workflows/build.yml    双平台构建和测试
VERSION                        对外发布版本
```

## Windows

在 Windows x64 上执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
powershell -ExecutionPolicy Bypass -File .\tests\run.ps1
```

使用系统的 .NET Framework C# 编译器。安装包需要 Inno Setup 6，可放在 `build-tools/InnoSetup/`，也会检查标准安装路径。使用 `build.ps1 -RequireInstaller` 可要求必须生成安装包。

输出位于 `dist/1.0/`，包含 `夹心贴.exe`、使用说明和可选安装程序。`tests/run.ps1 -SkipScreenCapture` 面向无真实桌面的 CI，会明确跳过六项真实桌面捕获检查，继续执行绘制、配置、PNG、缓存和安装配置检查；普通测试默认保留屏幕捕获检查。

绘制基准入口是 `tests/benchmark.ps1`。`tests/run-ui.ps1` 支持 demo、real、settings、pin，使用独立测试配置和 F8 / F9，避免影响常规设置。

## macOS

安装 Apple Command Line Tools 后执行：

```bash
./build-macos.sh
./build-macos.sh --universal
swift run --package-path macos JiaXinTieRegression
dist/macOS/夹心贴.app/Contents/MacOS/JiaXinTie --smoke-test
```

第一条构建当前架构，第二条分别编译 arm64、x86_64 并用 `lipo` 合并，不要求完整 Xcode。通用 ZIP 为 `dist/macOS/JiaXinTie-macOS-universal-v1.0.zip`。

核心回归有 12 项检查。`--smoke-test` 在不可见原生窗口中用测试像素执行 17 项检查，不读取真实屏幕、剪贴板或用户配置，不能替代物理按键、输入法、屏幕录制权限和真实桌面的交互验收。

`--demo` 用生成的示例图片打开截图编辑器，使用独立配置；可配合 `--profile /绝对路径` 指定测试目录。

本地包及 CI 包使用临时签名，并执行签名结构校验。Developer ID 签名和 Apple 公证需要维护者另行配置，当前发布不声称已公证。

## 发布

1. 保持 `VERSION`、`src/AssemblyInfo.cs`、`macos/Info.plist` 的版本一致；安装器和产物命名从 `VERSION` 读取。
2. 推送 `main` 或手动运行 Build desktop apps 工作流。Windows 和 Mac 原生 runner 分别构建、测试，并上传平台 ZIP。
3. 所有检查通过后，在对应提交上建立版本标签，将两个 ZIP 和 SHA-256 校验文件上传 Release。发布记录写入 `CHANGELOG.md`。

首次统一发布标签为 `v1.0`，包含现有 Windows 功能及 macOS 实现。早期内部构建和历史性能对比不作为另一个对外版本发布。
