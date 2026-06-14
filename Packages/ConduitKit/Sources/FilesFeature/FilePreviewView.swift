#if os(iOS)
import SwiftUI
import UIKit
import DesignSystem

// Canonical full-file viewer — the single bottom-drawer file view (CONDUIT_UI_CONSISTENCY_RULES
// §7 / R7.2). Header: filename · path · line-count · read-only. Body: line-numbered mono that
// scrolls both axes. Footer: dismiss hint + Copy. Mirrors the migration board's `FileViewerSheet`.
// Present via `.filePreviewDrawer(...)` (bottom drawer, medium → large detents, grabber).

public struct FilePreviewView: View {
    let filename: String
    let path: String?
    let content: String

    @Environment(\.conduitTokens) private var t
    @Environment(\.dismiss) private var dismiss

    public init(filename: String, content: String, path: String? = nil) {
        self.filename = filename
        self.content = content
        self.path = path
    }

    private var lines: [Substring] {
        content.split(separator: "\n", omittingEmptySubsequences: false)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            DSDivider()
            fileBody
            footer
        }
        .background(t.termBg)
    }

    // MARK: Header — filename · path · line-count · read-only, with a close affordance.

    private var header: some View {
        HStack(spacing: 9) {
            DSIconView(.file, size: 15, color: t.termText2)
            VStack(alignment: .leading, spacing: 1) {
                Text(filename)
                    .font(.dsMonoPt(13.5, weight: .semibold))
                    .foregroundStyle(t.termText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.dsMonoPt(10.5))
                    .foregroundStyle(t.termText3)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 8)
            Button {
                Haptics.selection()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(t.termText2)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 2)
        .padding(.bottom, 10)
    }

    private var subtitle: String {
        let n = lines.count
        let location = path.map { "\($0) · " } ?? ""
        return "\(location)\(n) line\(n == 1 ? "" : "s") · read-only"
    }

    // MARK: Body — line-numbered, monospaced, scrolls both axes.

    private var fileBody: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(i + 1)")
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.termText3)
                            .frame(width: 28, alignment: .trailing)
                            .textSelection(.disabled)
                        Text(lines[i].isEmpty ? " " : String(lines[i]))
                            .font(.dsMonoPt(12))
                            .foregroundStyle(t.termText)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 1.5)
                }
            }
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Footer — dismiss hint + Copy.

    private var footer: some View {
        HStack(spacing: 10) {
            Text("swipe down to dismiss")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.termText3)
            Spacer(minLength: 8)
            Button {
                UIPasteboard.general.string = content
                Haptics.success()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc").font(.system(size: 13))
                    Text("Copy").font(.dsMonoPt(12, weight: .medium))
                }
                .foregroundStyle(t.termText)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(t.termBorder))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .overlay(DSDivider(), alignment: .top)
    }
}

// MARK: - Bottom-drawer presentation

public extension View {
    /// Presents `FilePreviewView` as the canonical bottom drawer (R7.2): medium → large
    /// detents with a grabber, custom in-sheet header (so no extra navigation chrome).
    func filePreviewDrawer(
        filename: String?,
        content: String?,
        path: String? = nil,
        isPresented: Binding<Bool>
    ) -> some View {
        sheet(isPresented: isPresented) {
            Group {
                if let name = filename, let text = content {
                    FilePreviewView(filename: name, content: text, path: path)
                } else {
                    ContentUnavailableView("No file", systemImage: "doc.text")
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

#endif
