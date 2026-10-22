import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var hotKeys: HotKeyManager
    @ObservedObject var store: NoteStore
    @State private var shortcutError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("Settings").font(.system(size: 18, weight: .medium))

                section("Keyboard shortcuts") {
                    shortcutRow("Open newest note", keyPath: \.openShortcut)
                    shortcutRow("Full list editor", keyPath: \.listShortcut)
                    HStack { Text("New blank note (in Drafts)"); Spacer(); KeyCap(text: "⌘N") }
                    HStack { Text("Copy all and close"); Spacer(); KeyCap(text: LocalCommand.copyAndClose.label) }
                    HStack { Text("Find notes (in notepad)"); Spacer(); KeyCap(text: "⌘F") }
                    HStack { Text("Hide note"); Spacer(); KeyCap(text: "esc") }
                    if let error = shortcutError ?? hotKeys.error {
                        Text(error).font(.system(size: 11)).foregroundStyle(DraftsTheme.text).textSelection(.enabled)
                    }
                }

                Toggle("Keep above other windows", isOn: $preferences.value.keepOnTop)
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Hide menu bar icon", isOn: $preferences.value.hideMenuBarIcon)
                        .disabled(hotKeys.error != nil)
                    Text("Open Drafts with \(preferences.value.openShortcut.label) or from Applications, then press ⌘, for Settings. The icon stays visible if a global shortcut is unavailable.")
                        .font(.system(size: 11)).foregroundStyle(DraftsTheme.secondary)
                }
                Divider().opacity(0.5)

                section("Note storage") {
                    Picker("Note storage", selection: $preferences.value.autoDeleteEnabled) {
                        Text("Keep everything").tag(false)
                        Text("Automatically delete after last edit").tag(true)
                    }.pickerStyle(.radioGroup).labelsHidden()
                    HStack {
                        Text("After")
                        Spacer()
                        retentionField
                    }.disabled(!preferences.value.autoDeleteEnabled)
                    Text(preferences.value.autoDeleteEnabled
                         ? "Permanently deletes notes, including Trash, after this time since the last edit. The open note is protected while you use it. Checks run on launch and every 30 seconds."
                         : "All notes are kept. Nothing is automatically deleted, including notes in Trash.")
                        .font(.system(size: 11)).foregroundStyle(DraftsTheme.secondary)
                }

                Divider().opacity(0.5)
                HStack {
                    Text("Stored only on this Mac").foregroundStyle(DraftsTheme.secondary)
                    Spacer()
                    Button("Show files") { NSWorkspace.shared.open(store.directory) }.buttonStyle(.plain)
                }.font(.system(size: 11))
                SaveErrorBanner(store: store)
            }.padding(26)
        }
        .font(.system(size: 12)).foregroundStyle(DraftsTheme.text)
        .toggleStyle(.switch).controlSize(.small)
        .tint(DraftsTheme.accent)
        .background(DraftsTheme.surface)
        .environment(\.colorScheme, .dark)
        .frame(width: 520, height: 600)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(DraftsTheme.secondary)
            content()
        }
    }

    private func shortcutRow(_ title: String, keyPath: WritableKeyPath<Preferences, Shortcut>) -> some View {
        HStack {
            Text(title)
            Spacer()
            ShortcutRecorder(shortcut: preferences.value[keyPath: keyPath]) { shortcut in
                shortcutError = preferences.value.shortcutConflict(shortcut, replacing: keyPath)
                guard shortcutError == nil else { return }
                preferences.value[keyPath: keyPath] = shortcut
            }.frame(width: 135, height: 27)
        }
    }

    private var retentionField: some View {
        HStack(spacing: 6) {
            TextField("Time", value: $preferences.value.retentionAmount, format: .number.grouping(.never))
                .labelsHidden().textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing).frame(width: 52)
                .onChange(of: preferences.value.retentionAmount) { _, new in preferences.value.retentionAmount = min(36_500, max(1, new)) }
            Stepper("Time", value: $preferences.value.retentionAmount, in: 1...36_500).labelsHidden().fixedSize()
            Picker("Unit", selection: $preferences.value.retentionUnit) {
                ForEach(RetentionUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.labelsHidden().frame(width: 90)
        }.fixedSize()
    }
}
