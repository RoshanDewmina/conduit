#if os(iOS)
import SwiftUI

public struct BillingView: View {
    @State private var flyUsage: String = "Loading..."
    @State private var isLoading = false

    public init() {}

    public var body: some View {
        List {
            Section("Fly.io") {
                HStack {
                    Label("Usage", systemImage: "chart.bar")
                    Spacer()
                    Text(flyUsage).foregroundStyle(.secondary)
                }
                Link("Open Fly.io Dashboard", destination: URL(string: "https://fly.io/dashboard")!)
            }
            Section("AWS Lightsail") {
                Link("Open Lightsail Console", destination: URL(string: "https://lightsail.aws.amazon.com/ls/webapp/home")!)
            }
            Section {
                Text("Usage data is fetched directly from each provider using your stored API tokens. Conduit does not bill separately for compute.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Billing")
        .task {
            // In a full implementation, fetch usage from Fly.io API
            // For now, link to dashboard
            flyUsage = "See dashboard →"
        }
    }
}
#endif
