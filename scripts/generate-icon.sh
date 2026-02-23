#!/bin/bash
# Genera AppIcon.icns a partir del SF Symbol "externaldrive.badge.timemachine"
set -euo pipefail

OUTPUT_DIR="${1:-.}"
ICONSET_DIR=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET_DIR"

# Swift script que renderiza el SF Symbol a PNG en todos los tamanos requeridos
swift -e '
import Cocoa

let sizes: [(String, Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

let outputDir = CommandLine.arguments[1]

for (name, size) in sizes {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()

    // Background: rounded rect with gradient
    let rect = NSRect(x: 0, y: 0, width: s, height: s)
    let cornerRadius = s * 0.22
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.18, green: 0.20, blue: 0.25, alpha: 1.0),
        ending: NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.12, alpha: 1.0)
    )!
    gradient.draw(in: path, angle: -90)

    // SF Symbol in white
    if let symbol = NSImage(systemSymbolName: "externaldrive.badge.timemachine",
                            accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: s * 0.45, weight: .medium)
            .applying(.init(paletteColors: [.white]))
        let configured = symbol.withSymbolConfiguration(config)!

        let symbolSize = configured.size
        let x = (s - symbolSize.width) / 2
        let y = (s - symbolSize.height) / 2

        configured.draw(in: NSRect(x: x, y: y, width: symbolSize.width, height: symbolSize.height),
                       from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    img.unlockFocus()

    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        continue
    }

    let url = URL(fileURLWithPath: "\(outputDir)/\(name).png")
    try! png.write(to: url)
}
' "$ICONSET_DIR"

# Convertir iconset a icns
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_DIR/AppIcon.icns"
rm -rf "$(dirname "$ICONSET_DIR")"

echo "Icono generado: $OUTPUT_DIR/AppIcon.icns"
