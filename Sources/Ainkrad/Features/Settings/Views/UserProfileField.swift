import Foundation

/// One profile fact the user can state about themselves.
///
/// The single source of the four keys. `SetupYouStepView` and the Settings You page both
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
