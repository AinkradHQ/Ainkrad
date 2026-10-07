import AinkradHostRuntime
import Foundation
import Observation

/// Decodes one array element of `SandboxProfileDocument.userDefined` without letting a
/// single malformed profile fail the whole array. `SandboxProfile.init(from:)` (Task 1)
/// decodes `fsPolicy`/`networkPolicy` as REQUIRED, so a corrupt or legacy persisted
/// profile can throw — that failure is caught HERE, per element, so it never propagates
/// up to fail the containing array (which would otherwise drop every good profile too).
private struct FailableSandboxProfile: Decodable {
    let profile: SandboxProfile?
    init(from decoder: Decoder) throws {
        do {
            profile = try SandboxProfile(from: decoder)
        } catch {
            Log.persistence.error("Dropping malformed sandbox profile: \(String(describing: error), privacy: .public)")
            profile = nil
        }
    }
}

struct SandboxProfileDocument: PersistableDocument {
    static let documentID = "sandbox-profiles"
    var userDefined: [SandboxProfile] = []

    init(userDefined: [SandboxProfile] = []) { self.userDefined = userDefined }

    // Repo idiom: hand-written forward-compatible decoding (decodeIfPresent + defaults),
    // PLUS fail-closed per-element decoding of `userDefined` (see `FailableSandboxProfile`
    // above). Any failure decoding the field at all (missing key, wrong shape) falls back
    // to an empty array rather than throwing — never a crash, never a permissive default.
    private enum CodingKeys: String, CodingKey { case userDefined }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let raw = try? c.decode([FailableSandboxProfile].self, forKey: .userDefined) {
            userDefined = raw.compactMap(\.profile)
        } else {
            userDefined = []
        }
    }
}

/// Built-ins (immutable, shipped) union user-defined (CRUD, persisted). Built-in ids are
/// reserved: they can never be shadowed, overwritten, or deleted via this store, so a
/// corrupt/malicious persisted profile can never redefine e.g. `host-trusted`.
@MainActor
@Observable
final class SandboxProfileStore {
    private var document: SandboxProfileDocument
    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        self.document = persistence.load(SandboxProfileDocument.self) ?? SandboxProfileDocument()
    }

    /// Built-ins first, then user-defined (a user id never shadows a built-in).
    func all() -> [SandboxProfile] {
        BuiltInSandboxProfiles.all
            + document.userDefined.filter { !BuiltInSandboxProfiles.reservedIDs.contains($0.id) }
    }

    func profile(id: String) -> SandboxProfile? { all().first { $0.id == id } }

    func upsert(_ profile: SandboxProfile) {
        guard !BuiltInSandboxProfiles.reservedIDs.contains(profile.id) else { return }  // built-ins immutable
        if let idx = document.userDefined.firstIndex(where: { $0.id == profile.id }) {
            document.userDefined[idx] = profile
        } else {
            document.userDefined.append(profile)
        }
        persistence.save(document)
    }

    func delete(id: String) {
        guard !BuiltInSandboxProfiles.reservedIDs.contains(id) else { return }
        document.userDefined.removeAll { $0.id == id }
        persistence.save(document)
    }
}
