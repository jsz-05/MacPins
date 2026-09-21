# MacPins

MacPins is a small DeskPins-style macOS menu-bar utility. It pins a live mirror
of almost any application window above other windows, including FaceTime.

## Requirements

- macOS 14 Sonoma or later
- Screen & System Audio Recording permission (required for the live mirror)
- Accessibility permission (optional, required for forwarding clicks/scrolls)

## Use

1. Launch `MacPins.app`. Its main window and Dock icon appear, and a standalone
   pin icon is also added to the macOS menu bar near the clock.
2. Choose **Pin a Window…**, then click the window to pin.
3. Grant Screen Recording permission when macOS asks. If prompted to relaunch,
   quit and reopen MacPins, then pin the window again.
4. Click the red pin badge on a mirror, select its checked menu item, or choose
   **Unpin All** to remove a pin.

Click the main window's yellow minimize button to hide the window and remove
MacPins from the Dock. The menu-bar pin remains available. Opening `MacPins.app`
again restores its window and Dock icon.

The global **Control-Command-P** shortcut toggles the current frontmost window.
Command-clicking a mirror switches to the original window. Pinned mirrors follow
their original windows and can appear across Spaces.

## Build

No Xcode project is required. The packaging script creates a universal app for
Apple Silicon and Intel Macs:

```sh
zsh build-app.sh
```

## Technical note

macOS does not expose a public API that lets one app change the window level of
another app. MacPins therefore uses ScreenCaptureKit to draw a live copy inside
a floating `NSPanel`. Mouse event forwarding uses Core Graphics event routing
and may vary between applications; keyboard input intentionally remains in the
active app.

This implementation was informed by the public-domain WindowPin project:
https://github.com/PerpetualBeta/WindowPin
