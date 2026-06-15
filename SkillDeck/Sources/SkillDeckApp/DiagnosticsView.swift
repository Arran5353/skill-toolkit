import SwiftUI
import SkillDeckCore

struct DiagnosticsView: View {
    let store: AppStore
    var body: some View {
        if store.warnings.isEmpty {
            ContentUnavailableView("No issues", systemImage: "checkmark.seal",
                description: Text("All skills and commands parsed cleanly."))
        } else {
            List(Array(store.warnings.enumerated()), id: \.offset) { _, w in
                VStack(alignment: .leading) {
                    Text(w.message).font(.body)
                    Text(w.filePath).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
