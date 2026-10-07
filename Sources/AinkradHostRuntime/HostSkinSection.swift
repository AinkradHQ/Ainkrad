import AinkradAppKitUI
import Foundation

/// Host representation of a decoded theme file's custom host metadata.
struct HostSkinSection: Equatable, Codable, Sendable {
    let skyProfile: SkyProfile
    let iconColorFamily: AppIconColor

    init(skyProfile: SkyProfile, iconColorFamily: AppIconColor) {
        self.skyProfile = skyProfile
        self.iconColorFamily = iconColorFamily
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let profileArray = try container.decode([Double].self, forKey: .skyProfile)
        guard profileArray.count == 5 else {
            throw DecodingError.dataCorruptedError(
                forKey: .skyProfile, in: container, debugDescription: "skyProfile array must have 5 entries")
        }
        self.skyProfile = SkyProfile(
            profileArray[0], profileArray[1], profileArray[2], profileArray[3], profileArray[4])

        let familyString = try container.decode(String.self, forKey: .iconColorFamily)
        guard let family = AppIconColor(rawValue: familyString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .iconColorFamily, in: container, debugDescription: "Unknown iconColorFamily '\(familyString)'")
        }
        self.iconColorFamily = family
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let profileArray = [
            skyProfile.aurora, skyProfile.embers, skyProfile.mist, skyProfile.fireflies, skyProfile.lightRays,
        ]
        try container.encode(profileArray, forKey: .skyProfile)
        try container.encode(iconColorFamily.rawValue, forKey: .iconColorFamily)
    }

    private enum CodingKeys: String, CodingKey {
        case skyProfile
        case iconColorFamily
    }
}
