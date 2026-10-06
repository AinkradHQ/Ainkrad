import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Masked API-key entry with a reveal (eye) toggle. Thin adapter over the kit's
/// `AinkradSecureField` (which already carries the reveal toggle + chamfer focus
/// ring). The `tokens` parameter is unused (kit reads `\.ainkradTheme`) but kept
/// so its Sage Connections consumers stay untouched. Never logs or
/// otherwise surfaces the value beyond this field.
struct NeonSecureField: View {
    @Binding var text: String
    let placeholder: String
    let tokens: DesignTokens  // unused adapter param — kit reads \.ainkradTheme

    var body: some View {
        AinkradSecureField(text: $text, placeholder: placeholder)
    }
}
