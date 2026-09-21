import AppKit
import ApplicationServices
import CoreMedia
import IOSurface
import ScreenCaptureKit

final class WindowOverlay: NSPanel {
    let targetWindowID: CGWindowID
    let targetPID: pid_t

    var onUnpin: (() -> Void)?
    var onNeedsAccessibility: (() -> Void)?
    var onFailure: ((String) -> Void)?

    private let contentLayer = CALayer()
    private let pinBadge = PinBadgeView(frame: CGRect(x: 8, y: 8, width: 28, height: 28))
    private let sampleQueue: DispatchQueue
    private var scWindow: SCWindow?
    private var captureStream: SCStream?
    private var displayedFrame: CVPixelBuffer?
    private var syncTimer: Timer?
    private var streamPixelScale: CGFloat = 2
    private var lastStreamSize: CGSize = .zero
    private(set) var isPinVisible = false

    static var pinToAllSpaces: Bool {
        UserDefaults.standard.object(forKey: "pinToAllSpaces") as? Bool ?? true
    }

    static var forwardEvents: Bool {
        UserDefaults.standard.object(forKey: "forwardEvents") as? Bool ?? true
    }

    init(window: ForeignWindow) {
        targetWindowID = window.windowID
        targetPID = window.ownerPID
        sampleQueue = DispatchQueue(label: "app.macpins.capture.\(window.windowID)")

        let initialFrame = WindowDetector.appKitFrame(forCGFrame: window.bounds)
        super.init(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        collectionBehavior = Self.pinToAllSpaces
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            : [.fullScreenAuxiliary]

        let root = NSView(frame: CGRect(origin: .zero, size: initialFrame.size))
        root.wantsLayer = true
        contentLayer.frame = root.bounds
        contentLayer.contentsGravity = .resize
        contentLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        root.layer?.addSublayer(contentLayer)

        pinBadge.frame.origin = CGPoint(x: 8, y: max(initialFrame.height - 36, 0))
        pinBadge.autoresizingMask = [.minYMargin]
        root.addSubview(pinBadge)
        contentView = root
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func start() {
        guard captureStream == nil else { return }
        isPinVisible = true
        syncFrameWithTarget()

        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: false
                )
                guard let window = content.windows.first(where: { $0.windowID == targetWindowID }) else {
                    onFailure?("The selected window is no longer available.")
                    return
                }
                guard isPinVisible else { return }
                scWindow = window
                try await showInitialFrame(for: window)
                startStream(for: window)
                startFrameSync()
            } catch {
                onFailure?("MacPins could not capture this window: \(error.localizedDescription)")
            }
        }
    }

    func bringToFront() {
        guard !isPinVisible else { return }
        isPinVisible = true
        syncFrameWithTarget()
        level = .floating
        orderFront(nil)
        if let scWindow { startStream(for: scWindow) }
        startFrameSync()
    }

    func sendBehind() {
        guard isPinVisible else { return }
        isPinVisible = false
        stopStream()
        stopFrameSync()
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.normalWindow)) - 1)
        orderBack(nil)
    }

    func closeOverlay() {
        isPinVisible = false
        stopStream()
        stopFrameSync()
        orderOut(nil)
    }

    func updateCollectionBehavior() {
        collectionBehavior = Self.pinToAllSpaces
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            : [.fullScreenAuxiliary]
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, pinBadge.frame.contains(event.locationInWindow) {
            onUnpin?()
            return
        }

        guard isPinVisible, Self.forwardEvents else {
            super.sendEvent(event)
            return
        }

        switch event.type {
        case .leftMouseDown where event.modifierFlags.contains(.command):
            activateRealWindow()
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged,
             .rightMouseDown, .rightMouseUp, .rightMouseDragged,
             .otherMouseDown, .otherMouseUp, .otherMouseDragged,
             .scrollWheel:
            guard AXIsProcessTrusted() else {
                onNeedsAccessibility?()
                return
            }
            EventForwarder.forward(event, from: self)
        default:
            super.sendEvent(event)
        }
    }

    private func activateRealWindow() {
        sendBehind()
        guard let runningApp = NSRunningApplication(processIdentifier: targetPID) else { return }
        runningApp.activate(options: [.activateAllWindows])
        raiseMatchingAccessibilityWindow()
    }

    private func raiseMatchingAccessibilityWindow() {
        guard AXIsProcessTrusted(),
              let target = WindowDetector.windowInfo(windowID: targetWindowID) else { return }

        let app = AXUIElementCreateApplication(targetPID)
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }

        for window in windows {
            var positionValue: AnyObject?
            var sizeValue: AnyObject?
            guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
                  AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
                  let positionAX = positionValue as! AXValue?,
                  let sizeAX = sizeValue as! AXValue? else { continue }
            var position = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(positionAX, .cgPoint, &position)
            AXValueGetValue(sizeAX, .cgSize, &size)
            if abs(position.x - target.bounds.minX) < 5,
               abs(position.y - target.bounds.minY) < 5,
               abs(size.width - target.bounds.width) < 5,
               abs(size.height - target.bounds.height) < 5 {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                return
            }
        }
    }

    private func showInitialFrame(for window: SCWindow) async throws {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        streamPixelScale = max(CGFloat(filter.pointPixelScale), 1)
        let configuration = streamConfiguration(scale: streamPixelScale)
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        guard isPinVisible else { return }
        contentLayer.contents = image
        level = .floating
        alphaValue = 0
        orderFront(nil)
        await NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 1
        }
    }

    private func startStream(for window: SCWindow) {
        guard captureStream == nil, isPinVisible else { return }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        streamPixelScale = max(CGFloat(filter.pointPixelScale), 1)
        lastStreamSize = frame.size
        let stream = SCStream(
            filter: filter,
            configuration: streamConfiguration(scale: streamPixelScale),
            delegate: self
        )
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            captureStream = stream
            stream.startCapture { [weak self] error in
                guard let error else { return }
                DispatchQueue.main.async {
                    guard self?.captureStream === stream else { return }
                    self?.captureStream = nil
                    self?.onFailure?("The capture stream stopped: \(error.localizedDescription)")
                }
            }
        } catch {
            onFailure?("MacPins could not start the capture stream: \(error.localizedDescription)")
        }
    }

    private func stopStream() {
        guard let stream = captureStream else { return }
        captureStream = nil
        stream.stopCapture { _ in }
    }

    private func streamConfiguration(scale: CGFloat) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = max(Int(frame.width * scale), 1)
        configuration.height = max(Int(frame.height * scale), 1)
        configuration.captureResolution = .best
        configuration.scalesToFit = true
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 4
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        return configuration
    }

    private func startFrameSync() {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.syncFrameWithTarget()
        }
    }

    private func stopFrameSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    private func syncFrameWithTarget() {
        guard let target = WindowDetector.windowInfo(windowID: targetWindowID) else { return }
        let nextFrame = WindowDetector.appKitFrame(forCGFrame: target.bounds)
        if frame != nextFrame {
            setFrame(nextFrame, display: false)
        }

        guard let stream = captureStream,
              abs(nextFrame.width - lastStreamSize.width) > 1
                || abs(nextFrame.height - lastStreamSize.height) > 1 else { return }
        lastStreamSize = nextFrame.size
        stream.updateConfiguration(streamConfiguration(scale: streamPixelScale)) { _ in }
    }

    deinit {
        syncTimer?.invalidate()
        captureStream?.stopCapture { _ in }
    }
}

extension WindowOverlay: SCStreamOutput, SCStreamDelegate {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: false
              ) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int,
              status == SCFrameStatus.complete.rawValue,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let surface = CVPixelBufferGetIOSurface(pixelBuffer) else { return }

        let retainedSurface = surface.takeUnretainedValue()
        DispatchQueue.main.async { [weak self] in
            self?.displayedFrame = pixelBuffer
            self?.contentLayer.contents = retainedSurface
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard self?.captureStream === stream else { return }
            self?.captureStream = nil
            self?.onFailure?("The capture stream stopped: \(error.localizedDescription)")
        }
    }
}

private final class PinBadgeView: NSView {
    override var isOpaque: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()

        if let symbol = NSImage(
            systemSymbolName: "pin.fill",
            accessibilityDescription: "Unpin window"
        ) {
            let configured = symbol.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            ) ?? symbol
            configured.isTemplate = true
            NSColor.white.set()
            configured.draw(in: bounds.insetBy(dx: 6, dy: 6))
        }
    }
}
