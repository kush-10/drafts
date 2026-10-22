import AppKit
import Combine

@main
enum DraftsApplication {
    static func main() {
        let app = NSApplication.shared
        app.appearance = NSAppearance(named: .darkAqua)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let store = NoteStore()
    private let preferences = PreferencesStore()
    private let hotKeys = HotKeyManager()
    private var windows: WindowCoordinator!
    private var statusItem: NSStatusItem?
    private var subscriptions = Set<AnyCancellable>()
    private var cleanupTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        windows = WindowCoordinator(store: store, preferences: preferences, hotKeys: hotKeys)
        installMainMenu()
        installStatusItem()
        hotKeys.onOpen = { [weak self] in self?.windows.openNewestNote() }
        hotKeys.onList = { [weak self] in self?.windows.showFullList() }
        preferences.$value.sink { [weak self] value in
            self?.hotKeys.register(value)
            self?.statusItem?.isVisible = !value.hideMenuBarIcon || self?.hotKeys.error != nil
            // @Published emits before assignment; use the emitted value for immediate window updates.
            self?.windows.scratchpad?.level = value.keepOnTop ? .floating : .normal
        }.store(in: &subscriptions)
        windows.runCleanup()
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.windows.runCleanup() }
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in self?.store.flush() }.store(in: &subscriptions)

        windows.openNewestNote()
        if hotKeys.error != nil { windows.showSettings() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows.openNewestNote()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !store.flush() else { return .terminateNow }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Some changes haven’t been saved"
        alert.informativeText = (store.lastError ?? "Check available disk space and try again.") + " Quitting now will lose unsaved changes."
        alert.addButton(withTitle: "Keep Drafts Open")
        alert.addButton(withTitle: "Quit Without Saving")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "Drafts")
        statusItem?.button?.toolTip = "Drafts — a little room to think"
        let menu = NSMenu()
        menu.addItem(item("Open Note", #selector(openNote)))
        menu.addItem(item("New Blank Note", #selector(newNote)))
        menu.addItem(.separator())
        menu.addItem(item("Full List Editor…", #selector(fullList)))
        menu.addItem(item("Settings…", #selector(settings)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Drafts", #selector(quit)))
        statusItem?.menu = menu
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(findNotes) { return NSApp.keyWindow === windows?.scratchpad && windows?.scratchpad?.isVisible == true }
        if menuItem.action == #selector(copyAndClose) {
            return NSApp.keyWindow === windows?.scratchpad && windows?.scratchpad?.isVisible == true
                && store.note(windows?.workspace.currentID)?.deletedAt == nil && store.note(windows?.workspace.currentID) != nil
        }
        let editorActions: [Selector] = [#selector(bold), #selector(italic), #selector(underline), #selector(bulletList)]
        if let action = menuItem.action, editorActions.contains(action) {
            return activeEditor != nil
        }
        return true
    }

    private func installMainMenu() {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(item("About Drafts", #selector(about)))
        appMenu.addItem(.separator())
        appMenu.addItem(command(.settings, action: #selector(settings)))
        appMenu.addItem(.separator())
        appMenu.addItem(command(.quit, action: #selector(quit)))
        addMenu(appMenu, title: "Drafts", to: main)

        let file = NSMenu(title: "File")
        file.addItem(item("Open Note", #selector(openNote)))
        file.addItem(command(.newNote, action: #selector(newNote)))
        file.addItem(command(.copyAndClose, action: #selector(copyAndClose)))
        file.addItem(.separator())
        file.addItem(item("Full List Editor…", #selector(fullList)))
        file.addItem(item("Close Window", #selector(closeWindow), key: "w"))
        addMenu(file, title: "File", to: main)

        let edit = NSMenu(title: "Edit")
        for (binding, selector) in [
            (LocalCommand.undo, Selector(("undo:"))),
            (.redo, Selector(("redo:"))),
            (.cut, #selector(NSText.cut(_:))),
            (.copy, #selector(NSText.copy(_:))),
            (.paste, #selector(NSText.paste(_:))),
            (.selectAll, #selector(NSText.selectAll(_:)))
        ] {
            let entry = command(binding, action: selector)
            entry.target = nil
            edit.addItem(entry)
        }
        edit.addItem(.separator())
        let find = command(.find, action: #selector(findNotes))
        edit.addItem(find)
        addMenu(edit, title: "Edit", to: main)

        let format = NSMenu(title: "Format")
        format.addItem(command(.bold, action: #selector(bold)))
        format.addItem(command(.italic, action: #selector(italic)))
        format.addItem(command(.underline, action: #selector(underline)))
        format.addItem(command(.bullets, action: #selector(bulletList)))
        addMenu(format, title: "Format", to: main)
        NSApp.mainMenu = main
    }

    private func command(_ binding: LocalCommand, action: Selector) -> NSMenuItem {
        let entry = item(binding.title, action, key: binding.key)
        entry.keyEquivalentModifierMask = binding.modifiers
        return entry
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
    private func addMenu(_ menu: NSMenu, title: String, to parent: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        parent.addItem(item)
    }

    @objc private func openNote() { windows.openNewestNote() }
    @objc private func newNote() { windows.newBlank() }
    @objc private func copyAndClose() { windows.copyAndClose() }
    @objc private func fullList() { windows.showFullList() }
    @objc private func findNotes() { windows.showNotePicker() }
    @objc private func settings() { windows.showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func closeWindow() {
        guard let key = NSApp.keyWindow else { return }
        if key === windows.scratchpad { windows.hideScratchpad() } else { key.performClose(nil) }
    }
    private var activeEditor: EditorBridge? { (NSApp.keyWindow?.firstResponder as? DraftsTextView)?.editorBridge }
    @objc private func bold() { activeEditor?.toggleBold() }
    @objc private func italic() { activeEditor?.toggleItalic() }
    @objc private func underline() { activeEditor?.toggleUnderline() }
    @objc private func bulletList() { activeEditor?.toggleBullets() }
    @objc private func about() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Drafts", .applicationVersion: "0.6.0",
            .credits: NSAttributedString(string: "A minimal, local-only scratchpad.")
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}
