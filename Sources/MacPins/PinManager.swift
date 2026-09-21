import AppKit
import ApplicationServices

final class PinManager {
    private(set) var pinnedWindows: [CGWindowID: ForeignWindow] = [:]
    private var overlays: [CGWindowID: WindowOverlay] = [:]
    private var parkedSources: [CGWindowID: SourceWindowParking.Token] = [:]
    private var pinOrder: [CGWindowID] = []
    private var activationObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var orderingGeneration = 0

    var onChange: (() -> Void)?
    var onNeedsAccessibility: (() -> Void)?
    var onError: ((String) -> Void)?

    init() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reassertOverlayOrder()
        }

        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            let ids = self.pinnedWindows.values
                .filter { $0.ownerPID == app.processIdentifier }
                .map(\.windowID)
            ids.forEach { self.unpin(windowID: $0) }
        }
    }

    func toggle(window: ForeignWindow) {
        if pinnedWindows[window.windowID] != nil {
            unpin(windowID: window.windowID)
        } else {
            pin(window: window)
        }
    }

    func pin(window: ForeignWindow) {
        guard pinnedWindows[window.windowID] == nil else { return }
        guard AXIsProcessTrusted() else {
            onNeedsAccessibility?()
            return
        }

        let overlay = WindowOverlay(window: window)
        overlay.onUnpin = { [weak self] in
            self?.unpin(windowID: window.windowID)
        }
        overlay.onReady = { [weak self] in
            self?.captureBecameReady(windowID: window.windowID)
        }
        overlay.onFailure = { [weak self] message in
            self?.unpin(windowID: window.windowID)
            self?.onError?(message)
        }

        pinnedWindows[window.windowID] = window
        overlays[window.windowID] = overlay
        pinOrder.append(window.windowID)
        overlay.start()
        onChange?()
    }

    func unpin(windowID: CGWindowID) {
        guard pinnedWindows.removeValue(forKey: windowID) != nil else { return }
        pinOrder.removeAll { $0 == windowID }
        let overlay = overlays.removeValue(forKey: windowID)
        let destination = overlay.map {
            WindowDetector.cgFrame(forAppKitFrame: $0.frame)
        }
        parkedSources.removeValue(forKey: windowID)?.restore(
            to: destination,
            bringToFront: true
        )
        overlay?.closeOverlay()
        onChange?()
    }

    func unpinAll(bringToFront: Bool = true) {
        let frontWindowID = bringToFront ? pinOrder.last : nil
        for (id, token) in parkedSources {
            let destination = overlays[id].map {
                WindowDetector.cgFrame(forAppKitFrame: $0.frame)
            }
            token.restore(
                to: destination,
                bringToFront: id == frontWindowID
            )
        }
        parkedSources.removeAll()
        pinOrder.removeAll()
        overlays.values.forEach { $0.closeOverlay() }
        overlays.removeAll()
        pinnedWindows.removeAll()
        onChange?()
    }

    func updateAllSpacesSetting() {
        overlays.values.forEach { $0.updateCollectionBehavior() }
    }

    private func captureBecameReady(windowID: CGWindowID) {
        guard parkedSources[windowID] == nil,
              let window = pinnedWindows[windowID] else { return }
        guard AXIsProcessTrusted() else {
            unpin(windowID: windowID)
            onNeedsAccessibility?()
            return
        }
        guard let token = SourceWindowParking.park(window: window) else {
            unpin(windowID: windowID)
            onError?(
                "This application would not allow its window to be parked at the screen edge, so MacPins removed the pin without moving the source."
            )
            return
        }
        parkedSources[windowID] = token
        reassertOverlayOrder()
    }

    private func reassertOverlayOrder() {
        orderingGeneration += 1
        let generation = orderingGeneration
        overlays.values.forEach { $0.ensureOnTop() }

        // App activation can finish its ordering transaction after this
        // notification. Reassert on the next turn so ordinary windows do not
        // jump above a pin.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, self.orderingGeneration == generation else { return }
            self.overlays.values.forEach { $0.ensureOnTop() }
        }
    }

    deinit {
        for (id, token) in parkedSources {
            let destination = overlays[id].map {
                WindowDetector.cgFrame(forAppKitFrame: $0.frame)
            }
            token.restore(to: destination, bringToFront: false)
        }
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
        }
    }
}
