#if os(iOS)
import SwiftUI

/// Agent (vendor CLI) picker for New Chat — filters to host-installed CLIs
/// when `installed` is known; otherwise shows the full catalog. Single list
/// with one checkmark source of truth (no duplicated Active + Installed rows).
public struct VendorPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let selected: DispatchVendorSelection
    let installed: [String]?
    let onSelect: (DispatchVendorSelection) -> Void

    public init(
        selected: DispatchVendorSelection,
        installed: [String]?,
        onSelect: @escaping (DispatchVendorSelection) -> Void
    ) {
        self.selected = selected
        self.installed = installed
        self.onSelect = onSelect
    }

    private var options: [DispatchVendorSelection] {
        DispatchVendorSelection.available(installed: installed, keeping: selected)
    }

    public var body: some View {
        VStack(spacing: 0) {
            RepoSheetHeader(title: "Agent") { dismiss() }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    RepoSectionHeader(title: "Installed")
                        .padding(.top, 20)

                    ForEach(options, id: \.self) { vendor in
                        vendorRow(vendor, showsCheckmark: vendor == selected) {
                            onSelect(vendor)
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

    private func vendorRow(
        _ vendor: DispatchVendorSelection,
        showsCheckmark: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: vendor.systemImage)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                Text(vendor.displayName)
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
        .accessibilityLabel(Text(vendor.displayName))
        .accessibilityAddTraits(showsCheckmark ? .isSelected : [])
    }
}

#Preview {
    Color(.systemGroupedBackground)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            VendorPickerView(
                selected: .claudeCode,
                installed: ["claudeCode", "codex", "opencode"],
                onSelect: { _ in }
            )
        }
}
#endif
