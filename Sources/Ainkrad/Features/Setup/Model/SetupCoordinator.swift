import AinkradHostRuntime
import Foundation

@MainActor
@Observable
final class SetupCoordinator {
    /// Bump when a step is added. Existing users are then asked for that step only.
    static let currentSetupVersion = 1

    private let persistence: PersistenceStore
    private(set) var steps: [SetupStep]
    private(set) var step: SetupStep
    private(set) var isComplete: Bool
    /// Steps the user walked past without satisfying. Seeded from the marker, so
    /// a relaunch resumes owing exactly what the last run recorded.
    private(set) var deferredSteps: Set<SetupStep>

    init(
        persistence: PersistenceStore,
        isProvisionalHome: Bool,
        /// Deliberately re-walking a finished setup from Settings, rather than
        /// being gated into it. Not the same as an incomplete marker: nothing
        /// is OWED here, the user simply asked to go through it again.
        isReplay: Bool = false
    ) {
        let doc = persistence.load(SetupDocument.self) ?? SetupDocument()
        let completedVersion = doc.completedAt == nil ? -1 : doc.setupVersion
        let deferred = Set(doc.deferredSteps.compactMap(SetupStep.init(rawValue:)))

        let resolvedSteps: [SetupStep]
        if isReplay {
            // Every step except `.home`. A vault whose setup is finished
            // stands, and re-offering to move it is not a question a replay
            // gets to ask — the same rule the re-raised gate follows below,
            // and the reason Settings shows Home read-only.
            resolvedSteps = SetupStep.allCases.filter { $0 != .home }
        } else if isProvisionalHome || completedVersion < 0 {
            // The full wizard, always — in TWO cases, and the second is the
            // subtle one:
            //
            // 1. No vault chosen yet.
            // 2. A vault HAS just been adopted, but setup has never completed
            //    in it. The user is still walking the wizard, so `.home` stays
            //    in the list and Back can return to it to pick a different
            //    folder. An earlier version dropped `.home` the instant a folder
            //    was adopted, which made the step vanish mid-wizard and left the
            //    choice unchangeable until setup finished — for the one screen
            //    that decides where all of the user's work will live.
            //
            // Derived from the marker rather than a flag passed in: "has setup
            // ever completed here" is the real question, and a caller cannot get
            // it wrong.
            resolvedSteps = SetupStep.allCases
        } else {
            // Setup HAS completed in this vault before, so this is the re-raised
            // gate: only steps introduced since the version the user completed —
            // or deferred by them, which owes the step for the same reason and
            // is resolved by the same filter — plus the closing screen.
            //
            // `.home` is never re-asked HERE, and only here: a vault whose setup
            // is finished stands, and re-offering to move it is not a first-run
            // question. Changing it afterwards belongs in Settings, not in a
            // gate the user cannot dismiss.
            resolvedSteps = SetupStep.allCases.filter {
                $0 == .done
                    || ($0 != .home && ($0.introducedIn > completedVersion || deferred.contains($0)))
            }
        }

        // Assigned only after every local is resolved: with `@Observable`,
        // reading `self.steps` mid-init (before every stored property has a
        // value) fails to compile, since the macro routes property access
        // through observation-tracking accessors.
        self.persistence = persistence
        self.steps = resolvedSteps
        self.step = resolvedSteps.first ?? .done
        self.deferredSteps = deferred
        // A deferred step keeps setup INCOMPLETE, which is what re-raises the
        // gate at launch. Combined with the step filter above, the gate comes
        // back on that step alone rather than replaying the wizard.
        self.isComplete =
            doc.completedAt != nil
            && doc.setupVersion >= Self.currentSetupVersion
            && deferred.isEmpty
    }

    /// Records (or clears) a step as deferred-but-owed. Persisted by `complete()`.
    ///
    /// Clearing matters as much as setting: a user who returns through the
    /// banner and connects a provider must stop owing the step, or the gate
    /// would greet them again forever.
    func setDeferred(_ step: SetupStep, _ deferred: Bool) {
        if deferred { deferredSteps.insert(step) } else { deferredSteps.remove(step) }

        // Write through IF a completion marker already exists — which is exactly
        // the re-raised-gate session, where quitting between deferring and
        // pressing Finish would otherwise lose the record and silently clear the
        // debt. `completedAt` is carried from the existing marker, never minted:
        // during a FIRST run there is no marker, nothing is written, and quitting
        // mid-wizard correctly replays the whole thing rather than being recorded
        // as a completed setup that owes one step.
        guard var doc = persistence.load(SetupDocument.self), doc.completedAt != nil else { return }
        doc.deferredSteps = deferredSteps.map(\.rawValue).sorted()
        persistence.save(doc)
        isComplete = doc.setupVersion >= Self.currentSetupVersion && deferredSteps.isEmpty
    }

    var canAdvance: Bool { step != .done }

    /// False only on the first step shown. Drives the Back control's PRESENCE,
    /// not its enablement: a greyed button the user can never use is noise.
    ///
    /// Note what this is not gated on — the current step's own validation. Back
    /// is always available (except on the first step) whether or not the step's
    /// requirements are met. The Providers step is the reason that matters: it
    /// is mandatory, and a user who cannot get a connection to verify must be
    /// able to go back rather than being stuck on it.
    var canGoBack: Bool { (steps.firstIndex(of: step) ?? 0) > 0 }

    func advance() {
        guard let i = steps.firstIndex(of: step), i + 1 < steps.count else { return }
        step = steps[i + 1]
    }

    func back() {
        guard let i = steps.firstIndex(of: step), i > 0 else { return }
        step = steps[i - 1]
    }

    /// Writes the completion marker, including anything still owed.
    ///
    /// `isComplete` deliberately tracks the marker rather than being forced
    /// true: if a step was deferred, setup is *not* complete, and the next
    /// launch must say so.
    func complete() {
        persistence.save(
            SetupDocument(
                completedAt: Date(),
                setupVersion: Self.currentSetupVersion,
                deferredSteps: deferredSteps.map(\.rawValue).sorted()))
        isComplete = deferredSteps.isEmpty
    }
}
