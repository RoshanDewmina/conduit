#if os(iOS)
import SwiftUI

/// Info card under the Review sheet totals when the session branch has no open PR.
struct ReviewPRHintCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .padding(.top, 1)
            Text("PR not opened yet — open a PR from this branch to see CI checks, reviews, and deployments.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("review-pr-hint-card")
    }
}
#endif
