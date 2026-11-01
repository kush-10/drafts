import SwiftUI

struct OrganisationControls: View {
    @ObservedObject var intelligence: IntelligenceController
    @ObservedObject private var models: TopicModelManager
    init(intelligence: IntelligenceController) {
        self.intelligence = intelligence
        models = intelligence.models
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if intelligence.isOrganisingAll {
                HStack {
                    ProgressView(value: Double(intelligence.batchCompleted), total: Double(max(1, intelligence.batchTotal)))
                    Button("Cancel") { intelligence.cancelOrganisation() }
                }
                Text("\(intelligence.batchCompleted) / \(intelligence.batchTotal) processed" + (intelligence.batchFailed > 0 ? " · \(intelligence.batchFailed) failed" : ""))
                    .font(.system(size: 11)).foregroundStyle(DraftsTheme.secondary)
            } else {
                Button("Organise all notes") { intelligence.organiseAllNotes() }
                    .disabled(!intelligence.hasSelectedModel || intelligence.organisableNoteCount == 0)
                Text(intelligence.hasSelectedModel
                     ? "Classifies all existing notes, excluding Trash and blanks. Manual topics and note text stay unchanged."
                     : "Download and select a local model in Settings → Models first.")
                    .font(.system(size: 11)).foregroundStyle(DraftsTheme.secondary)
                if intelligence.batchTotal > 0 {
                    Text(intelligence.status).font(.system(size: 11)).foregroundStyle(DraftsTheme.secondary)
                }
            }
        }
    }
}
