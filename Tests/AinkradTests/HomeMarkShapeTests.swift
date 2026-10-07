import CoreGraphics
import SwiftUI
import Testing

@testable import Ainkrad

/// Pins the geometry of the brand chevron and the Launcher's targeting
/// brackets, so moving either onto its kit twin is provably pixel-identical.
@Suite("Home mark shapes")
struct HomeMarkShapeTests {
    private let box = CGRect(x: 0, y: 0, width: 160, height: 56)

    @Test func chevronIsTheNotchedBrandArrow() {
        var expected = Path()
        expected.move(to: CGPoint(x: 80, y: 0))
        expected.addLine(to: CGPoint(x: 160, y: 56))
        expected.addLine(to: CGPoint(x: 160 * 0.68, y: 56))
        expected.addLine(to: CGPoint(x: 80, y: 56 * 0.42))
        expected.addLine(to: CGPoint(x: 160 * 0.32, y: 56))
        expected.addLine(to: CGPoint(x: 0, y: 56))
        expected.closeSubpath()
        #expect(ChevronMark().path(in: box) == expected)
    }

    @Test func bracketsAreFourCornerArms() {
        let l: CGFloat = 10
        var expected = Path()
        expected.move(to: CGPoint(x: 0, y: l))
        expected.addLine(to: CGPoint(x: 0, y: 0))
        expected.addLine(to: CGPoint(x: l, y: 0))
        expected.move(to: CGPoint(x: 160 - l, y: 0))
        expected.addLine(to: CGPoint(x: 160, y: 0))
        expected.addLine(to: CGPoint(x: 160, y: l))
        expected.move(to: CGPoint(x: 160, y: 56 - l))
        expected.addLine(to: CGPoint(x: 160, y: 56))
        expected.addLine(to: CGPoint(x: 160 - l, y: 56))
        expected.move(to: CGPoint(x: l, y: 56))
        expected.addLine(to: CGPoint(x: 0, y: 56))
        expected.addLine(to: CGPoint(x: 0, y: 56 - l))
        #expect(TargetingBrackets(length: l).path(in: box) == expected)
    }

    @Test func bracketsDefaultToEightPointArms() {
        #expect(TargetingBrackets().path(in: box) == TargetingBrackets(length: 8).path(in: box))
    }
}
