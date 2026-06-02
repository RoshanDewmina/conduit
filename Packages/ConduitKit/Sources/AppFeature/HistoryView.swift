#if os(iOS)
import SwiftUI
import UIKit
import Observation
import ConduitCore
import PersistenceKit
import SessionFeature

@MainActor @Observable
public final class HistoryViewModel {
    public var query: String = ""
    public var results: [Block] = []
    public var isLoading: Bool = false
    public var error: String?

    private let repository: BlockRepository
    private weak var liveSession: SessionViewModel?

    public init(repository: BlockRepository, liveSession: SessionViewModel?) {
        self.repository = repository
        self.liveSession = liveSession
    }

    public func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            results = try await repository.search(trimmed, limit: 200)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func copy(_ block: Block) {
        #if os(iOS)
        UIPasteboard.general.string = block.command
        #endif
    }

    public func rerun(_ block: Block) async {
        guard let liveSession else { return }
        await liveSession.runCommand(block.command)
    }

    public func toggleStar(_ block: Block) async {
        var updated = block
        updated.isStarred.toggle()
        do {
            try await repository.persist(updated)
            if let idx = results.firstIndex(where: { $0.id == block.id }) {
                results[idx] = updated
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

public struct HistoryView: View {
    @State private var vm: HistoryViewModel

    public init(viewModel: HistoryViewModel) {
        _vm = State(initialValue: viewModel)
    }

    public var body: some View {
        List {
            if vm.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView("Search command history", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .listRowBackground(Color.clear)
            } else if vm.results.isEmpty && !vm.isLoading {
                ContentUnavailableView.search(text: vm.query)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(vm.results, id: \.id) { block in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(block.command)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                        HStack {
                            Text(block.prompt.hostName)
                            Text("·")
                            Text(block.startedAt.formatted(date: .abbreviated, time: .shortened))
                            if block.isStarred {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .contextMenu {
                        Button {
                            Task { await vm.rerun(block) }
                        } label: {
                            Label("Re-run", systemImage: "arrow.clockwise")
                        }
                        Button {
                            vm.copy(block)
                        } label: {
                            Label("Copy command", systemImage: "doc.on.doc")
                        }
                        Button {
                            Task { await vm.toggleStar(block) }
                        } label: {
                            Label(block.isStarred ? "Unstar" : "Star", systemImage: block.isStarred ? "star.slash" : "star")
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            Task { await vm.toggleStar(block) }
                        } label: {
                            Label(block.isStarred ? "Unstar" : "Star", systemImage: block.isStarred ? "star.slash" : "star")
                        }
                        .tint(.yellow)
                    }
                }
            }
        }
        .navigationTitle("History")
        .searchable(text: $vm.query, prompt: "FTS search")
        .onSubmit(of: .search) { Task { await vm.search() } }
        .onChange(of: vm.query) { _, _ in Task { await vm.search() } }
        .overlay {
            if vm.isLoading { ProgressView() }
        }
        .alert("Error", isPresented: .constant(vm.error != nil), actions: {
            Button("OK") { vm.error = nil }
        }, message: {
            Text(vm.error ?? "")
        })
    }
}
#endif
