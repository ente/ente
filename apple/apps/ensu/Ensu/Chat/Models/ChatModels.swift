import Foundation

enum ChatMessageTagRegex {
    static let think = try? NSRegularExpression(pattern: "<think>([\\s\\S]*?)</think>", options: [])
    static let todoList = try? NSRegularExpression(pattern: "<todo_list>([\\s\\S]*?)</todo_list>", options: [])
}

struct ChatAttachment: Identifiable, Equatable {
    enum Kind {
        case image
        case document
    }

    let id: UUID
    let name: String
    let size: Int64
    let kind: Kind
    let url: URL?
    var isUploading: Bool

    init(id: UUID = UUID(), name: String, size: Int64, kind: Kind, url: URL? = nil, isUploading: Bool = false) {
        self.id = id
        self.name = name
        self.size = size
        self.kind = kind
        self.url = url
        self.isUploading = isUploading
    }

    var formattedSize: String {
        size.formattedFileSize
    }

    var iconName: String {
        switch kind {
        case .image:
            return "Attachment01Icon"
        case .document:
            return "Attachment01Icon"
        }
    }
}

enum ChatAttachmentLimits {
    static let maxImagesPerMessage = 2
}

struct RenderedChatMessage: Identifiable, Equatable {
    enum Role: String {
        case user
        case assistant
    }

    let id: UUID
    var role: Role
    var text: String
    var timestamp: Date
    var attachments: [ChatAttachment]
    var isInterrupted: Bool
    var isSynthetic: Bool
    var tokensPerSecond: Double?
    var branchIndex: Int
    var branchCount: Int

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        timestamp: Date = Date(),
        attachments: [ChatAttachment] = [],
        isInterrupted: Bool = false,
        isSynthetic: Bool = false,
        tokensPerSecond: Double? = nil,
        branchIndex: Int = 1,
        branchCount: Int = 1
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.attachments = attachments
        self.isInterrupted = isInterrupted
        self.isSynthetic = isSynthetic
        self.tokensPerSecond = tokensPerSecond
        self.branchIndex = branchIndex
        self.branchCount = branchCount
    }
}

struct ChatSession: Identifiable, Equatable {
    let id: UUID
    var title: String
    var lastMessage: String
    var updatedAt: Date

    init(id: UUID = UUID(), title: String, lastMessage: String, updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.lastMessage = lastMessage
        self.updatedAt = updatedAt
    }
}

struct DownloadToastState: Identifiable, Equatable {
    enum Phase {
        case downloading
        case loading
        case ready
        case errorDownload
        case errorLoad
    }

    let id = UUID()
    var phase: Phase
    var percent: Int?
    var status: String
    var offerRetryDownload: Bool
}

struct OverflowAlertState: Identifiable, Equatable {
    let id = UUID()
    let inputTokens: Int
    let inputBudget: Int
    let contextLength: Int
    let maxOutput: Int
}
