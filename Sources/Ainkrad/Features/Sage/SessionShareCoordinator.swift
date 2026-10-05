import Foundation

/// Bridges the current transcript + a raw redaction field into `SessionShareStore`
/// and returns the artifact + a copyable `file://` link. Non-view so it is unit
/// testable without SwiftUI.
@MainActor
struct SessionShareCoordinator {
    let store: SessionShareStore
    init(store: SessionShareStore) { self.store = store }

    func shareCurrentSession(
        messages: [AgentMessage], title: String,
        redactionsText: String
    ) throws
        -> (record: SharedSessionRecord, clipboardLink: String)
    {
        let redactions = RedactionList.parse(redactionsText)
        let record = try store.share(messages: messages, title: title, redactions: redactions)
        return (record, record.fileURL.absoluteString)
    }
}
