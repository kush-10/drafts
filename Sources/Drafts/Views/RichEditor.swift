import AppKit
import SwiftUI

final class EditorBridge: ObservableObject {
    weak var textView: DraftsTextView? {
        didSet { if oldValue !== textView { noteID = nil; paletteID = nil } }
    }
    private(set) var noteID: UUID?
    private var paletteID: String?
    @Published private(set) var topicCompletion: EditorTopicCompletion?
    @Published private(set) var selectedTopicIndex = 0
    var availableTopics: () -> [NoteCategory] = { [] }
    var onAssignTopic: ((UUID, UUID) -> Bool)?
    var manualTopicLabels: ((UUID) -> CategoryLabels)?
    var onRestoreManualLabels: ((UUID, CategoryLabels) -> Bool)?
    var onTopicAccepted: ((UUID) -> Void)?
    private var dismissedTopicToken: String?
    private var isUpdatingAppearance = false
    var onNoteList: (() -> Void)?
    var onSmartSearch: (() -> Void)?
    var onToggleExpansion: (() -> Void)?
    var onCopyAndClose: (() -> Void)?
    var onSettings: (() -> Void)?

    func focus() {
        guard let view = textView, view.window?.isVisible == true else { return }
        view.window?.makeFirstResponder(view)
        (view.enclosingScrollView as? EditorScrollView)?.requestCaretVisibility()
    }

    func load(_ note: Note, force: Bool = false) {
        applyAppearance()
        guard force || noteID != note.id else { return }
        guard let view = textView, let content = try? note.attributedString() else { return }
        if topicCompletion != nil { topicCompletion = nil }
        dismissedTopicToken = nil
        isUpdatingAppearance = true
        defer { isUpdatingAppearance = false }
        // Legacy content is kept intact on disk. New input is restricted to the four basic styles.
        view.textStorage?.setAttributedString(EditorStyle.adaptingToAppearance(content))
        view.setSelectedRange(NSRange(location: content.length, length: 0))
        view.typingAttributes = EditorStyle.attributes
        view.undoManager?.removeAllActions()
        noteID = note.id
        (view.enclosingScrollView as? EditorScrollView)?.requestCaretVisibility()
    }

    func applyAppearance() {
        guard let view = textView else { return }
        let palette = DraftsTheme.palette
        let appearanceID = "\(palette.id)|\(EditorTypography.shared.identifier)"
        guard paletteID != appearanceID else { return }
        let scroll = view.enclosingScrollView as? EditorScrollView
        let keepCaretVisible = scroll?.isCaretVisible == true
        paletteID = appearanceID
        isUpdatingAppearance = true
        defer { isUpdatingAppearance = false }
        view.appearance = palette.appearance
        view.enclosingScrollView?.appearance = palette.appearance
        view.insertionPointColor = ThemePalette.native(palette.highlight)
        view.selectedTextAttributes = [.foregroundColor: EditorStyle.textColor, .backgroundColor: ThemePalette.native(palette.highlight).withAlphaComponent(0.3)]
        view.textStorage?.addAttribute(.foregroundColor, value: EditorStyle.textColor, range: NSRange(location: 0, length: view.string.utf16.count))
        view.typingAttributes[.foregroundColor] = EditorStyle.textColor
        if let storage = view.textStorage {
            let adapted = EditorTypography.shared.adapting(storage)
            adapted.enumerateAttribute(.font, in: NSRange(location: 0, length: adapted.length)) { value, range, _ in
                if let value { storage.addAttribute(.font, value: value, range: range) }
            }
        }
        let typing = NSAttributedString(string: "x", attributes: view.typingAttributes)
        view.typingAttributes[.font] = EditorTypography.shared.adapting(typing).attribute(.font, at: 0, effectiveRange: nil)
        scroll?.fitDocument()
        if keepCaretVisible { scroll?.requestCaretVisibility() }
    }

    func refreshTopicCompletion() {
        guard !isUpdatingAppearance else { return }
        guard let view = textView, noteID != nil,
              let completion = EditorTopicCompletion.find(in: view.string, selection: view.selectedRange(), topics: availableTopics()) else {
            if topicCompletion != nil { topicCompletion = nil }
            dismissedTopicToken = nil; return
        }
        let token = "\(completion.range.location)|\(completion.query)"
        guard dismissedTopicToken != token else { return }
        if topicCompletion?.range == completion.range, topicCompletion?.query == completion.query,
           topicCompletion?.topics.map(\.id) == completion.topics.map(\.id) { return }
        if selectedTopicIndex != 0 { selectedTopicIndex = 0 }
        topicCompletion = completion
    }

    func dismissTopicCompletion() {
        if let completion = topicCompletion { dismissedTopicToken = "\(completion.range.location)|\(completion.query)" }
        if topicCompletion != nil { topicCompletion = nil }
    }

    func moveTopicSelection(_ delta: Int) {
        guard let completion = topicCompletion else { return }
        selectedTopicIndex = (selectedTopicIndex + delta + completion.topics.count) % completion.topics.count
    }

    @discardableResult
    func acceptTopicCompletion(at index: Int? = nil) -> Bool {
        guard let view = textView, let noteID, let completion = topicCompletion,
              let current = EditorTopicCompletion.find(in: view.string, selection: view.selectedRange(), topics: availableTopics()),
              current.range == completion.range, current.query == completion.query else { return false }
        let index = index ?? selectedTopicIndex
        guard completion.topics.indices.contains(index) else { return false }
        let previousLabels = manualTopicLabels?(noteID)
        view.undoManager?.beginUndoGrouping()
        defer { view.undoManager?.endUndoGrouping() }
        guard onAssignTopic?(noteID, completion.topics[index].id) == true else { NSSound.beep(); return true }
        if let previousLabels {
            view.undoManager?.registerUndo(withTarget: self) { bridge in bridge.restoreTopicLabels(previousLabels, noteID: noteID) }
            view.undoManager?.setActionName("Assign topic")
        }
        topicCompletion = nil
        view.insertText("", replacementRange: completion.range)
        onTopicAccepted?(noteID)
        focus()
        return true
    }

    private func restoreTopicLabels(_ labels: CategoryLabels, noteID: UUID) {
        guard let previous = manualTopicLabels?(noteID), onRestoreManualLabels?(noteID, labels) == true else { return }
        textView?.undoManager?.registerUndo(withTarget: self) { bridge in bridge.restoreTopicLabels(previous, noteID: noteID) }
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
    static let caretBottomPadding: CGFloat = 36
    private var fitting = false
    private var caretRevealScheduled = false
    private var needsCaretReveal = false

    override func tile() { super.tile(); fitDocument() }
    override func layout() { super.layout(); fitDocument() }
    override func setFrameSize(_ newSize: NSSize) {
        let keepCaretVisible = frame.size != newSize && isCaretVisible
        super.setFrameSize(newSize)
        fitDocument()
        if keepCaretVisible { requestCaretVisibility() }
    }

    override func scrollWheel(with event: NSEvent) {
        needsCaretReveal = false
        super.scrollWheel(with: event)
    }

    var caretRect: NSRect? {
        guard let text = documentView as? DraftsTextView, let window = text.window,
              text.selectedRange().length == 0, text.selectedRange().location <= text.string.utf16.count else { return nil }
        if text.selectedRange().location == text.string.utf16.count,
           let manager = text.layoutManager, let container = text.textContainer {
            manager.ensureLayout(for: container)
            // AppKit can return a zero firstRect for the empty insertion line after a final newline.
            if manager.extraLineFragmentTextContainer === container {
                let line = manager.extraLineFragmentRect
                let font = text.typingAttributes[.font] as? NSFont ?? EditorStyle.font
                return NSRect(x: text.textContainerOrigin.x + line.minX, y: text.textContainerOrigin.y + line.minY,
                              width: 1, height: max(line.height, manager.defaultLineHeight(for: font)))
            }
        }
        let screenRect = text.firstRect(forCharacterRange: text.selectedRange(), actualRange: nil)
        guard screenRect.height > 0 else { return nil }
        var rect = text.convert(window.convertFromScreen(screenRect), from: nil)
        rect.size.width = max(1, rect.width)
        return rect
    }

    var isCaretVisible: Bool {
        guard let rect = caretRect else { return false }
        return documentVisibleRect.contains(rect)
    }

    func requestCaretVisibility() {
        needsCaretReveal = true
        guard !caretRevealScheduled else { return }
        caretRevealScheduled = true
        // AppKit must finish selection/line layout before revealing the new insertion point.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.caretRevealScheduled = false
            guard self.needsCaretReveal else { return }
            self.needsCaretReveal = false
            guard let text = self.documentView as? DraftsTextView, text.window?.firstResponder === text else { return }
            self.fitDocument()
            guard let caret = self.caretRect else { return }
            let target = NSRect(x: caret.minX, y: max(0, caret.minY - 12), width: caret.width,
                                height: caret.height + 12 + Self.caretBottomPadding)
            text.scrollToVisible(target)
        }
    }

    func fitDocument() {
        guard !fitting, let text = documentView as? NSTextView, contentView.bounds.width > 0 else { return }
        fitting = true
        defer { fitting = false }
        let viewport = contentView.bounds.size
        text.minSize = NSSize(width: 0, height: viewport.height)
        if text.frame.width != viewport.width { text.setFrameSize(NSSize(width: viewport.width, height: text.frame.height)) }
        let width = max(1, viewport.width - 2 * text.textContainerInset.width)
        if abs((text.textContainer?.containerSize.width ?? 0) - width) > 0.5 {
            text.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        }
        if let manager = text.layoutManager, let container = text.textContainer {
            manager.ensureLayout(for: container)
            var bottom = manager.usedRect(for: container).maxY
            if manager.extraLineFragmentTextContainer === container { bottom = max(bottom, manager.extraLineFragmentRect.maxY) }
            let padding = text is DraftsTextView ? Self.caretBottomPadding : 0
            let height = max(viewport.height, ceil(bottom + 2 * text.textContainerInset.height + padding))
            if text.frame.height != height { text.setFrameSize(NSSize(width: viewport.width, height: height)) }
        }
    }
}

final class DraftsTextView: NSTextView {
    weak var editorBridge: EditorBridge?

    override func cancelOperation(_ sender: Any?) {
        if editorBridge?.topicCompletion != nil { editorBridge?.dismissTopicCompletion() }
        else { window?.cancelOperation(sender) }
    }

    override func keyDown(with event: NSEvent) {
        if editorBridge?.topicCompletion != nil,
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            switch event.keyCode {
            case 125: editorBridge?.moveTopicSelection(1); return
            case 126: editorBridge?.moveTopicSelection(-1); return
            case 36, 48: if editorBridge?.acceptTopicCompletion() == true { return }
            case 53: editorBridge?.dismissTopicCompletion(); return
            default: break
            }
        }
        super.keyDown(with: event)
        (enclosingScrollView as? EditorScrollView)?.requestCaretVisibility()
    }

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
            case "k": if let action = editorBridge?.onSmartSearch { action(); return true }
            case "f": if let action = editorBridge?.onToggleExpansion { if !event.isARepeat { action() }; return true }
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
        if editorBridge?.acceptTopicCompletion() == true { return }
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

    override func insertTab(_ sender: Any?) {
        if editorBridge?.acceptTopicCompletion() == true { return }
        super.insertTab(sender)
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
        scroll.appearance = DraftsTheme.palette.appearance
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
            // Undo may restore attributed text captured under a different theme.
            view.textStorage?.addAttribute(.foregroundColor, value: EditorStyle.textColor, range: NSRange(location: 0, length: view.string.utf16.count))
            view.typingAttributes[.foregroundColor] = EditorStyle.textColor
            onChange(id, NSAttributedString(attributedString: view.attributedString()))
            bridge.refreshTopicCompletion()
            (view.enclosingScrollView as? EditorScrollView)?.requestCaretVisibility()
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            bridge.refreshTopicCompletion()
            if let view = notification.object as? DraftsTextView, view.window?.firstResponder === view {
                (view.enclosingScrollView as? EditorScrollView)?.requestCaretVisibility()
            }
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
        scroll.appearance = DraftsTheme.palette.appearance
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
        scroll.appearance = DraftsTheme.palette.appearance
        view.textStorage?.setAttributedString(EditorStyle.adaptingToAppearance(content))
        scroll.fitDocument()
    }
}
