#if os(iOS)
import SwiftUI

/// Cursor-parity Source filter: Phone (ledger) vs Desktop (observed sessions).
struct ThreadListSourceFilterSheet: View {
    @Binding var prefs: ThreadListFilterPrefs
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Show All", isOn: showAllBinding)
                }

                Section {
                    sourceToggle(.phone, isOn: prefs.showPhone)
                    sourceToggle(.desktop, isOn: prefs.showDesktop)
                } footer: {
                    Text("Phone is threads you dispatched from Lancer. Desktop is observed host sessions.")
                }
            }
            .navigationTitle("Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("thread-list-source-filter")
    }

    private var showAllBinding: Binding<Bool> {
        Binding(
            get: { prefs.showAllSources },
            set: { prefs = ThreadListFilters.applyingShowAllSources(prefs, enabled: $0) }
        )
    }

    private func sourceToggle(_ source: ThreadListFilterSource, isOn: Bool) -> some View {
        Toggle(source.label, isOn: Binding(
            get: { isOn },
            set: { prefs = ThreadListFilters.applyingSource(prefs, source, enabled: $0) }
        ))
        .accessibilityIdentifier("thread-list-source.\(source.rawValue)")
    }
}
#endif
