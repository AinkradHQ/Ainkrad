import AinkradHostRuntime
import Foundation
import Observation

struct VoiceSettingsDocument: PersistableDocument {
    static let documentID = "voice-settings"
    var backend: TranscriptionBackendKind
    var mode: PushToTalkMode
    var autoSend: Bool
    var providerOptIn: Bool
    var providerConnectionID: UUID?
    var providerModel: String
    var localeIdentifier: String

    init(
        backend: TranscriptionBackendKind = .onDevice, mode: PushToTalkMode = .hold,
        autoSend: Bool = false, providerOptIn: Bool = false, providerConnectionID: UUID? = nil,
        providerModel: String = "whisper-1", localeIdentifier: String = "en-US"
    ) {
        self.backend = backend
        self.mode = mode
        self.autoSend = autoSend
        self.providerOptIn = providerOptIn
        self.providerConnectionID = providerConnectionID
        self.providerModel = providerModel
        self.localeIdentifier = localeIdentifier
    }

    // Host idiom: hand-written decode with decodeIfPresent + defaults (forward-compatible).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        backend = try c.decodeIfPresent(TranscriptionBackendKind.self, forKey: .backend) ?? .onDevice
        mode = try c.decodeIfPresent(PushToTalkMode.self, forKey: .mode) ?? .hold
        autoSend = try c.decodeIfPresent(Bool.self, forKey: .autoSend) ?? false
        providerOptIn = try c.decodeIfPresent(Bool.self, forKey: .providerOptIn) ?? false
        providerConnectionID = try c.decodeIfPresent(UUID.self, forKey: .providerConnectionID)
        providerModel = try c.decodeIfPresent(String.self, forKey: .providerModel) ?? "whisper-1"
        localeIdentifier = try c.decodeIfPresent(String.self, forKey: .localeIdentifier) ?? "en-US"
    }

    private enum CodingKeys: String, CodingKey {
        case backend, mode, autoSend, providerOptIn, providerConnectionID, providerModel, localeIdentifier
    }
}

@MainActor
@Observable
final class VoiceSettingsStore {
    private(set) var document: VoiceSettingsDocument
    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        self.document = persistence.load(VoiceSettingsDocument.self) ?? VoiceSettingsDocument()
    }

    func setBackend(_ v: TranscriptionBackendKind) {
        document.backend = v
        save()
    }
    func setMode(_ v: PushToTalkMode) {
        document.mode = v
        save()
    }
    func setAutoSend(_ v: Bool) {
        document.autoSend = v
        save()
    }
    func setProviderOptIn(_ v: Bool) {
        document.providerOptIn = v
        save()
    }
    func setProviderConnection(_ id: UUID?) {
        document.providerConnectionID = id
        save()
    }
    func setProviderModel(_ v: String) {
        document.providerModel = v
        save()
    }
    func setLocale(_ v: String) {
        document.localeIdentifier = v
        save()
    }

    private func save() { persistence.save(document) }
}
