import AppKit
import CoreMedia
import IOSurface
import ScreenCaptureKit

/// A live floating view of a window owned by another application.
///
/// macOS does not allow MacPins to change another process's NSWindow level,
/// so the pin is a ScreenCaptureKit surface hosted in a panel MacPins owns.
/// The panel moves independently of the source.  This is important: moving
/// the source and polling its position made older builds visibly trail it.
final class WindowOverlay: NSPanel {
    let targetWindowID: CGWindowID
    let targetPID: pid_t

    var onUnpin: (() -> Void)?
    var onReady: (() -> Void)?
    var onFailure: ((String) -> Void)?

    private let imageLayer = CALayer()
    private let sampleQueue: DispatchQueue
    private let frameLock = NSLock()
    private var captureStream: SCStream?
    private var capturedWindow: SCWindow?
    private var displayedFrame: CVPixelBuffer?
    private var pendingFrame: CVPixelBuffer?
    private var frameDeliveryScheduled = false
    private var streamPixelScale: CGFloat = 2
    private var isRunning = false
    private var didSignalReady = false
    private var recoveryGeneration = 0

    static var pinToAllSpaces: Bool {
        UserDefaults.standard.object(forKey: "pinToAllSpaces") as? Bool ?? true
    }

    init(window: ForeignWindow) {
        targetWindowID = window.windowID
        targetPID = window.ownerPID
        sampleQueue = DispatchQueue(
            label: "app.macpins.capture.\(window.windowID)",
            qos: .userInteractive
        )

        let initialFrame = WindowDetector.appKitFrame(forCGFrame: window.bounds)
        let content = OverlayContentView(frame: CGRect(origin: .zero, size: initialFrame.size))

        super.init(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        animationBehavior = .none
        isMovableByWindowBackground = false
        updateCollectionBehavior()

        content.wantsLayer = true
        content.layer = CALayer()
        content.layer?.backgroundColor = NSColor.black.cgColor
        content.layer?.cornerRadius = 8
        content.layer?.cornerCurve = .continuous
        content.layer?.masksToBounds = true

        imageLayer.frame = content.bounds
        imageLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        imageLayer.contentsGravity = .resize
        imageLayer.contentsScale = screen?.backingScaleFactor ?? 2
        imageLayer.backgroundColor = NSColor.black.cgColor
        imageLayer.minificationFilter = .trilinear
        imageLayer.magnificationFilter = .linear
        content.layer?.addSublayer(imageLayer)

        let badgeSize = CGSize(width: 28, height: 28)
        let badge = PinBadgeView(
            frame: CGRect(
                x: 8,
                y: max(initialFrame.height - badgeSize.height - 8, 0),
                width: badgeSize.width,
                height: badgeSize.height
            )
        )
        badge.autoresizingMask = [.minYMargin]
        badge.onClick = { [weak self] in self?.onUnpin?() }
        content.addSubview(badge)

        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        recoveryGeneration += 1
        resolveAndStart(showInitialFrame: true)
    }

    /// Reassert the panel's global floating order without activating MacPins.
    func ensureOnTop() {
        guard isRunning else { return }
        level = .floating
        orderFrontRegardless()
    }

    func updateCollectionBehavior() {
        var behavior: NSWindow.CollectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .transient,
            .ignoresCycle,
        ]
        if Self.pinToAllSpaces {
            behavior.insert(.canJoinAllSpaces)
        }
        collectionBehavior = behavior
    }

    func closeOverlay() {
        guard isRunning else { return }
        isRunning = false
        recoveryGeneration += 1
        stopStream()
        frameLock.lock()
        pendingFrame = nil
        frameDeliveryScheduled = false
        frameLock.unlock()
        orderOut(nil)
    }

    private func resolveAndStart(showInitialFrame: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.isRunning else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: false
                )
                guard let window = content.windows.first(where: {
                    $0.windowID == self.targetWindowID
                }) else {
                    self.onFailure?("The selected window is no longer available.")
                    return
                }

                self.capturedWindow = window
                let filter = SCContentFilter(desktopIndependentWindow: window)
                self.streamPixelScale = max(CGFloat(filter.pointPixelScale), 1)

                if showInitialFrame {
                    let configuration = self.streamConfiguration()
                    let image = try await SCScreenshotManager.captureImage(
                        contentFilter: filter,
                        configuration: configuration
                    )
                    guard self.isRunning else { return }
                    self.imageLayer.contents = image
                    self.ensureOnTop()
                }

                self.startStream(for: window)
            } catch {
                guard self.isRunning else { return }
                self.onFailure?("MacPins could not capture this window: \(error.localizedDescription)")
            }
        }
    }

    private func startStream(for window: SCWindow) {
        guard isRunning, captureStream == nil else { return }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        streamPixelScale = max(CGFloat(filter.pointPixelScale), 1)
        let stream = SCStream(
            filter: filter,
            configuration: streamConfiguration(),
            delegate: self
        )

        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            captureStream = stream
            stream.startCapture { [weak self] error in
                guard let self, let error else { return }
                DispatchQueue.main.async {
                    guard self.captureStream === stream else { return }
                    self.captureStream = nil
                    self.scheduleRecovery(after: error)
                }
            }
            if !didSignalReady {
                didSignalReady = true
                onReady?()
            }
        } catch {
            scheduleRecovery(after: error)
        }
    }

    private func stopStream() {
        guard let stream = captureStream else { return }
        captureStream = nil
        stream.stopCapture { _ in }
    }

    private func streamConfiguration() -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = max(Int(frame.width * streamPixelScale), 1)
        configuration.height = max(Int(frame.height * streamPixelScale), 1)
        configuration.captureResolution = .best
        configuration.scalesToFit = true
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 5
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        return configuration
    }

    private func updateStreamSize() {
        guard let stream = captureStream else { return }
        stream.updateConfiguration(streamConfiguration()) { _ in }
    }

    private func scheduleRecovery(after lastError: Error) {
        guard isRunning else { return }
        recoveryGeneration += 1
        let generation = recoveryGeneration

        Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<4 {
                try? await Task.sleep(nanoseconds: 750_000_000)
                guard self.isRunning,
                      self.recoveryGeneration == generation,
                      self.captureStream == nil else { return }
                do {
                    let content = try await SCShareableContent.excludingDesktopWindows(
                        false,
                        onScreenWindowsOnly: false
                    )
                    if let window = content.windows.first(where: {
                        $0.windowID == self.targetWindowID
                    }) {
                        self.capturedWindow = window
                        self.startStream(for: window)
                        return
                    }
                } catch {
                    // Retry; display/Space transitions can briefly interrupt enumeration.
                }
            }
            guard self.isRunning, self.recoveryGeneration == generation else { return }
            self.onFailure?(
                "The pinned window closed or its capture stopped: \(lastError.localizedDescription)"
            )
        }
    }

    deinit {
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
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Keep only the newest frame. Enqueuing every frame on the main thread
        // creates a stale-frame backlog whenever the UI is briefly busy, which
        // looks like a low-frame-rate mirror trailing behind the source.
        frameLock.lock()
        pendingFrame = pixelBuffer
        let shouldSchedule = !frameDeliveryScheduled
        frameDeliveryScheduled = true
        frameLock.unlock()

        if shouldSchedule {
            DispatchQueue.main.async { [weak self] in
                self?.displayLatestFrame()
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.captureStream === stream else { return }
            self.captureStream = nil
            self.scheduleRecovery(after: error)
        }
    }
}

private extension WindowOverlay {
    func displayLatestFrame() {
        frameLock.lock()
        let pixelBuffer = pendingFrame
        pendingFrame = nil
        frameDeliveryScheduled = false
        frameLock.unlock()

        guard isRunning,
              let pixelBuffer,
              let surface = CVPixelBufferGetIOSurface(pixelBuffer) else { return }

        displayedFrame = pixelBuffer
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = surface.takeUnretainedValue()
        CATransaction.commit()

    }
}

/// The live pixels are intentionally view-only. A drag moves only the local
/// mirror panel and never activates, moves, or focuses the source application.
private final class OverlayContentView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        NSCursor.closedHand.push()
        window.performDrag(with: event)
        NSCursor.pop()
    }
}

private final class PinBadgeView: NSView {
    var onClick: (() -> Void)?

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
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
