#!/bin/bash
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
version=$(tr -d '\r\n' < "$root/VERSION")
bundle_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$root/macos/Info.plist")
if [ "$bundle_version" != "$version" ]; then
  printf 'VERSION and macos/Info.plist do not match.\n' >&2; exit 1
fi
build_flags=(--package-path "$root/macos" --configuration release --product JiaXinTie)
architectures=("$(uname -m)")
case "${1:-}" in
  "") ;;
  --universal) architectures=(arm64 x86_64) ;;
  *) printf 'Usage: %s [--universal]\n' "$0" >&2; exit 2 ;;
esac

# Build each architecture separately; SwiftPM's multi-arch mode requires full Xcode.
binaries=()
for architecture in "${architectures[@]}"; do
  swift build "${build_flags[@]}" --arch "$architecture"
  bin=$(swift build "${build_flags[@]}" --arch "$architecture" --show-bin-path)
  binaries+=("$bin/JiaXinTie")
done
mkdir -p "$root/build-tools" "$root/dist/macOS"
staging=$(mktemp -d "$root/build-tools/macos-package.XXXXXX")
app="$staging/夹心贴.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$staging/AppIcon.iconset"
if [ "${#binaries[@]}" -gt 1 ]; then
  lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/JiaXinTie"
  chmod +x "$app/Contents/MacOS/JiaXinTie"
else
  install -m 755 "${binaries[0]}" "$app/Contents/MacOS/JiaXinTie"
fi
cp "$root/macos/Info.plist" "$app/Contents/Info.plist"
cp "$root/assets/logo.png" "$app/Contents/Resources/logo.png"
cp "$root/docs/usage.zh-CN.md" "$app/Contents/Resources/使用说明.md"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$root/assets/logo.png" --out "$staging/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  doubled=$((size * 2))
  sips -z "$doubled" "$doubled" "$root/assets/logo.png" --out "$staging/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$staging/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier com.jesseovo.jiaxintie "$app"
codesign --verify --deep --strict "$app"
ditto "$app" "$root/dist/macOS/夹心贴.app"
package_arch="${architectures[0]}"
if [ "${#architectures[@]}" -gt 1 ]; then package_arch=universal; fi
archive="$root/dist/macOS/JiaXinTie-macOS-${package_arch}-v${version}.zip"
ditto -c -k --sequesterRsrc --keepParent "$root/dist/macOS/夹心贴.app" "$archive"
printf '\n应用：%s\n压缩包：%s\n' "$root/dist/macOS/夹心贴.app" "$archive"
