import AinkradAppKit
import AinkradHostRuntime
import AppKit
import SwiftUI

/// The Home step: the one irreversible screen in the wizard.
///
/// Choosing adopts the folder, migrates any legacy container into it, rebuilds the
/// environment against it and re-points every holder through
/// `AinkradHostApp.install(_:into:)` — reached here only via the injected
/// `SetupHomeInstaller`, never by re-pointing anything at this call site.
///
/// A refusal (a populated folder, a nested Home, an unwritable one) and the
/// "this folder is already a vault" confirmation are both raised through
/// `SetupModalPresenter`, over the whole gate. They were inline first, on the
/// reasoning that a second modal over a modal gate is what made the launch-time
/// alerts unverifiable — but hand-testing found both of them below the fold on
/// this step's own scroller, which is worse than unverifiable: it is invisible.
///
/// Nothing is written on a refusal — `adoptAndRebuild` throws before `install`
/// runs — so the step simply stays where it is.
struct SetupHomeStepView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.setupHomeInstaller) private var installer
    /// Where the "this folder is already a vault" decision is raised. Presented
    /// by `SetupOverlayView` over the whole gate — an inline version of it sat
    /// on this step's scroller and its buttons landed below the fold.
    @Environment(SetupModalPresenter.self) private var modals

    let coordinator: SetupCoordinator
    /// Handed the REBUILT environment so the overlay can re-seat anything it owns
    /// that still points at the provisional home (notably the coordinator's
    /// `PersistenceStore`, which would otherwise write setup state into a
    /// temporary directory the OS deletes).
    ///
    /// The `Bool` is `HomeAdoption.Result.migrated`: adoption may have moved an
    /// existing legacy container into the vault and renamed the original, and
    /// this step advances the instant it succeeds, so it has no surface of its
    /// own to say so. The overlay carries it to the closing step.
    let onAdopted: (AppEnvironment, Bool) -> Void

    /// The environment rebuilt against the adopted vault, and whether adoption
    /// moved a legacy container into it. Held as state rather than as locals
    /// because adoption can now be reached from two places — the chooser and the
    /// confirmation — and both hand the same values on.
    @State private var adoptedEnvironment: AppEnvironment?
    @State private var didMigrate = false

    /// True once a folder has been adopted, which on this step means the user
    /// arrived back here through Back and already has a Home.
    private var hasAdoptedHome: Bool { !environment.isProvisionalHome }

    /// The adopted vault's path, in tilde form, or `nil` while the home is still
    /// provisional.
    ///
    /// Read from `AinkradHome.resolve()` — the POINTER that adoption writes —
    /// rather than from this view's own state. State would be wrong on the path
    /// that matters: the step is re-created when the user comes Back to it, so
    /// anything remembered here is gone by the time they most need to see which
    /// folder they picked.
    private var adoptedPath: String? {
        guard hasAdoptedHome, case .ready(let home) = AinkradHome.resolve() else { return nil }
        return SetupHomeMigrationNotice.abbreviatingHome(home.vaultRoot.path)
    }

    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @Environment(\.setupGroupWidth) private var groupWidth
    @Environment(\.ainkradSkin) private var skin

    /// Asked BEFORE the user chooses, which is the entire point of this task:
    /// `VaultMigration.needsMigration(container:)` is answerable up front, so a
    /// user whose data is about to be moved and whose old container is about to
    /// be renamed is told first rather than on the closing screen after the
    /// fact. Never derived from `HomeAdoption.Result.migrated` — that value
    /// does not exist until the migration has already run.
    ///
    /// Computed once in `onAppear` rather than per body evaluation: it hits the
    /// file system, and the answer cannot change while this screen is up (the
    /// only thing that changes it is an adoption, which ends this screen).
    @State private var migrationNotice: SetupHomeMigrationNotice?

    /// Flipped once, by the first preview row to appear, to stage the folder
    /// listing in. Never reset — Back to this step re-mounts the view.
    @State private var hasSettled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(skin.size.s20)
                .onAppear { migrationNotice = SetupHomeMigrationNotice.make() }
            // The footer has two shapes, because this step has two states.
            //
            // BEFORE a folder is chosen the primary IS the requirement — there
            // is no Continue, because there is nothing to continue to. No
            // `SetupRequirementNote` either, unlike the other gated steps:
            // "Choose a folder to continue" printed above a button reading
            // "Choose Folder…" would be noise, not an explanation. The rule
            // still lives in `SetupValidation` so `canAdvance(from: .home,)`
            // tells a programmatic caller the truth.
            //
            // AFTER one is adopted the user can be back here via Back, so the
            // primary becomes Continue and changing the folder moves to a
            // secondary. Without that, returning to this step would trap them:
            // its only button would re-open a folder chooser they may have come
            // back merely to look at.
            if hasAdoptedHome {
                adoptedFooter
            } else {
                SetupStepFooter(
                    coordinator: coordinator,
                    primaryTitle: "Choose Folder…",
                    primaryIdentifier: "setup.home.choose"
                ) { choose() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// Names the folder that is currently the Home.
    ///
    /// Shown only once one is adopted, and placed ABOVE the "Inside it" preview
    /// so the order reads as a statement then its explanation: this is your
    /// folder, and this is what is in it. Someone who came Back to this step did
    /// so to check or change the folder, and the first thing they need is which
    /// one it currently is.
    private func selectedFolder(_ path: String, tokens: DesignTokens) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: skin.size.s9) {
            Image(systemName: "checkmark.circle.fill")
                .font(skin.font(AinkradFontToken(sizeKey: "t12", scaled: false)))
                .foregroundStyle(tokens.accentSecondary)
            VStack(alignment: .leading, spacing: skin.size.s3) {
                Text("Your Ainkrad Home")
                    .font(AinkradFont.display(11, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(skin.opacity.o50))
                Text(path)
                    // Monospaced: this is a path, and a path set in the UI face
                    // is harder to read back character by character — which is
                    // exactly what someone verifying a folder is doing.
                    .font(skin.font(AinkradFontToken(sizeKey: "t13", weight: "medium", mono: "system", scaled: false)))
                    .foregroundStyle(tokens.foreground)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(skin.size.s14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ChamferShape(cut: skin.radius.md)
                .fill(tokens.accentSecondary.opacity(skin.opacity.o09))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your Ainkrad Home is \(path)")
        .accessibilityIdentifier("setup.home.selected")
    }

    /// A folder the app will not claim.
    ///
    /// ONE button, and it re-opens the chooser rather than merely closing: the
    /// user is mid-task and the only thing they can do next is pick again, so
    /// making them dismiss and then find the button again is a step for nothing.
    private func refusalModal(_ message: String) -> SetupModalPresenter.Modal {
        SetupModalPresenter.Modal(
            title: "That folder can't be used",
            message: message,
            icon: "exclamationmark.circle",
            tone: .caution,
            primaryTitle: "Choose Another Folder",
            primary: {
                modals.dismiss()
                choose()
            },
            onDismiss: { modals.dismiss() })
    }

    /// The "this folder already holds a vault" decision.
    ///
    /// It states the COUNT, because "this folder is already an Ainkrad Home" and
    /// "this folder has 214 things in it" land very differently, and the second
    /// is the one that stops someone who picked the wrong folder.
    ///
    /// The safe action is the secondary, so dismissing the modal by any route —
    /// including a stray click on the scrim — picks again rather than claiming
    /// the vault.
    private func existingVaultModal(url: URL, entryCount: Int) -> SetupModalPresenter.Modal {
        SetupModalPresenter.Modal(
            title: "This folder is already an Ainkrad Home",
            message: "\(SetupHomeMigrationNotice.abbreviatingHome(url.path)) already holds an "
                + "Ainkrad vault with \(entryCount) item\(entryCount == 1 ? "" : "s") in it.\n\n"
                + "Using it keeps everything that is already there — this is how you reconnect "
                + "to your work after reinstalling, or on a new Mac. Nothing is deleted or "
                + "overwritten.",
            icon: "clock.arrow.circlepath",
            tone: .informational,
            primaryTitle: "Use This Vault",
            primary: { confirm(url) },
            secondaryTitle: "Pick a Different Folder",
            secondary: { modals.dismiss() },
            onDismiss: { modals.dismiss() })
    }

    /// The footer once a Home exists: Continue leads, Change is secondary.
    ///
    /// Change sits beside Back rather than as the primary, because by the time
    /// the user is standing here again the folder is settled — moving it is the
    /// exception, and the exception should not be the button under their thumb.
    private var adoptedFooter: some View {
        HStack {
            if coordinator.canGoBack {
                AinkradButton(title: "Back", style: .secondary) { coordinator.back() }
                    .accessibilityIdentifier("setup.back")
            }
            AinkradButton(title: "Change Folder…", style: .secondary) { choose() }
                .accessibilityIdentifier("setup.home.change")
            Spacer(minLength: 0)
            AinkradButton(title: "Continue", style: .primary) { coordinator.advance() }
                .accessibilityIdentifier("setup.continue")
        }
        .padding(skin.size.s20)
    }

    /// The folder is the idea, so the folder is what is drawn: a listing of
    /// what will exist inside whatever the user picks. Someone looking at this
    /// is choosing a place for their work to live, not filling in a path.
    private var content: some View {
        let tokens = environment.themeManager.tokens

        return ScrollView {
            VStack(alignment: .leading, spacing: skin.size.s18) {
                Text(
                    "Pick an empty folder, or make a new one anywhere you like — "
                        + "your Documents, an external drive, a synced folder. Ainkrad "
                        + "will never take over a folder that already has files in it."
                )
                .font(AinkradFont.display(14))
                .foregroundStyle(tokens.foreground.opacity(skin.opacity.o78))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                // Prose, so the READING measure — the folder listing below
                // is what uses the extra width.
                .frame(
                    maxWidth: SetupStageLayout.readingWidth(inGroupOf: groupWidth),
                    alignment: .leading)

                if let adoptedPath {
                    selectedFolder(adoptedPath, tokens: tokens)
                }

                folderPreview(tokens: tokens)

                if let migrationNotice {
                    notice(
                        title: migrationNotice.title,
                        message: migrationNotice.message,
                        icon: "arrow.right.doc.on.clipboard",
                        tint: tokens.accentSecondary,
                        tokens: tokens
                    )
                    .accessibilityIdentifier("setup.home.migrationWarning")
                }

            }
            .padding(.bottom, skin.spacing.xs)
        }
    }

    /// A live folder listing. No separator lines between the rows — one
    /// seamless recessed surface, per the design language — and each row
    /// arrives a beat after the one above it so the list assembles rather than
    /// appearing as a block. Flat under reduce-motion.
    private func folderPreview(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: skin.spacing.md) {
            HStack(spacing: skin.spacing.sm) {
                Image(systemName: "folder.fill")
                    .font(skin.font(AinkradFontToken(sizeKey: "t12", scaled: false)))
                    .foregroundStyle(tokens.accentPrimary)
                Text("Inside it")
                    .font(AinkradFont.display(12, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(skin.opacity.o50))
            }

            VStack(alignment: .leading, spacing: skin.size.s14) {
                ForEach(Array(SetupHomePreview.entries.enumerated()), id: \.element.id) {
                    index, entry in
                    entryRow(entry, index: index, tokens: tokens)
                }
            }
        }
        .padding(skin.spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ChamferShape(cut: skin.radius.md)
                .fill(tokens.surfaceElevated.opacity(skin.opacity.o35))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("What Ainkrad will create in the folder you choose")
    }

    private func entryRow(
        _ entry: SetupHomePreview.Entry, index: Int,
        tokens: DesignTokens
    ) -> some View {
        let geometry = SetupStageMotion.layerGeometry(
            .content,
            reduceMotion: reduceMotion,
            isForward: true)
        // The stage's own `.content` travel, scaled down — these are rows
        // settling inside a panel, not the panel arriving. Scaled rather than
        // hardcoded so the rows still track `SetupStageMotion`'s vocabulary if
        // that geometry is ever retuned.
        //
        // `isForward: true` above is not a direction claim: the stage already
        // owns directional entry for the step as a whole, and this is a settle
        // that runs once on appear. It is asked in the forward orientation
        // purely to take the magnitude and the reduce-motion gate.
        let travel = geometry.map { $0.travel * 0.22 } ?? 0
        // Per-index stagger ONLY. `SetupStageMotion.animation(layer: .content)`
        // already carries that layer's 0.11s delay; adding `geometry.delay` to
        // it — as this line originally did — counted the same delay twice and
        // held the first row off screen for 0.22s before the list began
        // assembling. `geometry` is still what is consulted, because `nil` is
        // the reduce-motion seam.
        let delay = geometry.map { _ in Double(index) * 0.05 } ?? 0

        return HStack(alignment: .top, spacing: skin.size.s10) {
            Image(systemName: entry.icon)
                .font(skin.font(AinkradFontToken(sizeKey: "t12", scaled: false)))
                .foregroundStyle(tokens.accentSecondary)
                .frame(width: skin.size.s16)
            VStack(alignment: .leading, spacing: skin.size.s3) {
                Text(entry.name)
                    .font(AinkradFont.mono(12))
                    .foregroundStyle(tokens.foreground.opacity(skin.opacity.o90))
                Text(entry.detail)
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(skin.opacity.o55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(hasSettled ? 1 : 0)
        .offset(x: hasSettled ? 0 : travel)
        // Through `SetupStageMotion`, never a bare `.animation` — reduce-motion
        // makes this `nil` and the rows are simply present.
        .animation(
            SetupStageMotion.animation(
                reduceMotion: reduceMotion,
                layer: .content)?.delay(delay),
            value: hasSettled
        )
        .onAppear {
            guard !hasSettled else { return }
            hasSettled = true
        }
    }

    /// The inline notice, now used only by the migration warning.
    ///
    /// It once also carried the refusal. That moved to a modal
    /// (`SetupModalPresenter`) because the user could not see it — a five-line
    /// explanation rendered below the fold on this step's scroller. What is left
    /// here is the right shape for THIS job: the migration warning is not a
    /// response to anything the user just did, it is part of the screen they are
    /// reading before they choose, so interrupting them with it would be wrong.
    ///
    /// It does not scroll. The step owns the only scroller on this axis.
    private func notice(
        title: String, message: String, icon: String,
        tint: Color, tokens: DesignTokens
    ) -> some View {
        HStack(alignment: .top, spacing: skin.size.s10) {
            Image(systemName: icon)
                .font(skin.font(AinkradFontToken(sizeKey: "t12", scaled: false)))
                .foregroundStyle(tint)
                .frame(width: skin.size.s16)
            VStack(alignment: .leading, spacing: skin.size.s5) {
                Text(title)
                    .font(AinkradFont.display(12, weight: .medium))
                    .foregroundStyle(tint)
                Text(message)
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(skin.opacity.o72))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(skin.size.s14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChamferShape(cut: skin.radius.md).fill(tint.opacity(skin.opacity.o09)))
    }

    private func choose() {
        // Bail BEFORE adopting, not at the re-point. `adoptAndRebuild` writes the
        // marker, migrates the real legacy container and writes the POINTER
        // before `install` is ever called, so an optional-chained
        // `installer?.install` would let all of that happen and skip only the
        // re-point — leaving the app running on the provisional home while a real
        // vault on disk had been claimed and the legacy tree renamed. Nothing at
        // all is the only safe answer when there is nobody to hand the rebuilt
        // environment to (previews, and any test that builds this view without an
        // installer).
        // Logged, not silent: returning is correct, but this step's ONLY button
        // then does nothing at all, with no refusal and no modal — a wizard that
        // appears frozen on its one irreversible screen. Anyone who hits it in a
        // preview or a hand-built tree needs to be told why.
        guard let installer else {
            Log.persistence.error(
                "Setup Home step has no SetupHomeInstaller; adoption is unavailable in this view tree")
            return
        }

        let outcome = withModel(installer) { $0.choose() }
        apply(outcome)
    }

    /// Adopt a folder the user has just confirmed in the notice below.
    private func confirm(_ url: URL) {
        guard let installer else {
            Log.persistence.error(
                "Setup Home step has no SetupHomeInstaller; adoption is unavailable in this view tree")
            return
        }
        modals.dismiss()
        apply(withModel(installer) { $0.adoptConfirmed(url) })
    }

    private func apply(_ outcome: SetupHomeStepModel.Outcome) {
        switch outcome {
        case .adopted:
            modals.dismiss()
        case .rejected(let message):
            modals.present(refusalModal(message))
        case .needsConfirmation(let url, let entryCount):
            modals.present(existingVaultModal(url: url, entryCount: entryCount))
        case .cancelled:
            break
        }
        // `install` always runs on a successful adoption, so `adoptedEnvironment`
        // is set by the time `.adopted` comes back. Advancing the OUTGOING
        // coordinator would move the wizard on while still bound to the
        // provisional store, so there is deliberately no fallback.
        if case .adopted = outcome, let rebuilt = adoptedEnvironment {
            onAdopted(rebuilt, didMigrate)
        }
    }

    /// Builds the model, runs `body` against it, and leaves the rebuilt
    /// environment in `adoptedEnvironment` for `apply` to hand on.
    ///
    /// Shared by `choose()` and `confirm(_:)` so the adoption path — which
    /// writes the marker, migrates the legacy container and re-points every
    /// holder — exists exactly once regardless of whether a confirmation was
    /// required.
    private func withModel(
        _ installer: SetupHomeInstaller,
        _ body: (SetupHomeStepModel) -> SetupHomeStepModel.Outcome
    )
        -> SetupHomeStepModel.Outcome
    {
        let model = SetupHomeStepModel(
            chooseVault: LaunchHomeResolver.presentFolderChooser,
            adopt: { url in
                let result = try HomeAdoption.adoptAndRebuild(chosen: url) { newEnvironment in
                    // The gate must stay up across the swap: `bootstrap` defaults
                    // this to false, and a rebuilt environment that forgets it
                    // would drop the user into the workspace mid-wizard.
                    newEnvironment.isSetupPresented = true
                    // The real vault is claimed, so the provisional restrictions
                    // (above all the throwaway Keychain namespace) are lifted.
                    newEnvironment.isProvisionalHome = false
                    adoptedEnvironment = newEnvironment
                    installer.install(newEnvironment)
                }
                // Carried, not just logged. This step advances the moment it
                // succeeds so it has no surface of its own left to render on,
                // but a user whose container was moved and whose old copy was
                // renamed `Documents.migrated` must be told somewhere — and
                // `.done` is that somewhere. Dropping it here is how the rename
                // became a thing users would only ever discover in Finder.
                didMigrate = result.migrated
                if result.migrated {
                    Log.persistence.info("Setup migrated the legacy container into the adopted Home")
                }
            })

        return body(model)
    }
}
