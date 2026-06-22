// Tier 1.5.3 — UI for reordering / hiding keys in the session-screen
// shortcut bar. Reads from + writes to `ShortcutKeyOrder` (DesignSystem).

#if os(iOS)
import SwiftUI
import DesignSystem

public struct ShortcutBarEditor: View {
    @State private var activeKeys: [ShortcutKey] = []
    @Environment(\.lancerTokens) private var t
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DSDetailHeader("shortcut bar", onBack: { dismiss() })

                    activeSection
                    availableSection
                    resetSection
                }
                .padding(.bottom, 24)
            }
        }
        .navigationBarHidden(true)
        .onAppear { activeKeys = ShortcutKeyOrder.load() }
    }

    // MARK: - Sections

    @ViewBuilder
    private var activeSection: some View {
        sectionHead("IN BAR")
        Text("Use the arrows to reorder. Remove keys you don't use.")
            .font(.dsSansPt(13))
            .foregroundStyle(t.text3)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

        card {
            ForEach(Array(activeKeys.enumerated()), id: \.element) { index, key in
                activeRow(key, index: index)
                if index < activeKeys.count - 1 {
                    DSDivider(.soft, leadingInset: 16)
                }
            }
        }
    }

    @ViewBuilder
    private var availableSection: some View {
        if !inactiveKeys.isEmpty {
            sectionHead("AVAILABLE")
            card {
                ForEach(Array(inactiveKeys.enumerated()), id: \.element) { index, key in
                    availableRow(key)
                    if index < inactiveKeys.count - 1 {
                        DSDivider(.soft, leadingInset: 16)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resetSection: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.14)) {
                ShortcutKeyOrder.reset()
                activeKeys = kDefaultShortcutKeyOrder
            }
        } label: {
            Text("Reset to defaults")
                .font(.dsSansPt(14, weight: .medium))
                .foregroundStyle(t.danger)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(t.surface)
                .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                        .strokeBorder(t.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .accessibilityLabel("Reset shortcut bar to defaults")
    }

    // MARK: - Rows

    @ViewBuilder
    private func activeRow(_ key: ShortcutKey, index: Int) -> some View {
        HStack(spacing: 10) {
            keyGlyph(key)
            Text(key.descriptiveName)
                .font(.dsSansPt(14))
                .foregroundStyle(t.text2)
            Spacer(minLength: 8)

            Button {
                move(from: index, to: index - 1)
            } label: {
                reorderIcon("chevron.up")
            }
            .buttonStyle(.plain)
            .disabled(index == 0)
            .opacity(index == 0 ? 0.3 : 1)
            .accessibilityLabel("Move \(key.descriptiveName) up")

            Button {
                move(from: index, to: index + 1)
            } label: {
                reorderIcon("chevron.down")
            }
            .buttonStyle(.plain)
            .disabled(index == activeKeys.count - 1)
            .opacity(index == activeKeys.count - 1 ? 0.3 : 1)
            .accessibilityLabel("Move \(key.descriptiveName) down")

            Button {
                remove(key)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(t.danger)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(key.descriptiveName)")
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func availableRow(_ key: ShortcutKey) -> some View {
        Button {
            add(key)
        } label: {
            HStack(spacing: 10) {
                keyGlyph(key)
                Text(key.descriptiveName)
                    .font(.dsSansPt(14))
                    .foregroundStyle(t.text2)
                Spacer(minLength: 8)
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(t.accent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .padding(.leading, 16)
            .padding(.trailing, 4)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(key.descriptiveName) to shortcut bar")
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func keyGlyph(_ key: ShortcutKey) -> some View {
        Text(key.label)
            .font(.dsMonoPt(15))
            .foregroundStyle(t.text)
            .frame(minWidth: 44, alignment: .center)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(t.surfaceSunk, in: RoundedRectangle(cornerRadius: t.r2, style: .continuous))
    }

    @ViewBuilder
    private func reorderIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(t.text4)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    private func sectionHead(_ title: String) -> some View {
        Text(title)
            .font(.dsMonoPt(10, weight: .medium))
            .tracking(1.1)
            .foregroundStyle(t.text4)
            .textCase(.uppercase)
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 6)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Mutations

    private func move(from: Int, to: Int) {
        guard activeKeys.indices.contains(from), activeKeys.indices.contains(to) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.14)) {
            activeKeys.swapAt(from, to)
        }
        persist()
    }

    private func remove(_ key: ShortcutKey) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.14)) {
            activeKeys.removeAll { $0 == key }
        }
        persist()
    }

    private func add(_ key: ShortcutKey) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.14)) {
            activeKeys.append(key)
        }
        persist()
    }

    private var inactiveKeys: [ShortcutKey] {
        let active = Set(activeKeys)
        return ShortcutKey.allCases.filter { !active.contains($0) }
    }

    private func persist() { ShortcutKeyOrder.save(activeKeys) }
}

#endif
