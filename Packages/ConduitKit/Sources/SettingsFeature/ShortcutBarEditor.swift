// Tier 1.5.3 — UI for reordering / hiding keys in the session-screen
// shortcut bar. Reads from + writes to `ShortcutKeyOrder` (DesignSystem).

#if os(iOS)
import SwiftUI
import DesignSystem

public struct ShortcutBarEditor: View {
    @State private var activeKeys: [ShortcutKey] = []
    @Environment(\.conduitTokens) private var t

    public init() {}

    public var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()

            List {
                activeSection
                availableSection
                resetSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Shortcut Bar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onAppear { activeKeys = ShortcutKeyOrder.load() }
    }

    // MARK: - Sections (split so the body type-checks quickly)

    @ViewBuilder
    private var activeSection: some View {
        Section {
            ForEach(activeKeys) { key in
                keyRow(key, trailing: Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14))
                    .foregroundStyle(t.text4))
                    .listRowBackground(t.surface)
            }
            .onMove { from, to in
                activeKeys.move(fromOffsets: from, toOffset: to)
                persist()
            }
            .onDelete { indices in
                activeKeys.remove(atOffsets: indices)
                persist()
            }
        } header: {
            sectionHeader("In bar — drag to reorder · swipe to remove")
        }
    }

    @ViewBuilder
    private var availableSection: some View {
        if !inactiveKeys.isEmpty {
            Section {
                ForEach(inactiveKeys) { key in
                    Button {
                        activeKeys.append(key)
                        persist()
                    } label: {
                        keyRow(key, trailing: Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(t.accent))
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(t.surface)
                }
            } header: {
                sectionHeader("Available")
            }
        }
    }

    @ViewBuilder
    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                ShortcutKeyOrder.reset()
                activeKeys = kDefaultShortcutKeyOrder
            } label: {
                Text("Reset to defaults")
                    .font(.dsSansPt(14))
                    .foregroundStyle(t.danger)
            }
            .listRowBackground(t.surface)
        }
    }

    @ViewBuilder
    private func keyRow<Trailing: View>(_ key: ShortcutKey, trailing: Trailing) -> some View {
        HStack(spacing: 10) {
            Text(key.label)
                .font(.dsMonoPt(15))
                .foregroundStyle(t.text)
                .frame(width: 44, alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .background(t.surfaceSunk, in: RoundedRectangle(cornerRadius: t.r2, style: .continuous))
            Text(key.descriptiveName)
                .font(.dsSansPt(14))
                .foregroundStyle(t.text2)
            Spacer()
            trailing
        }
    }

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.dsSansPt(11, weight: .semibold))
            .foregroundStyle(t.text3)
            .textCase(nil)
    }

    private var inactiveKeys: [ShortcutKey] {
        let active = Set(activeKeys)
        return ShortcutKey.allCases.filter { !active.contains($0) }
    }

    private func persist() { ShortcutKeyOrder.save(activeKeys) }
}

#endif
