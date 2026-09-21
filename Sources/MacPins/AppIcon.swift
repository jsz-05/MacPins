import AppKit

enum AppIcon {
    static func bundled() -> NSImage {
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let image = NSImage(contentsOfFile: path) {
            return image
        }
        return draw(size: 512)
    }

    static func draw(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        let background = NSBezierPath(
            roundedRect: rect.insetBy(dx: size * 0.055, dy: size * 0.055),
            xRadius: size * 0.22,
            yRadius: size * 0.22
        )
        let gradient = NSGradient(
            starting: NSColor(calibratedRed: 0.98, green: 0.31, blue: 0.27, alpha: 1),
            ending: NSColor(calibratedRed: 0.72, green: 0.06, blue: 0.12, alpha: 1)
        )
        gradient?.draw(in: background, angle: -90)

        let symbolSize = size * 0.55
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

        return image
    }
}
