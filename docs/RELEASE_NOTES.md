## Drafts v0.7.0 — public preview

A minimal, dark, translucent scratchpad for macOS 14+.

### New

- **⌘F** now expands the notepad to fill the current display's usable area. Press it again to restore the previous size and position, keeping your text, selection, and undo history. This does not enter a separate macOS full-screen Space.
- **⌘L** now opens the integrated searchable note list (previously ⌘F). Both shortcuts work while its search field is focused. The footer, menus, and Settings show the new bindings.
- Switching apps/windows or clicking outside now **saves and hides** the notepad and integrated list, without swallowing the click or stealing focus back. The separate full-list editor and Settings stay open until closed normally.

### Safety and polish

- Failed saves keep the note and pending changes open. Error sheets are protected from automatic dismissal, with no duplicate error dialogs.
- Reopening a hidden note starts at the usual compact 760 × 500 size; the global **⌥Space** show/hide toggle is preserved.
- Integrated-list selection stays in the same window, including when expanded. Blank-draft reuse, copy-and-close, formatting, and opt-in retention are unchanged.
- The About version now comes directly from the app bundle to prevent version drift. Existing notes and settings are preserved.

### Install or update

Download **Drafts-0.7.0-universal.dmg**, quit an older copy, drag Drafts into Applications, eject the disk image, then launch Drafts from Applications. A ZIP is also available. Both Apple Silicon and Intel are included; macOS 14+ is required. GitHub's “Source code” archives are not installers.

**This preview is ad-hoc signed and not Apple-notarized.** macOS may block the first launch. After attempting to open it, use **System Settings → Privacy & Security → Open Anyway**, then confirm Open, only if you trust the official download. Do not disable Gatekeeper. See the README for full instructions and checksum verification.

Drafts lives in the menu bar, not the Dock. **⌥Space** opens a note and saves/hides it on the next press. **⌘,** opens Settings, including the option to hide or restore the menu-bar icon. If an older custom global shortcut uses the now-reserved **⌘L**, choose another binding in Settings; the icon stays visible if registration fails.

### Data and limitations

Notes stay on your Mac. There is no account, sync, networking, clipboard monitoring, or global typing monitoring. Mouse-down/focus events are observed only while the notepad is visible to detect outside interactions; they are not recorded. No Accessibility permission is required.

Auto-delete is off by default. If enabled, hiding also applies the existing permanent last-edit retention policy, including Trash. Back up important notes.

Both CPU architectures are built and verified; runtime tests run on Apple Silicon, not physical Intel hardware. Spaces, full-screen apps, multiple displays, and older supported macOS versions need broader real-world testing. No automatic updater is included.
