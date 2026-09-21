import AppKit
import ApplicationServices

/// Moves a source window almost entirely beyond the right edge of its current
/// display. Keeping a few pixels onscreen prevents Chromium from treating the
/// window as fully occluded, while the ScreenCaptureKit mirror continues to
/// capture the complete window.
enum SourceWindowParking {
    private static let recoveryDefaultsKey = "sourceWindowRecoveryRecords"

    private struct RecoveryRecord: Codable {
        let windowID: UInt32
        let ownerPID: Int32
        let ownerName: String
        let bundleIdentifier: String?
        let title: String
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        let bootTime: Double

        var frame: CGRect {
            CGRect(x: x, y: y, width: width, height: height)
        }

        mutating func setFrame(_ frame: CGRect) {
            x = frame.origin.x
            y = frame.origin.y
            width = frame.width
            height = frame.height
        }
    }

    final class Token {
        private let windowID: CGWindowID
        private let ownerPID: pid_t
        private let element: AXUIElement
        private let originalPosition: CGPoint
        private let originalSize: CGSize
        private var hasRestored = false

        fileprivate init(
            windowID: CGWindowID,
            ownerPID: pid_t,
            element: AXUIElement,
            originalPosition: CGPoint,
            originalSize: CGSize
        ) {
            self.windowID = windowID
            self.ownerPID = ownerPID
            self.element = element
            self.originalPosition = originalPosition
            self.originalSize = originalSize
        }

        func restore(
            to targetFrame: CGRect? = nil,
            bringToFront: Bool = false
        ) {
            guard !hasRestored else { return }
            hasRestored = true
            let destination = targetFrame ?? CGRect(
                origin: originalPosition,
                size: originalSize
            )
            SourceWindowParking.updateRecovery(
                windowID: windowID,
                destination: destination
            )
            SourceWindowParking.setSize(destination.size, on: element)
            if SourceWindowParking.setPosition(destination.origin, on: element) {
                SourceWindowParking.removeRecovery(windowID: windowID)
            }
            if bringToFront {
                SourceWindowParking.bringToFront(
                    ownerPID: ownerPID,
                    element: element
                )
            }
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
        saveRecovery(
            for: target,
            destination: CGRect(origin: originalPosition, size: originalSize)
        )
        guard setPosition(parkedPosition, on: element),
              let actualPosition = pointAttribute(kAXPositionAttribute, of: element) else {
            removeRecovery(windowID: target.windowID)
            return nil
        }

        let actualBounds = CGRect(origin: actualPosition, size: originalSize)
        let visibleWidth = actualBounds.intersection(displayBounds).width
        guard abs(actualPosition.x - originalPosition.x) > 20,
              visibleWidth <= 48 else {
            setPosition(originalPosition, on: element)
            removeRecovery(windowID: target.windowID)
            return nil
        }

        return Token(
            windowID: target.windowID,
            ownerPID: target.ownerPID,
            element: element,
            originalPosition: originalPosition,
            originalSize: originalSize
        )
    }

    /// Restores windows left at the screen edge if MacPins was force-quit or
    /// crashed before normal unpin cleanup could run.
    static func restoreStrandedSources() {
        guard AXIsProcessTrusted() else { return }
        var records = loadRecoveryRecords()
        let currentBootTime = bootTime

        for (key, record) in records {
            guard abs(record.bootTime - currentBootTime) < 10 else {
                records.removeValue(forKey: key)
                continue
            }
            guard let application = NSRunningApplication(
                processIdentifier: record.ownerPID
            ),
            application.bundleIdentifier == record.bundleIdentifier,
            let current = WindowDetector.windowInfo(windowID: record.windowID) else {
                records.removeValue(forKey: key)
                continue
            }

            let target = ForeignWindow(
                windowID: record.windowID,
                ownerPID: record.ownerPID,
                ownerName: record.ownerName,
                title: record.title,
                bounds: current.bounds
            )
            let appElement = AXUIElementCreateApplication(record.ownerPID)
            guard let element = matchingWindow(
                in: appElement,
                target: target,
                currentBounds: current.bounds
            ) else { continue }

            setSize(record.frame.size, on: element)
            if setPosition(record.frame.origin, on: element) {
                records.removeValue(forKey: key)
            }
        }
        saveRecoveryRecords(records)
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

    private static func bringToFront(ownerPID: pid_t, element: AXUIElement) {
        guard let application = NSRunningApplication(
            processIdentifier: ownerPID
        ) else { return }
        application.activate(options: [.activateAllWindows])
        let appElement = AXUIElementCreateApplication(ownerPID)
        AXUIElementSetAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            element
        )
        AXUIElementSetAttributeValue(
            element,
            kAXMainAttribute as CFString,
            kCFBooleanTrue
        )
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
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

    private static var bootTime: Double {
        Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
    }

    private static func saveRecovery(for target: ForeignWindow, destination: CGRect) {
        var records = loadRecoveryRecords()
        let bundleIdentifier = NSRunningApplication(
            processIdentifier: target.ownerPID
        )?.bundleIdentifier
        records[String(target.windowID)] = RecoveryRecord(
            windowID: target.windowID,
            ownerPID: target.ownerPID,
            ownerName: target.ownerName,
            bundleIdentifier: bundleIdentifier,
            title: target.title,
            x: destination.origin.x,
            y: destination.origin.y,
            width: destination.width,
            height: destination.height,
            bootTime: bootTime
        )
        saveRecoveryRecords(records)
    }

    private static func updateRecovery(windowID: CGWindowID, destination: CGRect) {
        var records = loadRecoveryRecords()
        guard var record = records[String(windowID)] else { return }
        record.setFrame(destination)
        records[String(windowID)] = record
        saveRecoveryRecords(records)
    }

    private static func removeRecovery(windowID: CGWindowID) {
        var records = loadRecoveryRecords()
        records.removeValue(forKey: String(windowID))
        saveRecoveryRecords(records)
    }

    private static func loadRecoveryRecords() -> [String: RecoveryRecord] {
        guard let data = UserDefaults.standard.data(forKey: recoveryDefaultsKey),
              let records = try? JSONDecoder().decode(
                [String: RecoveryRecord].self,
                from: data
              ) else { return [:] }
        return records
    }

    private static func saveRecoveryRecords(_ records: [String: RecoveryRecord]) {
        if records.isEmpty {
            UserDefaults.standard.removeObject(forKey: recoveryDefaultsKey)
            return
        }
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: recoveryDefaultsKey)
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}
