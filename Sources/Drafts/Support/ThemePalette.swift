import SwiftUI

struct ThemePalette: Identifiable {
    let id: String
    let name: String
    let background: UInt32
    let foreground: UInt32
    let muted: UInt32
    let highlight: UInt32
    var light = false

    static let all: [ThemePalette] = [
        .init(id: "charcoal", name: "Drafts Charcoal", background: 0x171719, foreground: 0xe0e0e0, muted: 0x95959c, highlight: 0xb8b8c1),
        .init(id: "latte", name: "Catppuccin Latte", background: 0xeff1f5, foreground: 0x4c4f69, muted: 0x6c6f85, highlight: 0x8839ef, light: true),
        .init(id: "frappe", name: "Catppuccin Frappé", background: 0x303446, foreground: 0xc6d0f5, muted: 0xa5adce, highlight: 0xca9ee6),
        .init(id: "macchiato", name: "Catppuccin Macchiato", background: 0x24273a, foreground: 0xcad3f5, muted: 0xa5adcb, highlight: 0xc6a0f6),
        .init(id: "mocha", name: "Catppuccin Mocha", background: 0x1e1e2e, foreground: 0xcdd6f4, muted: 0xa6adc8, highlight: 0xcba6f7),
        .init(id: "paper", name: "Paper Room", background: 0xf7f4ec, foreground: 0x34332f, muted: 0x777269, highlight: 0x886133, light: true),
        .init(id: "lilac", name: "Lilac Letter", background: 0xf1eaf6, foreground: 0x493855, muted: 0x7a6386, highlight: 0x8050a3, light: true),
        .init(id: "peach", name: "Peach Postcard", background: 0xffefe4, foreground: 0x593c35, muted: 0x87665d, highlight: 0xb04d38, light: true),
        .init(id: "mint", name: "Mint Notebook", background: 0xe7f1e9, foreground: 0x294438, muted: 0x617c6b, highlight: 0x287451, light: true),
        .init(id: "blueprint", name: "Blue Margin", background: 0xe8edf7, foreground: 0x304361, muted: 0x65738e, highlight: 0x3557a6, light: true),
        .init(id: "sand", name: "Desert Page", background: 0xf5ebcf, foreground: 0x514728, muted: 0x7e7356, highlight: 0x936220, light: true),
        .init(id: "midnight", name: "Midnight Ink", background: 0x141d30, foreground: 0xc9daf4, muted: 0x8498b9, highlight: 0x80b6ff),
        .init(id: "rain", name: "Rain on Slate", background: 0x252d36, foreground: 0xd3dce5, muted: 0x9aaebc, highlight: 0x89c3c9),
        .init(id: "forest", name: "Forest Study", background: 0x202b26, foreground: 0xd6e1cb, muted: 0x9baa91, highlight: 0xadd38f),
        .init(id: "espresso", name: "Espresso Desk", background: 0x2b221e, foreground: 0xe8d6bf, muted: 0xb29a80, highlight: 0xe0ad71),
        .init(id: "plum", name: "Plum Afterglow", background: 0x2b2034, foreground: 0xe6d6ed, muted: 0xb49ac1, highlight: 0xd1a0ed),
        .init(id: "ocean", name: "Deepwater", background: 0x142a30, foreground: 0xc8e5e3, muted: 0x88adaa, highlight: 0x70d5c7),
        .init(id: "ember", name: "Quiet Ember", background: 0x2c2324, foreground: 0xf0d9ce, muted: 0xbe9e96, highlight: 0xf2a17e),
        .init(id: "orchid", name: "Electric Orchid", background: 0x211d32, foreground: 0xe5def5, muted: 0xaaa0c2, highlight: 0xe29be8),
        .init(id: "moon", name: "Moonlit Silver", background: 0x23252d, foreground: 0xe1e2eb, muted: 0xa2a5b6, highlight: 0xb1bef1)
    ]

    static func named(_ id: String) -> ThemePalette { all.first { $0.id == id } ?? all[0] }
    var scheme: ColorScheme { light ? .light : .dark }
    var appearance: NSAppearance? { NSAppearance(named: light ? .aqua : .darkAqua) }
    static func native(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: 1)
    }
}

final class ThemeController: ObservableObject {
    static let shared = ThemeController()
    @Published private(set) var palette = ThemePalette.all[0]
    func select(_ id: String) {
        let next = ThemePalette.named(id)
        if palette.id != next.id { palette = next }
    }
}

struct ThemedRoot<Content: View>: View {
    @ObservedObject private var theme = ThemeController.shared
    let content: Content
    var body: some View {
        content.environment(\.colorScheme, theme.palette.scheme).tint(DraftsTheme.accent)
    }
}
