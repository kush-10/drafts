# Contributing

Keep Drafts small, native, local-only, and keyboard-first. Open an issue before proposing a large feature or adding dependencies.

## Development

Requires macOS 14+ and Xcode 15+ / Swift 5.9+.

```sh
swift test
./scripts/build-app.sh debug
open dist/Drafts.app
```

Quit an older running app before launching another copy. Test note creation, blank reuse, save/hide/reopen, ⌘F expansion/restoration, the ⌘L integrated list, outside-click and focus-loss saving, clipboard copy, and the separate table. Use temporary directories and a uniquely named pasteboard in automated tests, never real notes or the user’s clipboard.

Add regression tests for fixes. Keep changes focused, preserve existing note contents and settings during migrations, and document any changes to deletion behavior. Automatic deletion must remain opt-in and clearly disclosed.

## Pull requests and reports

- Describe the behavior changed and how it was tested.
- Include macOS version and architecture for platform issues.
- Screenshots should contain synthetic data only.
- Never commit notes, build output, certificates, private keys, or credentials.
- Contributions are provided under the repository’s MIT license.

Release packaging and Apple signing are documented in [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md). GitHub Actions packages are development previews, not Apple-approved distribution builds.
