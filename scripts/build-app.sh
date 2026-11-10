#!/usr/bin/env bash
# 用 swiftc 直接編譯並打包成 build/Project Tracker.app（只需 Command Line Tools，不需 Xcode）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Project Tracker.app"
ARCH="$(uname -m)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

EXTRA=()
# 舊版 Command Line Tools 殘留的 module.modulemap 會和新版 bridging.modulemap
# 重複定義 SwiftBridging，導致 Foundation 無法匯入。用 VFS overlay 遮掉它（不需 sudo）。
# 根治方法：sudo rm "$STALE"
DEV_DIR="$(xcode-select -p)"
STALE="$DEV_DIR/usr/include/swift/module.modulemap"
if [[ -f "$STALE" && -f "$DEV_DIR/usr/include/swift/bridging.modulemap" ]]; then
  echo "▸ 偵測到重複的 SwiftBridging modulemap，套用 VFS overlay 繞過"
  mkdir -p "$ROOT/build"
  : > "$ROOT/build/empty.modulemap"
  cat > "$ROOT/build/vfs-overlay.yaml" <<EOF
{"version":0,"case-sensitive":"false","roots":[{"name":"$DEV_DIR/usr/include/swift","type":"directory","contents":[{"name":"module.modulemap","type":"file","external-contents":"$ROOT/build/empty.modulemap"}]}]}
EOF
  # Swift 前端與 clang importer 都要套用，只給 -Xcc 不會生效
  EXTRA+=(-vfsoverlay "$ROOT/build/vfs-overlay.yaml" -Xcc -ivfsoverlay -Xcc "$ROOT/build/vfs-overlay.yaml")
fi
# 使用專案自己的模組快取，避免全域快取裡中斷編譯留下的鎖檔讓編譯卡住
mkdir -p "$ROOT/build/ModuleCache"
EXTRA+=(-module-cache-path "$ROOT/build/ModuleCache")

echo "▸ 編譯 Swift 原始碼（$ARCH，首次編譯需建立系統模組快取，可能要數分鐘）…"
swiftc -O \
  -target "$ARCH-apple-macosx14.0" \
  -parse-as-library \
  ${EXTRA[@]+"${EXTRA[@]}"} \
  -o "$APP/Contents/MacOS/ProjectTracker" \
  "$ROOT"/Sources/ProjectTracker/*.swift

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "▸ ad-hoc 簽章…"
codesign --force --sign - "$APP" >/dev/null

echo "✓ 完成：$APP"
