import Foundation

/// Turns the `NSError` from `Bundle.loadAndReturnError()` into something a user
/// can act on.
///
/// WHY THIS EXISTS — do not simplify it back to a `Bool`.
///
/// On 2026-07-28 Terminal's bundle stopped loading and the App Store banner
/// said, in its entirety:
///
///     TerminalPlugin — Bundle.load() failed
///
/// That was the whole diagnostic, because the loader called `Bundle.load()`,
/// which returns a bare `Bool` and throws the reason away. Finding the actual
/// cause took a long session and ended in a manual symbol-set diff — `nm -u` on
/// the bundle, `nm -gU` on the host's embedded framework, `comm -23` between
/// them — which produced exactly one line:
///
///     _$s21AinkradAppKitContract15MCPResourceSpecV012requiresLiveB0Sbvs
///
/// i.e. the setter for `MCPResourceSpec.requiresLiveApp`. Terminal had been
/// built against a NEWER AinkradAppKit revision than the host embeds. Both were
/// generation 8, so the generation gate passed cleanly and the failure landed
/// at dynamic-link time instead. dyld had named the missing symbol and the
/// library it expected it in, the whole time; we simply discarded the message.
///
/// WHAT THE ERROR ACTUALLY CONTAINS (verified against a real reproduction: a
/// bundle linked against a dylib that was then rebuilt without the symbol):
/// domain `NSCocoaErrorDomain`, code 3588, NO `underlyingError`. The dyld text
/// lives in `NSDebugDescription` and looks like:
///
///     dlopen(…/Contents/MacOS/Probe, 0x0109): Symbol not found: _SYMBOL
///       Referenced from: <UUID> /…/Probe
///       Expected in:     <UUID> /…/libFakeSDK.dylib
///
/// `NSLocalizedDescription` is only "The bundle … couldn't be loaded." — which
/// is the same non-information the old string carried. So the useful text is
/// nested, and this type digs it out.
///
/// WHY TWO FORMS. The `banner` feeds `AppStoreStore.failureText`, a one-line
/// user-facing "couldn't be loaded" list; the full three-line dyld dump is
/// unreadable there. `log` is the untruncated error, emitted at error level by
/// the loader regardless of what the banner shows, so nothing is lost.
public enum PluginLoadDiagnostics {

    /// The two renderings of one load failure.
    public struct Diagnosis: Equatable, Sendable {
        /// One sentence, fit for the App Store banner.
        public let banner: String
        /// Everything we were given, for the unified log.
        public let log: String
    }

    /// The name of the SDK whose skew we call out by name. A missing symbol
    /// from anything else is still reported with its symbol, just without the
    /// "rebuild or bump the pin" advice, which only applies to our own SDK.
    private static let sdkName = "AinkradAppKit"

    public static func diagnose(_ error: NSError) -> Diagnosis {
        let detail = detailText(error)
        let log = detail.isEmpty ? error.localizedDescription : detail

        guard let symbol = missingSymbol(in: detail) else {
            // Not a symbol failure (missing executable, bad architecture,
            // corrupt image…). `NSDebugDescription`'s first line is already a
            // one-liner in those cases; fall back to the localized description
            // if there is no debug text at all.
            let firstLine = detail.split(separator: "\n").first.map(String.init)
            return Diagnosis(banner: firstLine ?? error.localizedDescription, log: log)
        }

        // The SDK-skew case: the symbol itself is Swift-mangled and carries the
        // defining module ("…21AinkradAppKitContract…"), and the `Expected in:`
        // line names the library. Either mentioning the SDK is enough.
        let looksLikeSDKSkew = symbol.contains(sdkName) || expectedInLibrary(in: detail)?.contains(sdkName) == true
        guard looksLikeSDKSkew else {
            return Diagnosis(
                banner:
                    "missing symbol \(symbol) at load time — this plugin was built against a different version of a library than the host provides",
                log: log)
        }
        // The sentence that would have saved the session. The raw symbol stays
        // in it: it is what makes the diagnosis certain rather than plausible.
        //
        // Deliberately does NOT claim a DIRECTION. A missing symbol proves the
        // plugin and the host disagree about the SDK; it says nothing about
        // which side is ahead. This message used to assert "built against a
        // NEWER AinkradAppKit" and advise bumping the host's pin — and the first
        // time it fired in anger the truth was the opposite: the plugins were
        // pinned BEHIND the host, to a revision where
        // `AinkradSearchField.init(text:placeholder:onSubmit:)` still existed
        // before a `focus:` parameter was added to it. Bumping the host would
        // have moved it further from the plugins, not closer.
        //
        // Rebuilding the plugin against the host's revision is the action that
        // is correct in BOTH directions, so that is the one named.
        return Diagnosis(
            banner: "was built against a different \(sdkName) revision than this host embeds — "
                + "repin the plugin to the host's SDK revision and rebuild it "
                + "(missing symbol \(symbol))",
            log: log)
    }

    /// The richest text the error carries. `NSDebugDescription` first (that is
    /// where dyld's message lands), then any `underlyingError`'s — checked even
    /// though the observed failure had none, because the key is documented and
    /// costs one lookup.
    private static func detailText(_ error: NSError) -> String {
        if let debug = error.userInfo[NSDebugDescriptionErrorKey] as? String, !debug.isEmpty { return debug }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            if let debug = underlying.userInfo[NSDebugDescriptionErrorKey] as? String, !debug.isEmpty { return debug }
            return underlying.localizedDescription
        }
        return ""
    }

    /// Extracts the symbol from a `Symbol not found: _foo` fragment. Mangled
    /// Swift names contain no whitespace, so "to end of line/whitespace" is a
    /// safe terminator.
    private static func missingSymbol(in text: String) -> String? {
        field(after: "Symbol not found:", in: text)
    }

    /// The library dyld expected the symbol in, from the `Expected in:` line.
    /// That line is `Expected in: <UUID> /path/to/lib` — the UUID is noise, so
    /// the last whitespace-separated component is the path.
    private static func expectedInLibrary(in text: String) -> String? {
        guard let line = text.split(separator: "\n").first(where: { $0.contains("Expected in:") }) else { return nil }
        return line.split(whereSeparator: \.isWhitespace).last.map(String.init)
    }

    private static func field(after marker: String, in text: String) -> String? {
        guard let range = text.range(of: marker) else { return nil }
        let rest = text[range.upperBound...]
        let token = rest.drop(while: \.isWhitespace).prefix(while: { !$0.isWhitespace })
        return token.isEmpty ? nil : String(token)
    }
}
