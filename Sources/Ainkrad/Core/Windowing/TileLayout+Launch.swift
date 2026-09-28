import AinkradAppKit

extension TileLayout {
    /// The open pane a launch should reuse instead of opening another: the
    /// most recently added pane of `appID`, and only for an open-document
    /// intent — any other launch (an SSH session for Rune) needs its own pane.
    func paneForDocument(appID: String, intent: AinkradLaunchIntent?) -> Block? {
        guard intent?.isOpenDocument == true else { return nil }
        return blocks.last { $0.appID == appID }
    }
}
