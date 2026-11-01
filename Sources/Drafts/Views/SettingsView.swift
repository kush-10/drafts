import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "General", appearance = "Appearance", shortcuts = "Shortcuts"
    case organisation = "Organisation", models = "Models", topics = "Topics & Memory", storage = "Storage"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "textformat"
        case .shortcuts: return "keyboard"
        case .organisation: return "sparkles"
        case .models: return "externaldrive"
        case .topics: return "tag"
        case .storage: return "folder"
        }
    }
    var subtitle: String {
        switch self {
        case .general: return "How your notepad behaves."
        case .appearance: return "Make room for your writing style. Changes preview live."
        case .shortcuts: return "Global shortcuts and commands inside Drafts."
        case .organisation: return "Local AI topics, on saves or for your whole collection."
        case .models: return "Download once. Process privately on this Mac."
        case .topics: return "Define your topics and review human-confirmed examples."
        case .storage: return "Your notes, files and retention policy."
        }
    }
}

struct SettingsView: View {
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var hotKeys: HotKeyManager
    @ObservedObject var store: NoteStore
    var intelligence: IntelligenceController? = nil
    @State private var shortcutError: String?
    @State private var page = SettingsPage.general

    init(preferences: PreferencesStore, hotKeys: HotKeyManager, store: NoteStore, intelligence: IntelligenceController? = nil, initialPage: SettingsPage = .general) {
        self.preferences = preferences; self.hotKeys = hotKeys; self.store = store; self.intelligence = intelligence
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Drafts").font(.system(size: 20, weight: .semibold)).padding(.horizontal, 12).padding(.top, 14)
                Text("Settings").foregroundStyle(DraftsTheme.secondary).padding(.horizontal, 12).padding(.bottom, 18)
                ForEach(SettingsPage.allCases) { item in
                    Button { hotKeys.setRecording(false); page = item } label: {
                        Label(item.rawValue, systemImage: item.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 10)
                            .background(page == item ? DraftsTheme.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Label("Only on this Mac", systemImage: "lock.shield").font(.system(size: 10)).foregroundStyle(DraftsTheme.secondary).padding(12)
            }.padding(10).frame(width: 180).background(DraftsTheme.text.opacity(0.025))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(page.rawValue).font(.system(size: 23, weight: .semibold))
                    Text(page.subtitle).font(.system(size: 12)).foregroundStyle(DraftsTheme.secondary)
                }.padding(28)
                Divider().padding(.horizontal, 28)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        pageContent
                        SaveErrorBanner(store: store)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(28)
                }.id(page)
            }
        }
        .font(.system(size: 12)).foregroundStyle(DraftsTheme.text)
        .toggleStyle(.switch).controlSize(.small)
        .tint(DraftsTheme.accent)
        .background(DraftsTheme.surface)
        .environment(\.colorScheme, DraftsTheme.palette.scheme)
        .frame(width: 820, height: 640)
    }

    @ViewBuilder private var pageContent: some View {
        switch page {
        case .general: generalSettings
        case .appearance:
            EditorFontSettings(preferences: preferences)
            Divider()
            DisclosureGroup("Colour theme · \(ThemePalette.named(preferences.value.themeID).name)") {
                ThemeChooser(preferences: preferences).padding(.top, 14)
            }
        case .shortcuts: shortcutSettings
        case .organisation:
            if let intelligence { IntelligenceSettings(intelligence: intelligence, preferences: preferences) }
        case .models:
            if let intelligence { TopicModelsSettings(models: intelligence.models, preferences: preferences) }
        case .topics:
            if let intelligence {
                CategoryManager(store: intelligence.categories)
                Divider()
                TopicMemorySettings(intelligence: intelligence, memory: intelligence.memory, preferences: preferences)
            }
        case .storage: storageSettings
        }
    }

    private var shortcutSettings: some View {
        VStack(alignment: .leading, spacing: 22) {
                section("From any app") {
                    shortcutRow("Show / hide notepad", keyPath: \.openShortcut)
                    shortcutRow("All notes (same window)", keyPath: \.listShortcut)
                    shortcutRow("Search notes from any app", keyPath: \.searchShortcut)
                    if let error = shortcutError ?? hotKeys.error {
                        Text(error).font(.system(size: 11)).textSelection(.enabled)
                    }
                    if hotKeys.error != nil { Button("Retry global shortcuts") { hotKeys.register(preferences.value) } }
                }
                Divider()
                section("Inside Drafts") {
                    HStack { Text("New blank note (in Drafts)"); Spacer(); KeyCap(text: "⌘N") }
                    HStack { Text("Copy all and close"); Spacer(); KeyCap(text: LocalCommand.copyAndClose.label) }
                    HStack { Text("Search notes and topics"); Spacer(); KeyCap(text: "⌘K") }
                    HStack { Text("Full screen / restore notepad"); Spacer(); KeyCap(text: LocalCommand.toggleExpansion.label) }
                    HStack { Text("Hide note"); Spacer(); KeyCap(text: "esc") }
                    Text("Type / in the editor to assign a topic. Enter/Tab confirms and removes the command.")
                        .font(.system(size: 11)).foregroundStyle(DraftsTheme.secondary)
                }
        }
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 22) {
            section("Window") {
                Toggle("Keep above other windows", isOn: $preferences.value.keepOnTop)
                HStack {
                    Text("Remember window size for")
                    Spacer()
                    TextField("Minutes", value: $preferences.value.sizeMemoryMinutes, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 60)
                        .onChange(of: preferences.value.sizeMemoryMinutes) { _, value in preferences.value.sizeMemoryMinutes = min(10_080, max(1, value)) }
                    Text("minutes")
                }
                Text("Reopen within this time to restore the previous size, including expanded mode. After that, use the default size.")
                    .font(.system(size: 11)).foregroundStyle(DraftsTheme.secondary)
                Text("Switching apps keeps your note open. Escape or your show/hide shortcut saves and hides it.")
                    .font(.system(size: 11)).foregroundStyle(DraftsTheme.secondary)
            }
            Divider()
            section("Menu bar") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Hide menu bar icon", isOn: $preferences.value.hideMenuBarIcon)
                        .disabled(hotKeys.error != nil)
                    Text("Open Drafts with \(preferences.value.openShortcut.label) or from Applications, then press ⌘, for Settings. The icon stays visible if a global shortcut is unavailable.")
                        .font(.system(size: 11)).foregroundStyle(DraftsTheme.secondary)
                }
            }
        }
    }

    private var storageSettings: some View {
        VStack(alignment: .leading, spacing: 22) {
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
            Text("Notes autosave as you type. Changing appearance never rewrites your saved collection.")
                .font(.system(size: 11)).foregroundStyle(DraftsTheme.secondary)
        }
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
            ShortcutRecorder(shortcut: preferences.value[keyPath: keyPath], onChange: { shortcut in
                shortcutError = preferences.value.shortcutConflict(shortcut, replacing: keyPath)
                guard shortcutError == nil else { return }
                preferences.value[keyPath: keyPath] = shortcut
            }, onRecordingChange: hotKeys.setRecording).frame(width: 155, height: 27)
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

struct EditorFontSettings: View {
    @ObservedObject var preferences: PreferencesStore
    private var previewFont: NSFont { EditorFontOption.font(id: preferences.value.editorFontID, size: preferences.value.editorFontSize) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Notepad text").font(.system(size: 13, weight: .semibold))
            Picker("Font", selection: $preferences.value.editorFontID) {
                ForEach(EditorFontOption.available) { option in
                    Text(option.name).font(Font(EditorFontOption.font(id: option.id, size: 14))).tag(option.id)
                }
            }
            HStack {
                Text("Size")
                Slider(value: $preferences.value.editorFontSize, in: 10...40, step: 1)
                Stepper(value: $preferences.value.editorFontSize, in: 10...40, step: 1) {
                    Text("\(Int(preferences.value.editorFontSize)) pt").monospacedDigit().frame(width: 44)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("A little room to think.").font(Font(previewFont))
                Text("Meeting notes, bright ideas, and the next thing to build.").font(Font(previewFont))
                HStack(spacing: 14) {
                    Text("Bold").font(Font(NSFontManager.shared.convert(previewFont, toHaveTrait: .boldFontMask)))
                    Text("Italic").font(Font(NSFontManager.shared.convert(previewFont, toHaveTrait: .italicFontMask)))
                    Text("0123456789").font(Font(previewFont))
                }
            }.frame(maxWidth: .infinity, minHeight: 145, alignment: .leading).padding(20)
                .background(DraftsTheme.text.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(DraftsTheme.secondary.opacity(0.15)))
                .accessibilityLabel("Font preview")
            HStack {
                Text("Built-in Mac fonts. Bold, italic and underline are preserved.").font(.system(size: 11)).foregroundStyle(DraftsTheme.secondary)
                Spacer()
                Button("Reset") { preferences.value.editorFontID = "system"; preferences.value.editorFontSize = 16 }
            }
        }
    }
}
