import AinkradAppKit
import Foundation

/// What to tell the user when the Home cannot be resolved, and what they may do
/// about it. A pure function of the error — no AppKit, no I/O — so the launch
/// paths that have never once been executed by a human (nobody has ever clicked
/// a button in this panel: assistive access was refused) are nonetheless covered
/// by tests. `LaunchHomeResolver.presentAlert` is the only part left to
/// inspection.
enum LaunchRecovery {
    enum Action: Equatable {
        /// Ask the user for a folder and claim it. Never a folder the app picked.
        case chooseFolder
        case quit
    }

    struct Prompt: Equatable {
        let title: String
        let message: String
        /// Button titles, in display order; the first is the default.
        let buttons: [String]
        /// Parallel to `buttons`.
        let actions: [Action]
    }

    private static func recoverable(
        _ title: String, _ message: String,
        choose: String = "Choose Folder…"
    ) -> Prompt {
        Prompt(
            title: title, message: message,
            buttons: [choose, "Quit Ainkrad"], actions: [.chooseFolder, .quit])
    }

    /// `nil` means "not something to show an alert about" — only
    /// `setupCancelled`, which the launch path handles by exiting cleanly.
    static func prompt(for error: Error) -> Prompt? {
        switch error {
        case LaunchHomeResolver.Failure.setupCancelled:
            return nil

        case LaunchHomeResolver.Failure.vaultMissing(let path):
            return recoverable(
                "Your Ainkrad Home isn’t available",
                """
                Ainkrad expected your Home at:

                \(path)

                That folder isn’t there right now — it may be on an external or \
                network drive that hasn’t been mounted yet. Reconnect the drive \
                and open Ainkrad again, or choose where your Home is now.

                Ainkrad will not start somewhere else on its own: that would give \
                you a second, empty Home and split your data in two.
                """,
                choose: "Locate Home…")

        case LaunchHomeResolver.Failure.notAnAinkradHome(let path):
            return recoverable(
                "That folder isn’t this Ainkrad Home",
                """
                Ainkrad is pointed at:

                \(path)

                The folder is there, but it isn’t recognised as this Home — its \
                identity file is missing or belongs to a different Home. This is \
                normal if a vault was copied from another Mac.

                Choose the folder you want Ainkrad to use, and it will be claimed \
                as your Home.
                """,
                choose: "Choose Folder…")

        case HomeError.notEmpty(let url):
            return recoverable(
                "That folder already has files in it",
                """
                \(url.path)

                Ainkrad only takes over a folder that is empty, or one it already \
                set up. This is deliberate: pointing it at a folder something else \
                owns — a notes vault, a Documents folder — would put Ainkrad’s \
                files in the middle of your own.

                Choose an empty folder, or create a new one.
                """,
                choose: "Choose Another Folder…")

        case HomeError.nestedHome(let url):
            return recoverable(
                "That folder is inside another Ainkrad Home",
                """
                \(url.path)

                One Home cannot live inside another — Ainkrad would not be able to \
                tell which one your data belongs to. Choose a folder outside any \
                existing Ainkrad Home.
                """,
                choose: "Choose Another Folder…")

        case HomeError.notWritable(let url):
            return recoverable(
                "Ainkrad can’t write to that folder",
                """
                \(url.path)

                Ainkrad needs to be able to write into your Home. Check the \
                folder’s permissions, or choose a different folder.
                """,
                choose: "Choose Another Folder…")

        case HomeError.systemLocation(let url):
            return recoverable(
                "That’s a system folder",
                """
                \(url.path)

                Your Home holds your own files, so it has to live somewhere that \
                belongs to you — inside your home folder, or on a drive you own.
                """,
                choose: "Choose Another Folder…")

        case HomeError.doesNotExist(let url):
            return recoverable(
                "That folder no longer exists",
                """
                \(url.path)

                It may have been moved, renamed or deleted since you picked it. \
                Choose the folder you want Ainkrad to use.
                """,
                choose: "Choose Another Folder…")

        default:
            // Includes `unrecognizedResolution` (a newer AinkradAppKit reporting an
            // outcome this host doesn't know) and anything unforeseen. Quitting is
            // the only offer: the app has no idea what state it is in, so inviting
            // the user to pick a folder could claim one over an outcome it cannot
            // interpret. Still an alert and a clean exit rather than a crash.
            return Prompt(
                title: "Ainkrad can’t start",
                message: """
                    Ainkrad couldn’t open your Home.

                    \(error.localizedDescription)

                    Nothing has been changed. If this keeps happening, please report it.
                    """,
                buttons: ["Quit Ainkrad"], actions: [.quit])
        }
    }
}
