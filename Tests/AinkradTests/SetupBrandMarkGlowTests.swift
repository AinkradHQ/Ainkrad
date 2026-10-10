import AinkradAppKit
import SwiftUI
import Testing

@testable import Ainkrad

/// E5.2 (G2/G9): a theme that clears its bloom gets the plain mark.
@MainActor
@Suite("Setup brand mark glow")
struct SetupBrandMarkGlowTests {
    private func shot(_ tokens: AinkradSkin) throws -> Data {
        try SignalSnapshotTests.render(
            SetupBrandMark(tokens: tokens, reduceMotion: true).ainkradSkin(tokens), size: CGSize(width: 236, height: 236))
    }

    @Test("a cleared bloom drops the sparks, halo and glow")
    func clearedBloomIsPlain() throws {
        var plain = AinkradSkin.standard
        plain.effects.glowBloom.color = .clear
        #expect(try shot(plain) != shot(.standard))
    }
}
