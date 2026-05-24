#if os(iOS)
import SwiftUI
import SSHTransport

public struct PreviewToolbar: View {
    @Binding var vm: PreviewViewModel
    let session: SSHSession
    var onScreenshot: ((String) -> Void)?

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
            // Port picker
            portPicker

            Divider().frame(height: 20)

            // Viewport presets
            Picker("Viewport", selection: $vm.viewportPreset) {
                ForEach(PreviewViewModel.ViewportPreset.allCases, id: \.self) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)

            Divider().frame(height: 20)

            // Reload
            Button {
                vm.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }

            // Detect ports
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
    }

    private var portPicker: some View {
        Menu {
            ForEach(vm.detectedPorts, id: \.self) { port in
                Button(":\(port)") { vm.selectedPort = port }
            }
            if !vm.detectedPorts.isEmpty {
                Divider()
            }
            Button("Manual…") { /* TODO: show manual port input sheet */ }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "network")
                Text(vm.activePort.map { ":\($0)" } ?? "No port")
                    .font(.system(.callout, design: .monospaced))
            }
        }
    }
}
#endif
