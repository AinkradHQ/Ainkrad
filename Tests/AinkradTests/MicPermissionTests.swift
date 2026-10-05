import Foundation
import Testing

@testable import Ainkrad

final class FakeMicPermission: MicPermissionProviding, @unchecked Sendable {
    var status: MicAuthorization
    var grantOnRequest: Bool
    init(status: MicAuthorization, grantOnRequest: Bool = true) {
        self.status = status
        self.grantOnRequest = grantOnRequest
    }
    func request() async -> Bool {
        status = grantOnRequest ? .authorized : .denied
        return grantOnRequest
    }
}

@Suite("MicPermission")
struct MicPermissionTests {
    @Test func requestUpdatesStatus() async {
        let p = FakeMicPermission(status: .notDetermined, grantOnRequest: true)
        let granted = await p.request()
        #expect(granted)
        #expect(p.status == .authorized)
    }

    @Test func deniedStaysDenied() async {
        let p = FakeMicPermission(status: .notDetermined, grantOnRequest: false)
        #expect(await p.request() == false)
        #expect(p.status == .denied)
    }
}
