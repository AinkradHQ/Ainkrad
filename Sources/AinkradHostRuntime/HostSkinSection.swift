import AinkradAppKitUI
import Foundation

/// Host representation of a decoded theme file's custom host metadata.
/// Every key is optional so a language-only `host` block decodes; a missing
/// sky profile or icon family falls back to the Neon value.
struct HostSkinSection: Equatable, Codable, Sendable {
    let skyProfile: SkyProfile
    let iconColorFamily: AppIconColor
    /// Present only on a theme variant (a design language at one appearance).
    /// A `.theme` file without it is a base skin.
    let language: LanguageSection?

    init(skyProfile: SkyProfile, iconColorFamily: AppIconColor, language: LanguageSection? = nil) {
        self.skyProfile = skyProfile
        self.iconColorFamily = iconColorFamily
        self.language = language
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let profileArray = try container.decodeIfPresent([Double].self, forKey: .skyProfile) {
            guard profileArray.count == 5 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .skyProfile, in: container, debugDescription: "skyProfile array must have 5 entries")
            }
            self.skyProfile = SkyProfile(
                profileArray[0], profileArray[1], profileArray[2], profileArray[3], profileArray[4])
        } else {
            self.skyProfile = .neutral
        }

        if let familyString = try container.decodeIfPresent(String.self, forKey: .iconColorFamily) {
            guard let family = AppIconColor(rawValue: familyString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .iconColorFamily, in: container,
                    debugDescription: "Unknown iconColorFamily '\(familyString)'")
            }
            self.iconColorFamily = family
        } else {
            self.iconColorFamily = .blue
        }
        self.language = try container.decodeIfPresent(LanguageSection.self, forKey: .language)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let profileArray = [
            skyProfile.aurora, skyProfile.embers, skyProfile.mist, skyProfile.fireflies, skyProfile.lightRays,
        ]
        try container.encode(profileArray, forKey: .skyProfile)
        try container.encode(iconColorFamily.rawValue, forKey: .iconColorFamily)
        try container.encodeIfPresent(language, forKey: .language)
    }

    private enum CodingKeys: String, CodingKey {
        case skyProfile
        case iconColorFamily
        case language
    }
}

/// Light or dark: which system appearance a theme variant or colour scheme is for.
enum ThemeAppearance: String, Codable, Sendable, CaseIterable {
    case dark
    case light
}

/// `host.language` in a theme variant file: which design language the file
/// belongs to and at which appearance. A missing key takes the Neon value.
struct LanguageSection: Equatable, Codable, Sendable {
    let id: String
    let name: String
    let appearance: ThemeAppearance
    let defaultColorScheme: String
    let fontFamily: String

    init(
        id: String = "neon", name: String = "Neon", appearance: ThemeAppearance = .dark,
        defaultColorScheme: String = "neonBlue", fontFamily: String = "exo2"
    ) {
        self.id = id
        self.name = name
        self.appearance = appearance
        self.defaultColorScheme = defaultColorScheme
        self.fontFamily = fontFamily
    }

    init(from decoder: Decoder) throws {
        let neon = LanguageSection()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? neon.id
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? neon.name
        self.appearance = try container.decodeIfPresent(ThemeAppearance.self, forKey: .appearance) ?? neon.appearance
        self.defaultColorScheme =
            try container.decodeIfPresent(String.self, forKey: .defaultColorScheme) ?? neon.defaultColorScheme
        self.fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily) ?? neon.fontFamily
    }
}
