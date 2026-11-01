import AppKit
import Carbon
import Combine

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var key: String

    func hasSameBinding(as other: Shortcut) -> Bool { keyCode == other.keyCode && modifiers == other.modifiers }

    var label: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + key
    }
}

enum RetentionUnit: String, Codable, CaseIterable {
    case minutes, hours, days
    var seconds: TimeInterval {
        switch self { case .minutes: return 60; case .hours: return 3600; case .days: return 86_400 }
    }
}

struct Preferences: Codable, Equatable {
    var keepOnTop = true
    var hideMenuBarIcon = false
    var autoDeleteEnabled = false
    var retentionAmount = 30
    var retentionUnit: RetentionUnit = .days
    var openShortcut = Shortcut(keyCode: 49, modifiers: UInt32(optionKey), key: "Space")
    var listShortcut = Shortcut(keyCode: 37, modifiers: UInt32(optionKey | shiftKey), key: "L")
    var searchShortcut = Shortcut(keyCode: 40, modifiers: UInt32(optionKey | shiftKey), key: "K")
    var sizeMemoryMinutes = 30
    var themeID = "charcoal"
    var autoOrganise = true
    var topicModelID = "qwen3.5-9b"
    var modelIdleSeconds = 30
    var useTopicMemory = true
    var editorFontID = "system"
    var editorFontSize: Double = 16

    var shortcuts: [Shortcut] { [openShortcut, listShortcut, searchShortcut] }
    var retentionInterval: TimeInterval { Double(max(1, retentionAmount)) * retentionUnit.seconds }

    func shortcutConflict(_ shortcut: Shortcut, replacing keyPath: WritableKeyPath<Preferences, Shortcut>) -> String? {
        let otherBindings = [\Preferences.openShortcut, \.listShortcut, \.searchShortcut].filter { $0 != keyPath }
        if otherBindings.contains(where: { self[keyPath: $0].hasSameBinding(as: shortcut) }) {
            return "That shortcut is already assigned to another action."
        }
        if let command = LocalCommand.allCases.first(where: { $0.shortcut.hasSameBinding(as: shortcut) }) {
            return "\(shortcut.label) is reserved for \(command.title.lowercased())."
        }
        return nil
    }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case keepOnTop, hideMenuBarIcon, autoDeleteEnabled, retentionAmount, retentionUnit
        case retentionDays // Read only: preserve the old interval, but not its different deletion policy.
        case openShortcut, listShortcut, searchShortcut
        case sizeMemoryMinutes, themeID, autoOrganise
        case topicModelID, modelIdleSeconds
        case useTopicMemory
        case editorFontID, editorFontSize
    }

    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        keepOnTop = try values.decodeIfPresent(Bool.self, forKey: .keepOnTop) ?? keepOnTop
        hideMenuBarIcon = try values.decodeIfPresent(Bool.self, forKey: .hideMenuBarIcon) ?? false
        // The former policy moved notes to Trash. Permanent auto-deletion requires a new opt-in.
        autoDeleteEnabled = try values.decodeIfPresent(Bool.self, forKey: .autoDeleteEnabled) ?? false
        retentionAmount = min(36_500, max(1, try values.decodeIfPresent(Int.self, forKey: .retentionAmount)
            ?? values.decodeIfPresent(Int.self, forKey: .retentionDays) ?? retentionAmount))
        retentionUnit = try values.decodeIfPresent(RetentionUnit.self, forKey: .retentionUnit) ?? .days
        // Retire the old toggle/capture/search bindings without resetting retention settings.
        openShortcut = try values.decodeIfPresent(Shortcut.self, forKey: .openShortcut) ?? openShortcut
        listShortcut = try values.decodeIfPresent(Shortcut.self, forKey: .listShortcut) ?? listShortcut
        // The pre-v1 searchShortcut belonged to a retired action. Only read the new binding
        // when this preferences document also uses the current open/list shortcut schema.
        if values.contains(.openShortcut) || values.contains(.listShortcut) {
            searchShortcut = try values.decodeIfPresent(Shortcut.self, forKey: .searchShortcut) ?? searchShortcut
        }
        if !values.contains(.searchShortcut), [openShortcut, listShortcut].contains(where: { $0.hasSameBinding(as: searchShortcut) }) {
            let alternatives = [UInt32(controlKey | optionKey), UInt32(cmdKey | optionKey)]
            for modifiers in alternatives {
                let candidate = Shortcut(keyCode: 40, modifiers: modifiers, key: "K")
                if ![openShortcut, listShortcut].contains(where: { $0.hasSameBinding(as: candidate) }) { searchShortcut = candidate; break }
            }
        }
        sizeMemoryMinutes = min(10_080, max(1, try values.decodeIfPresent(Int.self, forKey: .sizeMemoryMinutes) ?? 30))
        themeID = try values.decodeIfPresent(String.self, forKey: .themeID) ?? "charcoal"
        autoOrganise = try values.decodeIfPresent(Bool.self, forKey: .autoOrganise) ?? true
        topicModelID = try values.decodeIfPresent(String.self, forKey: .topicModelID) ?? "qwen3.5-9b"
        let idle = try values.decodeIfPresent(Int.self, forKey: .modelIdleSeconds) ?? 30
        modelIdleSeconds = [0, 30, 60].contains(idle) ? idle : 30
        useTopicMemory = try values.decodeIfPresent(Bool.self, forKey: .useTopicMemory) ?? true
        let fontID = try values.decodeIfPresent(String.self, forKey: .editorFontID) ?? "system"
        editorFontID = EditorFontOption.available.contains { $0.id == fontID } ? fontID : "system"
        editorFontSize = EditorFontOption.clampedSize(try values.decodeIfPresent(Double.self, forKey: .editorFontSize) ?? 16)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(keepOnTop, forKey: .keepOnTop)
        try values.encode(hideMenuBarIcon, forKey: .hideMenuBarIcon)
        try values.encode(autoDeleteEnabled, forKey: .autoDeleteEnabled)
        try values.encode(retentionAmount, forKey: .retentionAmount)
        try values.encode(retentionUnit, forKey: .retentionUnit)
        try values.encode(openShortcut, forKey: .openShortcut)
        try values.encode(listShortcut, forKey: .listShortcut)
        try values.encode(searchShortcut, forKey: .searchShortcut)
        try values.encode(sizeMemoryMinutes, forKey: .sizeMemoryMinutes)
        try values.encode(themeID, forKey: .themeID)
        try values.encode(autoOrganise, forKey: .autoOrganise)
        try values.encode(topicModelID, forKey: .topicModelID)
        try values.encode(modelIdleSeconds, forKey: .modelIdleSeconds)
        try values.encode(useTopicMemory, forKey: .useTopicMemory)
        try values.encode(editorFontID, forKey: .editorFontID)
        try values.encode(editorFontSize, forKey: .editorFontSize)
    }
}

final class PreferencesStore: ObservableObject {
    @Published var value: Preferences {
        didSet {
            ThemeController.shared.select(value.themeID)
            EditorTypography.shared.select(fontID: value.editorFontID, size: value.editorFontSize)
            if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: "preferences.v1") }
        }
    }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        value = defaults.data(forKey: "preferences.v1")
            .flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        ThemeController.shared.select(value.themeID)
        EditorTypography.shared.select(fontID: value.editorFontID, size: value.editorFontSize)
    }
}
