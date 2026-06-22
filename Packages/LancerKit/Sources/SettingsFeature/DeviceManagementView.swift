#if os(iOS)
import SwiftUI
import AccountKit
import DesignSystem

public struct DeviceManagementView: View {
    @Environment(\.lancerTokens) private var t
    @Environment(\.dismiss) private var dismiss

    private let backendURL: String
    private let accountSession: AccountSessionController?

    @State private var devices: [BoundDevice] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var revokingID: String?
    @State private var pendingRevoke: BoundDevice?

    public init(backendURL: String, accountSession: AccountSessionController?) {
        self.backendURL = backendURL
        self.accountSession = accountSession
    }

    private var resolvedBackend: URL? {
        let trimmed = backendURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    private var canManage: Bool {
        accountSession?.isStandardAccount == true && resolvedBackend != nil
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                DSDetailHeader("devices", onBack: { dismiss() })

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if isLoading {
                            ProgressView()
                                .tint(t.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else if let errorText {
                            DSQuoteBlock(title: "couldn't load devices", message: errorText, tone: .danger)
                                .accessibilityIdentifier("devices.error")
                            DSButton("retry", variant: .secondary, size: .sm, mono: true) {
                                Task { await load() }
                            }
                        } else if !canManage {
                            DSQuoteBlock(
                                title: "no account",
                                message: "Sign in to a standard Lancer account to manage bound daemons.",
                                tone: .accent
                            )
                            .accessibilityIdentifier("devices.noAccount")
                        } else if devices.isEmpty {
                            DSQuoteBlock(
                                title: "no devices yet",
                                message: "Pair a daemon from Onboarding to bind it to your account.",
                                tone: .accent
                            )
                            .accessibilityIdentifier("devices.empty")
                        } else {
                            ForEach(devices) { device in
                                deviceCard(device)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .task { await load() }
        .alert("Revoke device", isPresented: revokeAlertBinding, presenting: pendingRevoke) { device in
            Button("Cancel", role: .cancel) { pendingRevoke = nil }
            Button("Revoke", role: .destructive) {
                let target = device
                pendingRevoke = nil
                Task { await revoke(target) }
            }
        } message: { device in
            Text("The daemon \"\(device.name)\" will no longer be able to act on this account until it is paired again.")
        }
    }

    private var revokeAlertBinding: Binding<Bool> {
        Binding(get: { pendingRevoke != nil }, set: { if !$0 { pendingRevoke = nil } })
    }

    @ViewBuilder
    private func deviceCard(_ device: BoundDevice) -> some View {
        let status = device.status()
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(device.name)
                    .font(.dsDisplayPt(15, weight: .bold))
                    .foregroundStyle(t.text)
                Spacer(minLength: 0)
                statusBadge(status)
            }
            Text("fp \(device.publicFingerprint.prefix(12))…")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text3)
            if let bound = boundLabel(device) {
                Text(bound)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }
            if status != .revoked {
                DSButton(
                    "revoke",
                    variant: .destructive,
                    size: .sm,
                    mono: true,
                    isLoading: revokingID == device.id
                ) {
                    Haptics.selection()
                    pendingRevoke = device
                }
                .accessibilityIdentifier("devices.revoke.\(device.id)")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(t.border, lineWidth: 1))
    }

    @ViewBuilder
    private func statusBadge(_ status: BoundDevice.Status) -> some View {
        Text(badgeLabel(status))
            .font(.dsMonoPt(10, weight: .bold))
            .foregroundStyle(badgeColor(status))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(t.surface2, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func badgeLabel(_ status: BoundDevice.Status) -> String {
        switch status {
        case .active: "ACTIVE"
        case .awaitingDaemon: "AWAITING"
        case .pending: "PENDING"
        case .expired: "EXPIRED"
        case .revoked: "REVOKED"
        }
    }

    private func badgeColor(_ status: BoundDevice.Status) -> Color {
        switch status {
        case .active: t.ok
        case .awaitingDaemon, .pending: t.accent
        case .expired: t.text3
        case .revoked: t.warn
        }
    }

    private func boundLabel(_ device: BoundDevice) -> String? {
        guard let raw = device.redeemedAt ?? device.boundAt, !raw.isEmpty else { return nil }
        if let date = BoundDevice.parseDate(raw) {
            return "bound \(date.formatted(date: .abbreviated, time: .shortened))"
        }
        return "bound \(raw)"
    }

    private func load() async {
        guard canManage, let backend = resolvedBackend, let session = accountSession else {
            devices = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            devices = try await session.listDevices(backendURL: backend)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func revoke(_ device: BoundDevice) async {
        guard let backend = resolvedBackend, let session = accountSession else { return }
        Haptics.warning()
        revokingID = device.id
        defer { revokingID = nil }
        do {
            try await session.revokeDevice(id: device.id, backendURL: backend)
            Haptics.success()
            await load()
        } catch {
            errorText = error.localizedDescription
            Haptics.error()
        }
    }
}
#endif
