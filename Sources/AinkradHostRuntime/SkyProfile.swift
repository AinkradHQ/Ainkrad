import AinkradAppKitUI
import SwiftUI

/// Emphasis multipliers that give each theme's ambient sky its own character.
/// Every field scales an effect's baseline strength; `1.0` is unchanged, so
/// `.neutral` reproduces the original look. Colors are unaffected — those come
/// from the skin — this is purely how loud each effect plays.
public struct SkyProfile: Equatable, Hashable, Sendable {
    public let aurora: Double
    public let embers: Double
    public let mist: Double
    public let fireflies: Double
    public let lightRays: Double

    public init(
        _ aurora: Double, _ embers: Double, _ mist: Double,
        _ fireflies: Double, _ lightRays: Double
    ) {
        self.aurora = aurora
        self.embers = embers
        self.mist = mist
        self.fireflies = fireflies
        self.lightRays = lightRays
    }

    public static let neutral = SkyProfile(1, 1, 1, 1, 1)
}

extension AinkradSkin {
    /// One palette colour, resolved: `skin.color(\.accentSecondary)`.
    public func color(_ key: KeyPath<AinkradSkinPalette, AinkradColorToken>) -> Color {
        color(palette[keyPath: key])
    }
}
