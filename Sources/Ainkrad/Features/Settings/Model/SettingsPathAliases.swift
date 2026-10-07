import AinkradAppKitContract

/// Retired paths resolve forward rather than dead-ending. The IA restructure
/// moved settings people had muscle memory for; a stale deep-link or a
/// persisted selection from an older build should still land somewhere sane.
///
/// Entries are permanent. Deleting one breaks links that may exist in saved
/// sessions, docs, or assistant transcripts.
enum SettingsPathAliases {
    private static let map: [String: String] = [
        "workspace.livingSky": "workspace.appearance",
        "workspace.appIcon": "workspace.appearance",
        "workspace.sound": "workspace.soundAndVoice",
        "workspace.shortcuts": "workspace.keyboard",
        "workspace.mcp": "intelligence.tools",
        "workspace.lsp": "intelligence.tools",
        "workspace.skills": "intelligence.skills",
        "workspace.memory": "intelligence.memory",
        "assistant.models": "intelligence.model",
        "assistant.access": "intelligence.permissions",
        "assistant.data": "intelligence.privacy",
        "assistant.web": "intelligence.tools",
        "assistant.voice": "workspace.soundAndVoice",
        // Sage's appearance (surface opacity, blur, message font and size) did
        // NOT move to WORKSPACE ▸ Appearance — that page is the workspace
        // theme, Living Sky, and app icon. They are the Appearance tab of
        // Sage's own app page.
        "assistant.appearance": "app.sage",
        // The v0.16.0 app rename. An app's settings page id is derived from its
        // app id, so renaming the app moved its page. These keep a persisted
        // selection or an old deep-link resolving instead of dead-ending.
        "app.assistant": "app.sage",
        "app.files": "app.hoard",
        "app.canvas": "app.scry",
    ]

    /// Follows the alias chain to a fixed point, so retiring an already-retired
    /// path's target (chaining two entries together) still resolves all the
    /// way through instead of stopping at the stale intermediate. Guards
    /// against a cycle (which would only ever be a bug in `map` itself) by
    /// capping the walk at `map.count` hops — more hops than that means we're
    /// looping, so bail out to the last path seen rather than spin forever.
    static func resolve(_ path: SettingsPath) -> SettingsPath {
        var current = path
        var seen = Set<String>()
        for _ in 0..<map.count {
            guard let target = map[current.rawValue],
                let resolved = SettingsPath(rawValue: target)
            else { return current }
            guard !seen.contains(resolved.rawValue) else { return current }
            seen.insert(current.rawValue)
            current = resolved
        }
        return current
    }

    static var allTargets: [SettingsPath] {
        map.values.compactMap { SettingsPath(rawValue: $0) }
    }

    /// Every retired path this table knows about. Exposed so tests can
    /// assert the table stays a flat "retired -> current" map (no target is
    /// itself a key) without reaching into `map` directly.
    static var allKeys: [String] {
        Array(map.keys)
    }
}
