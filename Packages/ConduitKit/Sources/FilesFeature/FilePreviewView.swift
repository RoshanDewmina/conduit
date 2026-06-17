#if os(iOS)
import SwiftUI
import UIKit
import DesignSystem

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
            DSDivider(.strong)
            fileBody
            footer
        }
        .background(t.termBg)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(filename.lowercased())
                    .font(.dsDisplayPt(22, weight: .bold))
                    .foregroundStyle(t.termText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    if let path {
                        Text(path)
                            .foregroundStyle(t.termText3)
                    }
                    Text("\(lines.count) lines")
                        .foregroundStyle(t.termText3)
                    Text("·")
                        .foregroundStyle(t.termText3)
                    Text("read-only")
                        .foregroundStyle(t.termText3)
                }
                .font(.dsMonoPt(11))
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                Haptics.selection()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(t.termText2)
                    .frame(width: 36, height: 36)
                    .background(t.termSurface)
                    .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                            .strokeBorder(t.termBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var fileBody: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(i + 1)")
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.termText3)
                            .frame(width: 32, alignment: .trailing)
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
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

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
                .background(t.termSurface)
                .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                        .strokeBorder(t.termBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .overlay(DSDivider(.strong), alignment: .top)
    }
}

// MARK: - Bottom-drawer presentation

public extension View {
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
