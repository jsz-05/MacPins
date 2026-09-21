import AppKit
import ApplicationServices

enum EventForwarder {
    private static let eventSource = CGEventSource(stateID: .combinedSessionState)

    static func forward(_ event: NSEvent, from overlay: WindowOverlay) {
        guard let targetPoint = mapToTarget(event: event, overlay: overlay) else { return }

        if event.type == .scrollWheel {
            postScroll(event, at: targetPoint, windowID: overlay.targetWindowID, pid: overlay.targetPID)
        } else {
            postMouse(event, at: targetPoint, windowID: overlay.targetWindowID, pid: overlay.targetPID)
        }
    }

    private static func mapToTarget(event: NSEvent, overlay: WindowOverlay) -> CGPoint? {
        guard let target = WindowDetector.windowInfo(windowID: overlay.targetWindowID) else { return nil }
        let size = overlay.frame.size
        guard size.width > 0, size.height > 0 else { return nil }

        let location = event.locationInWindow
        let fractionX = location.x / size.width
        let fractionYFromTop = (size.height - location.y) / size.height

        return CGPoint(
            x: target.bounds.minX + fractionX * target.bounds.width,
            y: target.bounds.minY + fractionYFromTop * target.bounds.height
        )
    }

    private static func postMouse(
        _ event: NSEvent,
        at point: CGPoint,
        windowID: CGWindowID,
        pid: pid_t
    ) {
        guard let (type, button) = mouseType(for: event),
              let cgEvent = CGEvent(
                mouseEventSource: eventSource,
                mouseType: type,
                mouseCursorPosition: point,
                mouseButton: button
              ) else { return }

        cgEvent.flags = flags(from: event.modifierFlags)
        cgEvent.setIntegerValueField(.mouseEventClickState, value: Int64(max(event.clickCount, 1)))
        address(cgEvent, to: windowID, pid: pid)
        cgEvent.postToPid(pid)
    }

    private static func postScroll(
        _ event: NSEvent,
        at point: CGPoint,
        windowID: CGWindowID,
        pid: pid_t
    ) {
        let units: CGScrollEventUnit = event.hasPreciseScrollingDeltas ? .pixel : .line
        guard let cgEvent = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: units,
            wheelCount: 2,
            wheel1: steps(event.scrollingDeltaY),
            wheel2: steps(event.scrollingDeltaX),
            wheel3: 0
        ) else { return }

        cgEvent.location = point
        cgEvent.flags = flags(from: event.modifierFlags)
        if event.hasPreciseScrollingDeltas {
            cgEvent.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            cgEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: event.scrollingDeltaY)
            cgEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: event.scrollingDeltaX)
        }
        address(cgEvent, to: windowID, pid: pid)
        cgEvent.postToPid(pid)
    }

    private static func address(_ event: CGEvent, to windowID: CGWindowID, pid: pid_t) {
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))
        event.setIntegerValueField(
            .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
            value: Int64(windowID)
        )

        // These routing fields are not named in the public SDK, but are needed
        // for background AppKit windows to accept a specifically addressed event.
        if let targetWindowField = CGEventField(rawValue: 51) {
            event.setIntegerValueField(targetWindowField, value: Int64(windowID))
        }
        if let routingField = CGEventField(rawValue: 58) {
            event.setIntegerValueField(routingField, value: 1)
        }
    }

    private static func mouseType(for event: NSEvent) -> (CGEventType, CGMouseButton)? {
        switch event.type {
        case .leftMouseDown: return (.leftMouseDown, .left)
        case .leftMouseUp: return (.leftMouseUp, .left)
        case .leftMouseDragged: return (.leftMouseDragged, .left)
        case .rightMouseDown: return (.rightMouseDown, .right)
        case .rightMouseUp: return (.rightMouseUp, .right)
        case .rightMouseDragged: return (.rightMouseDragged, .right)
        case .otherMouseDown: return (.otherMouseDown, .center)
        case .otherMouseUp: return (.otherMouseUp, .center)
        case .otherMouseDragged: return (.otherMouseDragged, .center)
        default: return nil
        }
    }

    private static func flags(from modifiers: NSEvent.ModifierFlags) -> CGEventFlags {
        var result: CGEventFlags = []
        if modifiers.contains(.command) { result.insert(.maskCommand) }
        if modifiers.contains(.control) { result.insert(.maskControl) }
        if modifiers.contains(.option) { result.insert(.maskAlternate) }
        if modifiers.contains(.shift) { result.insert(.maskShift) }
        return result
    }

    private static func steps(_ delta: CGFloat) -> Int32 {
        if delta == 0 { return 0 }
        let rounded = Int32(delta.rounded())
        return rounded == 0 ? (delta > 0 ? 1 : -1) : rounded
    }
}
