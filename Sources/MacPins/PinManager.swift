import AppKit

final class PinManager {
    private(set) var pinnedWindows: [CGWindowID: ForeignWindow] = [:]
    private var overlays: [CGWindowID: WindowOverlay] = [:]
    private var pollTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?

    var onChange: (() -> Void)?
    var onNeedsAccessibility: (() -> Void)?
    var onError: ((String) -> Void)?

    init() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.removeClosedWindows()
        }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            self.updateOverlays(forActivatedPID: app.processIdentifier)
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

        let overlay = WindowOverlay(window: window)
        overlay.onUnpin = { [weak self] in
            self?.unpin(windowID: window.windowID)
        }
        overlay.onNeedsAccessibility = { [weak self] in
            self?.onNeedsAccessibility?()
        }
        overlay.onFailure = { [weak self] message in
            self?.unpin(windowID: window.windowID)
            self?.onError?(message)
        }

        pinnedWindows[window.windowID] = window
        overlays[window.windowID] = overlay
        overlay.start()
        onChange?()
    }

    func unpin(windowID: CGWindowID) {
        guard pinnedWindows.removeValue(forKey: windowID) != nil else { return }
        overlays.removeValue(forKey: windowID)?.closeOverlay()
        onChange?()
    }

    func unpinAll() {
        overlays.values.forEach { $0.closeOverlay() }
        overlays.removeAll()
        pinnedWindows.removeAll()
        onChange?()
    }

    func updateAllSpacesSetting() {
        overlays.values.forEach { $0.updateCollectionBehavior() }
    }

    private func updateOverlays(forActivatedPID pid: pid_t) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard pid != ownPID else { return }

        for (windowID, window) in pinnedWindows {
            if window.ownerPID == pid {
                overlays[windowID]?.sendBehind()
            } else {
                overlays[windowID]?.bringToFront()
            }
        }
    }

    private func removeClosedWindows() {
        let vanished = pinnedWindows.keys.filter { WindowDetector.windowInfo(windowID: $0) == nil }
        vanished.forEach { unpin(windowID: $0) }
    }

    deinit {
        pollTimer?.invalidate()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
        }
    }
}
