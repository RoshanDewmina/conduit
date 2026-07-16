#if os(iOS)
import SwiftUI

/// Cursor-parity Customize sheet: Group by, Status/Source filters, Agent Metadata toggles.
struct ThreadListCustomizeSheet: View {
    @Binding var prefs: ThreadListFilterPrefs
    @Environment(\.dismiss) private var dismiss
    @State private var isStatusPresented = false
    @State private var isSourcePresented = false

    var body: some View {
        NavigationStack {
            List {
                Section("Group by") {
                    ForEach(ThreadListGroupBy.allCases, id: \.self) { option in
                        Button {
                            prefs.groupBy = option
                        } label: {
                            HStack {
                                Text(option.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if prefs.groupBy == option {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .accessibilityIdentifier("thread-list-group.\(option.rawValue)")
                    }
                }

                Section("Filter rows") {
                    Button {
                        isStatusPresented = true
                    } label: {
                        filterRow(title: "Status", value: ThreadListFilters.statusSummary(prefs))
                    }
                    .accessibilityIdentifier("thread-list-customize.status")

                    Button {
                        isSourcePresented = true
                    } label: {
                        filterRow(title: "Source", value: ThreadListFilters.sourceSummary(prefs))
                    }
                    .accessibilityIdentifier("thread-list-customize.source")
                }

                Section("Agent Metadata") {
                    Toggle("Diff stats", isOn: $prefs.showDiffStats)
                        .accessibilityIdentifier("thread-list-meta.diffStats")
                    Toggle("Last updated", isOn: $prefs.showLastUpdated)
                        .accessibilityIdentifier("thread-list-meta.lastUpdated")
                }
            }
            .navigationTitle("Customize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isStatusPresented) {
                ThreadListStatusFilterSheet(prefs: $prefs)
            }
            .sheet(isPresented: $isSourcePresented) {
                ThreadListSourceFilterSheet(prefs: $prefs)
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("thread-list-customize")
    }

    private func filterRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }
}
#endif
