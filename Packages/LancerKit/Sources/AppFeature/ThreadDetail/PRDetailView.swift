#if os(iOS)
import SwiftUI

/// PR detail surface — honest empty state until real PR wiring lands.
/// No invented checks / file diffs.
public struct PRDetailView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Pull request")
                        .font(.system(size: 22, weight: .bold))
                        .padding(.top, 20)

                    Text("Not available yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("PR status and diffs will show here when ship actions are wired to a real pull request.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                circleButton(systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Back"))

            Spacer()
        }
    }

    private func circleButton(systemImage: String) -> some View {
        Circle()
            .fill(Color(.secondarySystemBackground))
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
            )
    }
}

#Preview {
    NavigationStack {
        PRDetailView()
    }
}
#endif
