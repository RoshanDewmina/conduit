#if os(iOS)
import SwiftUI

/// Model picker sheet — single list of Claude Code models with one checkmark
/// source of truth (no duplicated "Active" + "More" rows).
public struct ModelPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let selected: DispatchModelSelection
    let onSelect: (DispatchModelSelection) -> Void

    public init(
        selected: DispatchModelSelection,
        onSelect: @escaping (DispatchModelSelection) -> Void
    ) {
        self.selected = selected
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 0) {
            RepoSheetHeader(title: "Model") { dismiss() }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    RepoSectionHeader(title: "Claude Code")
                        .padding(.top, 20)

                    ForEach(DispatchModelSelection.allCases, id: \.self) { model in
                        modelRow(model, showsCheckmark: model == selected) {
                            onSelect(model)
                            dismiss()
                        }
                        Divider()
                            .padding(.leading, 58)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func modelRow(
        _ model: DispatchModelSelection,
        showsCheckmark: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                Text(model.displayName)
                    .font(.system(size: 17))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer()

                if showsCheckmark {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(model.displayName))
        .accessibilityAddTraits(showsCheckmark ? .isSelected : [])
    }
}

#Preview {
    Color(.systemGroupedBackground)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            ModelPickerView(selected: .haiku, onSelect: { _ in })
        }
}
#endif
