## Drafts v0.9.1 — public preview

A minimal, translucent scratchpad for macOS 14+. Apple Silicon and Intel are included; optional local AI requires Apple Silicon.

### New since v0.7.0

- **Optional on-device AI topics:** download and select an MLX model in Settings. No server, API key, or bundled model weights. Downloads are explicit and checksum-verified.
- **Topic organisation:** automatic analysis after successful saves, cancellable organisation of existing notes, manual overrides, and optional memory based on human-confirmed examples. Note text is never rewritten.
- **Quick topic assignment:** type `/Topic` while writing. Search note text and topics with **⌘K**, or **⌥⇧K** from any app. Search never runs AI.
- **Integrated All notes:** **⌥⇧L** opens the notes table in the notepad, with filtering, sorting, multiple selection, batch topic actions, Trash, and restore.
- **Appearance and settings:** twenty themes, font and size controls with live previews, and settings grouped into focused sections.
- **Writing improvements:** a draggable top bar, improved caret visibility, configurable global shortcuts, and remembered window size.
- **Self-contained packages:** the native MLX helper, Metal resources, and Swift compatibility libraries are included. Xcode is not required to run the app.

### Changed window behaviour

Switching apps or clicking outside now **keeps the notepad open**. Use **⌥Space**, Escape, or Copy & close to save and hide. **⌘F** still expands/restores the window. Size and expanded state are remembered for 30 minutes by default, adjustable in Settings.

**⌘K** is search; **⌥⇧L** is All notes. **⌘L** is no longer bound. Reopening chooses the most recently edited active note.

### Install or update

Download **Drafts-0.9.1-universal.dmg**, quit an older copy, and drag Drafts into Applications. Eject the disk image and launch Drafts from Applications. A ZIP, `SHA256SUMS.txt`, and `release-info.json` are also available. GitHub's “Source code” archives are not installers. There is no automatic updater.

**This preview is ad-hoc signed and not Apple-notarized.** If macOS blocks the official download and you trust it, first try opening the app, then use **System Settings → Privacy & Security → Open Anyway**. Never disable Gatekeeper, bypass a managed Mac's restrictions, or override malware or damaged-app warnings. See the [installation guide](https://github.com/kush-10/drafts/blob/main/docs/GUIDE.md#install) for details and checksum verification.

Drafts lives in the menu bar, not the Dock. **⌥Space** shows the notepad and saves/hides it on the next press; **⌘,** opens Settings.

### Data and limitations

- Notes and topic analysis stay on your Mac. Network access is used only for model downloads you request. No accounts, sync, analytics, clipboard monitoring, or Accessibility permission.
- Notes, manual topic choices, preferences, and downloaded models remain separate from the app bundle. Back up `~/Library/Application Support/Drafts/Notes/`, including its hidden `.drafts/` subfolder.
- Automatic deletion is off by default. If enabled, expired notes are permanently deleted, including Trash.
- Local AI is Apple Silicon only. Physical Intel hardware, Spaces, full-screen apps, multiple displays, and older supported macOS versions need broader testing.
