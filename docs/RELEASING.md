# Releasing MacPins

MacPins is distributed outside the Mac App Store. GitHub releases can be made
without a paid Apple Developer Program membership. Those builds are ad-hoc
signed, not notarized, and require the Gatekeeper **Open Anyway** step on first
launch. Always explain that clearly to users.

## Free release process

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`.
2. Build and test both architectures, then package the app:

   ```sh
   MACPINS_CODE_SIGN_IDENTITY=- zsh build-app.sh
   zsh scripts/build-dmg.sh
   ```

3. Create the ZIP and checksums:

   ```sh
   ditto -c -k --sequesterRsrc --keepParent dist/MacPins.app dist/MacPins.zip
   shasum -a 256 dist/MacPins.dmg dist/MacPins.zip > dist/SHA256SUMS.txt
   ```
4. Create and push a version tag, such as `v0.7.6`, after the release commit.
5. Publish a normal GitHub Release with the DMG, ZIP, checksum file, install
   instructions, and an explicit unnotarized-app warning.
6. Download the DMG from GitHub on another Mac or a clean user account and
   verify installation, both permissions, pinning, unpinning, login launch,
   and the Gatekeeper instructions.

## Optional notarized releases later

A lower-friction public release requires a **Developer ID Application**
certificate, hardened runtime, and Apple notarization. This requires the paid
Apple Developer Program. The optional `Optional signed release` GitHub Actions
workflow is manual-only; ordinary version tags do not trigger it.

To use that workflow, create a Developer ID Application certificate, export it
as a password-protected `.p12`, create an app-specific password for notarization,
and set these GitHub repository secrets:

| Secret | Value |
| --- | --- |
| `APPLE_ID` | Apple ID used for notarization |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password |
| `BUILD_CERTIFICATE_BASE64` | Base64-encoded `.p12` certificate |
| `BUILD_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
| `DEVELOPER_ID_APPLICATION` | Full certificate name |
| `KEYCHAIN_PASSWORD` | Strong temporary CI keychain password |

Never commit these values to the repository. Start the workflow manually with
an existing version tag that does not yet have a GitHub release. It builds the
universal app, signs and notarizes it, staples the tickets, and publishes the
downloads.
