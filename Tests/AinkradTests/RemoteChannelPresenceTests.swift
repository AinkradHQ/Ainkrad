import Testing

@testable import Ainkrad

@Suite("Remote channel presence")
struct RemoteChannelPresenceTests {
    @Test func onlyListeningShowsPresence() {
        #expect(RemoteChannelPresence.isListening(.listening))
        #expect(!RemoteChannelPresence.isListening(.off))
        #expect(!RemoteChannelPresence.isListening(.needsToken))
        #expect(!RemoteChannelPresence.isListening(.stopped))
    }
}
