import AppKit

final class WindowSelector {
    private var windows: [SelectionPanel] = []
    private var completion: ((ForeignWindow?) -> Void)?

    var isSelecting: Bool { !windows.isEmpty }

    func begin(completion: @escaping (ForeignWindow?) -> Void) {
        cancel(notify: false)
        self.completion = completion

        windows = NSScreen.screens.map { screen in
            let panel = SelectionPanel(screen: screen)
            panel.onMove = { [weak self] point in
                self?.updateHighlight(at: point)
            }
            panel.onPick = { [weak self] point in
                self?.finish(with: WindowDetector.window(atAppKitPoint: point))
            }
            panel.onCancel = { [weak self] in
                self?.cancel(notify: true)
            }
            panel.orderFrontRegardless()
            return panel
        }
    }

    func cancel(notify: Bool = true) {
        guard !windows.isEmpty || completion != nil else { return }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        let callback = completion
        completion = nil
        if notify { callback?(nil) }
    }

    private func updateHighlight(at point: CGPoint) {
        let window = WindowDetector.window(atAppKitPoint: point)
        let appKitFrame = window.map { WindowDetector.appKitFrame(forCGFrame: $0.bounds) }
        windows.forEach { $0.selectionView.highlightedGlobalFrame = appKitFrame }
    }

    private func finish(with window: ForeignWindow?) {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        let callback = completion
        completion = nil
        callback?(window)
    }
}

private final class SelectionPanel: NSPanel {
    let selectionView: SelectionView
    var onMove: ((CGPoint) -> Void)? {
        didSet { selectionView.onMove = onMove }
    }
    var onPick: ((CGPoint) -> Void)? {
        didSet { selectionView.onPick = onPick }
    }
    var onCancel: (() -> Void)? {
        didSet { selectionView.onCancel = onCancel }
    }

    init(screen: NSScreen) {
        selectionView = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.001)
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = selectionView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class SelectionView: NSView {
    var onMove: ((CGPoint) -> Void)?
    var onPick: ((CGPoint) -> Void)?
    var onCancel: (() -> Void)?

    var highlightedGlobalFrame: CGRect? {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseMoved(with event: NSEvent) {
        guard let window else { return }
        onMove?(window.convertPoint(toScreen: event.locationInWindow))
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        onPick?(window.convertPoint(toScreen: event.locationInWindow))
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if let globalFrame = highlightedGlobalFrame, let window {
            let local = CGRect(
                x: globalFrame.minX - window.frame.minX,
                y: globalFrame.minY - window.frame.minY,
                width: globalFrame.width,
                height: globalFrame.height
            )
            NSColor.systemRed.withAlphaComponent(0.12).setFill()
            NSBezierPath(rect: local).fill()
            NSColor.systemRed.setStroke()
            let path = NSBezierPath(rect: local.insetBy(dx: 2, dy: 2))
            path.lineWidth = 4
            path.stroke()
        }

        let message = "Click a window to pin  •  Right-click to cancel"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = message.size(withAttributes: attributes)
        let menuBarInset: CGFloat
        if let screen = window?.screen {
            menuBarInset = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        } else {
            menuBarInset = 38
        }
        let panelHeight = size.height + 16
        let panelRect = CGRect(
            x: (bounds.width - size.width) / 2 - 18,
            y: bounds.height - panelHeight - menuBarInset - 12,
            width: size.width + 36,
            height: panelHeight
        )
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: panelRect, xRadius: 10, yRadius: 10).fill()
        message.draw(
            at: CGPoint(x: panelRect.minX + 18, y: panelRect.minY + 8),
            withAttributes: attributes
        )
    }
}
