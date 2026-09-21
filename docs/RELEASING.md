# Releasing MacPins

MacPins is distributed outside the Mac App Store. A low-friction public release
must be signed with a **Developer ID Application** certificate, use the hardened
runtime, and be notarized by Apple. An Apple Development signature is suitable
for local development but not public distribution.

## One-time setup

1. Join the paid Apple Developer Program.
2. Create a Developer ID Application certificate and export it as a password-
   protected `.p12` file.
3. Create an app-specific password for the Apple ID used for notarization.
4. Add these GitHub Actions repository secrets:

   | Secret | Value |
   | --- | --- |
   | `APPLE_ID` | Apple ID used for notarization |
   | `APPLE_TEAM_ID` | Ten-character Apple Developer Team ID |
   | `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password |
   | `BUILD_CERTIFICATE_BASE64` | Base64-encoded `.p12` certificate |
   | `BUILD_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
   | `DEVELOPER_ID_APPLICATION` | Full certificate name, such as `Developer ID Application: Name (TEAMID)` |
   | `KEYCHAIN_PASSWORD` | A strong temporary CI keychain password |

Never commit these values to the repository.

## Publish a release

Preview builds without Developer ID credentials can be built locally with
`MACPINS_CODE_SIGN_IDENTITY=- zsh build-app.sh` and
`zsh scripts/build-dmg.sh`. Publish them only as GitHub pre-releases with a
`-preview` tag and clearly state that they are not notarized. Preview tags are
excluded from the signed release workflow.

For a full release:

Update `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`, merge
the release commit, then create and push a matching tag:

```sh
git tag v0.7.6
git push origin v0.7.6
```

The `Signed release` workflow builds a universal app, signs it with Developer
ID, submits both the app and DMG to Apple's notarization service, staples the
tickets, creates checksums, and publishes the artifacts as a GitHub Release.

Before announcing a release, download the DMG from GitHub on a different Mac
or a clean user account and verify installation, both permissions, pinning,
unpinning, login launch, and Gatekeeper acceptance.
