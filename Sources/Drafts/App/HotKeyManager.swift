import AppKit
import Carbon
import Combine
import SwiftUI

final class HotKeyManager: ObservableObject {
    @Published private(set) var error: String?
    var onOpen: (() -> Void)?
    var onList: (() -> Void)?
    var onSearch: (() -> Void)?
    private var references: [Int: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private var shortcuts: [Shortcut] = []
    private let signature: OSType = 0x44524654
    private var registrationFailures: [Int: String] = [:]
    private var latestPreferences: Preferences?
    private(set) var isRecording = false

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr else { return status }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
            guard identifier.signature == manager.signature else { return OSStatus(eventNotHandledErr) }
            return manager.handleHotKey(identifier.id) ? noErr : OSStatus(eventNotHandledErr)
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if status != noErr { error = "Couldn’t install global shortcuts (\(status)). You can still use the menu bar." }
    }

    func register(_ preferences: Preferences) {
        latestPreferences = preferences
        guard !isRecording else { return }
        guard handler != nil else { return }
        let paths = [\Preferences.openShortcut, \.listShortcut, \.searchShortcut]
        let conflicts = paths.compactMap { preferences.shortcutConflict(preferences[keyPath: $0], replacing: $0) }
        guard conflicts.isEmpty else { error = conflicts.joined(separator: "\n"); return }
        let oldShortcuts = shortcuts
        shortcuts = preferences.shortcuts
        let changed = shortcuts.indices.filter { references[$0] == nil || !oldShortcuts.indices.contains($0) || !shortcuts[$0].hasSameBinding(as: oldShortcuts[$0]) }
        // Release changed bindings together, allowing two actions to swap bindings without a false conflict.
        for index in changed {
            if let reference = references.removeValue(forKey: index) { UnregisterEventHotKey(reference) }
            registrationFailures.removeValue(forKey: index)
        }
        let names = ["Show / hide notepad", "All notes", "Search notes"]
        for index in changed {
            let shortcut = shortcuts[index]
            var reference: EventHotKeyRef?
            let identifier = EventHotKeyID(signature: signature, id: UInt32(index + 1))
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, identifier, GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference { references[index] = reference }
            else { registrationFailures[index] = "\(names[index]): \(shortcut.label) is unavailable (\(status)). Choose another shortcut." }
        }
        error = registrationFailures.isEmpty ? nil : registrationFailures.sorted { $0.key < $1.key }.map(\.value).joined(separator: "\n")
    }

    func setRecording(_ recording: Bool) {
        guard recording != isRecording else { return }
        isRecording = recording
        if recording {
            // Carbon hotkeys otherwise consume an already-bound chord before the recorder sees it.
            references.values.forEach { UnregisterEventHotKey($0) }
            references.removeAll()
        } else if let preferences = latestPreferences {
            shortcuts = []
            register(preferences)
        }
    }

    @discardableResult
    func handleHotKey(_ id: UInt32) -> Bool {
        if isRecording { return (1...3).contains(id) }
        switch id {
        case 1: onOpen?()
        case 2: onList?()
        case 3: onSearch?()
        default: return false
        }
        return true
    }

    deinit {
        references.values.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: Shortcut
    let onChange: (Shortcut) -> Void
    var onRecordingChange: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        button.target = button
        button.action = #selector(RecorderButton.beginRecording)
        button.toolTip = "Click, then press a shortcut with Command, Option, or Control. Escape cancels."
        button.setAccessibilityLabel("Record keyboard shortcut")
        return button
    }
    func updateNSView(_ view: RecorderButton, context: Context) {
        view.shortcut = shortcut
        view.onChange = onChange
        view.onRecordingChange = onRecordingChange
        if !view.recording { view.title = shortcut.label }
    }
    static func dismantleNSView(_ view: RecorderButton, coordinator: ()) { view.stopRecording() }
}

final class RecorderButton: NSButton {
    var shortcut = Preferences().openShortcut
    var onChange: ((Shortcut) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?
    private(set) var recording = false
    private var eventMonitor: Any?
    override var acceptsFirstResponder: Bool { true }

    @objc func beginRecording() {
        guard !recording else { return }
        guard window?.makeFirstResponder(self) != false else { return }
        recording = true
        title = "Press shortcut…"
        onRecordingChange?(true)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.recording, let window = self.window, event.window === window,
                  window.isKeyWindow, window.firstResponder === self else { return event }
            self.keyDown(with: event)
            return nil
        }
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { stopRecording(); return }
        guard !event.isARepeat else { return }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.intersection([.command, .option, .control]).isEmpty else {
            title = "Use ⌘, ⌥, or ⌃"
            NSSound.beep()
            return
        }
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let names: [UInt16: String] = [49: "Space", 36: "↵", 48: "⇥", 51: "⌫", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        // Control can yield ASCII control codes and Option can yield symbols. Display the base key.
        let characters = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers
        let printable = characters.flatMap { text -> String? in
            text.isEmpty || text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) ? nil : text.uppercased()
        }
        let key = names[event.keyCode] ?? printable ?? "Key \(event.keyCode)"
        onChange?(Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key))
        stopRecording()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if recording { keyDown(with: event); return true }
        return super.performKeyEquivalent(with: event)
    }

    override func resignFirstResponder() -> Bool { stopRecording(); return super.resignFirstResponder() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopRecording() }
    }
    func stopRecording() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor); self.eventMonitor = nil }
        guard recording else { return }
        recording = false; title = shortcut.label
        onRecordingChange?(false)
    }
    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        if recording { onRecordingChange?(false) }
    }
}
