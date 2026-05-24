import Foundation

public struct Snippet: Identifiable, Sendable, Hashable, Codable {
    public let id: SnippetID
    public var name: String
    public var body: String
    public var hostTags: [String]
    public var tags: [String]
    public var createdAt: Date
    public var lastUsedAt: Date?

    public init(
        id: SnippetID = .init(),
        name: String,
        body: String,
        hostTags: [String] = [],
        tags: [String] = [],
        createdAt: Date = .now,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.body = body
        self.hostTags = hostTags
        self.tags = tags
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}
