#if os(iOS)
import SwiftUI

/// Cursor-parity Status filter: Show All master + per-status toggles.
struct ThreadListStatusFilterSheet: View {
    @Binding var prefs: ThreadListFilterPrefs
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Show All", isOn: showAllBinding)
                }

                Section {
                    statusToggle(.working, isOn: prefs.showWorking)
                    statusToggle(.completed, isOn: prefs.showCompleted)
                    statusToggle(.failed, isOn: prefs.showFailed)
                    statusToggle(.archived, isOn: prefs.showArchived)
                    statusToggle(.unread, isOn: prefs.showUnread)
                }
            }
            .navigationTitle("Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("thread-list-status-filter")
    }

    private var showAllBinding: Binding<Bool> {
        Binding(
            get: { prefs.showAllStatuses },
            set: { prefs = ThreadListFilters.applyingShowAllStatuses(prefs, enabled: $0) }
        )
    }

    private func statusToggle(_ status: ThreadListFilterStatus, isOn: Bool) -> some View {
        Toggle(status.label, isOn: Binding(
            get: { isOn },
            set: { prefs = ThreadListFilters.applyingStatus(prefs, status, enabled: $0) }
        ))
        .accessibilityIdentifier("thread-list-status.\(status.rawValue)")
    }
}
#endif
