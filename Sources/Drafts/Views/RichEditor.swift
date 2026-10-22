import AppKit
import SwiftUI

final class EditorBridge: ObservableObject {
    weak var textView: DraftsTextView? {
        didSet { if oldValue !== textView { noteID = nil } }
    }
    private(set) var noteID: UUID?
    var onFind: (() -> Void)?
    var onCopyAndClose: (() -> Void)?
    var onSettings: (() -> Void)?

    func focus() {
        guard let view = textView, view.window?.isVisible == true else { return }
        view.window?.makeFirstResponder(view)
    }

    func load(_ note: Note, force: Bool = false) {
        guard force || noteID != note.id else { return }
        guard let view = textView, let content = try? note.attributedString() else { return }
        // Legacy content is kept intact on disk. New input is restricted to the four basic styles.
        view.textStorage?.setAttributedString(EditorStyle.adaptingToAppearance(content))
        view.setSelectedRange(NSRange(location: content.length, length: 0))
        view.typingAttributes = EditorStyle.attributes
        view.undoManager?.removeAllActions()
        noteID = note.id
    }

    func toggleBold() { toggleTrait(.boldFontMask, removing: .unboldFontMask) }
    func toggleItalic() { toggleTrait(.italicFontMask, removing: .unitalicFontMask) }

    private func toggleTrait(_ trait: NSFontTraitMask, removing: NSFontTraitMask) {
        guard let view = textView else { return }
        let range = view.selectedRange()
        let font = currentFont()
        let remove = NSFontManager.shared.traits(of: font).contains(trait)
        if range.length == 0 {
            view.typingAttributes[.font] = NSFontManager.shared.convert(font, toHaveTrait: remove ? removing : trait)
        } else {
            let replacement = NSMutableAttributedString(attributedString: view.attributedString().attributedSubstring(from: range))
            replacement.enumerateAttribute(.font, in: NSRange(location: 0, length: replacement.length)) { value, subrange, _ in
                let converted = NSFontManager.shared.convert(value as? NSFont ?? EditorStyle.font, toHaveTrait: remove ? removing : trait)
                replacement.addAttribute(.font, value: converted, range: subrange)
            }
            view.insertRichText(replacement, replacing: range)
            view.setSelectedRange(range)
        }
        focus()
    }

    func toggleUnderline() {
        guard let view = textView else { return }
        let range = view.selectedRange()
        let current = range.length > 0
            ? view.attributedString().attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int
            : view.typingAttributes[.underlineStyle] as? Int
        let enabled = (current ?? 0) != 0
        if range.length == 0 {
            view.typingAttributes[.underlineStyle] = enabled ? nil : NSUnderlineStyle.single.rawValue
        } else {
            let replacement = NSMutableAttributedString(attributedString: view.attributedString().attributedSubstring(from: range))
            if enabled { replacement.removeAttribute(.underlineStyle, range: NSRange(location: 0, length: replacement.length)) }
            else { replacement.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: replacement.length)) }
            view.insertRichText(replacement, replacing: range)
            view.setSelectedRange(range)
        }
        focus()
    }

    func toggleBullets() {
        guard let view = textView else { return }
        let selection = view.selectedRange()
        let range = (view.string as NSString).paragraphRange(for: selection)
        let original = view.attributedString().attributedSubstring(from: range)
        let source = original.string as NSString
        let replacement = NSMutableAttributedString(attributedString: original)
        var locations: [Int] = []
        var offset = 0
        repeat {
            locations.append(offset)
            offset = NSMaxRange(source.paragraphRange(for: NSRange(location: offset, length: 0)))
        } while offset < source.length
        let remove = locations.allSatisfy { source.substring(from: $0).hasPrefix("• ") }
        for location in locations.reversed() {
            if source.substring(from: location).hasPrefix("• ") {
                if remove { replacement.deleteCharacters(in: NSRange(location: location, length: 2)) }
            } else { replacement.insert(EditorStyle.plain("• "), at: location) }
        }
        view.insertRichText(replacement, replacing: range)
        if selection.length > 0 { view.setSelectedRange(NSRange(location: range.location, length: replacement.length)) }
        else {
            let caret = min(NSMaxRange(range) + replacement.length - original.length, selection.location + replacement.length - original.length)
            view.setSelectedRange(NSRange(location: max(range.location, caret), length: 0))
        }
        focus()
    }

    private func currentFont() -> NSFont {
        guard let view = textView else { return EditorStyle.font }
        if view.selectedRange().length > 0 {
            return view.attributedString().attribute(.font, at: view.selectedRange().location, effectiveRange: nil) as? NSFont ?? EditorStyle.font
        }
        return view.typingAttributes[.font] as? NSFont ?? EditorStyle.font
    }
}

// SwiftUI can assign an NSScrollView a different width after its document view is created.
// Fit the document to the *actual clip view*, not an initial hard-coded editor width.
final class EditorScrollView: NSScrollView {
    private var fitting = false

    override func tile() { super.tile(); fitDocument() }
    override func layout() { super.layout(); fitDocument() }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); fitDocument() }

    func fitDocument() {
        guard !fitting, let text = documentView as? NSTextView, contentView.bounds.width > 0 else { return }
        fitting = true
        defer { fitting = false }
        let viewport = contentView.bounds.size
        text.minSize = NSSize(width: 0, height: viewport.height)
        let size = NSSize(width: viewport.width, height: max(viewport.height, text.frame.height))
        if text.frame.size != size { text.setFrameSize(size) }
        let width = max(1, viewport.width - 2 * text.textContainerInset.width)
        if abs((text.textContainer?.containerSize.width ?? 0) - width) > 0.5 {
            text.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        }
    }
}

final class DraftsTextView: NSTextView {
    weak var editorBridge: EditorBridge?

    override func cancelOperation(_ sender: Any?) { window?.cancelOperation(sender) }

    func insertRichText(_ content: NSAttributedString, replacing range: NSRange) {
        let formattingOnly = (string as NSString).substring(with: range) == content.string
        guard shouldChangeText(in: range, replacementString: formattingOnly ? nil : content.string) else { return }
        textStorage?.replaceCharacters(in: range, with: content)
        setSelectedRange(NSRange(location: range.location + content.length, length: 0))
        didChangeText()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if flags == .command {
            switch key {
            case "b": editorBridge?.toggleBold(); return true
            case "i": editorBridge?.toggleItalic(); return true
            case "u": editorBridge?.toggleUnderline(); return true
            case "f": editorBridge?.onFind?(); return true
            case ",": if let action = editorBridge?.onSettings { action(); return true }
            default: break
            }
        } else if flags == [.command, .shift] {
            if key == "b" { editorBridge?.toggleBullets(); return true }
            if key == "c", let action = editorBridge?.onCopyAndClose { action(); return true }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func paste(_ sender: Any?) {
        guard let content = PasteContent.read(from: .general) else { return }
        insertRichText(content, replacing: selectedRange())
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        // This also covers native drag-and-drop and prevents alternate paste paths importing images.
        guard let content = PasteContent.read(from: pboard) else { return false }
        insertRichText(content, replacing: selectedRange())
        return true
    }

    override func insertNewline(_ sender: Any?) {
        let ns = string as NSString
        let lineRange = ns.paragraphRange(for: NSRange(location: selectedRange().location, length: 0))
        let line = ns.substring(with: lineRange).trimmingCharacters(in: .newlines)
        if line == "• " {
            insertText("", replacementRange: NSRange(location: lineRange.location, length: 2))
            typingAttributes = EditorStyle.attributes
            return
        }
        super.insertNewline(sender)
        if line.hasPrefix("• ") { insertText("• ", replacementRange: selectedRange()) }
    }
}

struct RichEditor: NSViewRepresentable {
    let note: Note
    @ObservedObject var bridge: EditorBridge
    let onChange: (UUID, NSAttributedString) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange, bridge: bridge) }

    func makeNSView(context: Context) -> EditorScrollView {
        let scroll = EditorScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false
        scroll.appearance = NSAppearance(named: .darkAqua)
        let view = DraftsTextView(frame: .zero)
        view.minSize = NSSize(width: 0, height: 0)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 1, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainerInset = NSSize(width: 23, height: 24)
        view.isRichText = true
        view.importsGraphics = false
        view.allowsImageEditing = false
        view.usesFontPanel = false
        view.usesRuler = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.font = EditorStyle.font
        view.textColor = EditorStyle.textColor
        view.insertionPointColor = EditorStyle.textColor
        view.selectedTextAttributes = [.backgroundColor: NSColor(white: 1, alpha: 0.16), .foregroundColor: EditorStyle.textColor]
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticTextCompletionEnabled = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.usesFindBar = false
        view.delegate = context.coordinator
        view.editorBridge = bridge
        scroll.documentView = view
        scroll.fitDocument()
        bridge.textView = view
        bridge.load(note)
        return scroll
    }

    func updateNSView(_ scroll: EditorScrollView, context: Context) {
        context.coordinator.onChange = onChange
        bridge.load(note)
        scroll.fitDocument()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: (UUID, NSAttributedString) -> Void
        let bridge: EditorBridge
        init(onChange: @escaping (UUID, NSAttributedString) -> Void, bridge: EditorBridge) {
            self.onChange = onChange
            self.bridge = bridge
        }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView, let id = bridge.noteID else { return }
            onChange(id, NSAttributedString(attributedString: view.attributedString()))
        }
    }
}

struct RichPreview: NSViewRepresentable {
    let note: Note
    func makeNSView(context: Context) -> EditorScrollView {
        let scroll = EditorScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.appearance = NSAppearance(named: .darkAqua)
        let view = NSTextView()
        view.minSize = NSSize(width: 0, height: 0)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 26, height: 24)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: EditorScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, let content = try? note.attributedString() else { return }
        view.textStorage?.setAttributedString(EditorStyle.adaptingToAppearance(content))
        scroll.fitDocument()
    }
}
