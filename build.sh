#!/bin/bash
set -euo pipefail

DIR="$HOME/.local/share/backup-dev-apps"
APP_NAME="FolderSync"
APP_DIR="$DIR/$APP_NAME.app"

echo "Compilando $APP_NAME..."
swiftc -O -o "$DIR/$APP_NAME" "$DIR/app/main.swift" -framework Cocoa

echo "Generando icono..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/scripts/generate-icon.sh" "$DIR"

echo "Creando bundle .app..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mv "$DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
mv "$DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Folder Sync</string>
    <key>CFBundleIdentifier</key>
    <string>com.klab.folder-sync</string>
    <key>CFBundleVersion</key>
    <string>1.4.0</string>
    <key>CFBundleExecutable</key>
    <string>FolderSync</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
</dict>
</plist>
PLIST

echo "Build completado: $APP_DIR"
echo ""
echo "Para ejecutar:  open $APP_DIR"
echo "Para iniciar con el sistema: agregar a Ajustes > General > Items de inicio"
