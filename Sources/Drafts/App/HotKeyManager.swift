import AppKit
import Carbon
import Combine
import SwiftUI

final class HotKeyManager: ObservableObject {
    @Published private(set) var error: String?
    var onOpen: (() -> Void)?
    var onList: (() -> Void)?
    private var references: [Int: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private var shortcuts: [Shortcut] = []
    private let signature: OSType = 0x44524654
    private var registrationFailures: [Int: String] = [:]

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr else { return status }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
            guard identifier.signature == manager.signature else { return OSStatus(eventNotHandledErr) }
            switch identifier.id {
            case 1: manager.onOpen?()
            case 2: manager.onList?()
            default: return OSStatus(eventNotHandledErr)
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if status != noErr { error = "Couldn’t install global shortcuts (\(status)). You can still use the menu bar." }
    }

    func register(_ preferences: Preferences) {
        guard shortcuts != preferences.shortcuts else { return }
        guard handler != nil else { return }
        let paths = [\Preferences.openShortcut, \.listShortcut]
        let conflicts = paths.compactMap { preferences.shortcutConflict(preferences[keyPath: $0], replacing: $0) }
        guard conflicts.isEmpty else { error = conflicts.joined(separator: "\n"); return }
        let oldShortcuts = shortcuts
        shortcuts = preferences.shortcuts
        let changed = shortcuts.indices.filter { !oldShortcuts.indices.contains($0) || !shortcuts[$0].hasSameBinding(as: oldShortcuts[$0]) }
        // Release changed bindings together, allowing two actions to swap bindings without a false conflict.
        for index in changed {
            if let reference = references.removeValue(forKey: index) { UnregisterEventHotKey(reference) }
            registrationFailures.removeValue(forKey: index)
        }
        let names = ["Show / hide notepad", "Full list editor"]
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

    deinit {
        references.values.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: Shortcut
    let onChange: (Shortcut) -> Void

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
        if !view.recording { view.title = shortcut.label }
    }
}

final class RecorderButton: NSButton {
    var shortcut = Preferences().openShortcut
    var onChange: ((Shortcut) -> Void)?
    private(set) var recording = false
    override var acceptsFirstResponder: Bool { true }

    @objc func beginRecording() {
        recording = true
        title = "Press shortcut…"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { stop(); return }
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
        let key = names[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        onChange?(Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key))
        stop()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if recording { keyDown(with: event); return true }
        return super.performKeyEquivalent(with: event)
    }

    override func resignFirstResponder() -> Bool { stop(); return super.resignFirstResponder() }
    private func stop() { recording = false; title = shortcut.label }
}
