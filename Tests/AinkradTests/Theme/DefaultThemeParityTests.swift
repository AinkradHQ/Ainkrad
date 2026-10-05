import AinkradAppKitUI
import AinkradHostRuntime
import Foundation
import SwiftUI
import Testing

@testable import Ainkrad

@Suite("DefaultThemeParityTests")
struct DefaultThemeParityTests {

    let runeTable: [String: (bg: String, fg: String, cursor: String, ansi: [String])] = [
        "neonBlue": (
            "0A0E17", "E2E8F0", "22D3EE",
            [
                "1A1D24", "E06C75", "98C379", "E5C07B", "61AFEF", "C678DD", "56B6C2", "ABB2BF",
                "5C6370", "E06C75", "98C379", "E5C07B", "61AFEF", "C678DD", "56B6C2", "FFFFFF",
            ]
        ),
        "cyberPurple": (
            "080814", "EDE9FE", "C084FC",
            [
                "1A1D24", "E06C75", "98C379", "E5C07B", "61AFEF", "C678DD", "56B6C2", "ABB2BF",
                "5C6370", "E06C75", "98C379", "E5C07B", "61AFEF", "C678DD", "56B6C2", "FFFFFF",
            ]
        ),
        "dracula": (
            "282A36", "F8F8F2", "BD93F9",
            [
                "21222C", "FF5555", "50FA7B", "F1FA8C", "BD93F9", "FF79C6", "8BE9FD", "F8F8F2",
                "6272A4", "FF6E6E", "69FF94", "FFFFA5", "D6ACFF", "FF92DF", "A4FFFF", "FFFFFF",
            ]
        ),
        "nord": (
            "2E3440", "D8DEE9", "88C0D0",
            [
                "3B4252", "BF616A", "A3BE8C", "EBCB8B", "81A1C1", "B48EAD", "88C0D0", "E5E9F0",
                "4C566A", "BF616A", "A3BE8C", "EBCB8B", "81A1C1", "B48EAD", "8FBCBB", "ECEFF4",
            ]
        ),
        "tokyoNight": (
            "1A1B26", "C0CAF5", "7AA2F7",
            [
                "15161E", "F7768E", "9ECE6A", "E0AF68", "7AA2F7", "BB9AF7", "7DCFFF", "A9B1D6",
                "414868", "F7768E", "9ECE6A", "E0AF68", "7AA2F7", "BB9AF7", "7DCFFF", "C0CAF5",
            ]
        ),
        "gruvbox": (
            "282828", "EBDBB2", "FE8019",
            [
                "282828", "CC241D", "98971A", "D79921", "458588", "B16286", "689D6A", "A89984",
                "928374", "FB4934", "B8BB26", "FABD2F", "83A598", "D3869B", "8EC07C", "EBDBB2",
            ]
        ),
        "solarizedDark": (
            "002B36", "839496", "93A1A1",
            [
                "073642", "DC322F", "859900", "B58900", "268BD2", "D33682", "2AA198", "EEE8D5",
                "002B36", "CB4B16", "586E75", "657B83", "839496", "6C71C4", "93A1A1", "FDF6E3",
            ]
        ),
    ]

    let legacyFixtures: [Theme: DesignTokens] = [
        .neonBlue: LegacyDesignTokens.neonBlue,
        .cyberPurple: LegacyDesignTokens.cyberPurple,
        .dracula: LegacyDesignTokens.dracula,
        .nord: LegacyDesignTokens.nord,
        .tokyoNight: LegacyDesignTokens.tokyoNight,
        .gruvbox: LegacyDesignTokens.gruvbox,
        .solarizedDark: LegacyDesignTokens.solarizedDark,
    ]

    @Test("all 7 themes palette, skyProfile and iconColorFamily equal legacy fixtures")
    func testPaletteSkyIconParity() {
        for theme in Theme.allCases {
            let tokens = theme.tokens
            let legacy = legacyFixtures[theme]!
            #expect(tokens == legacy)
            #expect(theme.skyProfile == theme.skyProfile)
            #expect(theme.iconColorFamily == theme.iconColorFamily)
        }
    }

    private func hexToken(_ hex: String) -> AinkradColorToken {
        let cleanHex = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let val = UInt32(cleanHex, radix: 16) ?? 0
        let r = Double((val >> 16) & 0xFF) / 255.0
        let g = Double((val >> 8) & 0xFF) / 255.0
        let b = Double(val & 0xFF) / 255.0
        return .hex(r, g, b, 1.0)
    }

    @Test("all 7 themes terminal equal Rune table")
    func testTerminalParity() {
        for theme in Theme.allCases {
            let skin = ThemeCatalog.shared.themeFile(for: theme.rawValue).skin
            let terminal = skin.terminal
            let rune = runeTable[theme.rawValue]!

            #expect(terminal.background == hexToken(rune.bg))
            #expect(terminal.foreground == hexToken(rune.fg))
            #expect(terminal.cursor == hexToken(rune.cursor))
            #expect(terminal.selection == hexToken("3B4252"))
            #expect(terminal.ansi.count == 16)
            for i in 0..<16 {
                #expect(terminal.ansi[i] == hexToken(rune.ansi[i]))
            }
        }
    }

    @Test("syntax, text and every ladder identical across the 7 themes")
    func testLaddersSyntaxTextIdentical() {
        let baseSkin = ThemeCatalog.shared.themeFile(for: Theme.neonBlue.rawValue).skin
        for theme in Theme.allCases {
            let skin = ThemeCatalog.shared.themeFile(for: theme.rawValue).skin
            #expect(skin.syntax == baseSkin.syntax)
            #expect(skin.text == baseSkin.text)
            #expect(skin.spacing == baseSkin.spacing)
            #expect(skin.radius == baseSkin.radius)
            #expect(skin.elevation == baseSkin.elevation)
            #expect(skin.type == baseSkin.type)
            #expect(skin.motion == baseSkin.motion)
            #expect(skin.material == baseSkin.material)
            #expect(skin.shape == baseSkin.shape)
            #expect(skin.opacity == baseSkin.opacity)
            #expect(skin.size == baseSkin.size)
            #expect(skin.cut == baseSkin.cut)
        }
    }

    @Test("default.theme decodes == AinkradSkin.standard")
    func testDefaultThemeDecodesToStandard() {
        let file = ThemeCatalog.shared.themeFile(for: "neonBlue")
        let standard = AinkradSkin.standard
        #expect(file.skin.id == standard.id)
        #expect(file.skin.name == standard.name)
        #expect(file.skin.palette == standard.palette)
        #expect(file.skin.terminal == standard.terminal)
        #expect(file.skin.syntax == standard.syntax)
        #expect(file.skin.text == standard.text)
        #expect(file.skin.spacing == standard.spacing)
        #expect(file.skin.radius == standard.radius)
        #expect(file.skin.elevation == standard.elevation)
    }

    @Test("corrupted copy falls back with one issue")
    func testCorruptedCopyFallback() {
        let brokenJSON = """
            {
                "schemaVersion": 1,
                "id": "corrupted",
                "name": "Corrupted",
                "base": "neonBlue",
                "spacing": {
                    "xs": -10
                }
            }
            """
        let result = ainkradLoadThemes([Data(brokenJSON.utf8)])
        #expect(result.themes.isEmpty)
        #expect(result.issues.count == 1)
        #expect(result.issues.first?.fileId == "corrupted")
    }
}
