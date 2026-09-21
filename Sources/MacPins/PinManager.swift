import AppKit
import ApplicationServices

final class PinManager {
    private(set) var pinnedWindows: [CGWindowID: ForeignWindow] = [:]
    private var overlays: [CGWindowID: WindowOverlay] = [:]
    private var readyWindowIDs: Set<CGWindowID> = []
    private var parkedSources: [CGWindowID: SourceWindowParking.Token] = [:]
    private var activationObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var orderingGeneration = 0

    var onChange: (() -> Void)?
    var onNeedsAccessibility: (() -> Void)?
    var onError: ((String) -> Void)?

    var sourceParkingEnabled: Bool {
        UserDefaults.standard.bool(forKey: "parkSourcesAtScreenEdge")
    }

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
        overlay.start()
        onChange?()
    }

    func unpin(windowID: CGWindowID) {
        guard pinnedWindows.removeValue(forKey: windowID) != nil else { return }
        readyWindowIDs.remove(windowID)
        parkedSources.removeValue(forKey: windowID)?.restore()
        overlays.removeValue(forKey: windowID)?.closeOverlay()
        onChange?()
    }

    func unpinAll() {
        parkedSources.values.forEach { $0.restore() }
        parkedSources.removeAll()
        readyWindowIDs.removeAll()
        overlays.values.forEach { $0.closeOverlay() }
        overlays.removeAll()
        pinnedWindows.removeAll()
        onChange?()
    }

    func updateAllSpacesSetting() {
        overlays.values.forEach { $0.updateCollectionBehavior() }
    }

    func setSourceParkingEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "parkSourcesAtScreenEdge")
        if enabled {
            refreshSourceParking(requestPermissionIfNeeded: true)
        } else {
            parkedSources.values.forEach { $0.restore() }
            parkedSources.removeAll()
        }
        onChange?()
    }

    func refreshSourceParking(requestPermissionIfNeeded: Bool = false) {
        guard sourceParkingEnabled else { return }
        guard AXIsProcessTrusted() else {
            if requestPermissionIfNeeded { onNeedsAccessibility?() }
            return
        }

        for id in readyWindowIDs where parkedSources[id] == nil {
            guard let window = pinnedWindows[id],
                  let token = SourceWindowParking.park(window: window) else { continue }
            parkedSources[id] = token
        }
    }

    private func captureBecameReady(windowID: CGWindowID) {
        guard pinnedWindows[windowID] != nil else { return }
        readyWindowIDs.insert(windowID)
        refreshSourceParking()
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
        parkedSources.values.forEach { $0.restore() }
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
        }
    }
}
