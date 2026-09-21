import AppKit

final class MainWindowController: NSWindowController, NSWindowDelegate {
    var onPinWindow: (() -> Void)?
    var onHideToMenuBar: (() -> Void)?
    var onUnpinAll: (() -> Void)?

    private let pinnedWindowsLabel = NSTextField(labelWithString: "No windows are pinned.")
    private let unpinAllButton = NSButton(
        title: "Unpin All",
        target: nil,
        action: nil
    )

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacPins"
        window.minSize = NSSize(width: 520, height: 470)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
        window.contentViewController = makeContentViewController()
        window.setContentSize(NSSize(width: 560, height: 500))
        window.center()

        let minimizeButton = window.standardWindowButton(.miniaturizeButton)
        minimizeButton?.target = self
        minimizeButton?.action = #selector(hideToMenuBar)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
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

        let subtitle = NSTextField(
            wrappingLabelWithString: "Keep FaceTime or almost any other window visible above your work."
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

        let pinnedHeading = NSTextField(labelWithString: "Pinned windows")
        pinnedHeading.font = .systemFont(ofSize: 13, weight: .semibold)

        pinnedWindowsLabel.maximumNumberOfLines = 4
        pinnedWindowsLabel.lineBreakMode = .byTruncatingTail
        pinnedWindowsLabel.textColor = .secondaryLabelColor

        unpinAllButton.target = self
        unpinAllButton.action = #selector(unpinAll)
        unpinAllButton.bezelStyle = .inline
        unpinAllButton.isEnabled = false

        let pinnedRow = NSStackView(views: [pinnedWindowsLabel, unpinAllButton])
        pinnedRow.orientation = .horizontal
        pinnedRow.alignment = .top
        pinnedRow.spacing = 12
        pinnedWindowsLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        unpinAllButton.setContentHuggingPriority(.required, for: .horizontal)

        let pinnedBox = NSBox()
        pinnedBox.boxType = .custom
        pinnedBox.borderWidth = 1
        pinnedBox.cornerRadius = 9
        pinnedBox.borderColor = .separatorColor
        pinnedBox.fillColor = .controlBackgroundColor

        let pinnedBoxContent = NSView()
        pinnedBox.contentView = pinnedBoxContent
        pinnedHeading.translatesAutoresizingMaskIntoConstraints = false
        pinnedRow.translatesAutoresizingMaskIntoConstraints = false
        pinnedBoxContent.addSubview(pinnedHeading)
        pinnedBoxContent.addSubview(pinnedRow)

        NSLayoutConstraint.activate([
            pinnedHeading.topAnchor.constraint(equalTo: pinnedBoxContent.topAnchor, constant: 10),
            pinnedHeading.leadingAnchor.constraint(equalTo: pinnedBoxContent.leadingAnchor, constant: 12),
            pinnedHeading.trailingAnchor.constraint(lessThanOrEqualTo: pinnedBoxContent.trailingAnchor, constant: -12),
            pinnedRow.topAnchor.constraint(equalTo: pinnedHeading.bottomAnchor, constant: 8),
            pinnedRow.leadingAnchor.constraint(equalTo: pinnedBoxContent.leadingAnchor, constant: 12),
            pinnedRow.trailingAnchor.constraint(equalTo: pinnedBoxContent.trailingAnchor, constant: -12),
            pinnedRow.bottomAnchor.constraint(lessThanOrEqualTo: pinnedBoxContent.bottomAnchor, constant: -10),
        ])

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
            wrappingLabelWithString: "Click the yellow minimize button to hide this window and the Dock icon. MacPins will keep running from the menu-bar pin."
        )
        footer.textColor = .tertiaryLabelColor
        footer.font = .systemFont(ofSize: 11)
        footer.alignment = .center

        let stack = NSStackView(views: [
            iconView,
            title,
            subtitle,
            pinButton,
            shortcut,
            pinnedBox,
            menuBarNotice,
            footer,
        ])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(14, after: subtitle)
        stack.setCustomSpacing(14, after: shortcut)
        stack.setCustomSpacing(12, after: pinnedBox)
        root.addSubview(stack)

        pinnedBox.translatesAutoresizingMaskIntoConstraints = false
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        menuBarNotice.translatesAutoresizingMaskIntoConstraints = false
        footer.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 68),
            iconView.heightAnchor.constraint(equalToConstant: 68),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 34),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -34),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -20),
            pinnedBox.widthAnchor.constraint(equalTo: stack.widthAnchor),
            pinnedBox.heightAnchor.constraint(equalToConstant: 88),
            subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
            menuBarNotice.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        return controller
    }
}
