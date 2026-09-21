# MacPins

MacPins is a small DeskPins-style macOS menu-bar utility. It keeps a live view
of a FaceTime, Chrome, or other application window above normal windows.

## Requirements

- macOS 14 Sonoma or later
- Screen Recording permission (required for the live pinned view)
- Accessibility permission (required to park and restore the source window)

## Use

1. Launch `MacPins.app`. Its main window and Dock icon appear, and a pin icon is
   added to the macOS menu bar near the clock.
2. Choose **Pin a Window…**, then click the window to pin.
3. Drag the pinned view to move it smoothly without moving the source window.
4. The pinned view is deliberately view-only. Unpin it when you need to
   interact with the original application.
5. Click the red pin badge, select the checked window in the menu, or choose
   **Unpin All** to remove a pin. The original window returns at the pinned
   view's final position and is brought to the front.

After live capture begins, MacPins moves the original window almost entirely
offscreen. This hides the duplicate and keeps Chromium video rendering when it
would otherwise freeze because the source is fully covered. When unpinned, the
source is restored at the pinned view's final position and size.
If MacPins is force-quit while a source is parked, reopening MacPins restores
the stranded window from a small local recovery record.

Click the main window's yellow minimize button to hide the window and remove
MacPins from the Dock. The menu-bar pin remains available. Opening `MacPins.app`
again restores its window and Dock icon.

The global **Control-Command-P** shortcut toggles the current frontmost window.

## Build

No Xcode project is required. The packaging script creates a universal app for
Apple Silicon and Intel Macs:

```sh
zsh build-app.sh
```

## Technical note

AppKit does not expose a public API that lets one application change another
application window's level. MacPins therefore displays ScreenCaptureKit pixels
in a floating panel it owns. The capture path displays only the latest complete
frame, dropping stale frames rather than queuing them, and targets 60 frames per
second. Synthetic input forwarding and focus handoffs are intentionally absent:
macOS does not provide a reliable public way to address another application's
background window with mouse, trackpad, and keyboard input.

This implementation was initially informed by the public-domain WindowPin
project: https://github.com/PerpetualBeta/WindowPin
