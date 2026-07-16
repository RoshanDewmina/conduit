#if os(iOS)
import SwiftUI

/// Shared inline failure banner with Retry — used by catalog lists, search,
/// composer attachment transport, and similar honesty surfaces.
struct InlineRetryBanner: View {
    let title: String
    var message: String? = nil
    var retryTitle: String = "Retry"
    var accessibilityRetryLabel: String? = nil
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                if let message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(retryTitle, action: onRetry)
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityLabel(Text(accessibilityRetryLabel ?? retryTitle))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    private var accessibilitySummary: String {
        if let message, !message.isEmpty {
            return "\(title). \(message). \(retryTitle)."
        }
        return "\(title). \(retryTitle)."
    }
}
#endif
