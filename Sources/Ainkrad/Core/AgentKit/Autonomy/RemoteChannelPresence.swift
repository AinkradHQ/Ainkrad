import Foundation

/// Pure mapping used by the menu-bar presence indicator (unit-tested; keeps the
/// SwiftUI view thin).
enum RemoteChannelPresence {
    static func isListening(_ status: RemoteChannelStatus) -> Bool { status == .listening }
}
