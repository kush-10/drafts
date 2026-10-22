## Drafts v0.6.1 — public preview

A minimal, dark, translucent scratchpad for macOS 14+.

### Fixed

- The global open shortcut (default **⌥Space**) now toggles the notepad: press once to show the newest-created note, then again to save and hide it.
- Toggling while the in-window picker is open hides both the picker and note. Reopening returns to the editor without creating duplicate blank drafts.
- Hiding uses the existing safe-save and opt-in cleanup behavior. If saving fails, the note stays open with its pending edits intact.
- Settings and installation instructions now describe the shortcut as **Show / hide notepad**. Menu **Open Note**, launching, and reopening from Applications still always open the note.

### Included

- Universal app for Apple Silicon and Intel Macs.
- Floating, fixed-size notepad with automatic local saving.
- In-window note picker with `⌘F`, arrows, and Return.
- `⇧⌘C` copies the entire draft as text and hides the notepad.
- New Note reuses blank drafts rather than creating duplicates.
- Separate sortable table editor and basic bold / italic / underline / bullets.
- Optional **Hide menu bar icon** setting; `⌥Space` still opens Drafts and `⌘,` opens Settings.
- Simple storage choice: keep everything, or opt into permanent deletion after a custom last-edit interval. Keep everything is the default.
- MIT-licensed source and reproducible packaging scripts.

### Install

Download **Drafts-0.6.1-universal.dmg**, open it, drag Drafts into Applications, eject the disk image, then launch Drafts from Applications. Quit an older copy before replacing it; existing notes and settings are preserved. A ZIP is also available. Do not use GitHub’s “Source code” archives unless you intend to build the app.

**This preview is ad-hoc signed and not Apple-notarized.** macOS may block the first launch. After attempting to open it, use **System Settings → Privacy & Security → Open Anyway**, then confirm Open, only if you trust this download. Do not disable Gatekeeper. See the README for full instructions and checksum verification.

Drafts normally lives in the menu bar, not the Dock. Press **⌥Space** to open a note and again to save and hide it. If you hide the menu-bar icon, reopen Drafts from Applications or use the shortcut, then **⌘,** to restore it.

### Data and limitations

Notes stay on your Mac. There is no account, sync, network access, or clipboard monitoring. Auto-delete is off by default; if enabled, it permanently deletes expired notes, including Trash. Back up irreplaceable notes.

This is an early preview. Both CPU architectures are built and verified; runtime tests were run on Apple Silicon, not physical Intel hardware. Full-screen apps, Spaces, multiple displays, and older supported macOS versions need broader real-world testing. No automatic updater is included.
