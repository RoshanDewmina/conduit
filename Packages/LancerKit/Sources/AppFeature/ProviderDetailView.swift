#if os(iOS)
import SwiftUI
import DesignSystem
import LancerCore

// MARK: - Provider detail view

struct ProviderDetailView: View {
    let name: String
    let apiKey: String
    let models: [ModelOption]
    @Binding var selectedModel: String
    @Binding var isDefault: Bool
    let usageIn: String
    let usageOut: String
    let onSaveKey: (String) -> Void
    let onTestKey: () -> Void
    let onSelectModel: (String) -> Void
    let onToggleDefault: (Bool) -> Void

    @State private var keyInput = ""
    @State private var showKey = false
    @State private var isConnected = true
    @State private var isTestingKey = false
    @Environment(\.lancerTokens) private var t
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    apiKeySection
                    modelPickerSection
                    defaultAgentToggle
                    usageSummarySection
                }
                .padding(18)
            }
        }
        .navigationBarHidden(true)
        .overlay(alignment: .top) {
            DSDetailHeader(name.lowercased(), onBack: { dismiss() })
                .padding(.horizontal, 0)
        }
    }

    // MARK: - API Key

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(name)
                    .font(.dsSansPt(14, weight: .semibold))
                    .foregroundStyle(t.text)
                Spacer()
                isConnected
                    ? DSChip("connected", tone: .ok, variant: .soft, size: .sm)
                    : DSChip("not connected", tone: .neutral, variant: .soft, size: .sm)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            DSDivider(.soft, leadingInset: 16)

            VStack(alignment: .leading, spacing: 8) {
                maskedKeyField
                actionButtons
                testResultView
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1))
    }

    private var maskedKeyField: some View {
        HStack {
            if showKey {
                Text(apiKey)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text4)
            } else {
                Text(maskedKey)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text4)
                    .tracking(2)
            }
            Spacer()
            Button {
                showKey.toggle()
            } label: {
                Text(showKey ? "hide" : "show")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(t.surfaceSunk)
        .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1))
    }

    private var maskedKey: String {
        guard !apiKey.isEmpty else { return "••••••••••••••••" }
        let prefix = String(apiKey.prefix(min(6, apiKey.count)))
        let suffix = String(apiKey.suffix(min(3, apiKey.count)))
        let maskCount = max(apiKey.count - prefix.count - suffix.count, 0)
        return prefix + String(repeating: "•", count: maskCount) + suffix
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 8) {
            if !keyInput.isEmpty {
                Button("Save") {
                    onSaveKey(keyInput)
                    keyInput = ""
                }
                .font(.dsMonoPt(12, weight: .medium))
                .foregroundStyle(t.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(t.accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
            }
            if isTestingKey {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("Testing…").font(.dsMonoPt(11)).foregroundStyle(t.text3)
                }
            } else {
                DSButton("Test key", variant: .ghost, size: .sm, mono: true) {
                    isTestingKey = true
                    onTestKey()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        isTestingKey = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var testResultView: some View {
        if !keyInput.isEmpty {
            SecureField("Paste API key", text: $keyInput)
                .font(.dsMonoPt(13))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(t.surfaceSunk)
                .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        }
    }

    // MARK: - Model picker

    private var modelPickerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MODEL")
                .font(.dsMonoPt(10))
                .tracking(10 * 0.05)
                .foregroundStyle(t.text4)
            VStack(spacing: 4) {
                ForEach(models) { model in
                    modelOption(model)
                }
            }
        }
    }

    @ViewBuilder
    private func modelOption(_ model: ModelOption) -> some View {
        Button {
            selectedModel = model.id
            onSelectModel(model.id)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            selectedModel == model.id ? t.accent : t.text4,
                            lineWidth: 1.5)
                        .frame(width: 10, height: 10)
                    if selectedModel == model.id {
                        Circle()
                            .fill(t.accent)
                            .frame(width: 6, height: 6)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.name)
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text)
                    if let subtitle = model.subtitle {
                        Text(subtitle)
                            .font(.dsMonoPt(9.5))
                            .foregroundStyle(t.text4)
                    }
                }
                Spacer()
            }
            .padding(10)
            .padding(.horizontal, 2)
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                    .strokeBorder(
                        selectedModel == model.id ? t.accent : t.border,
                        lineWidth: selectedModel == model.id ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Default agent toggle

    private var defaultAgentToggle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Default agent")
                    .font(.dsMonoPt(11.5))
                    .foregroundStyle(t.text)
                Text("Fallback for new sessions")
                    .font(.dsMonoPt(9.5))
                    .foregroundStyle(t.text4)
            }
            Spacer()
            Toggle("", isOn: $isDefault)
                .tint(t.accent)
                .labelsHidden()
                .frame(width: 44)
                .onChange(of: isDefault) { _, newValue in
                    onToggleDefault(newValue)
                }
        }
        .padding(12)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1))
    }

    // MARK: - Usage summary

    private var usageSummarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("USAGE THIS MONTH")
                .font(.dsMonoPt(10))
                .tracking(10 * 0.05)
                .foregroundStyle(t.text4)
            HStack(spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(usageIn)
                        .font(.dsMonoPt(13, weight: .semibold))
                        .foregroundStyle(t.text)
                    Text("tokens in")
                        .font(.dsMonoPt(9.5))
                        .foregroundStyle(t.text4)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(usageOut)
                        .font(.dsMonoPt(13, weight: .semibold))
                        .foregroundStyle(t.text)
                    Text("tokens out")
                        .font(.dsMonoPt(9.5))
                        .foregroundStyle(t.text4)
                }
                Spacer()
            }
        }
        .padding(12)
        .background(t.surfaceSunk)
        .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1))
    }
}

// MARK: - Model option

struct ModelOption: Identifiable {
    let id: String
    let name: String
    let subtitle: String?
}
#endif
