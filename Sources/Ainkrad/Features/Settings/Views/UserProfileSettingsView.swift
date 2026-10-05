import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// One profile fact the user can state about themselves.
///
/// The single source of the four keys. `SetupYouStepView` and this pane both
/// read it, because they write the SAME facts to the SAME store — and a key
/// typo on one side would orphan what the other already wrote, with no error.
struct UserProfileField: Identifiable {
    let key: String
    let title: String
    let hint: String
    let placeholder: String

    var id: String { key }

    static let all: [UserProfileField] = [
        UserProfileField(
            key: "name",
            title: "Name",
            hint: "How you are referred to in writing.",
            placeholder: "Ada Lovelace"),
        UserProfileField(
            key: "callMe",
            title: "What to call you",
            hint: "How the assistant addresses you.",
            placeholder: "Ada"),
        UserProfileField(
            key: "role",
            title: "Role",
            hint: "What you do — it shapes the level the assistant pitches at.",
            placeholder: "Engineer"),
        UserProfileField(
            key: "timezone",
            title: "Timezone",
            hint: "Used for scheduling and time-aware answers.",
            placeholder: TimeZone.current.identifier),
    ]
}

/// The Settings counterpart to the wizard's You step.
///
/// Without this the four facts were write-once: the wizard collected them at
/// first run and nothing in the app could show, let alone correct, them
/// afterwards.
struct UserProfileSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var values: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(UserProfileField.all) { field in
                AinkradSettingsPanel(title: field.title, hint: field.hint) {
                    AinkradTextField(
                        text: Binding(
                            get: { values[field.key] ?? "" },
                            set: { newValue in
                                values[field.key] = newValue
                                write(newValue, for: field.key)
                            }),
                        placeholder: field.placeholder)
                }
            }

            Text(
                "These facts are projected into USER.md and the assistant's memory — "
                    + "they change what it knows about you, not just what it calls you."
            )
            .font(AinkradFont.display(11))
            .foregroundStyle(environment.themeManager.tokens.foreground.opacity(0.4))
            .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { values = environment.userProfileStore.all() }
    }

    /// Trimmed on the way in, exactly as the wizard does — a trailing space in
    /// a name reaches the agent's prompt otherwise.
    ///
    /// Unlike the wizard's `SetupYou.apply` (which skips blanks — a field left
    /// blank there just hasn't been answered yet), an emptied field HERE
    /// clears the stored fact: this is an editor, and a user must be able to
    /// delete a wrong value rather than have it linger in `profile.json` and
    /// keep projecting into `USER.md` forever.
    private func write(_ value: String, for key: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            environment.userProfileStore.remove(key)
            return
        }
        environment.userProfileStore.set(trimmed, for: key)
    }
}
