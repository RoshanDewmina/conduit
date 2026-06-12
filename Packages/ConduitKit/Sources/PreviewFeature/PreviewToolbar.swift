#if os(iOS)
import SwiftUI
import SSHTransport
import DesignSystem

public struct PreviewToolbar: View {
    @Binding var vm: PreviewViewModel
    let session: SSHSession
    var onScreenshot: ((String) -> Void)?

    @State private var showManualPortEntry = false

    public init(
        vm: Binding<PreviewViewModel>,
        session: SSHSession,
        onScreenshot: ((String) -> Void)? = nil
    ) {
        self._vm = vm
        self.session = session
        self.onScreenshot = onScreenshot
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalControls
            compactControls
        }
        .padding(.horizontal, 12)
        .sheet(isPresented: $showManualPortEntry) {
            ManualPortSheet(selectedPort: $vm.selectedPort)
        }
    }

    private var horizontalControls: some View {
        HStack(spacing: 12) {
            portPicker

            Divider().frame(height: 20)
            viewportPicker
                .frame(maxWidth: 220)

            Divider().frame(height: 20)
            reloadButton
            detectButton
        }
    }

    private var compactControls: some View {
        HStack(spacing: 12) {
            portPicker
            Spacer(minLength: 8)
            Menu {
                Picker("Viewport", selection: $vm.viewportPreset) {
                    ForEach(PreviewViewModel.ViewportPreset.allCases, id: \.self) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                Divider()
                Button {
                    vm.reload()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                Button {
                    Task { await vm.detectPorts(session: session) }
                } label: {
                    Label(vm.isDetecting ? "Detecting" : "Detect Ports",
                          systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(vm.isDetecting)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .imageScale(.large)
                    .frame(width: 36, height: 36)
            }
        }
    }

    private var viewportPicker: some View {
        Picker("Viewport", selection: $vm.viewportPreset) {
            ForEach(PreviewViewModel.ViewportPreset.allCases, id: \.self) { preset in
                Text(preset.rawValue).tag(preset)
            }
        }
        .pickerStyle(.segmented)
    }

    private var reloadButton: some View {
        Button {
            vm.reload()
        } label: {
            Image(systemName: "arrow.clockwise")
                .frame(width: 32, height: 32)
        }
        .accessibilityLabel("Reload preview")
    }

    private var detectButton: some View {
        Button {
            Task { await vm.detectPorts(session: session) }
        } label: {
            if vm.isDetecting {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .frame(width: 32, height: 32)
            }
        }
        .accessibilityLabel("Detect ports")
        .disabled(vm.isDetecting)
    }

    private var portPicker: some View {
        Menu {
            ForEach(vm.detectedPorts, id: \.self) { port in
                Button {
                    vm.selectedPort = port
                } label: {
                    Text(verbatim: ":\(port)")
                }
            }
            if !vm.detectedPorts.isEmpty {
                Divider()
            }
            Button("Manual…") { showManualPortEntry = true }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "network")
                Text(verbatim: vm.activePort.map { ":\($0)" } ?? "No port")
                    .font(.dsMonoPt(14))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                    .lineLimit(1)
            }
        }
    }
}

private struct ManualPortSheet: View {
    @Binding var selectedPort: Int?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t
    @State private var portText = ""
    @State private var isInvalid = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Port (1–65535)", text: $portText)
                        .keyboardType(.numberPad)
                        .onChange(of: portText) { _, _ in isInvalid = false }
                } footer: {
                    if isInvalid {
                        Text("Enter a number between 1 and 65535.")
                            .foregroundStyle(t.danger)
                    }
                }
            }
            .navigationTitle("Connect to Port")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") { commit() }
                }
            }
        }
        .presentationDetents([.height(200)])
    }

    private func commit() {
        guard let port = Int(portText), (1...65535).contains(port) else {
            isInvalid = true
            return
        }
        selectedPort = port
        dismiss()
    }
}
#endif
