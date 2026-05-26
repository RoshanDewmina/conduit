#if os(iOS)
import SwiftUI
import UIKit

// MARK: - Constants

private enum KeyCode {
    static let esc:   [UInt8] = [0x1b]
    static let tab:   [UInt8] = [0x09]
    static let up:    [UInt8] = [0x1b, 0x5b, 0x41]   // ESC [ A
    static let down:  [UInt8] = [0x1b, 0x5b, 0x42]   // ESC [ B
    static let right: [UInt8] = [0x1b, 0x5b, 0x43]   // ESC [ C
    static let left:  [UInt8] = [0x1b, 0x5b, 0x44]   // ESC [ D
    static let pipe:  [UInt8] = [UInt8(ascii: "|")]
    static let semi:  [UInt8] = [UInt8(ascii: ";")]
    static let slash: [UInt8] = [UInt8(ascii: "/")]
    static let dollar:[UInt8] = [UInt8(ascii: "$")]
    static let and2:  [UInt8] = Array("&&".utf8)

    /// Convert a printable ASCII character byte to its Ctrl equivalent.
    /// e.g. `ctrl(UInt8(ascii: "c"))` → `0x03` (ETX / Ctrl+C).
    static func ctrl(_ ascii: UInt8) -> [UInt8] {
        let c = ascii & 0x1f  // mask to Ctrl range 0x01–0x1a
        return [c]
    }
}

// MARK: - View model

/// Lightweight observable state for `KeyboardAccessoryRail`.
@Observable
final class RailViewModel {
    /// `true` when the Ctrl modifier is latched (next alpha key is sent as Ctrl+X).
    var ctrlHeld: Bool = false
}

// MARK: - SwiftUI wrapper

/// A `UIViewControllerRepresentable` keyboard accessory bar for raw/TUI mode.
///
/// Shows: `Esc  Tab  Ctrl  ↑  ↓  ←  →  |  ;  /  $  &&`
///
/// - **Sticky Ctrl**: tap once → `ctrlHeld = true` (button highlights); tap
///   any alpha key → sends Ctrl+key bytes, resets `ctrlHeld`.
/// - **Long-press arrows**: fires a repeating timer while the finger is held,
///   sending the arrow bytes at ~40 ms intervals.
/// - Byte output is delivered via `onBytes: ([UInt8]) -> Void`.
public struct KeyboardAccessoryRail: UIViewControllerRepresentable {

    /// Called with raw bytes whenever a key is tapped (or a repeat fires).
    public let onBytes: ([UInt8]) -> Void
    @Binding private var ctrlLatched: Bool

    public init(
        ctrlLatched: Binding<Bool> = .constant(false),
        onBytes: @escaping ([UInt8]) -> Void
    ) {
        self._ctrlLatched = ctrlLatched
        self.onBytes = onBytes
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onBytes: onBytes)
    }

    public func makeUIViewController(context: Context) -> RailViewController {
        let vc = RailViewController()
        let ctrlBinding = $ctrlLatched
        vc.onBytes = { [coordinator = context.coordinator] bytes in
            coordinator.send(bytes)
        }
        vc.onCtrlLatchChanged = { isLatched in
            ctrlBinding.wrappedValue = isLatched
        }
        return vc
    }

    public func updateUIViewController(_ vc: RailViewController, context: Context) {
        let ctrlBinding = $ctrlLatched
        vc.onBytes = { [coordinator = context.coordinator] bytes in
            coordinator.send(bytes)
        }
        vc.onCtrlLatchChanged = { isLatched in
            ctrlBinding.wrappedValue = isLatched
        }
        vc.setCtrlHeld(ctrlLatched)
    }

    // MARK: Coordinator

    public final class Coordinator: NSObject {
        private let onBytes: ([UInt8]) -> Void

        init(onBytes: @escaping ([UInt8]) -> Void) {
            self.onBytes = onBytes
        }

        func send(_ bytes: [UInt8]) {
            onBytes(bytes)
        }
    }
}

// MARK: - UIKit implementation

/// The underlying `UIViewController` that renders the accessory bar.
public final class RailViewController: UIViewController {

    // MARK: State

    var onBytes: (([UInt8]) -> Void)?
    var onCtrlLatchChanged: ((Bool) -> Void)?
    private var ctrlHeld: Bool = false {
        didSet {
            updateCtrlAppearance()
            onCtrlLatchChanged?(ctrlHeld)
        }
    }

    // MARK: Repeat timer (for arrow long-press)

    private var repeatTimer: Timer?
    private var repeatBytes: [UInt8] = []

    // MARK: Buttons

    private var ctrlButton: UIButton?

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        buildBar()
    }

    // MARK: - Bar construction

    private func buildBar() {
        view.backgroundColor = UIColor.secondarySystemBackground

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        let contentInset: CGFloat = 10
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: contentInset),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -contentInset),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])

        // Esc, Tab
        stack.addArrangedSubview(makeKey("Esc",  bytes: KeyCode.esc))
        stack.addArrangedSubview(makeKey("Tab",  bytes: KeyCode.tab))

        // Ctrl (sticky)
        let ctrl = makeKey("Ctrl", bytes: [])
        ctrl.addTarget(self, action: #selector(ctrlTapped), for: .touchUpInside)
        // Remove the default sendBytes action added by makeKey
        ctrl.removeTarget(nil, action: #selector(sendBytes(_:)), for: .touchUpInside)
        stack.addArrangedSubview(ctrl)
        ctrlButton = ctrl

        // Arrow keys (long-press repeat)
        for (label, bytes) in [("↑", KeyCode.up), ("↓", KeyCode.down),
                                ("←", KeyCode.left), ("→", KeyCode.right)] {
            stack.addArrangedSubview(makeArrowKey(label, bytes: bytes))
        }

        // Symbol keys
        for (label, bytes) in [("|", KeyCode.pipe), (";", KeyCode.semi),
                                ("/", KeyCode.slash), ("$", KeyCode.dollar),
                                ("&&", KeyCode.and2)] {
            stack.addArrangedSubview(makeKey(label, bytes: bytes))
        }
    }

    // MARK: - Button factories

    private func makeKey(_ title: String, bytes: [UInt8]) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseForegroundColor = .label
        config.baseBackgroundColor = UIColor.tertiarySystemBackground
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        config.cornerStyle = .medium

        let btn = UIButton(configuration: config)
        btn.setContentHuggingPriority(.required, for: .horizontal)
        btn.tag = 0
        btn.accessibilityLabel = title

        // Encode bytes into tag via indirect storage (use associated object)
        objc_setAssociatedObject(btn, &AssociatedKeys.bytes, bytes, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        btn.addTarget(self, action: #selector(sendBytes(_:)), for: .touchUpInside)
        return btn
    }

    private func makeArrowKey(_ title: String, bytes: [UInt8]) -> UIButton {
        let btn = makeKey(title, bytes: bytes)
        // Remove default tap action; replace with long-press aware target
        btn.removeTarget(self, action: #selector(sendBytes(_:)), for: .touchUpInside)
        btn.addTarget(self, action: #selector(arrowTapped(_:)), for: .touchUpInside)

        let lp = UILongPressGestureRecognizer(target: self, action: #selector(arrowLongPress(_:)))
        lp.minimumPressDuration = 0.4
        btn.addGestureRecognizer(lp)
        return btn
    }

    // MARK: - Actions

    @objc private func sendBytes(_ sender: UIButton) {
        guard let bytes = objc_getAssociatedObject(sender, &AssociatedKeys.bytes) as? [UInt8] else { return }
        deliver(bytes, from: sender)
    }

    @objc private func arrowTapped(_ sender: UIButton) {
        guard let bytes = objc_getAssociatedObject(sender, &AssociatedKeys.bytes) as? [UInt8] else { return }
        deliver(bytes, from: sender)
    }

    @objc private func arrowLongPress(_ gr: UILongPressGestureRecognizer) {
        guard let btn = gr.view as? UIButton,
              let bytes = objc_getAssociatedObject(btn, &AssociatedKeys.bytes) as? [UInt8]
        else { return }

        switch gr.state {
        case .began:
            repeatBytes = bytes
            repeatTimer?.invalidate()
            repeatTimer = Timer.scheduledTimer(
                timeInterval: 0.04,
                target: self,
                selector: #selector(repeatTimerFired(_:)),
                userInfo: nil,
                repeats: true
            )
        case .ended, .cancelled, .failed:
            repeatTimer?.invalidate()
            repeatTimer = nil
        default:
            break
        }
    }

    @objc private func repeatTimerFired(_ timer: Timer) {
        onBytes?(repeatBytes)
    }

    @objc private func ctrlTapped() {
        ctrlHeld.toggle()
    }

    func setCtrlHeld(_ isHeld: Bool) {
        guard ctrlHeld != isHeld, ctrlButton != nil else { return }
        ctrlHeld = isHeld
    }

    // MARK: - Byte delivery

    private func deliver(_ bytes: [UInt8], from sender: UIButton) {
        if ctrlHeld {
            // Map first byte to Ctrl equivalent if it's a printable ASCII letter.
            if let first = bytes.first, first >= 0x61 && first <= 0x7a {
                // lowercase a-z → 0x01-0x1a
                onBytes?(KeyCode.ctrl(first))
            } else if let first = bytes.first, first >= 0x41 && first <= 0x5a {
                // uppercase A-Z → 0x01-0x1a
                onBytes?(KeyCode.ctrl(first))
            } else {
                onBytes?(bytes)
            }
            ctrlHeld = false
        } else {
            onBytes?(bytes)
        }
    }

    // MARK: - Ctrl button appearance

    private func updateCtrlAppearance() {
        guard let ctrlButton else { return }
        var config = ctrlButton.configuration ?? UIButton.Configuration.filled()
        config.baseBackgroundColor = ctrlHeld
            ? UIColor.systemBlue
            : UIColor.tertiarySystemBackground
        config.baseForegroundColor = ctrlHeld ? .white : .label
        ctrlButton.configuration = config
    }
}

// MARK: - Associated object key storage

private enum AssociatedKeys {
    nonisolated(unsafe) static var bytes: UInt8 = 0
}

#endif
