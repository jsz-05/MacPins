# Contributing to MacPins

Thanks for helping improve MacPins. Bug reports, focused fixes, documentation,
and accessibility improvements are all welcome.

## Development setup

You need macOS 14 or newer and the Xcode Command Line Tools.

```sh
git clone https://github.com/jsz-05/MacPins.git
cd MacPins
swift build
```

Create a universal app bundle with:

```sh
MACPINS_CODE_SIGN_IDENTITY=- zsh build-app.sh
```

The resulting app is written to `dist/MacPins.app` and is ad-hoc signed for
local testing. Your first local build may need separate Screen Recording and
Accessibility approval because macOS permissions are tied to code identity.

## Pull requests

- Keep changes focused and explain the user-visible behavior.
- Build with warnings treated as errors before opening a pull request:

  ```sh
  swift build -Xswiftc -warnings-as-errors
  ```

- Test on at least one supported macOS version.
- Include before/after screenshots for visible UI changes.
- Never commit signing certificates, Apple credentials, provisioning profiles,
  or notarization passwords.

## Architecture

MacPins uses AppKit and ScreenCaptureKit without third-party runtime
dependencies. `WindowSelector` identifies the selected foreign window,
`PinManager` owns active pins, `WindowOverlay` displays the latest captured
frame, and `SourceWindowParking` handles safe parking and restoration.

Pinned views are deliberately view-only. Please do not add synthetic input
forwarding without first demonstrating reliable behavior across Chrome,
FaceTime, trackpads, keyboard focus, Spaces, and minimized windows.
