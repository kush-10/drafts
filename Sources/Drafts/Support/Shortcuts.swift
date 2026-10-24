import AppKit
import Carbon

// Shared labels and bindings for local menu commands.
enum LocalCommand: CaseIterable {
    case newNote, copyAndClose, noteList, toggleExpansion
    case bold, italic, underline, bullets
    case undo, redo, cut, copy, paste, selectAll
    case settings, quit

    enum Group: String, CaseIterable { case notes = "Notes", formatting = "Formatting", editing = "Editing", app = "App" }

    var group: Group {
        switch self {
        case .newNote, .copyAndClose, .noteList, .toggleExpansion: return .notes
        case .bold, .italic, .underline, .bullets: return .formatting
        case .settings, .quit: return .app
        default: return .editing
        }
    }

    var title: String {
        switch self {
        case .newNote: return "New blank note"
        case .copyAndClose: return "Copy all and close"
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .underline: return "Underline"
        case .bullets: return "Bullet points"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .cut: return "Cut"
        case .copy: return "Copy"
        case .paste: return "Paste"
        case .selectAll: return "Select all"
        case .noteList: return "Integrated note list"
        case .toggleExpansion: return "Expand / restore notepad"
        case .settings: return "Settings"
        case .quit: return "Quit Drafts"
        }
    }

    var key: String {
        switch self {
        case .newNote: return "n"
        case .bold, .bullets: return "b"
        case .italic: return "i"
        case .underline: return "u"
        case .undo, .redo: return "z"
        case .cut: return "x"
        case .copy, .copyAndClose: return "c"
        case .paste: return "v"
        case .selectAll: return "a"
        case .noteList: return "l"
        case .toggleExpansion: return "f"
        case .settings: return ","
        case .quit: return "q"
        }
    }

    var modifiers: NSEvent.ModifierFlags { self == .redo || self == .bullets || self == .copyAndClose ? [.command, .shift] : .command }
    var label: String { (modifiers.contains(.shift) ? "⇧⌘" : "⌘") + key.uppercased() }

    var shortcut: Shortcut {
        let codes: [String: UInt32] = ["n": 45, "w": 13, "l": 37, "/": 44, "b": 11, "i": 34, "u": 32, "z": 6, "x": 7, "c": 8, "v": 9, "a": 0, "f": 3, ",": 43, "q": 12]
        return Shortcut(keyCode: codes[key]!, modifiers: UInt32(cmdKey | (modifiers.contains(.shift) ? shiftKey : 0)), key: key.uppercased())
    }
}
