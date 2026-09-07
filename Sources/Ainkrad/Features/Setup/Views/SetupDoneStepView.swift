import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// The closing step, and the ONLY place `SetupCoordinator.complete()` is called.
///
/// Completion is deliberately concentrated here: `complete()` writes
/// `SetupDocument` to disk immediately, and a marker written anywhere earlier
/// would suppress the first-run gate on every future launch even though the
/// wizard never finished. Every earlier step therefore only calls `advance()`.
///
/// The Keychain line is not decorative. The Home folder is designed to be
/// copied to another Mac, but `Home.keychainServiceName` resolves API keys into
/// this Mac's Keychain — they are not in the vault and do not travel with it. A
/// user who copies their vault and finds their providers gone files a bug;
/// saying it plainly here is cheaper than that bug.
struct SetupDoneStepView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.setupGroupWidth) private var groupWidth

    let coordinator: SetupCoordinator

    /// True when the Home step's adoption migrated a legacy container into the
    /// vault. Adoption moves the old data in and renames the original to
    /// `Documents.migrated`; without this line that rename happens with zero UI
    /// acknowledgement anywhere, and the user meets it as an unexplained folder
    /// in Finder weeks later. `HomeAdoption.Result.migrated` reports exactly
    /// what happened (it is sampled before `adopt` and gated on the identical
    /// predicate), so this cannot claim a migration that did not occur.
    let didMigrateLegacyData: Bool

    /// `~/Library/Application Support/<bundle-id>`, where the renamed original
    /// still sits. Named literally so the user can find it.
    private var legacyCopyPath: String {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ainkrad.app"
        return "~/Library/Application Support/\(bundleID)/Documents.migrated"
    }

    var body: some View {
        let tokens = environment.themeManager.tokens

        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Everything is set up. Here is where your things live.")
                        .font(AinkradFont.display(14))
                        .foregroundStyle(tokens.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: SetupStageLayout.readingWidth(inGroupOf: groupWidth),
                               alignment: .leading)

                    // One point per row, each card full width. A flowing grid
                    // was tried and rejected here for the same reason it was on
                    // the You step: the wizard reads as a single top-to-bottom
                    // sequence, and a second column asks the reader to work out
                    // an order that carries no meaning.
                    VStack(alignment: .leading, spacing: 12) {
                        point(title: "In your Home folder",
                              body: "Workspaces, notes, skills, commands, agent history and "
                                  + "your settings all live in the folder you chose. It is "
                                  + "yours: back it up or copy it to another Mac and your "
                                  + "Ainkrad comes with it.",
                              icon: "folder",
                              tokens: tokens)

                        if didMigrateLegacyData {
                            point(title: "Your existing data was moved in",
                                  body: "Ainkrad found data from an earlier version and copied "
                                      + "it into your new Home folder — it is all there, nothing "
                                      + "was lost. The original copy has not been deleted: it is "
                                      + "still on this Mac at \(legacyCopyPath). You can remove "
                                      + "it once you are happy everything came across.",
                                  icon: "arrow.right.doc.on.clipboard",
                                  tokens: tokens)
                                .accessibilityIdentifier("setup.done.migrated")
                        }

                        point(title: "Not in your Home folder: your API keys",
                              body: "API keys are stored in this Mac's Keychain, never in "
                                  + "your Home folder, and they will not travel with it. If "
                                  + "you copy your Home to another Mac, reconnect your "
                                  + "providers there once — everything else is already in "
                                  + "place.",
                              icon: "key",
                              tokens: tokens)
                    }

                    Text("You can change any of these choices later in Settings.")
                        .font(AinkradFont.display(12))
                        .foregroundStyle(tokens.foreground.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: SetupStageLayout.readingWidth(inGroupOf: groupWidth),
                               alignment: .leading)
                }
                .padding(20)
                // FILLS the group, like every other step. The point cards hold
                // their own width through the grid above.
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // This step's Back used to be hand-rolled here — it was the only one
            // in the wizard. It now goes through `SetupStepFooter` like every
            // other step so there is one Back to find and change, not two.
            //
            // Back is safe here for a structural reason, not by luck: after the
            // Home step adopts a vault the coordinator is rebuilt with
            // `isProvisionalHome: false`, which drops `.home` from `steps`
            // entirely. `back()` walks `steps`, so it cannot return the user to
            // a screen that would re-ask for a Home already adopted.
            SetupStepFooter(coordinator: coordinator,
                            primaryTitle: "Start using Ainkrad",
                            primaryIdentifier: "setup.done.finish") {
                finish()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Marker first, gate second. `complete()` is synchronous and writes before
    /// it returns, so if anything went wrong the gate would still be up on the
    /// next launch rather than the user being dropped into an app whose setup
    /// state says it never happened.
    private func finish() {
        coordinator.complete()
        // Mirror what was just written, so the workspace's banner reflects this
        // run rather than the state the app launched in. This also CLEARS the
        // banner when a returning user connected a provider on the way through.
        environment.deferredSetupSteps = coordinator.deferredSteps
        environment.isSetupPresented = false
        // Cleared here rather than left set: a later legitimate gate raise — a
        // genuinely owed step after an app update — must not inherit replay
        // and walk the whole wizard instead of the one step it owes.
        environment.isSetupReplay = false
    }

    private func point(title: String, body: String, icon: String,
                       tokens: DesignTokens) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(tokens.accentSecondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AinkradFont.display(13, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.9))
                Text(body)
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.4)))
    }
}
