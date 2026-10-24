# Distribution guide

## What is published

- The public repository contains source, tests, documentation, MIT license, and packaging scripts.
- GitHub Releases contain a universal `.dmg`, a `.zip`, SHA-256 checksums, and `release-info.json` describing signing and notarization.
- A DMG contains `Drafts.app`, an Applications shortcut, installation instructions, and the license. The ZIP contains the app bundle.
- Neither source nor downloads contain anyone’s notes, preferences, signing certificates, or credentials.

The current release is a **preview**, ad-hoc signed and **not notarized**. Ad-hoc signatures verify bundle integrity but do not establish a developer identity trusted by Gatekeeper. Do not describe this as Developer ID signed, notarized, or App Store approved.

## Build release assets

Use a Mac with Xcode 15+ / Swift 5.9+ and the command-line tools selected. No third-party build tools are required.

```sh
swift test
./scripts/package-release.sh
```

The script reads the version from `Support/Info.plist`, builds both Apple Silicon and Intel slices, verifies the app signature and architectures, creates and verifies the DMG, and writes artifacts into `dist/releases/v<VERSION>/`. It stages a separate app so it does not overwrite a locally running `dist/Drafts.app`.

It refuses to overwrite an existing version’s release assets. Bump `CFBundleShortVersionString` and `CFBundleVersion` for a new release, and update README download links, `Support/Install.txt`, and release notes. The About panel reads its version directly from the app bundle.

To build just the universal app locally:

```sh
UNIVERSAL=1 ./scripts/build-app.sh
```

## Proper Apple signing and notarization

A normal public macOS release needs an Apple Developer Program membership, a **Developer ID Application** certificate with its private key, and working notarization credentials. An **Apple Development** certificate is not a substitute for Developer ID distribution signing.

Keep certificates and secrets out of Git. Store notarization credentials in the macOS keychain using `xcrun notarytool store-credentials`; see Apple’s documentation for the Apple ID / app-specific password or App Store Connect key options. Do not paste credentials into issues or commits.

Once the Developer ID identity and keychain profile are available:

```sh
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARYTOOL_PROFILE='drafts-notary' \
./scripts/package-release.sh
```

This enables hardened runtime and timestamped signing, submits the app to Apple, staples its ticket before ZIP/DMG packaging, and then notarizes and staples the DMG too. The script stops if submission or validation fails. A configured identity alone does **not** imply successful notarization; check `release-info.json`.

Until that is configured, install instructions must disclose the preview’s Gatekeeper warning and describe the per-app **System Settings → Privacy & Security → Open Anyway** flow. Never advise disabling Gatekeeper globally or bypassing an administrator’s policy.

## Publish a version

After tests and packages have been verified and committed:

```sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Support/Info.plist)
git tag -a "v$VERSION" -m "Drafts v$VERSION"
git push origin main --follow-tags
gh release create "v$VERSION" dist/releases/"v$VERSION"/* \
  --verify-tag --prerelease \
  --title "Drafts v$VERSION — preview" \
  --notes-file docs/RELEASE_NOTES.md
```

Use `--prerelease` while shipping ad-hoc-signed previews. Do not replace already published artifacts with different bytes under the same version. For a notarized stable release, update the release notes and installation documentation, verify the signing metadata, and omit `--prerelease`.

GitHub Actions runs tests and produces preview packages for pushes and pull requests. It does **not** automatically publish a release or have access to Apple signing secrets.
