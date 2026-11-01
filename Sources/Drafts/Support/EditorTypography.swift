import AppKit

struct EditorFontOption: Identifiable {
    let id: String
    let name: String

    static let available: [Self] = [
        Self(id: "system", name: "System"), Self(id: "monospaced", name: "System Mono"),
        Self(id: "Menlo", name: "Menlo"), Self(id: "Monaco", name: "Monaco"),
        Self(id: "Helvetica Neue", name: "Helvetica Neue"), Self(id: "Avenir Next", name: "Avenir Next"),
        Self(id: "Georgia", name: "Georgia"), Self(id: "Palatino", name: "Palatino"),
        Self(id: "Courier New", name: "Courier New"), Self(id: "Verdana", name: "Verdana")
    ].filter { ["system", "monospaced"].contains($0.id) || NSFont(name: $0.id, size: 16) != nil }

    static func font(id: String, size: Double) -> NSFont {
        let size = CGFloat(clampedSize(size))
        if id == "monospaced" { return .monospacedSystemFont(ofSize: size, weight: .regular) }
        return NSFont(name: id, size: size) ?? .systemFont(ofSize: size)
    }

    static func clampedSize(_ size: Double) -> Double { size.isFinite ? min(40, max(10, size)) : 16 }
}

final class EditorTypography {
    static let shared = EditorTypography()
    private(set) var fontID = "system"
    private(set) var size: Double = 16
    var identifier: String { "\(fontID)|\(size)" }
    var font: NSFont { EditorFontOption.font(id: fontID, size: size) }

    func select(fontID: String, size: Double) {
        self.fontID = EditorFontOption.available.contains { $0.id == fontID } ? fontID : "system"
        self.size = EditorFontOption.clampedSize(size)
    }

    func adapting(_ content: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: content)
        content.enumerateAttribute(.font, in: NSRange(location: 0, length: content.length)) { value, range, _ in
            let traits = (value as? NSFont).map { NSFontManager.shared.traits(of: $0).intersection([.boldFontMask, .italicFontMask]) } ?? []
            let adapted = traits.isEmpty ? font : NSFontManager.shared.convert(font, toHaveTrait: traits)
            result.addAttribute(.font, value: adapted, range: range)
        }
        return result
    }
}
