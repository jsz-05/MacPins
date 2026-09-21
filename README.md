<p align="center">
  <img src="assets/app-icon.png" width="128" alt="MacPins app icon">
</p>

<h1 align="center">MacPins</h1>

<p align="center">
  Keep FaceTime, videos, and almost any other macOS window visible above your work.
</p>

<p align="center">
  <a href="https://github.com/jsz-05/MacPins/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/jsz-05/MacPins?style=flat-square"></a>
  <a href="https://github.com/jsz-05/MacPins/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/jsz-05/MacPins/total?style=flat-square"></a>
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-blue?style=flat-square"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-black?style=flat-square&logo=apple">
  <a href="https://ko-fi.com/jeffreyszhou"><img alt="Support on Ko-fi" src="https://img.shields.io/badge/Ko--fi-Support-ff5e5b?style=flat-square&logo=ko-fi&logoColor=white"></a>
</p>

MacPins is a lightweight, open-source DeskPins-style utility for macOS. Pick a
window and MacPins creates a smooth, always-on-top live view that stays visible
while you work in other apps.

## Features

- Pin FaceTime, Chrome, video players, and most standard macOS windows.
- Smooth 60 FPS live views using ScreenCaptureKit.
- Drag a pin anywhere without revealing the parked source window.
- Restore the original window at the pin's final position when unpinned.
- Automatically bring the original window to the front after unpinning.
- Pin across Spaces when desired.
- Launch automatically at login using the native macOS login-item API.
- Control MacPins from a compact menu-bar icon or `Control-Command-P`.
- Recover source windows safely if MacPins is force-quit while they are parked.

## Install

1. Open the [latest release](https://github.com/jsz-05/MacPins/releases/latest)
   and download `MacPins.dmg`.
2. Open the disk image and drag `MacPins.app` into Applications.
3. Open MacPins and approve **Screen Recording** and **Accessibility** when
   prompted.
4. Choose **Pin a Window…** from the app or menu-bar pin, then click a window.

The universal build supports both Apple silicon and Intel Macs. **The current
download is ad-hoc signed and not notarized.** On first launch, macOS may block
it. If you trust this project's source and download, first try opening the app,
then go to **System Settings → Privacy & Security → Open Anyway**. This is a
one-time Gatekeeper step for the current distribution method.

## How to use it

Pinned views are intentionally view-only. Drag the pinned view to move it, then
click the red pin badge or use the menu-bar menu to unpin it before interacting
with the original app. This design avoids unreliable synthetic mouse, trackpad,
and keyboard forwarding on macOS.

MacPins parks the source window almost entirely offscreen while it is pinned.
That removes the distracting duplicate while keeping Chromium-based video
rendering active. The source returns at the pinned view's final position and is
brought to the front when you unpin it.

## Permissions

| Permission | Why MacPins needs it |
| --- | --- |
| Screen Recording | Supplies the live pixels for the pinned view. MacPins never records or saves video. |
| Accessibility | Parks, restores, positions, and raises the source window. |

All capture and window management happen locally on your Mac. MacPins has no
analytics, accounts, or network service.

## Build from source

Requirements:

- macOS 14 Sonoma or newer
- Xcode Command Line Tools

```sh
git clone https://github.com/jsz-05/MacPins.git
cd MacPins
swift build
zsh build-app.sh
```

The packaging script creates `dist/MacPins.app` as a universal Apple
silicon/Intel application. It uses a Developer ID or Apple Development identity
when one is available and otherwise falls back to ad-hoc signing for local
builds.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development details and
[docs/RELEASING.md](docs/RELEASING.md) for the release process.

## Support

MacPins is free and open source. If it makes your day a little easier, you can
[support future apps on Ko-fi](https://ko-fi.com/jeffreyszhou)—but it is never
expected.

## Acknowledgments

The first prototype was informed by the public-domain
[WindowPin](https://github.com/PerpetualBeta/WindowPin) project. MacPins now uses
its own ScreenCaptureKit-based view-only architecture.

## License

MacPins is available under the [MIT License](LICENSE).

Created by [Jeffrey Zhou](https://github.com/jsz-05).
