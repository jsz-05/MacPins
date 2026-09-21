import AppKit

enum WindowDetector {
    static func window(atAppKitPoint point: CGPoint) -> ForeignWindow? {
        let cgPoint = CGPoint(x: point.x, y: primaryScreenHeight - point.y)
        return visibleWindows().first { window in
            window.ownerPID != ProcessInfo.processInfo.processIdentifier
                && window.bounds.contains(cgPoint)
        }
    }

    static func frontmostForeignWindow() -> ForeignWindow? {
        let ownPID = ProcessInfo.processInfo.processIdentifier

        if let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           frontPID != ownPID,
           let exact = visibleWindows().first(where: { $0.ownerPID == frontPID }) {
            return exact
        }

        return visibleWindows().first(where: { $0.ownerPID != ownPID })
    }

    static func windowInfo(windowID: CGWindowID) -> ForeignWindow? {
        guard let raw = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID)
                as? [[String: Any]],
              let entry = raw.first else {
            return nil
        }
        return makeWindow(from: entry, requireNormalLayer: false)
    }

    static func appKitFrame(forCGFrame frame: CGRect) -> CGRect {
        CGRect(
            x: frame.origin.x,
            y: primaryScreenHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

    private static var primaryScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 0
    }

    private static func visibleWindows() -> [ForeignWindow] {
        guard let entries = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return entries.compactMap { makeWindow(from: $0, requireNormalLayer: true) }
    }

    private static func makeWindow(
        from entry: [String: Any],
        requireNormalLayer: Bool
    ) -> ForeignWindow? {
        guard let idNumber = entry[kCGWindowNumber as String] as? NSNumber,
              let pidNumber = entry[kCGWindowOwnerPID as String] as? NSNumber,
              let layerNumber = entry[kCGWindowLayer as String] as? NSNumber,
              let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else {
            return nil
        }

        if requireNormalLayer && layerNumber.intValue != 0 { return nil }
        if bounds.width < 80 || bounds.height < 50 { return nil }

        let alpha = (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        if alpha <= 0 { return nil }

        let owner = entry[kCGWindowOwnerName as String] as? String ?? "Unknown App"
        if owner == "Window Server" || owner == "Dock" { return nil }

        return ForeignWindow(
            windowID: idNumber.uint32Value,
            ownerPID: pidNumber.int32Value,
            ownerName: owner,
            title: entry[kCGWindowName as String] as? String ?? "",
            bounds: bounds
        )
    }
}
