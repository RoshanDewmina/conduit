#if os(iOS)
import SwiftUI

/// PR detail surface — real link/state when available; honest empty state otherwise.
public struct PRDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let prState: ReviewPRState?

    public init(prState: ReviewPRState? = nil) {
        self.prState = prState
    }

    public var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 12) {
                    Text(prState?.displayTitle ?? "Pull request")
                        .font(.system(size: 22, weight: .bold))
                        .padding(.top, 20)

                    if let prState, let url = prState.url {
                        statusRow(isOpen: prState.isOpen)

                        if let number = prState.number {
                            Text("#\(number)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Link(destination: url) {
                            Label("Open on GitHub", systemImage: "safari")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .accessibilityIdentifier("pr-detail-open-github")

                        Text(url.absoluteString)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    } else {
                        Text("Not available yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("PR status and diffs will show here when ship actions are wired to a real pull request.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func statusRow(isOpen: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isOpen ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            Text(isOpen ? "Open" : "Closed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(isOpen ? "PR status Open" : "PR status Closed"))
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

#Preview("Stub") {
    NavigationStack {
        PRDetailView()
    }
}

#Preview("Open PR") {
    NavigationStack {
        PRDetailView(
            prState: ReviewPRState(
                url: URL(string: "https://github.com/example/repo/pull/42"),
                title: "Review sheet PR actions",
                number: 42,
                isOpen: true
            )
        )
    }
}
#endif
