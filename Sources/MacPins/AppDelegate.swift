import AppKit
import ApplicationServices
import Carbon

private let hotKeySignature: OSType = 0x4D50494E // "MPIN"
private let hotKeyID: UInt32 = 1

private func hotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { delegate.toggleFrontmostWindow() }
    return noErr
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let pinManager = PinManager()
    private let windowSelector = WindowSelector()
    private var mainWindowController: MainWindowController?
    private var statusItem: NSStatusItem?
    private var hotKey: EventHotKeyRef?
    private var hotKeyEventHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = AppIcon.bundled()
        createStatusItem()
        registerHotKey()

        let mainWindowController = MainWindowController()
        mainWindowController.onPinWindow = { [weak self] in self?.beginWindowSelection() }
        mainWindowController.onHideToMenuBar = { [weak self] in self?.hideToMenuBar() }
        mainWindowController.onUnpinAll = { [weak self] in self?.pinManager.unpinAll() }
        mainWindowController.onEnableAccessibility = { [weak self] in
            self?.requestAccessibilityPermission()
        }
        mainWindowController.onEnableScreenRecording = { [weak self] in
            self?.requestScreenRecordingPermission()
        }
        mainWindowController.onSetSourceParking = { [weak self] enabled in
            self?.pinManager.setSourceParkingEnabled(enabled)
        }
        self.mainWindowController = mainWindowController

        pinManager.onChange = { [weak self] in
            self?.updateStatusIcon()
            self?.updateMainWindow()
        }
        pinManager.onNeedsAccessibility = { [weak self] in
            self?.requestAccessibilityPermission()
        }
        pinManager.onError = { [weak self] message in self?.showError(message) }
        updateMainWindow()
        mainWindowController.show()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        pinManager.refreshSourceParking()
        updateMainWindow()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        DispatchQueue.main.async { [weak self] in self?.showMainWindow() }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowSelector.cancel(notify: false)
        pinManager.unpinAll()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyEventHandler { RemoveEventHandler(hotKeyEventHandler) }
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.isVisible = true
        item.button?.toolTip = "MacPins — keep any window on top"
        item.button?.title = ""
        item.button?.imagePosition = .imageOnly
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        let symbol = pinManager.pinnedWindows.isEmpty ? "pin" : "pin.fill"
        statusItem?.button?.image = makeStatusIcon(symbolName: symbol)
        statusItem?.isVisible = true
    }

    private func makeStatusIcon(symbolName: String) -> NSImage {
        let canvasSize = NSSize(width: 26, height: 26)
        let symbolSize: CGFloat = 18.75
        let image = NSImage(size: canvasSize, flipped: false) { rect in
            guard let context = NSGraphicsContext.current,
                  let symbol = NSImage(
                    systemSymbolName: symbolName,
                    accessibilityDescription: "MacPins"
                  )?.withSymbolConfiguration(
                    NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .regular)
                  ) else { return false }

            context.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX, yBy: rect.midY - 1)
            transform.rotate(byDegrees: -45)
            transform.translateX(by: -rect.midX, yBy: -rect.midY)
            transform.concat()

            symbol.isTemplate = true
            NSColor.black.set()
            let symbolRect = NSRect(
                x: (rect.width - symbolSize) / 2,
                y: (rect.height - symbolSize) / 2,
                width: symbolSize,
                height: symbolSize
            )
            symbol.draw(in: symbolRect)
            context.restoreGraphicsState()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "MacPins"
        return image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Unknown"
        let versionItem = NSMenuItem(
            title: "MacPins \(version)",
            action: nil,
            keyEquivalent: ""
        )
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        addItem(to: menu, title: "Open MacPins", action: #selector(showMainWindow))
        menu.addItem(.separator())
        addItem(to: menu, title: "Pin a Window…", action: #selector(beginWindowSelection))
        let shortcut = NSMenuItem(title: "Toggle Frontmost Window   ⌃⌘P", action: nil, keyEquivalent: "")
        shortcut.isEnabled = false
        menu.addItem(shortcut)

        if !pinManager.pinnedWindows.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: "Pinned Windows", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for window in pinManager.pinnedWindows.values.sorted(by: { $0.displayName < $1.displayName }) {
                let item = addItem(
                    to: menu,
                    title: window.displayName,
                    action: #selector(unpinMenuItem(_:))
                )
                item.state = .on
                item.representedObject = NSNumber(value: window.windowID)
            }
            addItem(to: menu, title: "Unpin All", action: #selector(unpinAll))
        }

        menu.addItem(.separator())
        let allSpaces = addItem(
            to: menu,
            title: "Show Pins on All Spaces",
            action: #selector(toggleAllSpaces(_:))
        )
        allSpaces.state = WindowOverlay.pinToAllSpaces ? .on : .off
        let parkSources = addItem(
            to: menu,
            title: "Park Sources at Screen Edge (Experimental)",
            action: #selector(toggleSourceParking(_:))
        )
        parkSources.state = pinManager.sourceParkingEnabled ? .on : .off
        addItem(to: menu, title: "Permissions…", action: #selector(showMainWindow))

        menu.addItem(.separator())
        addItem(to: menu, title: "About MacPins", action: #selector(showAbout))
        addItem(to: menu, title: "Quit MacPins", action: #selector(quit), keyEquivalent: "q")
    }

    @discardableResult
    private func addItem(
        to menu: NSMenu,
        title: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func beginWindowSelection() {
        guard !windowSelector.isSelecting else { return }
        guard screenCapturePermissionIsAvailable() else { return }
        mainWindowController?.window?.orderOut(nil)
        windowSelector.begin { [weak self] window in
            guard let self else { return }
            guard let window else {
                self.showMainWindow()
                return
            }
            self.toggle(window: window)
            self.hideToMenuBar()
        }
    }

    func toggleFrontmostWindow() {
        guard let window = WindowDetector.frontmostForeignWindow() else {
            showError("MacPins could not find a frontmost window to pin.")
            return
        }
        toggle(window: window)
    }

    private func toggle(window: ForeignWindow) {
        if pinManager.pinnedWindows[window.windowID] != nil {
            pinManager.unpin(windowID: window.windowID)
            return
        }

        guard screenCapturePermissionIsAvailable() else { return }
        pinManager.pin(window: window)
    }

    @objc private func unpinMenuItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? NSNumber else { return }
        pinManager.unpin(windowID: id.uint32Value)
    }

    @objc private func unpinAll() {
        pinManager.unpinAll()
    }

    @objc private func toggleAllSpaces(_ sender: NSMenuItem) {
        let enabled = !WindowOverlay.pinToAllSpaces
        UserDefaults.standard.set(enabled, forKey: "pinToAllSpaces")
        pinManager.updateAllSpacesSetting()
    }

    @objc private func toggleSourceParking(_ sender: NSMenuItem) {
        pinManager.setSourceParkingEnabled(!pinManager.sourceParkingEnabled)
    }

    private func requestAccessibilityPermission() {
        guard !AXIsProcessTrusted() else {
            updateMainWindow()
            return
        }
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        updateMainWindow()
        openPrivacyPane("Privacy_Accessibility")
    }

    private func requestScreenRecordingPermission() {
        if !CGPreflightScreenCaptureAccess(), !CGRequestScreenCaptureAccess() {
            openPrivacyPane("Privacy_ScreenCapture")
        }
        updateMainWindow()
    }

    private func screenCapturePermissionIsAvailable() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        if CGRequestScreenCaptureAccess() {
            updateMainWindow()
            return true
        }

        openPrivacyPane("Privacy_ScreenCapture")
        showError(
            "Screen Recording is required to display a live pinned window. Enable MacPins in Privacy & Security → Screen & System Audio Recording, then reopen MacPins."
        )
        return false
    }

    private func openPrivacyPane(_ pane: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func showAbout() {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Unknown"
        let alert = NSAlert()
        alert.messageText = "MacPins \(version)"
        alert.informativeText = "A small DeskPins-style menu-bar utility for macOS.\n\n"
            + "Click the menu-bar pin and choose Pin a Window, or press Control-Command-P. "
            + "The pinned view is intentionally view-only: drag it to move the mirror and "
            + "click the red badge to unpin. The optional source-parking mode can hide the "
            + "duplicate source and help Chromium video keep rendering."
        alert.alertStyle = .informational
        present(alert)
    }

    @objc private func showMainWindow() {
        mainWindowController?.show()
    }

    private func hideToMenuBar() {
        NSApp.setActivationPolicy(.accessory)
        statusItem?.isVisible = true
    }

    private func updateMainWindow() {
        mainWindowController?.updatePinnedWindows(Array(pinManager.pinnedWindows.values))
        mainWindowController?.updatePermissions(
            screenRecording: CGPreflightScreenCaptureAccess(),
            accessibility: AXIsProcessTrusted()
        )
        mainWindowController?.updateSourceParking(enabled: pinManager.sourceParkingEnabled)
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "MacPins"
        alert.informativeText = message
        alert.alertStyle = .warning
        present(alert)
    }

    private func present(_ alert: NSAlert) {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func registerHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyEventHandler
        )

        let identifier = EventHotKeyID(signature: hotKeySignature, id: hotKeyID)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_P),
            UInt32(controlKey | cmdKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
    }
}
