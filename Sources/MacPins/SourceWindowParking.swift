import AppKit
import ApplicationServices

/// Optionally moves a source window almost entirely beyond the right edge of
/// its current display. Keeping a few pixels onscreen prevents Chromium from
/// treating the window as fully occluded, while the ScreenCaptureKit mirror
/// continues to capture the complete window. The exact original frame is
/// restored when the pin is removed.
enum SourceWindowParking {
    final class Token {
        private let element: AXUIElement
        private let originalPosition: CGPoint
        private let originalSize: CGSize
        private var hasRestored = false

        fileprivate init(
            element: AXUIElement,
            originalPosition: CGPoint,
            originalSize: CGSize
        ) {
            self.element = element
            self.originalPosition = originalPosition
            self.originalSize = originalSize
        }

        func restore() {
            guard !hasRestored else { return }
            hasRestored = true
            SourceWindowParking.setSize(originalSize, on: element)
            SourceWindowParking.setPosition(originalPosition, on: element)
        }

        deinit {
            restore()
        }
    }

    static func park(window target: ForeignWindow) -> Token? {
        guard AXIsProcessTrusted() else { return nil }

        let currentBounds = WindowDetector.windowInfo(windowID: target.windowID)?.bounds
            ?? target.bounds
        let appElement = AXUIElementCreateApplication(target.ownerPID)
        guard let element = matchingWindow(
            in: appElement,
            target: target,
            currentBounds: currentBounds
        ),
        let originalPosition = pointAttribute(kAXPositionAttribute, of: element),
        let originalSize = sizeAttribute(kAXSizeAttribute, of: element),
        let displayBounds = displayContainingMost(of: currentBounds) else { return nil }

        // Four points are enough for AppKit to classify the source as visible,
        // but small enough not to look like a second copy of the window.
        let parkedPosition = CGPoint(
            x: displayBounds.maxX - 4,
            y: originalPosition.y
        )
        guard setPosition(parkedPosition, on: element),
              let actualPosition = pointAttribute(kAXPositionAttribute, of: element) else {
            return nil
        }

        let actualBounds = CGRect(origin: actualPosition, size: originalSize)
        let visibleWidth = actualBounds.intersection(displayBounds).width
        guard abs(actualPosition.x - originalPosition.x) > 20,
              visibleWidth <= 48 else {
            setPosition(originalPosition, on: element)
            return nil
        }

        return Token(
            element: element,
            originalPosition: originalPosition,
            originalSize: originalSize
        )
    }

    private static func matchingWindow(
        in appElement: AXUIElement,
        target: ForeignWindow,
        currentBounds: CGRect
    ) -> AXUIElement? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &value
        ) == .success,
        let windows = value as? [AXUIElement] else { return nil }

        if let byBounds = windows.first(where: {
            guard let position = pointAttribute(kAXPositionAttribute, of: $0),
                  let size = sizeAttribute(kAXSizeAttribute, of: $0) else { return false }
            return abs(position.x - currentBounds.minX) < 8
                && abs(position.y - currentBounds.minY) < 8
                && abs(size.width - currentBounds.width) < 8
                && abs(size.height - currentBounds.height) < 8
        }) {
            return byBounds
        }

        if !target.title.isEmpty,
           let byTitle = windows.first(where: { title(of: $0) == target.title }) {
            return byTitle
        }

        return windows.count == 1 ? windows.first : nil
    }

    private static func pointAttribute(
        _ attribute: String,
        of element: AXUIElement
    ) -> CGPoint? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success,
        let value else { return nil }
        let axValue = value as! AXValue
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    private static func sizeAttribute(
        _ attribute: String,
        of element: AXUIElement
    ) -> CGSize? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success,
        let value else { return nil }
        let axValue = value as! AXValue
        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }

    @discardableResult
    private static func setPosition(_ position: CGPoint, on element: AXUIElement) -> Bool {
        var position = position
        guard let value = AXValueCreate(.cgPoint, &position) else { return false }
        return AXUIElementSetAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            value
        ) == .success
    }

    @discardableResult
    private static func setSize(_ size: CGSize, on element: AXUIElement) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            value
        ) == .success
    }

    private static func title(of element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXTitleAttribute as CFString,
            &value
        ) == .success else { return nil }
        return value as? String
    }

    private static func displayContainingMost(of window: CGRect) -> CGRect? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return nil
        }
        var displays = Array(repeating: CGDirectDisplayID(), count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else {
            return nil
        }
        return displays
            .prefix(Int(count))
            .map(CGDisplayBounds)
            .max { lhs, rhs in
                lhs.intersection(window).area < rhs.intersection(window).area
            }
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}
