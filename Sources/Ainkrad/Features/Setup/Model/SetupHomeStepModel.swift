import AinkradAppKit
import AinkradHostRuntime
import Foundation

/// Pure decision logic for the Home step, independent of SwiftUI and of NSOpenPanel,
/// so it can be tested without a UI. The view supplies the real chooser and adopter.
@MainActor
final class SetupHomeStepModel {
    enum Outcome: Equatable {
        case adopted
        case rejected(String)
        case cancelled
        /// The folder is ALREADY an Ainkrad Home with work in it. Adopting it is
        /// legitimate — it is the reinstall-and-restore path — but it is not
        /// what someone who meant to pick an empty folder expects, so it is
        /// confirmed rather than done silently.
        ///
        /// A folder that is not empty and NOT an Ainkrad Home is refused
        /// outright by `AinkradHome.validate`; there is no confirmation for that
        /// case, because there is no version of it that is safe.
        case needsConfirmation(url: URL, entryCount: Int)
    }

    private let chooseVault: LaunchHomeResolver.VaultChooser
    private let adopt: (URL) throws -> Void
    private let inspect: (URL) -> ExistingVault?

    /// What an already-populated Ainkrad Home looks like from outside.
    struct ExistingVault: Equatable {
        /// Entries in the folder, excluding the marker itself and `.DS_Store` —
        /// i.e. how much of the user's own work is in there.
        let entryCount: Int
    }

    init(
        chooseVault: @escaping LaunchHomeResolver.VaultChooser,
        adopt: @escaping (URL) throws -> Void,
        inspect: @escaping (URL) -> ExistingVault? = { SetupHomeStepModel.inspectVault(at: $0) }
    ) {
        self.chooseVault = chooseVault
        self.adopt = adopt
        self.inspect = inspect
    }

    /// Reports an existing Home with contents, or `nil` for anything else —
    /// including an EMPTY existing Home, which is indistinguishable from a fresh
    /// folder as far as the user is concerned and needs no confirmation.
    nonisolated static func inspectVault(at url: URL) -> ExistingVault? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: HomeMarker.url(in: url).path) else { return nil }
        let entries = ((try? fm.contentsOfDirectory(atPath: url.path)) ?? [])
            .filter { $0 != HomeMarker.filename && $0 != ".DS_Store" }
        return entries.isEmpty ? nil : ExistingVault(entryCount: entries.count)
    }

    func choose() -> Outcome {
        guard let chosen = chooseVault() else { return .cancelled }
        if let existing = inspect(chosen) {
            return .needsConfirmation(url: chosen, entryCount: existing.entryCount)
        }
        return adoptNow(chosen)
    }

    /// Adopt a folder the user has confirmed. Separate from `choose()` so the
    /// confirmation cannot be bypassed by accident: the only path that skips it
    /// is the one where `inspect` found nothing to confirm.
    func adoptConfirmed(_ url: URL) -> Outcome { adoptNow(url) }

    private func adoptNow(_ url: URL) -> Outcome {
        do {
            try adopt(url)
            return .adopted
        } catch {
            // Reuse the recovery copy so the wizard and the launch-time alerts
            // explain the same failures the same way.
            let message =
                LaunchRecovery.prompt(for: error)?.message
                ?? "That folder can't be used as your Ainkrad Home."
            return .rejected(message)
        }
    }
}
