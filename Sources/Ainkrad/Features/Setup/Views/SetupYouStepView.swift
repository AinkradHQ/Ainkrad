import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Writes the You step into the profile store, which projects into `USER.md` so
/// the assistant can read it. Blank fields are omitted rather than stored empty:
/// an empty fact would still be projected as `- role: ` and read as a fact.
///
/// The keys (`name`, `callMe`, `role`, `timezone`) are a contract — they are
/// what the assistant sees in `USER.md`, not an implementation detail.
///
/// Takes the whole `values` dictionary rather than four named parameters so
/// the caller can pass its state straight through, keyed by
/// `UserProfileField.key` — nothing here re-lists the four keys, which is the
/// same list `UserProfileField.all` already owns.
@MainActor
enum SetupYou {
    static func apply(values: [String: String], store: UserProfileStore) {
        for (key, value) in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            store.set(trimmed, for: key)
        }
    }
}

/// The "You" step: who the user is, in the assistant's own words.
///
/// Name and role ARE required — this reverses the step's original "everything
/// is optional" design at the product owner's decision, because an assistant
/// with no idea who it works for is the thing first-run exists to prevent. The
/// rules live in `SetupValidation`, and each unmet one is rendered beneath its
/// own field, not only as a disabled Continue. "What to call you" and
/// "Timezone" stay optional; timezone in particular is merely prefilled, and a
/// user who clears it must still be able to continue.
///
/// Each field commits on change (no Save button, no draft state), matching the
/// rest of the wizard and Settings. A field cleared back to blank leaves the
/// previously written fact in place rather than storing an empty one: this step
/// is additive, and editing/removing profile facts is a Memory concern, not a
/// first-run one.
///
/// Timezone is prefilled with `TimeZone.current.identifier` and written on
/// appear — a prefill, not a blank, so it lands in `USER.md` for the common
/// case where the user simply continues.
struct SetupYouStepView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.setupGroupWidth) private var groupWidth
    @Environment(\.ainkradSkin) private var skin

    let coordinator: SetupCoordinator

    /// Backs every field, keyed by `UserProfileField.key`. One dictionary
    /// rather than one `@State` per field so `binding(for:)` and `commit()`
    /// can both be driven directly off `UserProfileField.all` — a field added
    /// there needs no matching case added here, and none can be missed.
    @State private var values: [String: String] = ["timezone": TimeZone.current.identifier]
    /// Fields the user has typed in. A requirement note appears only for a
    /// field they have touched — see `message(for:)`.
    @State private var touched: Set<String> = []
    /// Which fields this step requires, asked of `SetupValidation` with every
    /// value blank so the answer is "what is required", not "what is missing".
    /// Derived rather than hardcoded: a rule added to `SetupValidation` shows
    /// up here without touching this view.
    private static let requiredFields = Set(
        SetupValidation.unmet(for: .you, values: [:]).map(\.field))

    var body: some View {
        let tokens = environment.themeManager.hostSkin

        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s18) {
                    intro(tokens: tokens)
                    AinkradSettingsPanel(
                        title: "About you",
                        hint: "Saved as you type — all of it stays editable later in Memory."
                    ) {
                        fieldGrid(tokens: tokens)
                    }
                }
                .padding(skin.size.s20)
                // FILLS the group, like every other step. The FIELDS are what
                // hold their own width — see `fieldGrid`.
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            SetupStepFooter(
                coordinator: coordinator,
                isPrimaryDisabled: !unmet.isEmpty
            ) {
                commit()
                coordinator.advance()
            }
        }
        .onAppear {
            // Seeds already-stored facts into the fields — the normal case now
            // that this step can be replayed from Settings on a vault that
            // already has a profile. Without this a replay shows blank fields
            // as if nothing had ever been entered, even though nothing was
            // lost (`SetupYou.apply` skips blanks on commit). Matches the
            // Settings You page, which seeds its drafts from the same store.
            for (key, value) in environment.userProfileStore.all() where !value.isEmpty {
                values[key] = value
            }
            write(values["timezone"] ?? "", for: "timezone")
        }
    }

    /// The rules live in `SetupValidation` so the next change to them is one
    /// file, not a `.disabled(...)` condition buried in this view.
    private var unmet: [SetupValidation.Requirement] {
        SetupValidation.unmet(for: .you, values: values)
    }

    /// The warning for `key`, shown only once the user has typed in that field
    /// and left it blank.
    ///
    /// Shown unconditionally, a first-time user arrives to two warnings about
    /// fields they have not yet been given the chance to answer, which reads as
    /// an error state on a blank form. What keeps the reason visible from
    /// arrival instead is the persistent "Required" marker beside those fields
    /// — a statement of the rule rather than an accusation. The warning is the
    /// escalation when the rule has actually been broken.
    ///
    /// Either way Continue stays disabled the whole time: this gates the note,
    /// never the gate.
    private func message(for key: String) -> String? {
        guard touched.contains(key) else { return nil }
        return unmet.first { $0.field == key }?.message
    }

    private func intro(tokens: AinkradSkin) -> some View {
        Text(
            "Anything you fill in here goes into the assistant's memory, so it knows who "
                + "it's working with. Your name and role are needed so it knows who it is "
                + "working for; the rest is optional, and all of it is editable later in "
                + "Memory."
        )
        .font(AinkradFont.display(12))
        .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o60))
        .fixedSize(horizontal: false, vertical: true)
        // Prose is capped even though the column fills.
        .frame(
            maxWidth: SetupStageLayout.readingWidth(inGroupOf: groupWidth),
            alignment: .leading)
    }

    /// The four fields, each one full width, stacked.
    ///
    /// A single column by decision, not by default: an adaptive two-column grid
    /// was tried and rejected. One field per row keeps the form a single
    /// top-to-bottom sequence — there is no reading order to work out, and the
    /// labels all start on the same left edge.
    ///
    /// The cards therefore take the whole column, which on a wide window means a
    /// wide text field. That is the accepted trade.
    private func fieldGrid(tokens: AinkradSkin) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s10) {
            ForEach(UserProfileField.all) { profileField in
                field(
                    tokens: tokens, title: profileField.title,
                    subtitle: profileField.hint,
                    placeholder: profileField.placeholder,
                    text: binding(for: profileField.key), key: profileField.key)
            }
        }
    }

    /// Maps a `UserProfileField.key` to a binding into `values`. Generic over
    /// the key rather than a `switch` over a fixed set of cases — a field
    /// added to `UserProfileField.all` gets a working binding automatically,
    /// with no case to remember to add and no silent no-op default to fall
    /// into on a typo.
    private func binding(for key: String) -> Binding<String> {
        Binding(get: { values[key] ?? "" }, set: { values[key] = $0 })
    }

    private func field(
        tokens: AinkradSkin, title: String, subtitle: String,
        placeholder: String, text: Binding<String>, key: String
    ) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s6) {
            HStack(spacing: skin.size.s6) {
                Text(title)
                    .font(AinkradFont.display(13, weight: .medium))
                    .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o90))
                // Visible from arrival, for required fields only. This is what
                // keeps the rule on screen without greeting a blank form with
                // warnings — see `message(for:)`.
                if Self.requiredFields.contains(key) {
                    Text("Required")
                        .font(AinkradFont.display(9, weight: .medium)).kerning(0.5)
                        .foregroundStyle(tokens.color(\.accentTertiary))
                        .accessibilityIdentifier("setup.you.\(key).required")
                }
                Spacer(minLength: 0)
            }
            Text(subtitle)
                .font(AinkradFont.display(11))
                .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o50))
            AinkradTextField(text: text, placeholder: placeholder)
                .onChange(of: text.wrappedValue) { _, new in
                    touched.insert(key)
                    write(new, for: key)
                }
            // Beside the field it is about, not only at the Continue button.
            if let message = message(for: key) {
                SetupRequirementNote(message: message, tokens: tokens)
                    .accessibilityIdentifier("setup.you.\(key).requirement")
            }
        }
        .padding(skin.size.s14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChamferShape(cut: skin.radius.md).fill(tokens.color(\.surfaceElevated).opacity(skin.opacity.o50)))
        .overlay(
            ChamferShape(cut: skin.radius.md).strokeBorder(tokens.color(\.accentPrimary).opacity(skin.opacity.o15), lineWidth: 1)
        )
    }

    /// Belt-and-braces: `onChange` already commits every keystroke, but a field
    /// left mid-composition when Continue is hit must not be lost.
    private func commit() {
        SetupYou.apply(values: values, store: environment.userProfileStore)
    }

    private func write(_ value: String, for key: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        environment.userProfileStore.set(trimmed, for: key)
    }
}
