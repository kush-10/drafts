import SwiftUI

struct ThemeChooser: View {
    @ObservedObject var preferences: PreferencesStore
    @State private var query = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Appearance").font(.system(size: 11, weight: .medium)).foregroundStyle(DraftsTheme.secondary)
            TextField("Search themes", text: $query).textFieldStyle(.roundedBorder)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(ThemePalette.all.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { theme in
                    Button { preferences.value.themeID = theme.id } label: {
                        HStack(spacing: 6) {
                            Text(theme.name).font(.system(size: 10, weight: .medium, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                            if preferences.value.themeID == theme.id { Image(systemName: "checkmark") }
                            Circle().fill(Color(nsColor: ThemePalette.native(theme.highlight))).frame(width: 9, height: 9)
                        }.foregroundStyle(Color(nsColor: ThemePalette.native(theme.foreground)))
                            .padding(10).frame(maxWidth: .infinity)
                            .background(Color(nsColor: ThemePalette.native(theme.background)), in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(nsColor: ThemePalette.native(theme.highlight)).opacity(preferences.value.themeID == theme.id ? 1 : 0.2), lineWidth: preferences.value.themeID == theme.id ? 2 : 1))
                    }.buttonStyle(.plain).help(theme.name).accessibilityLabel(theme.name)
                        .accessibilityValue(preferences.value.themeID == theme.id ? "Selected" : "")
                }
            }
            Text("Live preview · Catppuccin palettes and original Drafts themes. Credits are included with the app.")
                .font(.system(size: 10)).foregroundStyle(DraftsTheme.secondary)
        }
    }
}

struct IntelligenceSettings: View {
    @ObservedObject var intelligence: IntelligenceController
    @ObservedObject var preferences: PreferencesStore
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Identify topics after saving", isOn: $preferences.value.autoOrganise)
            Text("Five fixed topics, with multiple matches allowed. Prompt marks AI requests on any subject; it does not extract or execute them. Searching never runs the model.")
                .font(.system(size: 11)).foregroundStyle(DraftsTheme.secondary)
            OrganisationControls(intelligence: intelligence)
            Divider()
            Picker("Unload model after inactivity", selection: $preferences.value.modelIdleSeconds) {
                Text("Immediately after processing").tag(0)
                Text("30 seconds").tag(30)
                Text("1 minute").tag(60)
            }
            Text("Unloading frees RAM; deleting removes the downloaded files. Your notes always stay on this Mac.")
                .font(.system(size: 11)).foregroundStyle(DraftsTheme.secondary)
            Text(intelligence.status).font(.system(size: 11)).foregroundStyle(DraftsTheme.secondary)
            if let error = intelligence.lastError ?? intelligence.organisationState.lastError {
                Text(error).font(.system(size: 11)).foregroundStyle(DraftsTheme.accent).textSelection(.enabled)
            }
        }
    }
}

struct TopicMemorySettings: View {
    @ObservedObject var intelligence: IntelligenceController
    @ObservedObject var memory: TopicMemoryBank
    @ObservedObject var preferences: PreferencesStore
    @State private var clearConfirmation = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Use confirmed notes as topic memory", isOn: $preferences.value.useTopicMemory)
            Text("Manual corrections and ‘Remember these topics’ provide examples. On a save, up to three relevant excerpts help the model interpret similar notes. Its own guesses are never learned as facts. This is local context, not model retraining.")
                .font(.system(size: 11)).foregroundStyle(DraftsTheme.secondary)
            DisclosureGroup("Memory bank · \(memory.count) confirmed notes") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(intelligence.memorySummaries) { entry in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.title).lineLimit(1)
                                if !entry.included.isEmpty { Text("Confirmed: " + entry.included).font(.system(size: 10)).foregroundStyle(DraftsTheme.secondary) }
                                if !entry.excluded.isEmpty { Text("Not: " + entry.excluded).font(.system(size: 10)).foregroundStyle(DraftsTheme.secondary) }
                            }
                            Spacer()
                            Button("Forget") { memory.forget(entry.id) }.buttonStyle(.plain)
                        }
                    }
                    if memory.count == 0 { Text("Correct or confirm a saved note’s topics to start building memory.").foregroundStyle(DraftsTheme.secondary) }
                    Button("Clear memory…") { clearConfirmation = true }.disabled(memory.count == 0)
                }.padding(.top, 8)
            }
            if let error = memory.lastError { Text(error).font(.system(size: 11)).foregroundStyle(DraftsTheme.accent) }
        }
        .alert("Clear topic memory?", isPresented: $clearConfirmation) {
            Button("Clear memory", role: .destructive) { memory.clear() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes remembered examples, not notes or manual topic assignments. New confirmations can build memory again.") }
    }
}

struct TopicModelsSettings: View {
    @ObservedObject var models: TopicModelManager
    @ObservedObject var preferences: PreferencesStore
    @State private var downloadTarget: TopicModel?
    @State private var deleteTarget: TopicModel?
    @State private var expandedTiers: Set<ModelTier> = []
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Installed models · \(models.installedIDs.count)").font(.system(size: 12, weight: .medium))
            ForEach(TopicModel.catalogue.filter { models.installedIDs.contains($0.id) || models.downloadingID == $0.id }) { model in
                modelRow(model)
            }
            Text("Choose from \(TopicModel.catalogue.count) local models. Qwen 3.5 2B is the lightweight suggestion; 9B is recommended for 24 GB+ Macs. Download size is not runtime RAM usage.")
                .font(.system(size: 11)).foregroundStyle(DraftsTheme.secondary)
            ForEach(ModelTier.allCases) { tier in
                let available = TopicModel.catalogue.filter { $0.tier == tier && !models.installedIDs.contains($0.id) && models.downloadingID != $0.id }.sorted { $0.downloadBytes < $1.downloadBytes }
                if !available.isEmpty {
                    DisclosureGroup("\(tier.rawValue) · \(available.count)", isExpanded: Binding(get: { expandedTiers.contains(tier) }, set: {
                        if $0 { expandedTiers.insert(tier) } else { expandedTiers.remove(tier) }
                    })) {
                        VStack(alignment: .leading, spacing: 14) { ForEach(available) { modelRow($0) } }.padding(.top, 8)
                    }
                }
            }
            if let error = models.lastError { Text(error).font(.system(size: 11)).foregroundStyle(DraftsTheme.accent).textSelection(.enabled) }
            Text("Downloads use Hugging Face only when you click Download. No notes are sent. No Ollama or separate service is needed.")
                .font(.system(size: 10)).foregroundStyle(DraftsTheme.secondary)
        }
        .alert("Download local AI model?", isPresented: Binding(get: { downloadTarget != nil }, set: { if !$0 { downloadTarget = nil } })) {
            Button("Download") { if let model = downloadTarget { models.startDownload(model) }; downloadTarget = nil }
            Button("Cancel", role: .cancel) { downloadTarget = nil }
        } message: { Text("\(downloadTarget?.name ?? "Model") needs \(downloadTarget?.sizeLabel ?? "several GB") of disk space, plus working memory when loaded. Licence: \(downloadTarget?.licence ?? "see source terms"). Review the source/licence links before downloading. Verified files are kept if cancelled so Retry can reuse them.") }
        .alert("Delete downloaded model?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
            Button("Delete model", role: .destructive) { if let model = deleteTarget { models.delete(model) }; deleteTarget = nil }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: { Text("Your notes and topics will be kept. You can download this model again later.") }
    }

    private func modelRow(_ model: TopicModel) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name).fontWeight(.medium)
                if let recommendation = model.recommendation { Text(recommendation).font(.system(size: 10)).foregroundStyle(DraftsTheme.accent) }
                Text("\(model.sizeLabel) download · MLX 4-bit · \(model.minimumMemoryGB) GB+ RAM")
                    .font(.system(size: 10)).foregroundStyle(DraftsTheme.secondary)
                Text(model.guidance).font(.system(size: 10)).foregroundStyle(DraftsTheme.secondary).fixedSize(horizontal: false, vertical: true)
                HStack { Link("Source", destination: model.sourceURL); Link(model.licence, destination: model.licenceURL) }.font(.system(size: 10))
                if !model.canRun() { Text(TopicModel.supportedHardware ? "Not available with this Mac’s memory" : "Requires Apple Silicon").font(.system(size: 10)).foregroundStyle(DraftsTheme.secondary) }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                if models.downloadingID == model.id {
                    ProgressView(value: models.downloadProgress).frame(width: 70)
                    Text(models.downloadProgress.formatted(.percent.precision(.fractionLength(0)))).font(.system(size: 10)).monospacedDigit()
                    Button("Cancel") { models.cancelDownload() }
                } else if models.installedIDs.contains(model.id) {
                    if preferences.value.topicModelID == model.id { Text("Selected").foregroundStyle(DraftsTheme.accent) }
                    else { Button("Select") { preferences.value.topicModelID = model.id }.disabled(!model.canRun()) }
                    Button("Delete…") { deleteTarget = model }
                } else {
                    Button(models.partialIDs.contains(model.id) ? "Retry…" : "Download…") { downloadTarget = model }.disabled(models.downloadingID != nil || !model.canRun())
                    if models.partialIDs.contains(model.id) { Button("Delete partial…") { deleteTarget = model } }
                }
            }.buttonStyle(.plain)
        }
    }
}

struct CategoryManager: View {
    @ObservedObject var store: CategoryStore
    @State private var editingID: UUID?
    @State private var name = ""
    @State private var details = ""
    @State private var deleteTarget: NoteCategory?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your topics").font(.system(size: 12, weight: .medium))
            Text(store.hasFixedTopics ? "Mandir, University and Dev are domains. Prompt is a secondary marker; Scratchpad is the fallback. Edit descriptions to clarify boundaries. Manual choices are protected." : "Topics are assigned after saves. Manual choices are protected.")
                .font(.system(size: 11)).foregroundStyle(DraftsTheme.secondary)
            ForEach(store.categories) { category in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.name)
                        if !category.description.isEmpty { Text(category.description).font(.system(size: 10)).foregroundStyle(DraftsTheme.secondary).lineLimit(2) }
                    }
                    Spacer()
                    Button("Edit") { editingID = category.id; name = category.name; details = category.description }
                    if !store.hasFixedTopics { Button { deleteTarget = category } label: { Image(systemName: "trash") }.accessibilityLabel("Delete \(category.name) topic") }
                }.buttonStyle(.plain)
            }
            if !store.hasFixedTopics || editingID != nil {
            TextField("Topic name", text: $name).textFieldStyle(.roundedBorder).disabled(store.hasFixedTopics)
            TextField("What belongs here? Examples or a short description", text: $details, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2...4)
                .onChange(of: details) { _, value in if value.utf8.count > 1400 { details = String(value.prefix(300)) } }
            HStack {
                Button(editingID == nil ? "Add topic" : "Save topic") {
                    if store.saveCategory(id: editingID, name: name, description: details) { editingID = nil; name = ""; details = "" }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if editingID != nil { Button("Cancel edit") { editingID = nil; name = ""; details = "" } }
            }.buttonStyle(.plain)
            if let error = store.lastError { Text(error).font(.system(size: 11)).foregroundStyle(DraftsTheme.accent) }
            }
        }
        .alert("Delete topic?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
            Button("Delete topic", role: .destructive) { if let target = deleteTarget { store.deleteCategory(target.id) }; deleteTarget = nil }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: { Text("Your notes will be kept. Only the topic and its assignments will be removed.") }
    }
}

struct CategoryAssignmentMenu: View {
    @ObservedObject var store: CategoryStore
    let noteID: UUID
    var compact = false
    var body: some View {
        Menu {
            if store.categories.isEmpty { Text("Topics appear after saving with a downloaded model") }
            ForEach(store.categories) { category in
                Toggle(category.name, isOn: Binding(get: { store.labels(for: noteID).effective.contains(category.id) }, set: {
                    store.setManual(category.id, noteID: noteID, included: $0)
                }))
            }
            Divider()
            Button("Remember these topics for similar notes") { store.confirmTopics(noteID: noteID) }
                .disabled(store.labels(for: noteID).effective.isEmpty)
            Button("Use automatic topics") { store.useAutomatic(noteID: noteID) }
        } label: {
            if compact { Image(systemName: "tag").accessibilityLabel("Note topics") }
            else {
                Label(store.names(for: noteID).isEmpty ? "No topics" : store.names(for: noteID), systemImage: "tag")
                    .lineLimit(1).truncationMode(.tail)
            }
        }.menuStyle(.borderlessButton).fixedSize(horizontal: false, vertical: true)
            .help((store.names(for: noteID).isEmpty ? "No topics" : store.names(for: noteID)) + ". Click to change topics; manual choices are protected from automatic changes.")
    }
}
