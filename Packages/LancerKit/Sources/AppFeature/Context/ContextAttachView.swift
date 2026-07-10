#if os(iOS)
import SwiftUI

/// Section 6 of the frontend rebuild: a faithful, Apple-native recreation of
/// the Cursor-mobile "Context" attach sheet (owner reference screenshots
/// `IMG_2421`/`IMG_2422`). Presented from the New Chat composer's leading
/// `+` attach button. Visual-only for this milestone — the recent-context
/// thumbnail strip is static placeholder cards (not real screenshots), the
/// "Mode" rows (Plan/Draft) carry a simple selected/unselected visual state
/// with no real behavior, and the "Add" rows (Photos/Screenshots/Camera/
/// Files/MCP Servers) are all no-ops. System `SF Symbols` + semantic colors
/// only, no DesignSystem module. Reuses the shared sheet chrome
/// (`RepoSheetHeader`, `RepoSectionHeader`) defined in `RepoPickerView.swift`.
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

                thumbnailStrip
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

    private var thumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Self.thumbnails) { thumbnail in
                    ContextThumbnailCard(thumbnail: thumbnail)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Static sample data

    private static let thumbnails: [ContextThumbnail] = [
        ContextThumbnail(systemImage: "list.bullet.rectangle", tint: .blue),
        ContextThumbnail(systemImage: "chart.bar.xaxis", tint: .orange),
        ContextThumbnail(systemImage: "person.crop.circle.fill", tint: .purple),
        ContextThumbnail(systemImage: "doc.plaintext", tint: .teal),
    ]

    private static let addRows: [ContextAddRowModel] = [
        ContextAddRowModel(title: "Photos", systemImage: "photo", trailing: .none),
        ContextAddRowModel(title: "Screenshots", systemImage: "square.dashed", trailing: .chevron),
        ContextAddRowModel(title: "Camera", systemImage: "camera", trailing: .none),
        ContextAddRowModel(title: "Files", systemImage: "folder", trailing: .none),
        ContextAddRowModel(title: "MCP Servers", systemImage: "puzzlepiece.extension", trailing: .badgeAndChevron(count: 3)),
    ]
}

// MARK: - Mode section

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

// MARK: - Add section

enum ContextAddRowTrailing {
    case none
    case chevron
    case badgeAndChevron(count: Int)
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
            // No-op for this milestone.
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
                case .badgeAndChevron(let count):
                    Text("\(count)")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
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

// MARK: - Recent-context thumbnail strip

/// Static placeholder card standing in for a real recent-context screenshot
/// thumbnail — a tinted rounded rectangle with a representative SF Symbol,
/// proportioned to match the reference's small horizontally-scrolling cards.
struct ContextThumbnail: Identifiable {
    let id = UUID()
    let systemImage: String
    let tint: Color
}

struct ContextThumbnailCard: View {
    let thumbnail: ContextThumbnail

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.secondarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )
            .overlay(
                Image(systemName: thumbnail.systemImage)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(thumbnail.tint.opacity(0.8))
            )
            .frame(width: 108, height: 128)
    }
}

#Preview {
    ContextAttachView()
}
#endif
