// Tier 1.5.3 — UI for reordering / hiding keys in the session-screen
// shortcut bar. Reads from + writes to `ShortcutKeyOrder` (DesignSystem).

#if os(iOS)
import SwiftUI
import DesignSystem

public struct ShortcutBarEditor: View {
    @State private var activeKeys: [ShortcutKey] = []

    public init() {}

    public var body: some View {
        List {
            Section("In bar (drag to reorder · swipe to remove)") {
                ForEach(activeKeys) { key in
                    HStack {
                        Text(key.label)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 44, alignment: .leading)
                        Text(key.descriptiveName)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                    }
                }
                .onMove { from, to in
                    activeKeys.move(fromOffsets: from, toOffset: to)
                    persist()
                }
                .onDelete { indices in
                    activeKeys.remove(atOffsets: indices)
                    persist()
                }
            }

            if !inactiveKeys.isEmpty {
                Section("Available") {
                    ForEach(inactiveKeys) { key in
                        Button {
                            activeKeys.append(key)
                            persist()
                        } label: {
                            HStack {
                                Text(key.label)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 44, alignment: .leading)
                                Text(key.descriptiveName)
                                Spacer()
                                Image(systemName: "plus.circle")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    ShortcutKeyOrder.reset()
                    activeKeys = kDefaultShortcutKeyOrder
                } label: {
                    Text("Reset to defaults")
                }
            }
        }
        .navigationTitle("Shortcut Bar")
        .toolbar { EditButton() }
        .onAppear {
            activeKeys = ShortcutKeyOrder.load()
        }
    }

    private var inactiveKeys: [ShortcutKey] {
        let active = Set(activeKeys)
        return ShortcutKey.allCases.filter { !active.contains($0) }
    }

    private func persist() {
        ShortcutKeyOrder.save(activeKeys)
    }
}

#endif
