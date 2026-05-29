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
                Section {
                    ForEach(activeKeys) { key in
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
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 14))
                                .foregroundStyle(t.text4)
                        }
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
                    Text("In bar — drag to reorder · swipe to remove")
                        .font(.dsSansPt(11, weight: .semibold))
                        .foregroundStyle(t.text3)
                        .textCase(nil)
                }

                if !inactiveKeys.isEmpty {
                    Section {
                        ForEach(inactiveKeys) { key in
                            Button {
                                activeKeys.append(key)
                                persist()
                            } label: {
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
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(t.accent)
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(t.surface)
                        }
                    } header: {
                        Text("Available")
                            .font(.dsSansPt(11, weight: .semibold))
                            .foregroundStyle(t.text3)
                            .textCase(nil)
                    }
                }

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
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Shortcut Bar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onAppear { activeKeys = ShortcutKeyOrder.load() }
    }

    private var inactiveKeys: [ShortcutKey] {
        let active = Set(activeKeys)
        return ShortcutKey.allCases.filter { !active.contains($0) }
    }

    private func persist() { ShortcutKeyOrder.save(activeKeys) }
}

#endif
