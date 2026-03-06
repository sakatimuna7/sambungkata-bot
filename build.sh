#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  BUILD SCRIPT — SambungKata.app for macOS
#  Jalankan: bash build.sh
# ─────────────────────────────────────────────────────────────

set -e

APP_NAME="SambungKata"
APP_DIR="${APP_NAME}.app"
EXEC_DIR="${APP_DIR}/Contents/MacOS"
RES_DIR="${APP_DIR}/Contents/Resources"

echo "🔨 Building ${APP_NAME}.app..."

# Bersihkan build lama
[ -d "$APP_DIR" ] && rm -rf "$APP_DIR" && echo "🗑  Cleaned old build"

# Buat struktur folder .app
mkdir -p "$EXEC_DIR"
mkdir -p "$RES_DIR"

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    TARGET="arm64-apple-macosx12.0"
else
    TARGET="x86_64-apple-macosx12.0"
fi

echo "⚙️  Compiling Swift (${ARCH})..."

swiftc main.swift \
    -o "${EXEC_DIR}/${APP_NAME}" \
    -framework Cocoa \
    -framework WebKit \
    -framework Carbon \
    -target "$TARGET" \
    -O

if [ $? -ne 0 ]; then
    echo "❌ Compile gagal!"
    exit 1
fi

echo "✅ Compiled!"

# Copy files
echo "📄 Copying files..."
cp Info.plist "${APP_DIR}/Contents/Info.plist"
cp overlay.html "${RES_DIR}/overlay.html"

# Sign ad-hoc (tanpa Apple Developer account)
echo "✍️  Signing (ad-hoc)..."
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

# Remove quarantine flag
xattr -cr "$APP_DIR" 2>/dev/null || true

echo ""
echo "✅ Build sukses!"
echo "📦 $(pwd)/${APP_DIR}"
echo ""
echo "▶  Jalankan:"
echo "   open ${APP_DIR}"
echo ""
echo "⌨️  Hotkey: Cmd+Shift+K → show/hide overlay"
echo ""
echo "⚠️  Kalau muncul 'unidentified developer':"
echo "   System Settings → Privacy & Security → Open Anyway"
