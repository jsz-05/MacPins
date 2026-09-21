import AppKit
import ApplicationServices

final class MainWindowController: NSWindowController, NSWindowDelegate {
    var onPinWindow: (() -> Void)?
    var onHideToMenuBar: (() -> Void)?
    var onUnpinAll: (() -> Void)?
    var onEnableScreenRecording: (() -> Void)?
    var onEnableAccessibility: (() -> Void)?
    var onSetOpenAtLogin: ((Bool) -> Void)?
    var onOpenSupport: (() -> Void)?

    private let pinnedWindowsLabel = NSTextField(labelWithString: "No windows are pinned.")
    private let unpinAllButton = NSButton(title: "Unpin All", target: nil, action: nil)
    private let screenRecordingStatus = NSTextField(labelWithString: "Checking…")
    private let accessibilityStatus = NSTextField(labelWithString: "Checking…")
    private let screenRecordingButton = NSButton(title: "Enable…", target: nil, action: nil)
    private let accessibilityButton = NSButton(title: "Enable…", target: nil, action: nil)
    private let openAtLoginCheckbox = NSButton(
        checkboxWithTitle: "Open MacPins at Login",
        target: nil,
        action: nil
    )
    private let openAtLoginStatus = NSTextField(labelWithString: "Checking…")
    private var permissionTimer: Timer?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 775),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacPins"
        window.minSize = NSSize(width: 560, height: 745)
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace]
        window.center()

        super.init(window: window)
        window.delegate = self
        window.contentViewController = makeContentViewController()
        window.setContentSize(NSSize(width: 600, height: 775))
        window.center()

        let minimizeButton = window.standardWindowButton(.miniaturizeButton)
        minimizeButton?.target = self
        minimizeButton?.action = #selector(hideToMenuBar)

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshPermissions()
            self?.updateLoginItemState(LoginItemManager.state)
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        permissionTimer?.invalidate()
    }

    func show() {
        guard let window else { return }
        refreshPermissions()
        updateLoginItemState(LoginItemManager.state)
        NSApp.setActivationPolicy(.regular)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        window.makeKeyAndOrderFront(nil)
    }

    func updatePinnedWindows(_ windows: [ForeignWindow]) {
        if windows.isEmpty {
            pinnedWindowsLabel.stringValue = "No windows are pinned."
        } else {
            pinnedWindowsLabel.stringValue = windows
                .sorted(by: { $0.displayName < $1.displayName })
                .map { "• \($0.displayName)" }
                .joined(separator: "\n")
        }
        unpinAllButton.isEnabled = !windows.isEmpty
    }

    func updatePermissions(screenRecording: Bool, accessibility: Bool) {
        stylePermissionStatus(screenRecordingStatus, isEnabled: screenRecording)
        screenRecordingButton.isHidden = screenRecording
        stylePermissionStatus(accessibilityStatus, isEnabled: accessibility)
        accessibilityButton.isHidden = accessibility
    }

    func updateLoginItemState(_ state: LoginItemState) {
        openAtLoginCheckbox.isEnabled = state != .unavailable
        switch state {
        case .enabled:
            openAtLoginCheckbox.state = .on
            openAtLoginStatus.stringValue = "Enabled"
            openAtLoginStatus.textColor = .systemGreen
        case .disabled:
            openAtLoginCheckbox.state = .off
            openAtLoginStatus.stringValue = "Off"
            openAtLoginStatus.textColor = .secondaryLabelColor
        case .requiresApproval:
            openAtLoginCheckbox.state = .on
            openAtLoginStatus.stringValue = "Needs approval"
            openAtLoginStatus.textColor = .systemOrange
        case .unavailable:
            openAtLoginCheckbox.state = .off
            openAtLoginStatus.stringValue = "Unavailable"
            openAtLoginStatus.textColor = .secondaryLabelColor
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideToMenuBar()
        return false
    }

    @objc private func hideToMenuBar() {
        window?.orderOut(nil)
        onHideToMenuBar?()
    }

    @objc private func pinWindow() {
        onPinWindow?()
    }

    @objc private func unpinAll() {
        onUnpinAll?()
    }

    @objc private func enableScreenRecording() {
        onEnableScreenRecording?()
    }

    @objc private func enableAccessibility() {
        onEnableAccessibility?()
    }

    @objc private func setOpenAtLogin(_ sender: NSButton) {
        onSetOpenAtLogin?(sender.state == .on)
    }

    @objc private func openSupport() {
        onOpenSupport?()
    }

    private func refreshPermissions() {
        updatePermissions(
            screenRecording: CGPreflightScreenCaptureAccess(),
            accessibility: AXIsProcessTrusted()
        )
    }

    private func stylePermissionStatus(_ label: NSTextField, isEnabled: Bool) {
        label.stringValue = isEnabled ? "Enabled" : "Not enabled"
        label.textColor = isEnabled ? .systemGreen : .systemOrange
    }

    private func makeContentViewController() -> NSViewController {
        let controller = NSViewController()
        let root = NSView()
        controller.view = root

        let iconView = NSImageView(image: AppIcon.bundled())
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "MacPins")
        title.font = .systemFont(ofSize: 30, weight: .bold)
        title.alignment = .center

        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Unknown"
        let versionLabel = NSTextField(labelWithString: "Version \(version)")
        versionLabel.font = .systemFont(ofSize: 10.5)
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.alignment = .center

        let subtitle = NSTextField(
            wrappingLabelWithString: "Keep FaceTime, video, or almost any other window visible above your work."
        )
        subtitle.font = .systemFont(ofSize: 14)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center

        let pinButton = NSButton(
            title: "Pin a Window…",
            target: self,
            action: #selector(pinWindow)
        )
        pinButton.bezelStyle = .rounded
        pinButton.controlSize = .large
        pinButton.keyEquivalent = "\r"

        let shortcut = NSTextField(labelWithString: "or press Control–Command–P")
        shortcut.textColor = .tertiaryLabelColor
        shortcut.font = .systemFont(ofSize: 12)
        shortcut.alignment = .center

        let usage = NSTextField(
            wrappingLabelWithString: "Pinned views are deliberately view-only. Drag anywhere except the red pin to move the mirror. When unpinned, the original window returns at the mirror's final position."
        )
        usage.font = .systemFont(ofSize: 12)
        usage.textColor = .secondaryLabelColor
        usage.alignment = .center

        let pinnedBox = makePinnedBox()
        let permissionsBox = makePermissionsBox()
        let startupBox = makeStartupBox()

        let hiddenBarIsRunning = NSWorkspace.shared.runningApplications.contains {
            $0.localizedName == "Hidden Bar"
        }
        let menuBarNotice = NSTextField(wrappingLabelWithString: hiddenBarIsRunning
            ? "Hidden Bar is currently hiding the MacPins pin. Expand Hidden Bar, then Command-drag the pin into its visible section."
            : "The pin icon remains in the menu bar after this window is hidden.")
        menuBarNotice.textColor = hiddenBarIsRunning ? .systemOrange : .tertiaryLabelColor
        menuBarNotice.font = .systemFont(ofSize: 11, weight: hiddenBarIsRunning ? .medium : .regular)
        menuBarNotice.alignment = .center

        let footer = NSTextField(
            wrappingLabelWithString: "Click the yellow minimize button to hide this window and the Dock icon. MacPins keeps running from the menu-bar pin."
        )
        footer.textColor = .tertiaryLabelColor
        footer.font = .systemFont(ofSize: 11)
        footer.alignment = .center

        let creatorRow = makeCreatorRow()

        let stack = NSStackView(views: [
            iconView,
            title,
            versionLabel,
            subtitle,
            pinButton,
            shortcut,
            usage,
            pinnedBox,
            permissionsBox,
            startupBox,
            menuBarNotice,
            footer,
            creatorRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(12, after: subtitle)
        stack.setCustomSpacing(3, after: title)
        stack.setCustomSpacing(12, after: shortcut)
        stack.setCustomSpacing(12, after: usage)
        stack.setCustomSpacing(12, after: pinnedBox)
        stack.setCustomSpacing(12, after: permissionsBox)
        stack.setCustomSpacing(12, after: startupBox)
        stack.setCustomSpacing(4, after: footer)
        root.addSubview(stack)

        [subtitle, usage, pinnedBox, permissionsBox, startupBox, menuBarNotice, footer]
            .forEach { $0.translatesAutoresizingMaskIntoConstraints = false }

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 58),
            iconView.heightAnchor.constraint(equalToConstant: 58),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 34),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -34),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -18),
            subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
            usage.widthAnchor.constraint(equalTo: stack.widthAnchor),
            pinnedBox.widthAnchor.constraint(equalTo: stack.widthAnchor),
            pinnedBox.heightAnchor.constraint(equalToConstant: 82),
            permissionsBox.widthAnchor.constraint(equalTo: stack.widthAnchor),
            permissionsBox.heightAnchor.constraint(equalToConstant: 150),
            startupBox.widthAnchor.constraint(equalTo: stack.widthAnchor),
            startupBox.heightAnchor.constraint(equalToConstant: 84),
            menuBarNotice.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        return controller
    }

    private func makeCreatorRow() -> NSView {
        let credit = NSTextField(labelWithString: "By \(AppLinks.creatorName)")
        credit.font = .systemFont(ofSize: 11)
        credit.textColor = .tertiaryLabelColor

        let separator = NSTextField(labelWithString: "•")
        separator.font = .systemFont(ofSize: 11)
        separator.textColor = .tertiaryLabelColor

        let support = NSButton(
            title: "Support on Ko-fi",
            target: self,
            action: #selector(openSupport)
        )
        support.isBordered = false
        support.font = .systemFont(ofSize: 11, weight: .medium)
        support.contentTintColor = .systemPink
        support.image = NSImage(
            systemSymbolName: "heart.fill",
            accessibilityDescription: "Support"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        )
        support.imagePosition = .imageLeading

        let row = NSStackView(views: [credit, separator, support])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return row
    }

    private func makePinnedBox() -> NSBox {
        let heading = NSTextField(labelWithString: "Pinned windows")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)

        pinnedWindowsLabel.maximumNumberOfLines = 3
        pinnedWindowsLabel.lineBreakMode = .byTruncatingTail
        pinnedWindowsLabel.textColor = .secondaryLabelColor

        unpinAllButton.target = self
        unpinAllButton.action = #selector(unpinAll)
        unpinAllButton.bezelStyle = .inline
        unpinAllButton.isEnabled = false

        let row = NSStackView(views: [pinnedWindowsLabel, unpinAllButton])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 12
        pinnedWindowsLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        unpinAllButton.setContentHuggingPriority(.required, for: .horizontal)

        return boxedView(heading: heading, bodyViews: [row])
    }

    private func makePermissionsBox() -> NSBox {
        let heading = NSTextField(labelWithString: "Permissions")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)

        screenRecordingButton.target = self
        screenRecordingButton.action = #selector(enableScreenRecording)
        screenRecordingButton.bezelStyle = .rounded
        screenRecordingButton.controlSize = .small
        accessibilityButton.target = self
        accessibilityButton.action = #selector(enableAccessibility)
        accessibilityButton.bezelStyle = .rounded
        accessibilityButton.controlSize = .small

        let screen = permissionRow(
            title: "Screen Recording",
            detail: "Required for live window pixels. MacPins never saves video.",
            status: screenRecordingStatus,
            button: screenRecordingButton
        )
        let accessibility = permissionRow(
            title: "Accessibility",
            detail: "Required to park the source and restore it at the pin's final position.",
            status: accessibilityStatus,
            button: accessibilityButton
        )
        return boxedView(heading: heading, bodyViews: [screen, accessibility])
    }

    private func makeStartupBox() -> NSBox {
        let heading = NSTextField(labelWithString: "Startup")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)

        openAtLoginCheckbox.target = self
        openAtLoginCheckbox.action = #selector(setOpenAtLogin(_:))
        openAtLoginCheckbox.font = .systemFont(ofSize: 12, weight: .medium)

        let explanation = NSTextField(
            labelWithString: "Launch MacPins automatically after you sign in."
        )
        explanation.font = .systemFont(ofSize: 10.5)
        explanation.textColor = .secondaryLabelColor
        let labels = NSStackView(views: [openAtLoginCheckbox, explanation])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1

        openAtLoginStatus.font = .systemFont(ofSize: 11, weight: .medium)
        openAtLoginStatus.setContentHuggingPriority(.required, for: .horizontal)
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [labels, openAtLoginStatus])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return boxedView(heading: heading, bodyViews: [row])
    }

    private func permissionRow(
        title: String,
        detail: String,
        status: NSTextField,
        button: NSButton
    ) -> NSView {
        let name = NSTextField(labelWithString: title)
        name.font = .systemFont(ofSize: 12, weight: .medium)
        let explanation = NSTextField(labelWithString: detail)
        explanation.font = .systemFont(ofSize: 10.5)
        explanation.textColor = .secondaryLabelColor
        let labels = NSStackView(views: [name, explanation])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1

        status.font = .systemFont(ofSize: 11, weight: .medium)
        button.setContentHuggingPriority(.required, for: .horizontal)
        status.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [labels, status, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    private func boxedView(heading: NSTextField, bodyViews: [NSView]) -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.borderWidth = 1
        box.cornerRadius = 9
        box.borderColor = .separatorColor
        box.fillColor = .controlBackgroundColor

        let content = NSView()
        box.contentView = content
        heading.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(heading)

        let body = NSStackView(views: bodyViews)
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 8
        body.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(body)

        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: content.topAnchor, constant: 9),
            heading.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -12),
            body.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 7),
            body.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            body.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            body.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -9),
        ])

        for view in bodyViews {
            view.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        }
        return box
    }
}
