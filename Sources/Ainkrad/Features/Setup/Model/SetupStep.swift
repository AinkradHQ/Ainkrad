import Foundation

/// The ordered steps of first-run setup.
///
/// `introducedIn` is the `setupVersion` that added the step. A user who completed
/// an earlier version is asked only for steps introduced since, rather than being
/// walked through the whole wizard again.
enum SetupStep: String, CaseIterable, Identifiable, Sendable {
    case welcome, home, appearance, motionAndSound, you, providers, assistant, done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .home: return "Your Ainkrad Home"
        case .appearance: return "Appearance"
        case .motionAndSound: return "Motion & Sound"
        case .you: return "You"
        case .providers: return "Connect an AI Provider"
        case .assistant: return "Your Sage"
        case .done: return "Ready"
        }
    }

    /// The words at the top of the stage, at 30pt.
    ///
    /// Separate from `title` because the two are doing different jobs and the
    /// same string cannot do both well. `title` is a rail LABEL — it is read at
    /// 11pt-equivalent by VoiceOver and identifies a position in a sequence, so
    /// "You" and "Ready" are exactly right there. Set 30pt and left-aligned in
    /// the middle of an otherwise empty stage, a one-word noun reads as a
    /// section header on a form, which is precisely the shape this redesign is
    /// moving away from.
    ///
    /// Defaults to `title`, so a step only overrides when its rail label would
    /// make a poor headline. Overriding is deliberately cheap: the alternative
    /// was special-casing two steps inside `SetupStage`, which puts a step's
    /// copy somewhere nobody editing that step would think to look.
    var headline: String {
        switch self {
        // "Welcome" is the emptiest possible first impression: it says nothing
        // about what the product is, on the one screen whose entire job is to
        // say that.
        case .welcome: return "Ainkrad is a workspace where agents work beside you."
        default: return title
        }
    }

    /// True when the step shows the brand mark as its SUBJECT — large, centred,
    /// above the headline — rather than as a small mark beside it.
    ///
    /// Only `.welcome`. It is the one screen whose job is the first impression,
    /// so it is a centred composition rather than a left-aligned column; every
    /// other step is a form and reads correctly left-aligned.
    ///
    /// The stage renders ONE mark either way and moves it between the two
    /// arrangements, so this also decides where that mark travels to when the
    /// user leaves Welcome.
    ///
    /// Expressed as a property rather than a `case .welcome` inside `SetupStage`
    /// so the stage stays free of per-step knowledge.
    var usesHeroMark: Bool { self == .welcome }

    /// The `setupVersion` this step was introduced in. Every case ships in
    /// version 1 today; a later release can add a step at version 2 and
    /// re-gate existing users on only that step.
    var introducedIn: Int { 1 }
}
