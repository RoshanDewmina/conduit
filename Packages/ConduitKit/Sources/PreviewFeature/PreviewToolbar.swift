#if os(iOS)
import SwiftUI
import SSHTransport

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
        HStack(spacing: 12) {
            portPicker

            Divider().frame(height: 20)

            Picker("Viewport", selection: $vm.viewportPreset) {
                ForEach(PreviewViewModel.ViewportPreset.allCases, id: \.self) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)

            Divider().frame(height: 20)

            Button {
                vm.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }

            Button {
                Task { await vm.detectPorts(session: session) }
            } label: {
                if vm.isDetecting {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                }
            }
        }
        .padding(.horizontal)
        .sheet(isPresented: $showManualPortEntry) {
            ManualPortSheet(selectedPort: $vm.selectedPort)
        }
    }

    private var portPicker: some View {
        Menu {
            ForEach(vm.detectedPorts, id: \.self) { port in
                Button(":\(port)") { vm.selectedPort = port }
            }
            if !vm.detectedPorts.isEmpty {
                Divider()
            }
            Button("Manual…") { showManualPortEntry = true }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "network")
                Text(vm.activePort.map { ":\($0)" } ?? "No port")
                    .font(.system(.callout, design: .monospaced))
            }
        }
    }
}

private struct ManualPortSheet: View {
    @Binding var selectedPort: Int?
    @Environment(\.dismiss) private var dismiss
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
                            .foregroundStyle(.red)
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
