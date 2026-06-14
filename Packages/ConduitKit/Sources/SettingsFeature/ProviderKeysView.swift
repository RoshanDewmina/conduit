#if os(iOS)
import SwiftUI
import DesignSystem
import ConduitCore
import AgentKit

public struct ProviderKeysView: View {
    @State private var vm: SettingsViewModel
    @State private var anthropicInput = ""
    @State private var openaiInput = ""
    @Environment(\.conduitTokens) private var t
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: SettingsViewModel) {
        _vm = State(initialValue: viewModel)
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DSDetailHeader("provider keys", onBack: { dismiss() })

                    Text("API keys go directly from your device to the provider. Conduit never sees them.")
                        .font(.dsSansPt(14))
                        .foregroundStyle(t.text3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .padding(.bottom, 16)

                    providerCard(provider: .anthropic, hasKey: vm.hasAnthropicKey, keyBinding: $anthropicInput)
                    providerCard(provider: .openai, hasKey: vm.hasOpenAIKey, keyBinding: $openaiInput)
                }
            }
        }
        .navigationBarHidden(true)
        .task { await vm.load() }
    }

    @ViewBuilder
    private func providerCard(provider: AIProvider, hasKey: Bool, keyBinding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(provider.displayName)
                    .font(.dsSansPt(14, weight: .semibold))
                    .foregroundStyle(t.text)
                Spacer()
                HStack(spacing: 8) {
                    if hasKey {
                        DSChip("configured", tone: .ok, variant: .soft, size: .sm)
                        Button("Remove", role: .destructive) {
                            Task { await vm.remove(provider) }
                        }
                        .font(.dsSansPt(13))
                        .foregroundStyle(t.danger)
                    } else {
                        DSChip("not set", tone: .neutral, variant: .soft, size: .sm)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            DSDivider(.soft, leadingInset: 16)

            VStack(alignment: .leading, spacing: 8) {
                SecureField(hasKey ? "Replace API key" : "Paste API key", text: keyBinding)
                    .font(.dsMonoPt(13))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(t.surfaceSunk)
                    .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))

                HStack(spacing: 8) {
                    if !keyBinding.wrappedValue.isEmpty {
                        Button("Save") {
                            if provider == .anthropic { vm.anthropicKey = keyBinding.wrappedValue }
                            else if provider == .openai { vm.openaiKey = keyBinding.wrappedValue }
                            Task {
                                await vm.save()
                                keyBinding.wrappedValue = ""
                            }
                        }
                        .font(.dsMonoPt(12, weight: .medium))
                        .foregroundStyle(t.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(t.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                    }
                    if hasKey {
                        if vm.isTestingKey && vm.testKeyProvider == provider {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.7)
                                Text("Testing…").font(.dsMonoPt(11)).foregroundStyle(t.text3)
                            }
                        } else {
                            Button("Test key") {
                                Task { await vm.testKey(provider: provider) }
                            }
                            .font(.dsMonoPt(12, weight: .medium))
                            .foregroundStyle(t.accent)
                            .disabled(!vm.canTestKey)
                        }
                        if let result = vm.testKeyResult, vm.testKeyProvider == provider {
                            Text(result)
                                .font(.dsMonoPt(11))
                                .foregroundStyle(result.hasPrefix("Error") ? t.danger : t.risk(0))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let msg = vm.saveMessage, !msg.isEmpty {
                        Spacer()
                        Text(msg)
                            .font(.dsMonoPt(11))
                            .foregroundStyle(vm.saveIsError ? t.danger : t.risk(0))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }
}
#endif