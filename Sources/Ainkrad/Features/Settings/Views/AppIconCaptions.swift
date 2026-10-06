/// Captions for the app-icon control in the wizard's Appearance step
/// (`SetupAppearanceStepView`). The Settings pane and the wizard once
/// hardcoded their own copy and drifted — "Color"/"Colour" and
/// "Appearance"/"Light or dark" for the same two axes. "Color" is the
/// dominant spelling elsewhere in the app's user-facing strings, so it wins.
enum AppIconCaptions {
    static let color = "Color"
    static let appearance = "Appearance"
}
