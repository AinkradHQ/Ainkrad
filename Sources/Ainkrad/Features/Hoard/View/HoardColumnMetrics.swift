import AinkradAppKitUI
import SwiftUI

/// The ONE declaration of the list's column geometry. The header and the rows
/// are separate views, so without a shared source they drift — the first cut
/// had the header padded by `md` while rows were inset by the ScrollView's
/// `sm` PLUS `AinkradListRow`'s own `md`, leaving the header 8pt out.
enum HoardColumnMetrics {
    static let sizeWidth: CGFloat = 80
    static let modifiedWidth: CGFloat = 140

    /// Horizontal inset that makes the header line up with row CONTENT.
    /// `AinkradListRow` adds `AinkradSpacing.md` inside itself, and the
    /// scroll content adds `AinkradSpacing.sm` outside it.
    static let headerInset = AinkradSpacing.sm + AinkradSpacing.md

    /// Applied to the LazyVStack so rows and header share the outer inset.
    static let rowStackInset = AinkradSpacing.sm
}
