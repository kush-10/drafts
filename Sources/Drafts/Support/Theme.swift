import SwiftUI

enum DraftsTheme {
    static let accent = Color(white: 0.7)
    static let text = Color(white: 0.88)
    static let secondary = Color(white: 0.52)
    static let surface = Color(white: 0.09)
    static let cornerRadius: CGFloat = 14
}

struct GlassBackground: View {
    var body: some View {
        VisualEffectBackground()
            .overlay(Color.black.opacity(0.68))
            .allowsHitTesting(false)
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.appearance = NSAppearance(named: .darkAqua)
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = DraftsTheme.cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundStyle(DraftsTheme.secondary)
            .fixedSize()
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 12) {
            Text(title).font(.system(size: 16, weight: .regular))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SaveErrorBanner: View {
    @ObservedObject var store: NoteStore
    var body: some View {
        if let error = store.lastError {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(error).textSelection(.enabled)
                Spacer(minLength: 0)
                Button("Retry") { if store.flush() { store.lastError = nil } }
            }
            .font(.system(size: 11)).padding(12)
            .foregroundStyle(DraftsTheme.text)
            .background(Color.white.opacity(0.06))
        }
    }
}
