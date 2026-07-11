#if os(iOS)
import SwiftUI

/// Context attach sheet — honest empty recent-context strip; add rows are
/// affordances only (no fake MCP counts or invented thumbnails).
public struct ContextAttachView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMode: ContextMode = .plan

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RepoSheetHeader(title: "Context") { dismiss() }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 16)

                Text("No recent context yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                RepoSectionHeader(title: "Mode")

                VStack(spacing: 0) {
                    ForEach(ContextMode.allCases) { mode in
                        ContextModeRow(mode: mode, isSelected: selectedMode == mode) {
                            selectedMode = mode
                        }
                        Divider()
                            .padding(.leading, 58)
                    }
                }
                .padding(.top, 20)

                RepoSectionHeader(title: "Add")
                    .padding(.top, 24)

                VStack(spacing: 0) {
                    ForEach(Self.addRows) { row in
                        ContextAddRow(row: row)
                        Divider()
                            .padding(.leading, 58)
                    }
                }
                .padding(.top, 20)
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private static let addRows: [ContextAddRowModel] = [
        ContextAddRowModel(title: "Photos", systemImage: "photo", trailing: .none),
        ContextAddRowModel(title: "Screenshots", systemImage: "square.dashed", trailing: .chevron),
        ContextAddRowModel(title: "Camera", systemImage: "camera", trailing: .none),
        ContextAddRowModel(title: "Files", systemImage: "folder", trailing: .none),
        ContextAddRowModel(title: "MCP Servers", systemImage: "puzzlepiece.extension", trailing: .chevron),
    ]
}

enum ContextMode: String, CaseIterable, Identifiable {
    case plan
    case draft

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plan: return "Plan"
        case .draft: return "Draft"
        }
    }

    var systemImage: String {
        switch self {
        case .plan: return "checklist"
        case .draft: return "circle.dashed"
        }
    }
}

struct ContextModeRow: View {
    let mode: ContextMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 24)

                Text(mode.title)
                    .font(.system(size: 17))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

enum ContextAddRowTrailing {
    case none
    case chevron
}

struct ContextAddRowModel: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let trailing: ContextAddRowTrailing
}

struct ContextAddRow: View {
    let row: ContextAddRowModel

    var body: some View {
        Button {
            // Affordance only — attach wiring deferred.
        } label: {
            HStack(spacing: 14) {
                Image(systemName: row.systemImage)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                Text(row.title)
                    .font(.system(size: 17))
                    .foregroundStyle(.primary)

                Spacer()

                switch row.trailing {
                case .none:
                    EmptyView()
                case .chevron:
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContextAttachView()
}
#endif
