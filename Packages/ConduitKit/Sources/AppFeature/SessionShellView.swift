#if os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem
import SessionFeature
import InboxFeature
import PreviewFeature
import FilesFeature
import SSHTransport
import DiffFeature
import DiffKit
import SettingsFeature

enum SessionSurface: Hashable, CaseIterable {
    case terminal
    case preview
    case files
    case diff
    case inbox

    var title: String {
        switch self {
        case .terminal: "Terminal"
        case .preview: "Preview"
        case .files: "Files"
        case .diff: "Diff"
        case .inbox: "Inbox"
        }
    }

    var systemImage: String {
        switch self {
        case .terminal: "terminal"
        case .preview: "safari"
        case .files: "folder"
        case .diff: "plusminus"
        case .inbox: "tray"
        }
    }
}

struct SessionShellView: View {
    let viewModel: SessionViewModel?
    let inboxViewModel: InboxViewModel

    @State private var surface: SessionSurface = .terminal
    @State private var pm = PurchaseManager.shared
    @State private var showingPaywall = false
    @State private var paywallFeature = ""
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.conduitTokens) private var t

    private var isPro: Bool {
        #if DEBUG
        return true // DEV: Pro unlocked for UX eval — restore before release
        #else
        switch pm.purchaseState {
        case .purchased, .unknown: return true
        default: return false
        }
        #endif
    }

    var body: some View {
        if let viewModel {
            VStack(spacing: 0) {
                surfaceSwitcher
                Divider()
                surfaceContent(for: viewModel)
                    .id("\(viewModel.sessionID.uuidString)-\(surface.title)")
            }
            .navigationTitle(viewModel.host.name)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingPaywall) {
                PaywallSheet(featureName: paywallFeature)
            }
        } else {
            ContentUnavailableView(
                "No active session",
                systemImage: "terminal",
                description: Text("Pick a host from Workspaces to begin.")
            )
            .navigationTitle("Session")
        }
    }

    @ViewBuilder
    private var surfaceSwitcher: some View {
        HStack {
            if horizontalSizeClass == .compact {
                compactSurfaceMenu
                Spacer()
            } else {
                regularSurfacePicker
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(t.hudBg)
    }

    private var compactSurfaceMenu: some View {
        Menu {
            ForEach(SessionSurface.allCases, id: \.self) { item in
                Button {
                    surface = item
                } label: {
                    Label(item.title, systemImage: item.systemImage)
                }
            }
        } label: {
            Label(surface.title, systemImage: surface.systemImage)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minWidth: 132, alignment: .leading)
        }
        .background(t.termSurface2, in: Capsule())
    }

    private var regularSurfacePicker: some View {
        Picker("Session surface", selection: $surface) {
            ForEach(SessionSurface.allCases, id: \.self) { item in
                Label(item.title, systemImage: item.systemImage).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(6)
        .background(t.termSurface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func surfaceContent(for viewModel: SessionViewModel) -> some View {
        switch surface {
        case .terminal:
            SessionView(viewModel: viewModel)
        case .preview:
            if isPro {
                SmartPreviewView(session: viewModel.session)
            } else {
                ProGateView(featureName: "Dev Server Preview") {
                    paywallFeature = "Dev Server Preview"
                    showingPaywall = true
                }
            }
        case .files:
            if isPro {
                SFTPFilesView(
                    viewModel: SFTPFilesViewModel(
                        sftp: SFTPClient(session: viewModel.session),
                        initialPath: viewModel.cwd
                    )
                )
            } else {
                ProGateView(featureName: "SFTP File Browser") {
                    paywallFeature = "SFTP File Browser"
                    showingPaywall = true
                }
            }
        case .diff:
            if isPro {
                diffSurface(for: viewModel)
            } else {
                ProGateView(featureName: "Diff Review") {
                    paywallFeature = "Diff Review"
                    showingPaywall = true
                }
            }
        case .inbox:
            if isPro {
                InboxView(
                    viewModel: inboxViewModel,
                    sessionID: viewModel.sessionID,
                    title: "Session Inbox"
                )
            } else {
                ProGateView(featureName: "AI Agent Inbox") {
                    paywallFeature = "AI Agent Inbox"
                    showingPaywall = true
                }
            }
        }
    }

    @ViewBuilder
    private func diffSurface(for viewModel: SessionViewModel) -> some View {
        if let patch = latestPatch(for: viewModel) {
            DiffView(diff: UnifiedDiffParser.parse(patch))
        } else {
            ContentUnavailableView(
                "No patch pending",
                systemImage: "plusminus",
                description: Text("Patch approvals for this session appear here.")
            )
            .navigationTitle("Diff")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func latestPatch(for viewModel: SessionViewModel) -> String? {
        inboxViewModel.approvals.first {
            $0.sessionID == viewModel.sessionID && $0.kind == .patch && $0.patch != nil
        }?.patch
    }
}

private struct ProGateView: View {
    let featureName: String
    let onUpgrade: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("\(featureName) · Pro")
                .font(.title3.weight(.semibold))
            Text("Upgrade to Conduit Pro to unlock this feature.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Upgrade to Pro") { onUpgrade() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
