import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift GenerateIcon.swift <AppIcon.iconset directory>")
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for variant in variants {
    let size = CGFloat(variant.pixels)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: variant.pixels,
        pixelsHigh: variant.pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { continue }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill()

    // macOS app icons use generous optical padding inside the 1024-point
    // canvas. Keeping the tile near 81% prevents it from appearing oversized
    // next to Apple's Dock icons.
    let background = NSBezierPath(
        roundedRect: rect.insetBy(dx: size * 0.095, dy: size * 0.095),
        xRadius: size * 0.18,
        yRadius: size * 0.18
    )
    NSGradient(
        starting: NSColor(calibratedRed: 0.98, green: 0.31, blue: 0.27, alpha: 1),
        ending: NSColor(calibratedRed: 0.72, green: 0.06, blue: 0.12, alpha: 1)
    )?.draw(in: background, angle: -90)

    let symbolSize = size * 0.48
    if let symbol = NSImage(
        systemSymbolName: "pin.fill",
        accessibilityDescription: "MacPins"
    )?.withSymbolConfiguration(
        NSImage.SymbolConfiguration(
            pointSize: symbolSize,
            weight: .bold
        ).applying(.init(paletteColors: [.white]))
    ) {
        symbol.draw(
            in: NSRect(
                x: (size - symbolSize) / 2,
                y: (size - symbolSize) / 2,
                width: symbolSize,
                height: symbolSize
            )
        )
    }

    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else { continue }
    try png.write(to: outputDirectory.appendingPathComponent(variant.name))
}
