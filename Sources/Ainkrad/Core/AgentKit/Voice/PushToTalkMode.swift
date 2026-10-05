import Foundation

enum PushToTalkMode: String, Codable, Sendable, CaseIterable {
    case hold  // record while the hotkey is held; transcribe on release. Default.
    case toggle  // first press starts, next press stops + transcribes.
}
